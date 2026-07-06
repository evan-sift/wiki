---
title: Chat Service Goroutine Safety
tags: [chat, backend]
sources:
  - path: services/chat/v1/chat_service.go
    last_read: 2026-05-21
  - path: services/chat/v1/keepalive.go
    last_read: 2026-05-01
created: 2026-05-01
updated: 2026-05-16
last_accessed: 2026-05-21
---

Rules for spawning goroutines inside `HandleChat`. Violations cause silent turn
loss (no TurnComplete, no DB writes) or process-crashing nil pointer panics.

## The invariant

**`HandleChat` is the sole owner of the `EventSender`.** Any goroutine that
calls `sender.Send(...)` after `HandleChat` returns will dereference a nil
`http.ResponseWriter` and panic, crashing the entire service process.

Go does not recover panics in goroutines by default; an unrecovered panic in
any goroutine kills the whole process.

## History: the title goroutine that proved the point

This file used to document the inline title-generation goroutine as the
canonical example of the failure mode. Commit `8736201f65` changed the title
goroutine to call `persistAndEmitTitle(persistCtx, sender, ...)` directly,
which reached `sender.Send` from the background. The goroutine raced with the
handler return. When it lost, the result was a `net/http.(*response).FlushError`
nil pointer panic — the entire HTTP stream tore down without sending
`TurnComplete` and without persisting messages.

ENG-11429 removed the inline title goroutine entirely. Title generation now
runs as a separate, stateless `ChatService.Chat` call against the
`title_generator` profile — fired in parallel from the worker, never coupled
to the main turn's `HandleChat` lifetime. The class of bug this page used to
document can no longer occur in the title path because there is no shared
`sender` between the two turns. See [[chat-event-types]] for the broader event
architecture and the new profile registration sites.

## Correct pattern when a goroutine IS unavoidable

The general rule still applies: when you must compute on a goroutine, use a
buffered channel for the result and let the main goroutine own all
`sender.Send` calls.

```go
// GOOD — goroutine does only the compute work; main path handles all I/O.
resultCh := make(chan string, 1) // buffered: goroutine never blocks
go func() {
    resultCh <- expensiveCompute(ctx, ...)
}()

// ... do other work on the main goroutine ...

// After all other work, drain the channel and emit before TurnComplete.
if result := <-resultCh; result != "" {
    sender.Send(makeEvent(result)) // safe: still on the main goroutine
}
return sender.Send(turnCompleteEvent)
```

Buffer size of 1 guarantees the goroutine never blocks even if the main path
errors out and never reads the channel — the goroutine exits cleanly.

## Broken pattern (do not use)

```go
// BAD — goroutine touches the sender after HandleChat may have returned.
titleDoneCh := make(chan struct{})
go func() {
    defer close(titleDoneCh)
    title := expensiveCompute(ctx, ...)
    persistAndEmitTitle(persistCtx, sender, ...) // panic if handler already returned
}()

return sender.Send(turnCompleteEvent) // handler returns here
<-titleDoneCh                         // too late — stream is torn down
```

The `<-titleDoneCh` drain after the `return` is unreachable Go code. Even if
placed before the return, a race still exists: if `HandleChat` returns before
the goroutine calls `persistAndEmitTitle`, the panic fires.

## The keepalive goroutine: the lone in-handler exception

`keepalive.go` runs a `runKeepalive` goroutine that calls `sender.Send` from a
background loop. This is safe because `lockingEventSender` (a mutex wrapper)
serializes concurrent `Send` calls and the keepalive loop exits on
`ctx.Done()` — which fires when the request context is canceled, i.e., when
the handler is still alive or has just returned via cancellation. The key
distinction: the keepalive goroutine is structured to exit before (or
concurrent with) handler return, and it uses the mutex wrapper. New
goroutines should not follow this pattern without the same careful lifecycle
management.

## Preferred fix: split the work into its own RPC

When you have a derived value (title, follow-up suggestions, summarization)
that needs the LLM but is independent of the main turn, prefer a **stateless
profile** dispatched from the client rather than a goroutine inside
`HandleChat`. This is the structural fix ENG-11429 made for titles:

- Add a `Profile` to `chatcontext.Registry` with `Stateless: true` and a
  module list pointing at the prompt file.
- `HandleChat` routes stateless profiles to `handleStatelessTurn` at the top
  of the function — no observer, no keepalive, no
  `loadOrCreateConversation`, no agentic loop, no persistence.
- The worker fires the second `Chat` call in parallel and persists the
  result via `UpdateConversation` once the main turn completes.

This pattern is the right shape for any future async derivation (e.g. the
follow-up suggestion TODO at the top of `chat_service.go`).

## Diagnosis checklist

If TurnComplete is never received by the client and messages are not
persisted:

1. Check for a goroutine that holds a `sender` reference — grep for `sender`
   inside `go func()` blocks in `chat_service.go`.
2. Run unit tests with `-tags=unit` (required by the `//go:build unit` tag):
   `go test -tags=unit ./services/chat/v1/... -count=1`.
3. If the goroutine is doing async LLM work for a derived value, consider
   migrating it to a stateless profile (see above) rather than adding more
   drain logic.

## See also

- [[chat-event-types]] — event architecture and the 3-layer stack
- [[dev-commands]] — `-tags=unit` and other Go test invocations
