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
  - path: services/chat/conversation/types.go
    last_read: 2026-04-18
created: 2026-04-18
updated: 2026-06-11
last_accessed: 2026-05-21
---

Recipe for adding a new streaming event type to the Sift Reactor chat service —
e.g. a new LLM provider capability like "extended thinking," a richer tool-call
variant, or a provider-side progress signal. Distilled from PR #10707
(ENG-10323, "reactor thinking") which added `ThinkingChunkEvent` end to end.

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

## Adjacent surface: typed tool payloads

Not every `chat.proto` change is a new stream event. Tool definitions also add
typed `ToolInput`, `ToolOutput`, and `ResourceRef` variants. ENG-11049 added
`list_calculated_channels` with `ListCalculatedChannelsInput`,
`ListCalculatedChannelsOutput`, and `CalculatedChannelRef`, plus converter cases
in `services/chat/v1/tool_proto_converter.go` and registry/profile wiring in
`services/chat/tools` and `services/chat/context`. Its output is a trimmed
tool-facing result shape, not the full calculated-channel service proto; avoid
persisting or streaming tenant IDs, user IDs, user notes, metadata, or other
service fields the Reactor model does not need.

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
  block-ordering rules the provider enforces.
- **Streaming + persisted + human resume** (terminal pause before replay).
  Example: `ToolApprovalRequestEvent`. Adds a terminal stream event, persisted
  request/response messages, strict resume validation, and a model-visible tool
  result for every staged action after the human responds.

## Three worked examples from the repo

### Example 0 — `ToolApprovalRequestEvent` (writeback pause)

Writeback approval is a persisted human-in-the-loop pause for mutable Reactor
tools. The backend stages validated actions into server-only
`ChatMessageInternalMetadata.tool_approval_actions` on the persisted
`MESSAGE_ROLE_TOOL_APPROVAL_REQUEST` row, emits a terminal
`tool_approval_request`, and waits for a later `tool_approval_response`. The
client-visible approval request carries an `approval_request_id`, persisted
`message_id`, and one or more `ToolApprovalAction`s; it does not expose the
validated mutation payload.

On resume, the latest conversation message must still be the matching approval
request, and every staged action in that message metadata must have exactly one
approve or reject decision. Approved mutable actions re-read the latest entity version before
commit; if the rule or calculated-channel version changed since staging, the
action fails instead of mutating stale state. Rejected and failed actions are
returned to the model as `WritebackActionOutput` tool results so the agent loop
can continue with complete per-action outcomes.

Replay detail: the persisted user row that carries `tool_approval_response` is
for UI history only. It must be skipped when rebuilding provider messages; the
following persisted `TOOL_RESULT` row is the actual provider-visible response
paired with the prior assistant `tool_use` blocks. If the approval response
includes `follow_up_text`, the service appends that text after the tool-result
blocks on the same provider-visible user message and persists it on the
`TOOL_RESULT` row content so replay preserves the instruction.

### Example 1 — `TextChunkEvent` (streaming-only baseline)

The simplest possible event. Model emits a text delta, service forwards it to
the client.

**Proto** (`chat.proto`):

```proto
message ChatResponse {
  oneof event {
    TextChunkEvent text_chunk = 1;
    // ...
  }
}

message TextChunkEvent {
  string text = 1;
}
```

**LLM layer** (`services/chat/llm/types.go`):

```go
const (
    EventTextDelta EventType = iota
    // ...
)

type StreamEvent struct {
    Type      EventType
    TextDelta string // populated when Type == EventTextDelta
    // ...
}
```

**Bedrock gateway** (`bedrock_gateway.go`) — decode provider delta:

```go
case *brtypes.ContentBlockDeltaMemberText:
    ch <- StreamEvent{Type: EventTextDelta, TextDelta: delta.Value}
```

**Chat service** (`chat_service.go` `consumeStream`) — forward to wire:

```go
case llm.EventTextDelta:
    text.WriteString(ev.TextDelta)
    if err := sender.Send(&ichatv1pb.ChatResponse{
        Event: &ichatv1pb.ChatResponse_TextChunk{
            TextChunk: &ichatv1pb.TextChunkEvent{Text: ev.TextDelta},
        },
    }); err != nil {
        return nil, err
    }
```

Persistence is trivial — the accumulated `text.String()` ends up on
`ChatMessage.content` when the turn completes.

### Example 2 — Tool call events (multi-stage streaming)

Tools stream in three phases: start (name + id), deltas (JSON args), stop.
The service batches them up, runs the tool, and emits a single
`ToolCallResultEvent` to the client.

**Proto** (`chat.proto`):

```proto
message ChatResponse {
  oneof event {
    // ...
    ToolCallStartEvent tool_call_start = 4;
    ToolCallResultEvent tool_call_result = 5;
  }
}

message ToolCallStartEvent {
  string tool_call_id = 1;
  string name = 2;
}

message ToolCallResultEvent {
  string tool_call_id = 1;
  google.protobuf.Value result = 2;
  bool is_error = 3;
}
```

Persisted on `ChatMessage` as structured blocks (not free text):

```proto
message ChatMessage {
  string role = 1;
  string content = 2;
  repeated ToolCallInfo tool_calls = 3;    // on assistant messages
  repeated ToolResultInfo tool_results = 4; // on tool_result-role messages
}
```

**LLM layer** — three event types, three content-block types:

```go
const (
    EventToolUseStart EventType = iota
    EventToolUseDelta
    EventToolUseStop
    // ...
)

const (
    ContentToolUse ContentType = iota
    ContentToolResult
    // ...
)

type ContentBlock struct {
    Type       ContentType
    ToolUse    *ToolUse    // when Type == ContentToolUse
    ToolResult *ToolResult // when Type == ContentToolResult
    // ...
}
```

**Chat service** — the agentic loop in `HandleChat`:

```go
// If the LLM didn't request tools, we're done with the agentic loop.
if resp.StopReason != "tool_use" || len(resp.ToolUses) == 0 {
    turnMessages = append(turnMessages, assistantStored)
    turnCompleted = true
    break
}

// Execute each tool and build tool_result blocks for the next LLM call.
for _, tu := range resp.ToolUses {
    // ... run tool, collect result ...
    sender.Send(&ichatv1pb.ChatResponse{
        Event: &ichatv1pb.ChatResponse_ToolCallResult{
            ToolCallResult: &ichatv1pb.ToolCallResultEvent{ /* ... */ },
        },
    })
}
```

Key pattern: tool-use blocks must round-trip to the provider on the next
agentic-loop iteration, paired with a `user`-role message containing the
`ContentToolResult` blocks. The content-block tagged union is what makes this
provider-agnostic.

### Example 3 — `ThinkingChunkEvent` (streaming + persisted + multi-turn)

The fullest case: deltas stream to the client, a separate signature event
carries an opaque verification token, both get persisted, and on resume the
thinking block must be rehydrated in a specific order paired with its
signature — or Bedrock rejects the request.

**Proto** — wire event + persistence split:

```proto
message ChatResponse {
  oneof event {
    // ...
    ThinkingChunkEvent thinking_chunk = 6;
  }
}

message ThinkingChunkEvent {
  string text = 1;
}

// Client-visible.
message ChatMessage {
  // ...
  string thinking = 5;
}

// Server-only sibling — never returned on the wire.
message ChatMessageInternalMetadata {
  string thinking_signature = 1;
}

// On-disk envelope pairing the two.
message StoredChatMessage {
  ChatMessage message = 1;
  ChatMessageInternalMetadata metadata = 2;
}
```

Note that the **signature is a separate stream event**, not piggybacked on a
text delta. This was a deliberate design choice in #10707.

**LLM layer** — new content-block kind + two stream events:

```go
const (
    // ...
    ContentThinking
)

type ContentBlock struct {
    Type     ContentType
    // ...
    Thinking *Thinking // when Type == ContentThinking
}

type Thinking struct {
    Text      string
    Signature string // must echo back unmodified on multi-turn
}

const (
    // ...
    EventThinkingDelta
    EventThinkingSignature
)

type StreamEvent struct {
    Type              EventType
    // ...
    ThinkingDelta     string // when Type == EventThinkingDelta
    ThinkingSignature string // when Type == EventThinkingSignature
}
```

**Bedrock gateway** — enable via `AdditionalModelRequestFields`, decode
reasoning deltas, serialize replay blocks:

```go
// Enable extended thinking when the gateway is configured with a budget.
// Bedrock exposes this via AdditionalModelRequestFields (no first-class SDK field).
if g.thinkingBudget > 0 {
    input.AdditionalModelRequestFields = brdocument.NewLazyDocument(map[string]any{
        "thinking": map[string]any{
            "type":          "enabled",
            "budget_tokens": g.thinkingBudget,
        },
    })
}

// Decode stream deltas.
case *brtypes.ContentBlockDeltaMemberReasoningContent:
    switch rc := delta.Value.(type) {
    case *brtypes.ReasoningContentBlockDeltaMemberText:
        ch <- StreamEvent{Type: EventThinkingDelta, ThinkingDelta: rc.Value}
    case *brtypes.ReasoningContentBlockDeltaMemberSignature:
        ch <- StreamEvent{Type: EventThinkingSignature, ThinkingSignature: rc.Value}
    }

// Serialize for replay.
case ContentThinking:
    if b.Thinking == nil {
        continue
    }
    result = append(result, &brtypes.ContentBlockMemberReasoningContent{
        Value: &brtypes.ReasoningContentBlockMemberReasoningText{
            Value: brtypes.ReasoningTextBlock{
                Text:      &b.Thinking.Text,
                Signature: &b.Thinking.Signature,
            },
        },
    })
```

**Chat service** — forward to wire, persist into the right place, rehydrate:

```go
// consumeStream: wire forwarding + server-side accumulation.
case llm.EventThinkingDelta:
    thinking.WriteString(ev.ThinkingDelta)
    sender.Send(&ichatv1pb.ChatResponse{
        Event: &ichatv1pb.ChatResponse_ThinkingChunk{
            ThinkingChunk: &ichatv1pb.ThinkingChunkEvent{Text: ev.ThinkingDelta},
        },
    })

case llm.EventThinkingSignature:
    if signatureSeen {
        // Interleaved-thinking canary — see "flatten-with-warning" below.
        slog.WarnContext(ctx, "multiple thinking signatures in one response; flattening", ...)
    }
    thinkingSignature = ev.ThinkingSignature
    signatureSeen = true

// HandleChat: persist into Message vs Metadata.
assistantMsg := &ichatv1pb.ChatMessage{
    Role:     "assistant",
    Content:  resp.Text,
    Thinking: resp.ThinkingText, // client-visible
}
assistantStored := &ichatv1pb.StoredChatMessage{
    Message:  assistantMsg,
    Metadata: assistantMetadata(resp.ThinkingSignature), // server-only
}

// HandleChat: multi-turn replay — block order matters.
// Thinking blocks must precede text/tool_use blocks so the provider can verify
// the signature against the paired tool_use.
if resp.ThinkingText != "" {
    assistantBlocks = append(assistantBlocks, llm.ContentBlock{
        Type:     llm.ContentThinking,
        Thinking: &llm.Thinking{Text: resp.ThinkingText, Signature: resp.ThinkingSignature},
    })
}
// ... then text, then tool_use blocks.

// chatMessageToLLM: rehydrate on resume. Fail soft on missing signature.
if m.Thinking != "" {
    var sig string
    if meta != nil {
        sig = meta.ThinkingSignature
    }
    if sig == "" {
        slog.Warn("dropping thinking block with missing signature from replay", ...)
    } else {
        blocks = append(blocks, llm.ContentBlock{
            Type:     llm.ContentThinking,
            Thinking: &llm.Thinking{Text: m.Thinking, Signature: sig},
        })
    }
}
```

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
second one ever appears. Don't speculatively build a slice-shaped API.

```go
// complete.go pattern.
if signatureSeen {
    slog.WarnContext(ctx, "multiple thinking signatures in one response; flattening",
        "previous_signature_len", len(resp.ThinkingSignature),
        "new_signature_len", len(ev.ThinkingSignature),
    )
}
resp.ThinkingSignature = ev.ThinkingSignature
signatureSeen = true
```

This keeps the persistence shape compact today and makes future config drift
loud rather than silent — a much cheaper posture than carrying a slice API
that nothing produces.

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
