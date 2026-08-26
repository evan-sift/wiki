# Log

Append-only activity record. Each entry uses the format:
`## [YYYY-MM-DD] operation | subject`

Lint truncates to the last 50 entries; older entries are archived to `log-archive.md`.

---

## [2026-07-06] restructure | normative-only vault (codegraph owns structure)

Restructured the vault around one principle: codegraph now answers "what the
code IS" (structure, call paths), so the wiki keeps only normative content —
conventions, rules, gotchas, recipes, decision records, domain semantics,
operational runbooks. (The vault flatten to `~/wiki` was done separately,
before this.)

- **`_archive/` convention introduced.** Whole pages that were descriptive
  code walkthroughs moved (git mv) to `sift/_archive/` rather than deleted:
  channel-data-service, data-pipeline, docs-search-tool, explore2-slice,
  legend-v2, panel-types. Archived pages are excluded from the index and from
  check-stale (which only scans the vault root). Before archiving
  explore2-slice, its two normative nuggets (`ignoreCleanup: true` hydration
  semantics; the sharelink-compat rationale for `sharelinkRegression/`) were
  folded into [[state-management]].
- **Deleted `tables.md`** — a zero-content stub from the Notion migration.
- **Slimmed split pages in place** (normative content kept, code-structure
  walkthroughs dropped; git history preserves them): [[chat-cli]],
  [[chat-event-types]], [[coding-sandbox]], [[data-visualization]],
  [[directory-structure]], [[opfs-service]], [[scv]], [[skills]],
  [[storage-service]].
- **[[artifacts]] deliberately untouched** — it documents an unmerged branch
  (ENG-10586) that codegraph cannot see; revisit after merge.
- Rewrote wikilinks to archived/deleted pages in surviving pages (concept named
  in prose or pointed at codegraph). Fixed orphans: [[routing]] and
  [[rich-text-editor-options]] now linked from [[project-overview]]. Converted
  [[sift-domain-concepts]] and [[sift-mcp-and-cli]] `sources:` to the schema's
  `path:`/`last_read:` map form so check-stale sees them. Dropped the
  unregistered `sandbox` tag from [[coding-sandbox]] (covered by `agents`).
  Regenerated the index (28 pages).

## [2026-06-19] ingest | skills library (ENG-12120)

Created [[skills]]. The "skills library" feature deferred on 2026-06-18 (then
only on an unmerged branch) is now merged to `main`, so it can be grounded in
readable source. Documents the `skills` table + `skills_isolation_policy` RLS
(org-level in the policy; per-user privacy enforced in the service layer), the
`SkillService` REST/gRPC CRUD, and the chat agent's lazy `load_skill` tool.
Caveat flagged on the page: as of this commit the chat registry is built solely
from embedded `.md` skills (`web-service/main.go` → `chatskills.DefaultSkills()`),
so user-created DB skills are not yet wired into the agent's `load_skill`
registry — the two layers are independent until that connection lands. Tagged
backend / chat / domain-concepts; linked from [[reactor-adding-tools]].

## [2026-06-18] ingest | daily session mining — no new areas

Mined 40 sessions since the 2026-06-17 watermark (17 interactive azimuth/scripts
rows after discounting 23 `subagents` code-review runs). No pages created. The
dominant theme — a "skills library" backend feature (branch
`eng-12120-skills-library`, with a `skills_isolation_policy` RLS policy) — lives
only on an unmerged, actively-reviewed branch (not in main or any local
worktree), so it can't be grounded in readable source yet; revisit once it
merges. Remaining themes were out of scope: personal tooling outside
azimuth/sift (the yinyang collab tool, the code-review Claude skill), a minor
aws-login CLI flag tweak, and SCV bake work already covered by [[scv]] (updated
separately today).

## [2026-06-18] update | scv two-tier bake + branch-derived Tailscale hostname

Rewrote the [[scv]] image-bake section for the new two-tier model: `make foundation`
(`scv-foundation` family, ~52 min — the heavy dep/rust/seed half via
`install-foundation.sh`) and `make bake` (`scv` app family, ~10 min, built FROM the
foundation — `install-app-refresh.sh` rebuilds only the service images, pruning the
`base-rust`/`rust-chef`/`rust-binaries` toolchain targets since buildkit's layer cache
doesn't survive the GCE snapshot). Cut the app bake 18m→10m. Also documented boot-time
DB migrations, the `.bakeignore` upload trim, 150 GB disk lockstep, and the new SCV
Tailscale node naming (ingress sets `ts_hostname` from the Linear `branchName`, e.g.
`eng-12084-coding-sandbox-poc`, stable across TTL rehydration; falls back to
`scv-<run_id>`). Removed the dead single-tier `install-app.sh`.

## [2026-05-16] update | chat-service-goroutine-safety reflects ENG-11429

Rewrote [[chat-service-goroutine-safety]] after ENG-11429 removed the inline
title goroutine. The title path is no longer the canonical example of the
sender-after-return failure; it became the canonical example of the structural
fix instead — splitting derived async work into its own stateless `Chat`
profile call, dispatched from the worker. Updated `last_read` on the source
references and bumped [[chat-event-types]] for its `chat_service.go` source.

## [2026-05-13] ingest | chat-cli and chat-e2e harnesses

Ingested `cmd/chat-cli/` and `cmd/chat-e2e/` as two new pages: [[chat-cli]]
(commands, REPL event handling, SIGINT contract, personalities/EvalConfig,
verbose UIDs, tool-result dump, display helpers, auth interceptor) and
[[chat-e2e]] (asciinema-driven scenario runner: output layout, scenario
markers, conversation-ID extraction coupling to chat-cli's TurnComplete
output, scenario catalog including the `evals/` suite). Cross-linked from
[[chat-event-types]] (recipe step 6 mentions chat-cli) and added entries
under the `backend`, `testing`, `tooling`, and `chat` index sections.

## [2026-05-06] update | ENG-11049 Reactor calculated-channel tool review fixes

Updated Reactor tool guidance after tightening `list_calculated_channels`: the
tool now uses a trimmed JSON output shape rather than the full service proto,
deduplicates and caps explicit identifiers, covers service error branches, and
has a production registry regression test.

Pages updated:
- [[chat-event-types]] — noted that typed tool outputs should avoid persisting
  unnecessary service fields
- [[reactor-adding-tools]] — added privacy, bounded-lookup, error-branch, and
  production-registry test checklist items

## [2026-04-18] ingest | PR #10707 (ENG-10323 reactor thinking)

Distilled the extended-thinking PR into a recipe for adding new chat event
types. Covers the 3-layer architecture (proto wire / provider-agnostic LLM /
chat service), three worked examples (TextChunkEvent, tool-call events,
ThinkingChunkEvent), and the decision rubric (deployment policy vs per-request;
flatten-with-warning vs slice-shaped).

Pages created:
- [[chat-event-types]] — Recipe + worked examples for adding streaming event types

Tags added:
- `chat` — chat service, LLM gateway, AI message streaming, tool use, reactor

## [2026-04-12] init | Wiki initialized

Seeded wiki with initial pages from existing Claude auto-memory:
- [[legend-v2]] — from LegendV2 Architecture memory
- [[dev-commands]] — from Azimuth Development Commands memory

## [2026-04-12] ingest | internal-docs/src/web-app/

Ingested all 26 frontend documentation files from `internal-docs/src/web-app/`.
Synthesized into 9 new wiki pages covering the full frontend architecture:

Pages created:
- [[project-overview]] — Sift product context, tech stack, priorities
- [[directory-structure]] — Codebase layout, file naming, import aliases
- [[state-management]] — Redux, Context, TabState/OPFS, URL sync
- [[component-patterns]] — Compound components, Radix, hooks, styling, modals, tables
- [[data-fetching]] — RTK Query, generated hooks, cache invalidation
- [[data-pipeline]] — Web Workers, Arrow IPC, OPFS caching
- [[data-visualization]] — ECharts hooks, chart types, SiftDateTime
- [[performance-patterns]] — E2Syncer, EventTarget, escaping React lifecycle
- [[testing-patterns]] — Vitest conventions, gotchas, Radix issues
- [[routing]] — TanStack Router, file-based routes, URL state
- [[feature-flags-and-analytics]] — Amplitude flags and event tracking

Pages updated:
- [[legend-v2]] — added cross-references to new pages

## [2026-04-16] ingest | web-app/src/services/opfs/ + storage/ + worker pattern

Ingested the OPFS primitive layer, the Storage Service built on top of it, and spanned
`channelData`, `channelList`, `metricsData`, `tableData`, `annotations`, and `storage`
worker services to extract the shared pattern. Also covered `api/workers.ts` (worker-side
auth / fetch helpers), `util/worker.ts` (worker-only import convention), and
`util/arrow/opfsExplorer.worker.ts` (dev debug tool).

Pages created:
- [[opfs-service]] — primitive API, worker-only invariant, read dedup via in-flight
  promise map, handle-acquisition retry, best-effort eviction, empty-directory workaround
- [[storage-service]] — namespaced K/V on OPFS, pending-promise request/response
  protocol, LRU `cleanupItems`, worker-auth story (OIDC token via OPFS + fetchWithAuth),
  `appMeta` forwarding, opfsExplorer dev tool
- [[worker-service-pattern]] — Vite worker bootstrap idiom, two message protocols
  (subscription+callback vs request/response+pending-promise), MessageChannel escape
  hatch + `sendOneShot`/`streamFromWorker` helpers, init handshake variants,
  window-global forwarding, AbortController per subscription id, transferables,
  worker-only import rule, vitest pure-helper-file workaround

Pages updated:
- [[performance-patterns]] — linked to the three new pages from the Workers/OPFS sections
- [[data-pipeline]] — replaced inline Storage Service mention with pointer; added
  [[worker-service-pattern]] link
- [[state-management]] — TabState persistence now points at [[storage-service]] and
  [[opfs-service]] directly
- [[channel-data-service]] — added [[worker-service-pattern]] and [[opfs-service]] to
  Related
- [[_meta/index]] — registered the three new pages under architecture/frontend/
  performance/data-pipeline tags

## [2026-04-13] ingest | web-app/src/services/channelData/

Ingested the Channel Data Service implementation. Much richer than what the internal-docs
describe — revealed the subscription API design, cache v2 structure, quantization strategy,
`highestUnsampledMs` full-fidelity tracking, initial-response pattern (using other-sampleMs
caches to avoid blank charts during fetch), live-mode 5-min cutoff, MessageChannel one-shot
pattern for cache invalidation, and calculated-channel key format.

Pages created:
- [[channel-data-service]] — full architecture and cache strategy

Pages updated:
- [[data-pipeline]] — fixed v1→v2 cache path, replaced high-level Channel Data Service
  section with pointer to new detailed page
- [[data-visualization]] — added cross-ref to [[channel-data-service]] in the Arrow-to-chart flow
- [[performance-patterns]] — linked to [[channel-data-service]] as the primary Web Worker example

Contradictions flagged (fixed):
- [[data-pipeline]] had cache version `v1` from older internal docs; actual code uses `v2`

## [2026-04-13] ingest | web-app/src/store/explore2Slice/

Ingested the Explore 2 Redux slice — the largest slice in the app (~4,100 lines main file).
Covers the primary data exploration experience: multi-panel Dockview layouts, time-synced
charts, compare/alignment across runs, calculated channels, sharelinks.

Pages created:
- [[explore2-slice]] — state shape, modes, sidebars, data sources, sync/live modes,
  compare/alignment, URL syncer (~18 synced fields), migrations, sharelink regression
- [[panel-types]] — the 9 panel types (timeseries, fft, histogram, scatter, geo-map,
  metrics, table, file-viewer, empty), discriminated union, shared vs specific panel
  settings composition pattern, Y-axis/sampling conventions for timeseries

Pages updated:
- [[state-management]] — added explore2Slice as canonical URL-sync example; noted
  `ignoreCleanup: true` pattern for hydration-time dispatches
- [[channel-data-service]] — linked to explore2-slice and panel-types as the source
  of subscription options (channels, sampleMs, alignments, perChannelSamplingMethod)
- [[data-visualization]] — linked to panel-types from chart types table
## [2026-04-17] ingest | rich text editor findings

Ingested a durable summary of rich-text editor options for Azimuth frontend work. The page captures the current Lexical-based `CommentEditor` architecture, the adapter boundary around `CommentBodyElement[]`, and a selection heuristic for when to stay with textarea, move to Lexical, adopt Tiptap, or go directly to ProseMirror.

Pages created:
- [[rich-text-editor-options]] — editor tradeoffs, licensing notes, and selection guidance for future UI work
## [2026-04-22] stale-update | chat cancellation semantics

Updated the chat event architecture notes after a behavior change in `services/chat/v1/chat_service.go`. The page now records that request cancellation is returned from `HandleChat` as a wrapped `context.Canceled` error, while `consumeStream` suppresses a client-visible `ErrorEvent` for that case so canceled turns end quietly.

Pages updated:
- [[chat-event-types]] — documented the cancellation split between wrapped handler error and suppressed streamed `ErrorEvent`
## [2026-04-24] ingest | integration test workflow

Captured the local workflow for running Go integration tests (`//go:build integration`) against a real Postgres + S3 backend. The page documents the Docker stack switch (`make down` + `make integration-env-up-quick`), the connection env vars the test suite base reads, and invocation examples. Also cross-linked from dev-commands.

Pages created:
- [[integration-tests]] — integration test prerequisites, env vars, and invocation recipes

Pages updated:
- [[dev-commands]] — added pointer to integration-tests from the Testing section
## [2026-05-01] create | chat service goroutine safety

Captured the root cause of a production bug where TurnComplete was never sent and messages were not persisted. Commit `8736201f65` had changed the title goroutine to call `sender.Send` directly, which panicked when the goroutine ran after `HandleChat` returned and the HTTP response writer was torn down. The fix (restored in this session) reverts to the buffered channel pattern: goroutine does only compute work, main goroutine drains the channel and handles all stream I/O.

Pages created:
- [[chat-service-goroutine-safety]] — goroutine ownership rules for HandleChat, broken vs. correct patterns, diagnosis checklist
## [2026-05-06] migration | Notion back to local wiki

Restored the local `~/wiki/azimuth` vault as the source of truth and pulled the
Notion-only pages back into markdown.

Pages created:
- [[reactor-adding-tools]] - typed Reactor tool and resource-ref checklist
- [[tables]] - needs-review stub restored from the Notion migration

Pages updated:
- [[chat-event-types]] - added typed tool payload note and linked [[reactor-adding-tools]]
- [[routing]] - restored page-title guidance
- [[testing-patterns]] - restored slow UI interaction test guidance
- [[_meta/index]] - registered restored pages and backend/chat/tooling sections

Workflow updated:
- `~/.agents/AGENTS.md` now points Azimuth knowledge work at `~/wiki/azimuth`
- `~/.agents/skills/wiki-ingest/SKILL.md` now maintains the local wiki vault
## [2026-05-07] update | go integration tests against running local env

Empirically verified: Go integration tests can run against the already-running
`make up` local dev postgres without tearing it down. The local image is
`azimuth/postgres18` (same as integration env) and provisions
`read_write_user` / `temp_password` / `azimuth` on host port 5433. Ran
`TestChatServiceIntegrationTestSuite` (9 sub-tests) in 1.4s.

Pages updated:
- [[integration-tests]] — added TL;DR for running against live local env, added
  build-tag table, clarified that `make down` is only needed when local dev
  isn't running, refreshed source `last_read` dates

## [2026-05-08] update | Reactor tool selector bounds

Captured a recurring review finding for Reactor tool authoring: every
model-controlled selector list needs explicit local bounds after deduplication,
even if it only feeds URL construction or resource events rather than an
obvious paginated backend call.

Pages updated:
- [[reactor-adding-tools]] — added selector bounding guidance and matching
  over-cap test guidance

## [2026-05-20] update | Reactor writeback tools

Updated the Reactor tool authoring checklist with the write-tool approval path:
write tools stage validated payloads, return pending actions for approval, and
commit only after `ToolApprovalResponse` resumes the chat loop.

Pages updated:
- [[reactor-adding-tools]] — added write-tool interface, staging, commit, and
  profile registration notes for calculated-channel writebacks

## [2026-05-20] update | Reactor rule write tools

Recorded the rule writeback pattern alongside calculated-channel writebacks:
rule create/update use `BatchUpdateRules` for both validation and commit, while
rule archive stages from a read preview and commits with `ArchiveRule`.

Pages updated:
- [[reactor-adding-tools]] — added rule write-tool registration and validation
  notes

## [2026-05-20] update | Reactor writeback version guards

Revised the write-tool checklist to make version guards the concurrency
contract for mutable writebacks. Approval requests do not expire; edit/archive
commits re-read the latest entity and reject if the staged version is no longer
current.

Pages updated:
- [[reactor-adding-tools]] — replaced approval expiry guidance with staged
  version guard guidance for rules, calculated channels, and future write tools
- [[chat-event-types]] — added the writeback approval pause as the human-resume
  chat event example and noted that it has no expiry timestamp

## [2026-05-20] update | Reactor writeback preview normalization

Captured the approval preview contract after fixing a runtime
`structpb.NewStruct` failure: write-tool previews can be built from typed Go
values, but the streamed approval event is normalized through JSON before
constructing the protobuf struct.

Pages updated:
- [[reactor-adding-tools]] — documented JSON-normalized approval previews for
  write tools

## [2026-05-20] update | Reactor approval replay pairing

Recorded the provider replay invariant for writeback approvals: the persisted
human-readable approval response row is not replayed to the model, because the
following `TOOL_RESULT` row must pair directly with the prior assistant
`tool_use` blocks.

Pages updated:
- [[chat-event-types]] — documented writeback approval response replay behavior

## [2026-05-21] update | Reactor write tools use list-only lookups

Aligned write-tool lookup guidance with the Reactor list-tool contract from
PR 11624: direct rule and calculated-channel lookups should be exact CEL
filters over `List*` calls, not `BatchGet`/`Get` escape hatches on the narrow
tool interfaces.

Pages updated:
- [[reactor-adding-tools]] — documented list-only exact-ID/client-key lookup
  requirements for write-tool staging and commit version checks

## [2026-05-21] update | Reactor approval state stored on messages

Recorded the revised writeback approval architecture: staged write payloads live
on the server-only metadata of the persisted approval request message, not in a
separate pending-action table. Approval responses may also carry follow-up text,
which replays after the generated tool-result blocks.

Pages updated:
- [[chat-event-types]] — updated the writeback approval event example and replay
  details
- [[reactor-adding-tools]] — documented message-metadata persistence for staged
  write payloads
- [[chat-service-goroutine-safety]] — refreshed source access for
  `chat_service.go`

## [2026-06-17] ingest | New areas mined from a month of Claude sessions

Mined ~1 month of Claude Code sessions (942 transcripts) for recurring, durable
areas missing from the wiki, and ingested a handful as new pages. Each is grounded
in source rather than session chatter; maturity and discrepancies are flagged inline.

Pages created:
- [[scv]] — Sift Coding Vehicles (`ops/scv/`, RFC-0204). Note: live TTL is 3h, not
  the RFC's 6h; sessions/checkpoints/HITL have shipped beyond RFC chapters 01-05.
- [[sift-domain-concepts]] — asset/run/family/channel/rule/annotation/report from
  `protos/sift/*`. "Run group" is not a distinct entity; Family is the grouping primitive.
- [[sift-mcp-and-cli]] — MCP / CLI / REST / sift_client / sift_stream surfaces.
  Grounded in the separate `sift` repo (`~/code/sift`, `rust/crates/*`). Only
  `read_only_hint` exists in the MCP tool defs; destructive/idempotent are not asserted.
- [[reactor-eval-runner]] — Notion-driven eval harness (`scripts/run_eval/`).
- [[artifacts]] — conversation-attached artifact entity. IN-FLIGHT: only on branch
  `ENG-10586-artifacts-v1`, not merged to main.

Meta:
- Added the `agents` tag to `_meta/tags.md`.
- Added `## agents` and `## infrastructure` sections to the index; linked all five
  new pages from [[project-overview]] to avoid orphans.

## [2026-06-17] ingest | Daily watermark run — docs search/read tools

First scheduled daily run (in-session job 0a335846). The watermark window caught
3 sessions since 07:24: two were this session's own meta-work and a playful
multi-agent experiment (both discarded). The third (ENG-12265) surfaced the docs
search/read area, which was absent from the wiki.

Pages created:
- [[docs-search-tool]] — `search_sift_docs` / `read_sift_doc` Reactor tools and the
  `DocsService` HTTP API (`/api/v1/docs:search`, `/api/v1/docs:read`), grounded in
  `services/chat/tools/` + `services/repo/docs/v1/` on main (shipped via ENG-12213 /
  #12148). ENG-12265's match-line/context refinement is on an unmerged branch and is
  flagged as such.

Linked from [[sift-mcp-and-cli]]; indexed under backend/chat/tooling. Also fixed a
SIGPIPE bug in `wiki-ingest-digest.sh` (`jq | head` under `set -o pipefail`).

## 2026-07-14 — SCV pare-down (ENG-12894)

Rewrote [[scv]] for the review-only world: implementation mode, Slack/Linear
agent SDK, Firestore, Pub/Sub, Cloud Scheduler, Tailscale, the two-tier bake,
and canary/stable channels are all deleted on branch
eng-12894-pare-down-scv-to-only-pr-reviews. New content: instance-name mutex,
maxRunDuration backstop, scv-agent sandbox, boot-ack-as-success-signal,
three-dot diff fix, no thread auto-resolution. Old "docker compose stop" and
TTL/trust-code-over-RFC sections removed (machinery no longer exists).

## 2026-07-24 — SCV adversarial review (ENG-13153)

Updated [[scv]] for the attack→judge pipeline on branch
eng-13153-adversarial-review-as-the-default. Recorded the measured motivation
(25 runs, zero criticals, 8 "No new findings", PR 12805 clean at 29 files), the
five-stage wrapper, `slice.ts` partitioning, the code-side coverage gate, the
judge-only thread access, the two output tiers, and `out/coverage.json` as the
honesty mechanism. Corrected the now-historical claims: RFC-0204 ch. 04's
`code-review` skill is deleted and ch. 01/05's "pi runs once" no longer holds.
New gotchas: `vertex-proxy` must stay `ThreadingHTTPServer` with a cached
token, recon-agent `tools:` allowlists are the only bound on subagent
recursion, and per-pass transcripts live in `out/logs/`.

## 2026-07-27 — SCV self-review fixes (ENG-13153)

Updated [[scv]] after implementing SCV's own review of PR 13043. New durable
facts: `run_pass` must save/restore errexit (a bare `set -e` before
`return "$rc"` fires at the caller and killed every rc-inspecting salvage
path); `SCV_PR_REVIEW_TIMEOUT` is now a hard wall clock because the serial
coverage re-prompt sits outside the 55/35/10 split and could outrun
`maxRunDuration`; the cross-cut pass gets a manifest-derived
`inputs/crosscut.files` contract so gate and prompt spell paths identically;
`planSlices` filters empty buckets (zero-diff-line files never move the
bin-packer's pointer); and the vertex-proxy token cache invalidates on 401/403
plus a 30s `gcloud` fetch timeout under the lock. Also corrected the stale
"builder matches the runtime shape" claim — the Packer builder is
`e2-standard-4` on purpose; only `disk_size` tracks `gce.ts`.

## 2026-07-27 — SCV adversarial review, round 2 (ENG-13153)

Second multi-agent review pass over the branch. New durable facts in [[scv]]:
`run_pass`'s `usage-<name>.jsonl` redirect is the last element of a pipeline, so
a planted file makes it fail, SIGPIPE the producer, and return rc=141 — not 124 —
which skips the judge's salvage path and loses the whole review to one zero-byte
file. `startup.sh` now deletes `/scv/azimuth/.pi`: pi's subagent extension takes
`agentScope` as a model-chosen parameter, its project-agent confirmation is gated
on `ctx.hasUI` (always false under `--print`), and project definitions overwrite
baked ones by name, so a PR could replace a recon agent's `tools:` allowlist —
verified against pinned pi 0.81.1. Prior review threads are now staged in section
8 rather than up front, making the attacker/judge split structural instead of
prompt-level. Failed-gate passes keep their candidates (labelled) instead of
having them silently discarded. `coverage.json` gained `candidatesRaised` so
over-filtering by the judge is detectable at all.

## 2026-07-27 — SCV adversarial review, round 3 (ENG-13153)

Third pass. Three of round 2's own fixes were wrong or incomplete, which is the
case for the re-review-after-applying rule: `jq -s` on a missing file prints 0
*and* exits 2, so `|| echo 0` produced a two-line value that killed the
candidate-count loop mid-way; the unslurped concerns filter emitted nothing for a
whitespace-only file and two documents for trailing garbage, leaving concerns.json
unparseable (the exact outcome it was written to avoid); and `rm -f` does not
remove a planted *directory*, so the usage-path unlink didn't close the rc=141
hole. New durable facts in [[scv]]: pi's `<agentDir>/SYSTEM.md` REPLACES the
built-in system prompt and agentDir is the shared-uid home, so run_pass scrubs it
per pass; the subagent extension's children need `--no-context-files` or they load
the PR's AGENTS.md as `<project_instructions>` (patched at bake time, fail-loud);
`out/` must be ubuntu-owned 1775 with a pre-created `out/logs`, because `tee` is
the one write that cannot unlink first; and the usage glob must skip symlinks or
it copies the gh/Linear tokens into an agent-readable file.

## 2026-07-27 — SCV adversarial review, round 4 (ENG-13153)

Fourth pass. Three of round 3's four fixes were still incomplete, all of the same
shape: they guarded a *trigger* rather than validating a *value* or an
*ownership* assumption. `rm -rf` as ubuntu cannot clear an agent-owned non-empty
directory (needs write inside it), so the rc=141 hole stayed open — now
`clear_out_path()` has the agent remove it first. `[ -s ]` is true for a
directory and jq prints before failing, so the two-line `cand_n` bug survived —
now the captured value is validated as an integer. Same for the concerns filter's
multi-line capture. Fresh-eyes found the sharpest bug of all four rounds: a
planted `out/empty-diff` makes the driver post nothing at all, so one `touch`
silences a review that found defects. Also recorded: pi never activates
grep/find/ls (default active set is read/bash/edit/write), so the prompts were
reworded off a tool that was never offered; adding `--tools` is deferred because
it also filters extension tools and would need a live run to prove the recon
subagents survive.

## 2026-07-27 — SCV adversarial review, round 5 / cap (ENG-13153)

Fifth and final round. Same class a fourth time: round 4's `clear_out_path`
validated the planted path's *shape* (directory? symlink?) but not the outcome, so
a non-empty directory left mode 500 survived — rm never restores permissions it
lacks, so even the owning agent's `rm -rf` fails. And three `rm -f` clears of
agent-plantable paths (coverage.json, the judge's three outputs, the concerns
rewrite) were never converted, each of which aborts the wrapper under errexit on a
planted directory. Both fixed: chmod-then-rm, then assert the path is gone and
`exit 8` if not. Generalised rule now in [[scv]]: assert the outcome, do not
enumerate the ways an attacker can shape the input.

## 2026-07-28 — SCV self-review follow-ups (ENG-13153)

SCV's own re-review of the branch returned 1 finding + 5 concerns; CodeQL flagged
a partial SSRF that was already remediated in-tree via MODEL_MAP. Implemented: the
stale-`pr.review-threads.md` cleanup (a reused SCV_REVIEW_DIR broke the
staging-order boundary the wrapper asserts), 401-only token invalidation (403 is
authorization — a fresh token cannot help and dropping the cache stampedes
gcloud), a real `vertex-proxy/test_proxy.py` plus a `make test` target, and README
notes. Rejected two concerns with evidence from the pinned packages: pi already
retries rate limits with backoff, and `--thinking xhigh` clamps *upward* to `max`
on sonnet rather than being dropped. Both recorded in [[scv]] so they are not
re-raised.

## 2026-07-28 — SCV simplify pass (ENG-13153)

Four cleanup agents (reuse / simplification / efficiency / altitude) over the
branch. Removed 187 lines net. Biggest win: the three role prompts each repeated
the output schema, the six lenses, the recon-subagent section, the truncation
guidance and the doc-by-path table — now split into review-common.md (all passes)
and review-attacker.md (both attackers), wired through a prompts_for_pass that
emits one path per line into repeated --append-system-prompt flags (verified
repeatable in pi's arg parser). The judge deliberately does NOT get
review-attacker.md: it runs without -e "$subagent_ext", so describing a subagent
tool to it would invent a capability.

The pass also found a real bug that has nothing to do with LOC: the streaming
proxy used resp.read(4096), which blocks until 4 KB accumulates. Measured on a
200 B/100 ms stream: first relay at 2.08s with read, 0.00s with read1 — so on a
slow generation the proxy withheld output for exactly as long as the idle timeout
streaming exists to prevent. Now read1, pinned by a test whose double raises on
read (a BytesIO cannot show the difference, so the obvious streaming test passes
either way).

Four larger changes were considered and not landed, each needing a bake plus a
live run: redrawing the out/ trust boundary (per-pass drop dirs + a ubuntu-only
out/, which would delete clear_out_path and ~6 other guards, ~95 lines), moving
findings validation into the driver's TS validators (~48), dropping the cross-cut
per-file ledger (~12, and ~20k output tokens per large review), and root-owning
pi's agent config instead of scrubbing it per pass (~12). These were briefly
recorded in ops/TECH_DEBT.md and then removed: that file is for incidental
discoveries made while doing something else, not for a single PR's deferred scope.
The facts that matter live in [[scv]] and in comments at the point of use.

## 2026-07-29 — SCV confidence floor + cost rebalance (ENG-13153)

Two asks: more comments per review, and cheaper reviews. Floor dropped 70→50 with
two new bands below `mild` (speculative 50–59, tentative 60–69); the 70+ thresholds
are unchanged so nothing that was postable changes label. The rubric in
review-judge.md now says to use the whole range and not to round a 55 up to 70,
which is the part that actually moves the distribution.

Cost: solved the mix from two observed reviews rather than guessing — ~70% of spend
is output tokens (mostly xhigh thinking) at opus's $25/M, only ~30% cache reads. So
attackers moved to sonnet at `high` thinking and the judge kept opus at `xhigh`,
projecting ~$6–8 from $14–17. Recorded in [[scv]] that model and thinking must move
together: sonnet declares only `max` in its thinkingLevelMap and pi's clamp walks
forward, so `xhigh` on sonnet resolves UP to `max`. Also dropped the cross-cut
per-file ledger (~20k output tokens on a large PR, for coverage accounting
coverage.json never read).

## 2026-08-06 — Client analytics events API (ENG-12206)

Added a "Backend client events API" section to [[feature-flags-and-analytics]].
New endpoint `POST /api/analytics/v1/events` (commit 463c5df1d9): client
libraries record caller-named Amplitude events with a Sift API key; the
backend decorates with org, user, client, and environment. MCP server is the
first consumer; names are free-form by explicit decision (Evan), validated
for length and printability only.

## 2026-08-06 — ENG-12206 review round: allowlisted event names

Code review flagged that free-form names made the per-(org, event) budget,
Prometheus labels, and Amplitude event types unbounded. Evan switched the
design to a closed allowlist: `User called MCP tool <tool>` for the 35 tools
in the sift MCP catalog, mirrored into `mcpToolNames` in the handler.
Updated the [[feature-flags-and-analytics]] section accordingly.

## 2026-08-25/26 — Full wiki audit + staleness cleanup

Audited whether the wiki is still worth keeping (Evan asked; answer: yes).
Method: per-page drift measured as azimuth commits touching frontmatter
sources since each page's `updated` date, then four subagents verified the
six highest-drift pages claim-by-claim against main.

Results: [[skills]] fully accurate despite 28 commits of source drift.
[[dev-commands]], [[worker-service-pattern]], [[integration-tests]], and
[[sift-domain-concepts]] mostly accurate with specific stale or wrong claims,
now fixed. [[reactor-adding-tools]] was the hazard (96 commits of drift):
proto tag 7 is reserved (next free input 9 / output 11, numbering diverged),
write previews are a typed proto oneof plus a tool_approval.go case (not a
JSON map), and new ResourceRef variants must be wired into BucketRefs and
access.go CheckResourceRefs or they silently bypass the access check. All
corrected, plus the renames: CalculatedChannelReadWriter / RuleReadWriter,
marshalToolJSON, GuideContent + subguides, the schemas package,
newProductionChatToolRegistry, and the frontend move to
useAgentResourceLookups.ts (LoadingFlags → ResourceLoadingFlags).

Dropped all proto line-number citations from [[sift-domain-concepts]] — the
fastest-rotting detail; four of eight ranges were already stale. Family
unstable marker removed (public since 2026-07, e3938ba606); reports now carry
ReportType (RULE_EVALUATION | CANVAS, canvas merge ce36ead611); the MCP
catalog grew list_annotations, list_rule_versions,
list_report_rule_summaries, list_report_templates, list_users.

Structural finding: check-stale's changed-files mode only sees my own diffs,
and every damaging error came from teammates' commits. Added
`check-stale --drift`: counts commits per page source since the page's
updated date; run from the azimuth checkout. First run flags
chat-service-goroutine-safety (12) and chat-event-types (7) as next to
re-verify.

Housekeeping: wiki now has a remote (github.com/evan-sift/wiki); previously
uncommitted work is committed and pushed.
