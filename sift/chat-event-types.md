---
title: Adding Chat Event Types
tags: [chat, backend, architecture]
sources:
  - path: protos/sift_internal/chat/v1/chat.proto
    last_read: 2026-05-21
  - path: services/chat/llm/types.go
    last_read: 2026-04-18
  - path: services/chat/llm/complete.go
    last_read: 2026-04-18
  - path: services/chat/llm/bedrock_gateway.go
    last_read: 2026-04-18
  - path: services/chat/v1/chat_service.go
    last_read: 2026-05-21
created: 2026-04-18
updated: 2026-07-06
last_accessed: 2026-07-06
---

Recipe for adding a new streaming event type to the Sift Reactor chat service —
e.g. a new LLM provider capability like "extended thinking," a richer tool-call
variant, or a provider-side progress signal. Distilled from PR #10707
(ENG-10323, "reactor thinking") which added `ThinkingChunkEvent` end to end.
For the current code at each layer, query codegraph; worked examples with full
Go/proto excerpts live in this page's git history.

## The 3-layer architecture

Every chat event touches three parallel layers; a new type lands in all three
in lockstep:

1. **Proto wire** — `protos/sift_internal/chat/v1/chat.proto`
   - `ChatResponse.event` oneof carries streaming events to clients.
   - `ChatMessage` is the client-visible persisted form.
   - `ChatMessageInternalMetadata` is the server-only sibling (signatures,
     provider IDs, cache markers). `StoredChatMessage` envelopes both.
   - Rule: **never** put server-only data on `ChatMessage`.

2. **Provider-agnostic LLM layer** — `services/chat/llm/`
   - `ContentType` enum + `ContentBlock` tagged union — the multi-turn replay
     shape, independent of any specific provider.
   - `EventType` enum + `StreamEvent` tagged union — the streaming event shape.
   - Per-gateway files (`bedrock_gateway.go`, future providers) translate
     between provider SDK types and these internal types in both directions.
   - `complete.go` accumulates a stream into a `CompletionResponse`.

3. **Chat service** — `services/chat/v1/chat_service.go`
   - `consumeStream` translates `llm.StreamEvent` → `ichatv1pb.ChatResponse`
     wire events.
   - `HandleChat` runs the agentic loop and owns persistence: assembles
     `StoredChatMessage` envelopes (`Message` = client-visible, `Metadata` =
     server-only) to append to the conversation.
   - `chatMessageToLLM` rehydrates stored messages back into `llm.Message` on
     resume. This is the symmetric inverse of the event/persistence path.
   - Cancellation is a special case: if the request context is canceled, the
     service drops the whole turn and returns a wrapped `context.Canceled`
     error from `HandleChat`, but `consumeStream` must not emit a client-visible
     `ErrorEvent` for that cancellation.

## Taxonomy: which flavor of event?

Ask up front which bucket your new type falls into — the work scales with it:

- **Streaming-only** (fire-and-forget chunk, no persistence, no replay).
  Examples: `TextChunkEvent`, a hypothetical `ProgressEvent` or
  `CitationEvent`. Touches proto + LLM layer + `consumeStream` + client
  rendering. **3 files.**
- **Streaming + tool invocation** (multi-stage: start → args → result).
  Example: `ToolCallStartEvent` / `ToolCallResultEvent`. Adds a
  `ContentToolUse` / `ContentToolResult` block that must replay, plus a
  service-side tool executor. **Same 3 files plus the tool runner and
  persistence of `ToolCallInfo` / `ToolResultInfo` on `ChatMessage`.**
- **Streaming + persisted + multi-turn replay** (round-trips on resume).
  Example: `ThinkingChunkEvent`. Adds everything above plus
  `ChatMessageInternalMetadata` fields, `chatMessageToLLM` rehydration, and
  block-ordering rules the provider enforces (thinking blocks must precede
  text/tool_use blocks so the provider can verify the signature).
- **Streaming + persisted + human resume** (terminal pause before replay).
  Example: `ToolApprovalRequestEvent`. Adds a terminal stream event, persisted
  request/response messages, strict resume validation, and a model-visible tool
  result for every staged action after the human responds.

## Adjacent surface: typed tool payloads

Not every `chat.proto` change is a new stream event. Tool definitions also add
typed `ToolInput`, `ToolOutput`, and `ResourceRef` variants (converter cases in
`services/chat/v1/tool_proto_converter.go`, registry/profile wiring in
`services/chat/tools` and `services/chat/context` — see
[[reactor-adding-tools]]). A tool's output should be a trimmed tool-facing
result shape, not the full service proto; avoid persisting or streaming tenant
IDs, user IDs, user notes, metadata, or other service fields the Reactor model
does not need.

## Writeback approval replay rules

Writeback approval (`ToolApprovalRequestEvent`) is a persisted
human-in-the-loop pause for mutable Reactor tools. The rules that keep replay
correct:

- Staged validated actions live in server-only
  `ChatMessageInternalMetadata.tool_approval_actions` on the persisted
  `MESSAGE_ROLE_TOOL_APPROVAL_REQUEST` row; the client-visible request never
  exposes the validated mutation payload.
- On resume, the latest conversation message must still be the matching
  approval request, and every staged action must have exactly one
  approve/reject decision.
- Approved mutable actions re-read the latest entity version before commit; if
  the entity changed since staging, the action fails instead of mutating stale
  state. Rejected and failed actions still return tool results to the model so
  the agent loop continues with complete per-action outcomes.
- The persisted user row carrying `tool_approval_response` is UI history only —
  **skip it when rebuilding provider messages**; the following persisted
  `TOOL_RESULT` row is the actual provider-visible response paired with the
  prior assistant `tool_use` blocks. If the response includes `follow_up_text`,
  it is appended after the tool-result blocks on the same provider-visible user
  message and persisted on the `TOOL_RESULT` row so replay preserves it.

## Decision rubric

Two questions to answer before you start coding:

### Deployment policy vs. per-request knob?

- **Policy** (applies to every completion in this deployment): add a field on
  `BedrockConfig`, wire it from an env var, validate at
  `NewBedrockGateway` time. Example: `ThinkingBudget` from
  `BEDROCK_THINKING_BUDGET` (default `1024`, `0` disables, negatives rejected).
  This is the default for capabilities controlled by ops.
- **Per-request**: add to `CompletionRequest`. Reserve for genuine caller-
  driven choice.

PR #10707 deliberately chose policy for thinking budget — it's an ops-level
cost/quality knob, not a caller concern.

### Flatten-with-warning vs. slice-shaped?

If the provider guarantees "at most one of this thing per response" under
current config, but could change (e.g. enabling an interleaved-thinking beta
later), **flatten** the repeated shape into scalars and add a warning log if a
second one ever appears (see the thinking-signature handling in `complete.go`).
Don't speculatively build a slice-shaped API. This keeps the persistence shape
compact today and makes future config drift loud rather than silent — a much
cheaper posture than carrying a slice API that nothing produces.

## Checklist for a new event type

Recipe A — **streaming-only** (no replay):

1. `chat.proto` — add `FooEvent` message; add it to `ChatResponse.event`
   oneof with the next tag.
2. `make generated`.
3. `services/chat/llm/types.go` — add `EventFoo` to `EventType`, add payload
   field(s) on `StreamEvent`.
4. Each gateway (`bedrock_gateway.go`, future providers) — decode provider
   deltas into `StreamEvent{Type: EventFoo, ...}`.
5. `chat_service.go` `consumeStream` — `case llm.EventFoo:` forwards to the
   wire oneof.
6. `chat-cli/main.go` — add a render case (see [[chat-cli]]). Mind ANSI-reset
   bugs between adjacent event types (this is how the thinking PR discovered a
   dim-escape leak into tool-call lines).
7. Tests: a gateway-level `TestComplete_*` and a service-level `consumeStream`
   test asserting the new wire event fires.

Recipe B — **streaming + persisted + replay** (add these on top of Recipe A):

8. `chat.proto` — client-visible fields on `ChatMessage`; server-only fields
   on `ChatMessageInternalMetadata`. Never mix.
9. `services/chat/llm/types.go` — if the block must replay, add `ContentFoo`
   to `ContentType` and a `Foo *Foo` field on `ContentBlock`.
10. `bedrock_gateway.go` `buildBedrockContentBlocks` — `case ContentFoo:`
    serializes into the provider's request shape.
11. `chat_service.go` `HandleChat` — stash client-visible on `Message`,
    server-only on `Metadata` (use a `fooMetadata()` helper like
    `assistantMetadata`). Insert the new block in the provider-required order
    when building the replay `assistantBlocks`.
12. `chat_service.go` `chatMessageToLLM` — rehydrate from `stored.Message` +
    `stored.Metadata`. Drop-and-warn if paired metadata is missing; never
    hard-fail the replay.
13. Tests, mirroring the thinking set:
    - `TestChatMessageToLLM_FooBlockOrder` — replay block ordering
    - `TestChatMessageToLLM_NoFooBlockWhenEmpty` — empty field ⇒ no phantom
      block
    - `TestChatMessageToLLM_DropsFooWhenMetadataMissing` — fail-soft path
    - `TestChat_FooPersistedToStore` — end-to-end persistence
    - `TestChat_FooReplayedOnResume` — catches cross-turn regressions

## Hard rules (worth not relearning)

- Never put server-only data on `ChatMessage`; always on
  `ChatMessageInternalMetadata`.
- Never piggyback new semantics on an existing event (PR #10707 explicitly
  rejected tucking the thinking signature onto a text delta).
- Never hard-fail replay on a corrupt/missing block — drop-and-warn keeps old
  conversations usable.
- When in doubt about shape, flatten and warn; grow to a slice only when a
  config change actually requires it.

## See also

- [[reactor-adding-tools]] — companion recipe for typed tools and resource refs
- [[project-overview]] — where the chat service fits in the Sift product
- [[dev-commands]] — build/test commands for Go services
- [[coding-sandbox]] — the sandbox relay (`services/chat/sandbox`) is an
  alternative producer of the `ChatResponse` stream, routing agents turns to an
  opencode container instead of the stock Bedrock agentic loop (ENG-12084 PoC).
