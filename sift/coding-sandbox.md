---
title: coding-sandbox
tags: [chat, sandbox, agents, backend]
sources:
  - path: containers/coding_sandbox/
    last_read: 2026-06-18
  - path: services/chat/sandbox/
    last_read: 2026-06-18
  - path: services/chat/v1/chat_service.go
    last_read: 2026-06-11
  - path: web-service/docker.local.env
    last_read: 2026-06-11
  - path: database/migrations/
    last_read: 2026-06-30
created: 2026-06-11
updated: 2026-06-30
last_accessed: 2026-06-30
---

The Sift Agents Coding Sandbox (ENG-12084 PoC) is a local Docker container
running opencode + the Sift CLI/MCP server + a pre-baked Python analysis stack.
It lets the /agents chat surface run real data analysis against Sift without any
model code changes on the main agentic loop path.

## Container (containers/coding_sandbox/)

`run.sh` builds and starts the container. `SIFT_PROFILE` selects which
sift-cli profile is injected (default: `localdev`). The container listens on
`http://localhost:4096` (the opencode server REST/SSE API).

`smoke.sh` runs five checks against a live container: process, API reachability,
session creation, prompt dispatch, and MCP tool connectivity.

Artifacts the agent writes land in `./workspace/` on the host. opencode silently
strips config fields that don't match its schema; smoke test check [4/5] exists
to catch that class of regression.

### Image build (tranche 2, 2026-06-18)

The image is now a repo-root bake target — `coding-sandbox` in `docker-bake.hcl`,
built like `python-runner` (CI job in `prep_deploy_images.yml`, AMD64 for runsc
nodes; `.dockerignore` allowlists `containers/coding_sandbox`). `run.sh` builds
the same image from the repo root (`-f Dockerfile "$REPO_ROOT"`).

It is **read-only-rootfs compatible**: the venv and baked config/skills live
under `/opt/coding-sandbox`; the entrypoint materializes config + skills into the
writable `$HOME`/`$XDG_*` mounts on startup and writes `sift.toml` from the
injected key. Runs as UID 10001. This is the image the per-conversation leased
pods will run (off a node/opencode base, not the FIPS python base — opencode
can't ride python-runner's chainguard `python-fips` base).

## Go relay (services/chat/sandbox/)

The relay sits between the ChatService and the opencode container. It translates
opencode bus events into `ChatResponse` stream events consumed by [[chat-cli]]
and the /agents UI.

### SSE envelope gotcha

opencode exposes two SSE endpoints with different envelope keys:

- `GET /api/event` uses `"data"` as the payload key (opencode REST API, used
  by the opencode CLI attach command).
- `GET /event` uses `"properties"` as the payload key (the bus the relay
  subscribes to via `Client.Events`).

`BusEvent.Properties` in `client.go` reflects this; using `"data"` here was an
early bug (fixed in ENG-12084).

### Key types

- `Client` — HTTP client for the opencode REST/SSE API (`client.go`).
- `SandboxResolver` — maps a conversation to the `*Client` for its sandbox pod
  (`resolver.go`), resolved once per turn in `HandleTurn`. `fixedResolver`
  returns one shared client (localdev / `CHAT_SANDBOX_URL`); the cluster impl
  (in progress) reattaches or provisions the conversation's leased pod.
  `NewRelay(*Client)` wraps a `fixedResolver`; `NewRelayWithResolver` is the
  cluster seam.
- `Relay` — maps conversations to opencode sessions, owns the session registry
  and per-conversation pending-question state (`relay.go`).
- `Translator` — translates one turn's bus events into `ChatResponse` protos
  (`translate.go`). Not safe for concurrent use; driven serially by the relay's
  event loop.
- `PendingQuestion` — records the in-flight `question.asked` state while the
  relay is paused waiting for a user answer.

### Relay pause/resume via /question

When opencode emits `question.asked`, the translator returns a
`RequestUserInputEvent` and sets `PendingQuestion`. The relay stops pumping
events and returns `TurnResult{Paused: true}`. The chat service then emits
`TurnComplete` and returns to the client.

On the next turn, the client sends a `RequestUserInputResponse`. The relay calls
`POST /question/{id}/reply` with the mapped answers (opencode answers by option
label), clears the pending state, and resumes the event loop.

### CHAT_SANDBOX_URL branch in chat_service.go

When `CHAT_SANDBOX_URL` is non-empty, `web-service/main.go` constructs a
`sandbox.Relay` and passes it to `chat.WithSandboxRelay`. Inside `HandleChat`,
when the relay is set and the request uses the default (agents) profile, the
call is routed to `handleSandboxTurn` instead of the stock agentic loop. The
relay owns all content events; the service emits `TurnStart` and `TurnComplete`
as normal. Errors from the relay are surfaced as `ErrorEvent` in the stream.

## Persistence & provenance (Tranche A, shipped 2026-06-12)

Relay turns are persisted to the DB at turn end via `AppendChatMessages` using
the same stock-shaped row format as the main agentic loop. `GetConversation` and
page reload now show full history; `TurnCompleteEvent.messages` is the canonical
list.

ResourceRefs are extracted from sift MCP tool outputs (`list_assets`,
`list_runs`, `list_channels`, `get_data`) and attached to tool result messages
and the corresponding persisted rows. This is the same self-reported provenance
fidelity as the stock loop; API-attested provenance is Tranche C.

New schema additions:
- Proto field `ChatMessageInternalMetadata.sandbox_external_id` (server-only,
  maps a persisted row back to the opencode message ID).
- Migration `chat_conversations.sandbox_state JSONB`: captures model/agent/
  provider switch events so they can be re-applied when a fresh opencode session
  is created after a backend restart.

### Recap re-seed

When the backend restarts, the in-memory session map is wiped but DB rows
survive. On the next turn the relay detects no active session and re-seeds a
fresh opencode session with a bounded transcript recap built from persisted rows.
The agent regains context without requiring user action. Model/agent/provider
settings captured in `sandbox_state` are re-applied via `POST /session {model,
agent}` at re-seed time.

## Permission HITL (Tranche A, shipped 2026-06-12)

opencode emits `permission.asked` when a tool matches the `"ask"` policy. The
relay translates this into a `ToolApprovalRequestEvent`, pauses the turn, and
exposes an approval gate at `POST /permission/{id}/reply`. A
`TOOL_APPROVAL_REQUEST` row is persisted. The `/agents` UI surfaces an approval
card; approve/reject resumes the opencode turn.

The gated MCP tool is `sift_upload_dataset`, verified live (including after a
prior bash round within the same conversation).

**Prefixed-key gotcha**: opencode keys MCP-tool permissions by the
server-prefixed tool name. `"sift_upload_dataset": "ask"` fires correctly;
`"upload_dataset": "ask"` (un-prefixed) parses but never fires. Per-pattern bash
maps (`{"sift-cli import*": "ask", "*": "allow"}`) likewise parse but never fire
— the `"*": "allow"` fallback wins. bash-mediated writes are therefore NOT gated;
the AGENTS.md confirm-first rule is their only guardrail until Tranche B ships
server-side enforcement.

**Approval follow-up text**: the opencode permission reply carries only
once/always/reject, no text payload. A `tool_approval_response` that includes
`follow_up_text` is rejected by the relay as InvalidArgument. The frontend's
"Do something else" button therefore errors on sandbox approvals; send follow-up
intent as a separate message after the approval resolves.

## Key gotchas

- **docker restart vs compose recreate**: `docker restart` does NOT re-read env
  files. `CHAT_SANDBOX_URL` is baked at container creation. Always use
  `docker compose ... up -d` to pick up env changes.
- **opencode silently strips invalid config**: if the MCP smoke check fails, a
  config field mismatch is the first suspect.
- **Question round-trip works headless**: the relay has been tested via
  `chat-cli` without a browser; the picker renders in the TUI and the resume
  path works.
- **Input-token counts look low**: opencode `step-finish` parts only report
  non-cache tokens; prompt cache reads are not reflected.
- **Empty/invalid CEL filter → backend 500**: a non-boolean CEL expression
  (e.g. `""`) hits Postgres error 22P02 which `web-service/model/list_entities.go`
  surfaces as Internal 500 instead of InvalidArgument. Pre-existing gap exposed
  by the sandbox agent. AGENTS.md steers the agent to omit empty filters; the
  durable fix (bool-type check + 22P02 mapping) is a separate backend change.

## UCE execution substrate (ENG-12084 tranche 2, 2026-06-18)

The sandbox now runs as an **AGENT `UserCodeExecution`** dispatched through pyworker (the "UCE is the execution substrate" model), not a single fixed `CHAT_SANDBOX_URL` server. Enabled by `CHAT_SANDBOX_LEASING=true`.

Flow: relay → `UCEResolver.Resolve(conv)` reattaches a live lease or (cold) enqueues an AGENT UCE + `sandbox_leases` row → pyworker `runNextJob`/`evaluateUserCodeExecution` dispatches AGENT to `SandboxLauncher` (docker local / on-demand k8s Pod via `buildHardenedPodSpec`) → the worker reports its endpoint through `UpdateUserCodeExecution{sandbox_endpoint,sandbox_pod_ref}` → the UCE service registers it on the lease (`RegisterSandboxLeaseEndpointForUCE`) and removes the UCE from the active queue → the resolver polls `lease.endpoint` and returns the client.

Key pieces:
- **`sandbox_leases`** (migration `20260618000000`): per-conversation serving-state, FKs to chat_conversations(CASCADE)/orgs/UCE(SET NULL), unique `pod_ref` (cross-conversation isolation), status enum `BUSY|IDLE|AWAITING_HUMAN`.
- **Lease state machine** is driven by the turn lifecycle (`relay.markBusy/markIdle/markAwaitingHuman` via the `LeaseActivity` hook): a HITL pause → `AWAITING_HUMAN`, which the reaper spares from the 10m idle TTL (own ~60m cap).
- **`LeaseReaper`** sweeps idle/wedged-busy/awaiting-human-hard-cap leases and evicts the relay's in-memory maps via `OnReap` → `Relay.Evict`.
- **Scoped token**: the dequeue's transient per-user key is the sandbox `SIFT_API_KEY` (not the admin key); credential patterns are redacted from command text (`redactCredentials`).
- **Gotcha (fixed via live test):** AGENT executions must NOT be requeued after launch (requeue re-arms the `is_executing=false` claim → re-dequeue → double-launch); pyworker skips requeue for AGENT and the UCE leaves the active queue on endpoint registration.

Localdev: `pyworker` launches the `azimuth/coding-sandbox` image on the compose network (`CODING_SANDBOX_IMAGE_NAME` + `CODING_SANDBOX_NETWORK`, own vars so rule/canvas dispatch is untouched). Live e2e: `web-service/model/sandbox_e2e_manual_test.go` (`SANDBOX_E2E_MANUAL=1`).

Open (plan's gated items): D12 cold-path transparent re-prompt (opencode replay/permission spike) and D13 backend-committed writeback approval (needs sandbox writebacks re-modeled as stock write actions — `ToolApprovalAction` has no validated payload for `GetWriteTool().Commit()`).

## Warm-pool autoscaling (Plan B, ENG-12084, 2026-06-30)

Later work supersedes the `sandbox_leases`/`LeaseReaper` model above with
`agent_pod_leases` (migration `20260627000000`): one active lease per
conversation, tracking `pod_endpoint` + `last_heartbeat_at` directly instead of
a status-enum lease table. Migration `20260630000000_eng_12084_agent_pool_scale_and_session_secret`
adds:

- `agent_pod_leases.session_secret TEXT` — opaque per-session token minted by
  the pod, checked by the pod-driven release endpoint before it's allowed to
  end its own UCE (plaintext for now; hashing/rotation is a follow-up).
- `agent_pool_scale_metric(buffer int) RETURNS int` — `SECURITY DEFINER`,
  RLS-safe count of queued AGENT work + active leases + a buffer, read by a
  KEDA `postgresql` ScaledObject trigger (KEDA's raw DB connection sets no
  `app.*` GUCs, so it needs a definer function to see across orgs).
- `release_stale_agent_leases(idle interval) RETURNS TABLE(user_code_execution_id uuid)` —
  `SECURITY DEFINER` crash backstop: flips stale-heartbeat active leases to
  `released` and returns their UCE ids so a backend sweeper can end them.
- Both functions are granted to `sift_read_write_user` (the `postgres.api_username`
  in `ops/kubernetes/klu/apps/_vars/defaults.yaml`); neither table sets `FORCE
  ROW LEVEL SECURITY`, so the definer (owned by the migration role, which owns
  the tables) bypasses RLS as intended. Note: `sift_read_write_user` does not
  exist in the plain local docker-compose bootstrap (`read_write_user` does);
  it is granted conditionally on-prem via migration `20251031112125_eng_4411`.

KEDA scale-down is intentionally disabled (`scaleDown.selectPolicy: Disabled`)
so autoscaling never deletes a leased pod — reclamation is this sweeper plus
the pod's own clean idle-exit plus the existing stale-execution reaper.

## See also

- [[chat-event-types]] — the `ChatResponse` stream the relay produces; the
  sandbox relay (`services/chat/sandbox`) is an alternative producer.
- [[chat-cli]] — the Go test harness that renders relay output in the terminal.
- [[chat-service-goroutine-safety]] — cancellation contract the relay depends on.
