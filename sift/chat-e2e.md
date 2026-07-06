---
title: chat-e2e
tags: [chat, tooling, testing]
sources:
  - path: cmd/chat-e2e/
    last_read: 2026-05-13
created: 2026-05-13
updated: 2026-05-13
last_accessed: 2026-05-19
---

`chat-e2e` is a Bash harness that drives [[chat-cli]] with a scripted scenario
under `asciinema`, producing PR-ready verification evidence (cast + GIF +
transcript). One scenario can span multiple `chat-cli` invocations, including
resuming a conversation started earlier in the same run.

Invocation:

```bash
source .env
./cmd/chat-e2e/chat-e2e.sh cmd/chat-e2e/scenarios/smoke.txt [--verbose]
```

Requires `asciinema` (brew). `agg` is optional and produces an animated GIF;
without it only the `.cast` file is emitted.

## Output layout

Each run lands in `chat-e2e-out/<scenario>-<timestamp>/`:

- `recording.cast` — asciinema capture
- `recording.gif` — animated GIF if `agg` is installed
- `transcript.log` — concatenated `chat-cli` stdout across every session
- `sessions/session-N.txt` — per-session user-message files (kept for debugging)
- `sessions/meta` — one session kind per line (`new` or `resume`)
- `driver.sh` — generated script that asciinema executes inside its PTY

`chat-e2e-out/` is the canonical place for PR artifacts.

## Scenario format

Plain-text files:

- One user message per non-blank, non-comment line.
- `#` lines are ignored.
- `---session new` starts a fresh conversation.
- `---session resume` reopens the most recent conversation seen so far in the
  same run, by grepping the running `transcript.log`.
- A scenario without any `---session` markers is treated as one `new` session
  (backward-compatible single-session form).

Multi-session scenarios are how cross-turn behaviors (persistence, message-UID
agreement between live stream and reloaded history) are exercised end-to-end.

## Conversation-ID extraction (resume)

`resume` sessions need to know which conversation to reopen. The driver greps
the in-progress transcript with:

```
sed -nE 's/.*\[conversation: ([0-9a-fA-F-]+) \| tokens.*/\1/p' "$LOG" | tail -1
```

This pattern matches the `[conversation: <uuid> | tokens: in=N out=N]` line
that `chat-cli` prints on every `TurnComplete`. **If that output format
changes in [[chat-cli]], update the sed pattern in `chat-e2e.sh`** — there
is no other coupling, but breaking the contract silently breaks every
multi-session scenario.

## Driver mechanics

The script writes a self-contained `driver.sh`, then runs
`asciinema rec --overwrite --cols 120 --rows 36 -c "$DRIVER"`.
`$SIFT_LOCAL_ADMIN_USER_API_KEY` is exported (not baked into the script on
disk) so it survives the asciinema PTY without ending up in any artifact.

Inside the driver, each session calls `go run ./cmd/chat-cli chat ...` with
its session file piped on stdin. `chat-cli` detects the pipe and echoes each
message after the `> ` prompt so transcripts/GIFs read naturally.

## Scenario catalog

Top-level scenarios cover specific PR-level verifications:

| File | Purpose |
|---|---|
| `smoke.txt` | Minimal one-message echo of the full streaming path. |
| `persistence.txt` | Two sessions — `new` then `resume` — verifies the agent recalls a fact across a reconnect. |
| `timing-verbose.txt` | ENG-10284 observability: with `--verbose`, asserts the `[timing | ttft: ... | total: ... | tools: N (Nms)]` line shows up correctly for a text-only turn vs a tool-using turn. |
| `verbose-ids.txt` | ENG-10435 / PR #10775: verifies live-streamed UIDs (`TurnStart` user-msg ID, per-assistant divider, `msg=<uid>` on tool results) match the UIDs rendered when the same conversation is reloaded in session 2. |

`scenarios/evals/` (01–16) is the agent-quality eval suite — persona-tagged
scenarios that exercise tool selection, multi-turn context retention,
ambiguity handling, capability disclosure (e.g. `14-aspirational-pdf-report`),
and cross-run aggregation. Each file's header lists the persona, summary, and
"Looking for" expectations rather than asserting them automatically — these
scenarios are graded by reading the GIF/transcript, not by a test runner.

## Related

- [[chat-cli]] — the CLI this script drives.
- [[chat-event-types]] — the stream events whose rendered output forms the
  transcript that `resume` greps.
