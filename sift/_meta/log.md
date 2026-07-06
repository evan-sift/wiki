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
