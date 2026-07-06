---
title: Reactor Eval Runner
tags: [testing, chat, agents]
sources:
  - path: scripts/run_eval/
    last_read: 2026-06-17
created: 2026-06-17
updated: 2026-06-17
last_accessed: 2026-06-17
---

The Reactor eval runner is a Notion-driven harness that exercises the Sift agent (Reactor) end to end: it reads scenarios from a Notion table, drives [[chat-cli]] against a chat backend, pulls the resulting traces, and writes transcripts plus grading scaffolding back into Notion for human graders. It lives in `scripts/run_eval/` and is invoked through the `/run-eval` skill or directly via `main.py`. Use it to measure agent answer quality, tool selection, and multi-turn / writeback behavior across a curated dataset.

## What it tests

Each scenario is a single user prompt (or a scripted multi-step conversation) sent to the live agent. The harness captures the agent's final answer, token counts, the full transcript, and the `turn_trace` / `turn_summary` trace records, then surfaces them in a Notion run page so graders score correctness by hand. It does not auto-grade; it produces the evidence and the grading columns. It is distinct from the deterministic Go tests in [[chat-cli]] / [[chat-e2e]] / [[integration-tests]] — those assert fixed behavior, while this measures agent quality against a golden corpus.

## Dataset and row model

Scenarios live in the first `table` block on a single Notion source page (default: the Golden Dataset Evals page, `main.py:57`). The first table row is the header; every subsequent row is one case. Columns are matched by name (`main.py:114-126`):

- `Prompt` (required) — the user message. For scripted rows it instead holds a YAML step list.
- `Single or Multiple turn` — `Multiple` plus a Prompt whose first non-space char is `-` routes the row through chat-cli's `--script` mode; anything else runs as one plain prompt (`prompt_is_script`, `main.py:552`). Legacy prose `Multiple` rows keep working.
- `Expected Result`, `Expected Tool Calls` — rendered on the case detail page for graders.
- `Context Relevance`, `Tool selection precision`, `Semantic Correctness (for CEL particularly)` — known grading-dimension headers; these source columns are dropped from the run DB (`GRADE_HEADERS`, `main.py:121`).
- Any other header (`Category`, `Inferred Result`, …) is copied verbatim into the run DB as rich text.

Scripted rows are an ordered list of typed steps (`turn`, `approval: approve|reject`, `user_input: first|all|<text>`), each matching a real agent pause. A scripted desync (agent pauses where the script does not expect it, or vice versa) is a hard failure: chat-cli aborts with an `[eval-error: …]` line and non-zero exit. Step parsing is in `cmd/chat-cli/script.go:39`.

## How to run

Setup (venv lives outside the repo to avoid the venv `.gitignore *` footgun, `README.md:142`):

```bash
python3 -m venv ~/.venvs/run_eval
~/.venvs/run_eval/bin/pip install -r scripts/run_eval/requirements.txt
```

Required env (`main.py:1043-1058`):

- `NOTION_TOKEN` — Notion internal integration secret with read+write on the source page.
- `SIFT_LOCAL_ADMIN_USER_API_KEY` — required for `--env localdev`.
- `SIFT_API_KEY` — required for `--env dev`. The runner selects the key strictly per `--env` and refuses to send a localdev key to the dev URL.
- For `--env dev`: a live AWS SSO session and the `azimuth` binary on `PATH` (used by the Athena trace scraper). Dev pre-flights `aws sts get-caller-identity` before creating the run page (`check_aws_auth`, `main.py:509`).

Invocation:

```bash
# Local docker backend (run make up first):
python scripts/run_eval/main.py --env localdev

# Dev cluster:
python scripts/run_eval/main.py --env dev --trace-wait 5m

# Subset by 1-based row index (matches table order):
python scripts/run_eval/main.py --env localdev --rows 1,3,5

# Serial (default is 5-way parallel):
python scripts/run_eval/main.py --env localdev --parallelism 1

# Dry run: create the run page + DB, skip chat:
python scripts/run_eval/main.py --env localdev --dry-run
```

Key flags (`main.py:1005-1041`): `--env` (required, `localdev`|`dev`), `--source-page` (alias `--hub-page`, default Golden Dataset Evals), `--name` (run-page title suffix), `--chat-url` (defaults to `http://localhost:8080` localdev / `https://api.development.siftstack.com` dev), `--trace-wait` (e.g. `30s`, `5m`; defaults 10s localdev / 300s dev), `--rows`, `--parallelism` (default 5), `--dry-run`, `--no-cleanup`.

The `/run-eval` skill wraps this: it verifies cwd is under `~/code/azimuth*`, collects env / row subset / name / parallelism via prompts, runs pre-flight checks, executes in the foreground, and reports the run page URL. `/run-eval setup` runs the one-time venv + dependency + `azimuth` install workflow. Shortcut tokens: `localdev`/`dev`, `dry`, `smoke` (row 1 only).

## Where results land

Results go to Notion, not the filesystem. The runner creates a child page named `Run <UTC-timestamp> [env]` (plus the `--name` suffix) under the source page, containing a `Cases` database that mirrors the source schema (`create_run_page` / `create_run_db`, `main.py:300,315`). Each case row gets `Status` (pending → running → done/failed), `Agent Result` (final answer sliced from the transcript), `Conversation ID`, `Runtime (s)`, `Run Notes`, and per-grader `Score` / `Categories` / `Comments` columns (`GRADERS`, `main.py:131`). Opening a row shows `## Expected`, `## Meta`, `## Transcript`, `## Trace (JSONL)`, and `## Script` (scripted rows only). The script prints the run page URL last. Note: `--env dev` writes real tenant data (asset names, run IDs, user emails) into Notion, so the source page must be access-restricted to the dev tenant's audience (`README.md:7`).

Property names carry a two-digit prefix (`01 `, `02 `, …) because Notion's default view sorts alphabetically and the public API gives no way to reorder columns; the prefix forces the intended logical order (`create_run_db`, `main.py:315`). A `column_map` maps logical names to the prefixed physical names; all writers go through it.

## Execution flow

Per `main.py` and `README.md:231`: build `cmd/chat-cli` once into a tempdir (`build_chat_cli`, `main.py:532`) so the case loop execs a prebuilt binary instead of paying `go run`'s compile cost per case. Cases run concurrently in a bounded `ThreadPoolExecutor` (`case_loop`, `main.py:919`) — threads are sufficient because each case is IO-bound. Per case (`_process_case`, `main.py:749`):

1. Set `Status = running`, exec chat-cli with the API key supplied via the child's `SIFT_API_KEY` env (kept off argv so `ps` cannot read it; `_chat_cli_env`, `main.py:502`). Scripted rows add `--script` and `--dump-created-resources`; plain rows pipe the prompt on stdin.
2. Parse the `[conversation: <uuid> | tokens: in=N out=N]` marker (`CONVERSATION_RE`, `main.py:64`) emitted at `cmd/chat-cli/main.go:602`. A missing marker is treated as a case failure.
3. Fetch traces via `scripts/pull_chat_traces.sh` (`fetch_traces`, `main.py:661`): localdev bounds the docker logs read with `--docker-since`; dev queries Athena filtered by `conversation_id`, retrying every 30s up to `--trace-wait` (ingestion lag tolerance).
4. Append `## Expected` / `## Meta` / `## Transcript` / `## Trace (JSONL)` to the row; set `Status = done`, fill `Conversation ID`, `Runtime (s)`, `Agent Result`. The transcript is ANSI-stripped and scrubbed of the bearer token (`_scrub`, `main.py:491`) before write.

Per-case exceptions set `Status = failed` and record the error in `Run Notes`; the transcript is still appended when available and the loop continues. The process exits non-zero if any case failed.

## Cleanup

Writeback scenarios create real rules and calculated channels in the eval tenant. chat-cli writes a sidecar of created-resource IDs via `--dump-created-resources` (passed automatically for scripted rows), and after each case the runner archives the captured `rule` and `calc_channel` IDs through the Sift SDK (`sift_client`): `client.rules.archive` / `client.calculated_channels.archive`, guarded by a lock so the parallel loop is safe (`cleanup.py:27`, wired in `main.py:838`). SDK endpoints per env are in `SDK_URL_DEFAULTS` (`main.py:43`). Per-resource failures are logged and skipped. `--no-cleanup` skips archiving.

Known limitation (`README.md:134`): a committed writeback's result is not streamed back as a tool-call result, so the sidecar does not yet capture resources created behind an approval gate — the common writeback case. Run writeback rows with `--no-cleanup` and archive manually until that capture path is fixed. `evaluate_rule` cleanup (report + annotations) is also deferred: the sidecar records `report_id`/`job_id`, but the runner does not archive them (`report` and unknown kinds are ignored in `cleanup.py:42`).

## Relation to Reactor tools

The runner is a black-box driver: it sends prompts and reads what the agent did, so it tracks Reactor's tool surface without depending on tool internals. The script step types map directly to Reactor's interactive pauses — `approval` resumes a writeback approval gate, `user_input` resumes a `request_user_input` pause. The grading `Categories` options mirror `AGENT_FEEDBACK_WRONG_REASON_LABELS` in the web-app feedback modal (`FEEDBACK_CATEGORY_OPTIONS`, `main.py:156`); keep both in sync. When adding new typed Reactor tools (see [[reactor-adding-tools]]), writeback cleanup may need a new sidecar `kind`, and `extract_final_response` (`main.py:615`) assumes the chat-cli transcript markers documented in [[chat-event-types]] — both can break if chat-cli's output format changes.

## Tests

```bash
python -m unittest scripts/run_eval/test_main.py
```

`test_main.py` covers the pure helpers (ID normalization, duration parsing, transcript slicing, name synthesis), the Notion read path with a fake client, the chat-cli driver (token kept off argv, scrubbed from the transcript), run-DB schema ordering, script detection, and sidecar archiving. It does not hit a live backend or Notion.
