---
title: chat-cli
tags: [chat, tooling, backend]
sources:
  - path: cmd/chat-cli/
    last_read: 2026-05-13
created: 2026-05-13
updated: 2026-07-06
last_accessed: 2026-07-06
---

`chat-cli` is the Go test harness for the ChatService ConnectRPC backend. It
streams responses from the real service over Connect, so it doubles as a manual
QA tool and the engine that [[chat-e2e]] drives for recorded scenarios.
Commands, flags, and rendering structure: query codegraph (`cmd/chat-cli/`).
What follows are the contracts and gotchas that are not obvious from the code.

## TurnComplete output contract (chat-e2e depends on it)

On every `TurnComplete`, the REPL prints a line matching
`[conversation: <uuid> | tokens: in=N out=N]`. [[chat-e2e]] extracts the
conversation ID for `---session resume` by sed-grepping the transcript for
exactly this shape. **If this output format changes, update the sed pattern in
`chat-e2e.sh`** — there is no other coupling, and breaking it silently breaks
every multi-session scenario.

## Gotchas

- **Archive filter must use `archived_date == null`.** `archive-all` pages
  through `ListConversations` filtering `archived_date == null` — intentionally,
  because that predicate hits the `chat_conversations_user_active_idx` partial
  index; `is_archived == false` would not.
- **Avoid SGR 2 (dim) in stream rendering.** Thinking chunks render in
  bright-black (`\033[90m`) instead of dim because `agg` does not honor SGR 2
  when converting asciinema casts to GIFs. Mind ANSI resets between adjacent
  event types generally — a dim-escape once leaked into tool-call lines.

## Related

- [[chat-event-types]] — the ChatResponse event taxonomy this CLI renders.
- [[chat-service-goroutine-safety]] — server-side rules for the cancellation
  semantics this CLI relies on (Ctrl-C cancels the turn; the server drops it).
- [[chat-e2e]] — scenario runner that drives this CLI under `asciinema`.
