---
title: SCV (Sift Coding Vehicles)
tags: [architecture, infrastructure, agents]
sources:
  - path: ops/scv/
    last_read: 2026-06-17
  - path: internal-docs/src/rfcs/rfc-0204-scv/
    last_read: 2026-06-17
created: 2026-06-17
updated: 2026-06-21
last_accessed: 2026-06-21
---

An **SCV** ("Sift Coding Vehicle") is a one-shot, ephemeral GCE VM that runs the [pi.dev](https://pi.dev) coding agent against a pre-baked Azimuth dev environment. A developer mentions `@scv` from Slack or a Linear comment, or asks `@scv-sift` to review a GitHub PR; the ingress service spawns a VM, the agent does the work and opens a draft PR (or posts review comments), and the VM self-destructs. SCV is **new and actively evolving** — RFC-0204 is the design of record, but the live code has already moved ahead of several RFC chapters (see [In-flight / accuracy notes](#in-flight--accuracy-notes)). For depth beyond this overview, read `internal-docs/src/rfcs/rfc-0204-scv/`.

## Why it exists

Routine coding tasks (fix a flaky test, address PR feedback, review a diff) can be dispatched from where the work is already being discussed — Slack, Linear, GitHub — without a developer cloning, booting a stack, and babysitting an agent. Each task gets an isolated, disposable VM with a full running Azimuth stack already warm, so the agent can build, run tests, and iterate against real services. This is distinct from the in-product [[coding-sandbox]] (a local Docker container that powers the `/agents` chat surface); SCV is operator-facing infrastructure that produces PRs, not a chat backend.

Everything lives under `ops/scv/`. The four moving parts are the **ingress** Cloud Run service, the per-VM **driver**, the GCE **image bake**, and a local-loopback **vertex-proxy**.

## Lifecycle (trigger to PR)

1. **Trigger.** The `scv-ingress` Cloud Run service receives a Slack mention, a Linear comment, or a GitHub webhook. It gates the request (HMAC / identity / `scv` prefix / owner checks), resolves a Linear branch name when the task names `ENG-NNNN` (best-effort), writes a run document to Firestore, and creates the per-run Pub/Sub topics.
2. **Spawn.** Ingress calls GCE `instances.insert` for an `e2-standard-8` instance named `scv-{run_id}`, booted from the latest image in the `scv` family by default, or `scv-canary` when the spawn is tagged `scv:canary` (`ops/scv/ingress/src/services/gce.ts`). Run parameters ride along as GCE metadata. A one-shot Cloud Scheduler TTL job is created as a backstop.
3. **Boot.** `startup.sh` (baked into the image, invoked from the instance `startup-script`) reads metadata, authenticates `gh` as the bot, checks out the run branch off `SCV_BASE_BRANCH`, resumes the pre-seeded Docker stack with `docker compose start`, runs the DB migration delta, writes pi's MCP + models config, and writes/starts two systemd units: `vertex-proxy.service` and `scv-pi.service`. It also joins the tailnet as an ephemeral node named for the ticket branch (the ingress sets `ts_hostname` from the Linear `branchName`, e.g. `eng-12084-coding-sandbox-poc`, falling back to `scv-<run_id>`) and publishes the `:3000` dev server via `tailscale serve` — so the URL is memorable and stable across TTL rehydration.
4. **Run.** `scv-driver` (Node) launches `pi --mode rpc`, passing `SCV.md` via `--append-system-prompt`. Pi drives the LLM through the local vertex-proxy and calls bash / edit / read / write / git / gh / Linear-MCP tools. The driver bridges pi's JSONL RPC to Pub/Sub.
5. **Outbound.** The driver publishes events on the global `scv-out` topic; ingress holds a single streaming pull (`scv-out-bot`) and posts them back to the originating Slack thread or Linear comment.
6. **PR.** When pi finishes a turn (`agent_end`), the driver's post-task pipeline commits any stray changes, pushes the branch, and opens a draft PR (`gh pr create --draft`, first time) or pushes follow-ups. Review-thread replies carry the commit SHA.
7. **Teardown.** Agent-mode VMs idle between turns and are reaped by the TTL job (currently 3h, with a sliding refresh on each inbound). pr-review VMs publish `run_complete` and ingress tears the VM down immediately.

The architecture and per-VM diagrams are in `rfc-0204-scv/01-architecture.md`.

## Image bake pipeline

Booting cold (clone, `make build`, `org init`, start pi) would cost 20+ minutes per spawn. Instead, Packer images do that work ahead of time, so VM boot is "pull the image, run `startup.sh`, resume the stopped Docker stack" in roughly 60–90 seconds. The bake is **two-tier** (`ops/scv/packer/`):

- **Foundation** (`foundation.pkr.hcl` → `scv-foundation` family, `make foundation`, ~52 min). The heavy, slow-changing half: `install-deps.sh`/`install-tools.sh` (Docker, Go, Rust, Node 22, `gh`, `gcloud`), then `install-foundation.sh` — pull `sift/base` + `sift/base-rust` from nexus, clone `sift-stack/azimuth`, build the Rust dependency images (`rust-chef`/`rust-binaries`), `make build` all service images, `make up` + seed Postgres via `org init` + `scv-seed`, then `docker compose stop`. The snapshot carries the seeded DB and the warm `rust-target`/`go-build-cache` volumes. Rebake only on dep/toolchain/base-image changes.
- **App** (`scv.pkr.hcl` → `scv` / `scv-canary` family, ~10 min). Built `FROM` the latest `scv-foundation` image. The `image_channel` Packer var (default `canary`) selects the family: **`make bake-canary` → `scv-canary`** (local dev images, the default, so iterating never disturbs the team's deployed images) and **`make bake-stable` → `scv`** (finalized images the deployed ingress boots by default). A botched channel value fails the bake (HCL validation) rather than silently clobbering stable. `install-app-refresh.sh` fetches the latest `SCV_BASE_BRANCH` source, `make generated`, and rebuilds **only the service images** — the `base-rust`/`rust-chef`/`rust-binaries` toolchain targets are pruned (they already exist in the foundation and don't depend on app source, and buildkit's layer cache doesn't survive the GCE snapshot), then recreates the stopped stack against the rebuilt images and applies any migration delta. `install-pi.sh` adds the pi.dev agent layer (driver, `SCV.md`, skills). Source upload is trimmed to `ops/scv/**` via `.bakeignore`.
- **`docker compose stop`, not `down`.** `stop` preserves the named Postgres volume so the seeded DB is captured in the snapshot; `down -v` would discard it (`rfc-0204-scv/02-vm-image-pipeline.md`).
- `spawnSCV` resolves the latest `scv` family member by default, so shipping a driver or `startup.sh` change just needs an app rebake — no image pinning. A spawn tagged **`scv:canary`** instead resolves `scv-canary`: the single `scv:canary` pattern is honoured in the @scv instruction text (parsed + stripped like `base_branch=`), as a Linear issue label, or as a GitHub PR label (`gce.ts` `family = canary ? 'scv-canary' : 'scv'`). Default (untagged) stays stable so the rest of the team is never affected. The spawned VM keeps its `scv-<run_id>` name (the teardown + `scv-*` CLI key) and instead carries a `channel` GCE label (`canary`/`stable`) — `scv-list` shows it, and `gcloud compute instances list --filter="labels.channel=canary"` filters by it. Reaching `nexus.siftstack.net` from the Cloud Build builder requires the SCV Tailscale subnet router (`ops/terraform/scv/tailscale.tf`). Disk is 150 GB in lockstep across foundation, app image, and the runtime VM (`gce.ts diskSizeGb`).
- `SCV.md` (`ops/scv/pi-config/SCV.md`) is the agent's workflow policy, layered on top of the repo's `AGENTS.md` / `CLAUDE.md` files (which it explicitly defers to). Behavior-only changes mean editing `SCV.md` and rebaking — no driver/ingress change.

## Ingress (Cloud Run `scv-ingress`)

A TypeScript Bolt app (`ops/scv/ingress/`) with `min-instances=1` (the streaming Pub/Sub pull must stay alive). It exposes Slack (`/slack/events`), GitHub (`/github/webhook`), and Linear (`/linear/webhook` + `/linear/oauth/*`) routes, plus the `scv-out-bot` outbound pull.

Three operator **surfaces** converge on a shared spawn path:

- **Slack** — `@scv ENG-1234 <task>`. A top-level mention spawns a new run; a mention inside an existing SCV thread is relayed as a follow-up `instruction` rather than spawning a duplicate (`handlers/slack/appMention.ts`).
- **Linear** — `@scv` in an issue comment spawns or resumes a run for that issue; outbound events post back as Linear comments / agent activity so the developer stays in Linear (`handlers/linear/`, `surfaces/linear/adapter.ts`). Linear-agent OAuth tokens live in Secret Manager.
- **GitHub** — three webhook event types feed PR-review mode: `pull_request` (`review_requested` with the bot as requested reviewer), `issue_comment` and `pull_request_review_comment` (both matching `@scv-sift … review`). The same `pull_request_review_comment` stream also carries agent-fix follow-up comments on an SCV's own draft PR.

Outbound rendering is surface-agnostic: the dispatcher applies shared state mutations (run status, `pr_url`, branch sync, session state) then hands an `AgentActivity` to the per-surface adapter (`surfaces/`). The agent-activity union is rich — `session_started`, `thought`, `action` (with phase + structured tool-call payload), `result`, `artifact`, `question`, `error`, `run_complete`, `checkpoint` (`ingress/src/types.ts`). The bot is the single source of `BOT_GITHUB_LOGIN` (currently `scv-sift`); rename = one env-var change.

Operational config is via `gcloud run deploy --set-env-vars` (`GCP_PROJECT_ID`, `GCE_ZONE`, `SCV_VM_SERVICE_ACCOUNT`, `SCV_SCHEDULER_SERVICE_ACCOUNT`, `SCV_BASE_BRANCH`, `BOT_GITHUB_LOGIN`); secrets resolve from Secret Manager at boot. Terraform for the GCP resources is in `ops/terraform/scv/` (plain Terraform, GCS backend, no Terragrunt). See `rfc-0204-scv/03-ingress.md`.

## Sessions vs runs (Firestore)

The data model separates the durable unit of work from a single compute attempt (`ingress/src/types.ts`, `ingress/src/services/firestore.ts`):

- A **`SessionDocument`** (`sessions/{session_id}`) is the long-lived aggregate. It owns the **surface keys** a piece of work appears on (`branch`, `linear_issue_id`, `linear_agent_session_id`, `pr_number`/`pr_url`) and a model-authored `state` digest. Any surface lookup resolves to the same session, which is what unifies resume across Slack / Linear / PR.
- A **`RunDocument`** (`runs/{run_id}`) is one ephemeral VM attempt, pointing at a session via `session_id`. It carries `kind` (`agent` | `pr-review`), `status`, `branch`, `task`, surface coordinates, and PR fields. Invariant: at most one current run per session, enforced by an `is_current` filter; a resumed run mints a new `run_id`, flips the old one's `is_current` to false, and records `resumed_from`.
- **Resume / hydration.** A model-authored **checkpoint** (`SessionState`: summary, decisions, open questions, files touched, next step) is written to `sessions/{id}.state` at phase boundaries. When a TTL-killed session is resumed, `spawnResume` wraps the new task with the prior state so the fresh VM does not redo work.
- **HITL pause.** Pi can publish a `question` outbound and the run goes `awaiting_response`; the next reply on that surface relays without an `@scv` mention, then status restores (`pre_question_status`).

pr-review runs are the exception: they carry no `session_id` and use a single-field `pr_dedupe_key` (`${repo}#${prNumber}@${headSha}`) for idempotent spawn dedupe.

## Agent harness (`scv-driver`)

One Node process per VM (`ops/scv/scv-driver/`) that branches on `SCV_MODE`. The earlier pi-extension design hung pi's event loop and had no reliable steering hook; `pi --mode rpc` (JSONL over stdio, long-lived) fixed both (`rfc-0204-scv/04-agent-harness.md`).

In **agent mode** the driver spawns `pi --mode rpc` for the VM's full life, owns Pub/Sub I/O, and runs the post-task pipeline. Key state: `streaming` (inbound becomes a pi `steer` mid-turn, `prompt` when idle) and **resume detection** (on boot, if a PR already exists for the branch the driver does *not* re-send the initial task — the fix for restart-created-duplicate-PRs). `scv-pi.service` is `Restart=no` on purpose so a crash fails loud rather than spamming Slack.

## pr-review mode

GitHub-triggered, read-only, short-lived. `startup.sh` skips the Docker stack and checks out the PR head SHA detached; the driver short-circuits to `prReview.ts` instead of the agent loop. It resolves prior SCV review threads (GraphQL), runs `scripts/scv-pr-review.sh` (which stages the diff + PR context, then invokes `pi --print` with the **`code-review` pi skill** at `pi-config/skills/code-review.md`), validates the findings JSON, posts one inline comment per finding (with ```` ```suggestion ```` blocks where applicable), aggregates any unanchored findings into a top-level summary, and publishes `run_complete` to trigger teardown. The wrapper trusts the on-disk findings JSON over pi's exit code (a known pi 0.75.5 post-loop quirk) and caps wall time at 45 min. Detail in `rfc-0204-scv/04-agent-harness.md` and `05-github-feedback-loop.md`.

## Vertex proxy

`vertex-proxy.service` (Python, `127.0.0.1:8083`, `ops/scv/vertex-proxy/proxy.py`) exists because Vertex's OpenAI-compatible endpoint returns 404 for current Claude models. It translates pi's Anthropic-Messages requests into Vertex `rawPredict` / `streamRawPredict` calls under `publishers/anthropic/models`, fetching an OAuth token from the VM service account's ADC. The model is selected per-request by pi via `~/.pi/agent/models.json`; the proxy's own fallback default is `claude-sonnet-4-6`.

## Operational commands

From `ops/scv/Makefile`:

- `make foundation` — bake a new `scv-foundation` image (~52 min). Needed only for dep/toolchain/base-image changes.
- `make bake-canary` — bake a new **canary** app image (`scv-canary` family) off the latest foundation (~10 min). The local-dev default; needed for changes to the driver, `startup.sh`, `SCV.md`, skills, or app source. `make bake-stable` does the same but publishes to the `scv` (stable) family the deployed ingress boots — run it to promote a finalized image.
- `make deploy` — build `scv-ingress` at HEAD and roll out a new Cloud Run revision. No rebake needed for ingress-only changes.
- `make sweep` / `make logs` — fire and inspect the orphan-topic GC sweep.

For invoking and babysitting runs locally, `ops/scv/setup-local.sh` installs `scv-list`, `scv-ssh`, `scv-logs`, `scv-tail`, and `scv-stop` shell aliases (IAP-tunneled; needs `gcloud` auth to the SCV project and `roles/iap.tunnelResourceAccessor`). See `ops/scv/README.md`. General Sift dev workflow is in [[dev-commands]]; product context is [[project-overview]].

## In-flight / accuracy notes

SCV moves fast and the code currently leads several RFC chapters. Where they disagree, trust the code:

- **TTL is 3h, not 6h.** `ingress/src/services/scheduler.ts` sets `TTL_WINDOW_MS = 3 * 60 * 60 * 1000` and `refreshTTLJob` slides it forward on every inbound publish so an active run never expires mid-conversation. RFC chapters 01 and 05 still say a flat 6h with no refresh.
- **Sessions, checkpoints, and the `question`/`awaiting_response` HITL pause are live** (per `08-followup.md` Phase 1–3 and confirmed in `types.ts`), and the outbound union is far richer than the small `ready`/`pr_created`/`progress` set in `01-architecture.md`. The Linear webhook surface and Linear-agent OAuth are also shipped, beyond the Slack/GitHub picture in the early chapters.
- **Model.** `01-architecture.md` labels the inference path "Claude Opus 4.7"; the running config is whatever `models.json` pins per request, with the proxy defaulting to `claude-sonnet-4-6`. Treat any single model name in the RFC as illustrative.
- Several cleanup items remain open: orphan per-run Pub/Sub topic GC, a bot-side terminate endpoint, tightening `scv-vm@` Pub/Sub IAM, and the `mcp-remote` Linear-token-in-`ps` leak. See `08-followup.md` for the full list.

## See also

- [[coding-sandbox]] — the in-product local Docker agent for the `/agents` chat surface; SCV is the operator-facing PR-producing counterpart.
- [[reactor-adding-tools]] — how typed agent tools are added on the product side.
- [[chat-event-types]] — the product chat streaming protocol (analogous in spirit to SCV's outbound `AgentActivity` union, but unrelated code).
- [[dev-commands]], [[project-overview]] — general Azimuth dev workflow and product context.
