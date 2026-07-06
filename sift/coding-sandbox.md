---
title: coding-sandbox
tags: [chat, agents, backend]
sources:
  - path: containers/coding_sandbox/
    last_read: 2026-06-18
  - path: services/chat/sandbox/
    last_read: 2026-06-18
  - path: web-service/docker.local.env
    last_read: 2026-06-11
  - path: database/migrations/
    last_read: 2026-06-30
created: 2026-06-11
updated: 2026-07-06
last_accessed: 2026-07-06
---

The Sift Agents Coding Sandbox (ENG-12084) runs opencode + the Sift CLI/MCP
server + a pre-baked Python analysis stack in a container, letting the /agents
chat surface run real data analysis against Sift. The Go relay
(`services/chat/sandbox/`) translates opencode bus events into `ChatResponse`
stream events. Architecture, key types, and turn flow: query codegraph. This
page keeps the gotchas and the supersession history.

## Gotchas

- **SSE envelope keys differ per endpoint.** opencode's `GET /api/event` uses
  `"data"` as the payload key; `GET /event` (the bus the relay subscribes to
  via `Client.Events`) uses `"properties"`. `BusEvent.Properties` in
  `client.go` reflects this; using `"data"` there was an early bug.
- **MCP-tool permissions are keyed by the server-prefixed tool name.**
  `"sift_upload_dataset": "ask"` fires; `"upload_dataset": "ask"` parses but
  never fires. Per-pattern bash maps (`{"sift-cli import*": "ask", "*":
  "allow"}`) likewise parse but never fire — the `"*": "allow"` fallback wins.
  bash-mediated writes are therefore NOT gated; the AGENTS.md confirm-first
  rule is their only guardrail until server-side enforcement ships.
- **Approval replies carry no text.** The opencode permission reply is only
  once/always/reject, so a `tool_approval_response` with `follow_up_text` is
  rejected by the relay as InvalidArgument (the frontend's "Do something else"
  button errors on sandbox approvals). Send follow-up intent as a separate
  message after the approval resolves.
- **`docker restart` does NOT re-read env files.** `CHAT_SANDBOX_URL` and
  friends are baked at container creation. Always use
  `docker compose ... up -d` to pick up env changes.
- **opencode silently strips invalid config** fields that don't match its
  schema. If the MCP smoke check fails, a config field mismatch is the first
  suspect (`smoke.sh` check [4/5] exists for this).
- **AGENT executions must NOT be requeued after launch.** Requeue re-arms the
  `is_executing=false` claim → re-dequeue → double-launch. pyworker skips
  requeue for AGENT; the UCE leaves the active queue on endpoint registration.
  Found via live test.
- **Empty/invalid CEL filter → backend 500.** A non-boolean CEL expression
  (e.g. `""`) hits Postgres error 22P02, which
  `web-service/model/list_entities.go` surfaces as Internal 500 instead of
  InvalidArgument. Pre-existing gap exposed by the sandbox agent; AGENTS.md
  steers the agent to omit empty filters. Durable fix (bool-type check + 22P02
  mapping) is a separate backend change.
- **Input-token counts look low.** opencode `step-finish` parts only report
  non-cache tokens; prompt cache reads are not reflected.

## Supersession history

The execution substrate has been rebuilt twice; older docs/branches reference
superseded models:

1. **Fixed relay (`CHAT_SANDBOX_URL`, 2026-06-11).** One shared local Docker
   container; `web-service` routes default-profile turns to the relay when the
   env var is set. Persistence/provenance (stock-shaped rows,
   `sandbox_external_id` metadata, `sandbox_state` JSONB re-seed) and
   permission HITL shipped in this phase.
2. **UCE leasing (`CHAT_SANDBOX_LEASING=true`, tranche 2, 2026-06-18).**
   Per-conversation AGENT `UserCodeExecution` dispatched through pyworker;
   `sandbox_leases` table (migration `20260618000000`) with status enum
   `BUSY|IDLE|AWAITING_HUMAN` plus a `LeaseReaper`.
3. **Warm-pool autoscaling (Plan B, 2026-06-30) — current.** `agent_pod_leases`
   (migration `20260627000000`) supersedes `sandbox_leases`: one active lease
   per conversation tracking `pod_endpoint` + `last_heartbeat_at`. Migration
   `20260630000000` adds `session_secret` (pod-driven release auth) and two
   `SECURITY DEFINER` functions: `agent_pool_scale_metric(buffer)` (read by a
   KEDA `postgresql` trigger — KEDA's raw connection sets no `app.*` GUCs, so
   it needs a definer function to see across orgs) and
   `release_stale_agent_leases(idle)` (crash backstop). KEDA scale-down is
   intentionally disabled (`scaleDown.selectPolicy: Disabled`) so autoscaling
   never deletes a leased pod. Note: `sift_read_write_user` (granted these
   functions) does not exist in the plain local docker-compose bootstrap
   (`read_write_user` does); it is granted conditionally on-prem via migration
   `20251031112125_eng_4411`.

The container image cannot use python-runner's chainguard `python-fips` base
(opencode needs a node/opencode base); it is read-only-rootfs compatible and
runs as UID 10001.

## See also

- [[chat-event-types]] — the `ChatResponse` stream the relay produces; the
  sandbox relay is an alternative producer.
- [[chat-cli]] — the Go test harness that renders relay output in the terminal.
- [[chat-service-goroutine-safety]] — cancellation contract the relay depends on.
