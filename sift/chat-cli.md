---
title: chat-cli
tags: [chat, tooling, backend]
sources:
  - path: cmd/chat-cli/
    last_read: 2026-05-13
created: 2026-05-13
updated: 2026-05-13
last_accessed: 2026-05-19
---

`chat-cli` is the Go test harness for the ChatService ConnectRPC backend. It
streams responses from the real service over Connect, so it doubles as a manual
QA tool and the engine that [[chat-e2e]] drives for recorded scenarios.

## Commands

All commands share `--url` (default `http://localhost:8080`) and `--token`
(Sift API key). Source `.env` first so `$SIFT_LOCAL_ADMIN_USER_API_KEY` is set.

| Command | Purpose |
|---|---|
| `echo` | Server-streams a message back word-by-word. Validates the ConnectRPC streaming path without touching the LLM. Flags: `--delay`, `--repeat`. |
| `chat` | Interactive REPL. Shows a conversation picker by default; `--new` skips it, `--conversation <id>` resumes by ID. |
| `archive` | Soft-deletes a conversation via `UpdateConversation` with `archived_date` set to now. |
| `unarchive` | Clears `archived_date` on a conversation. |
| `archive-all` | Pages through `ListConversations` (50/page) filtering `archived_date == null` and archives each. The filter intentionally uses `archived_date == null` so it hits the `chat_conversations_user_active_idx` partial index; `is_archived == false` would not. |

## Chat REPL behavior

Stream rendering branches on each `ChatResponse` event (see [[chat-event-types]]):

- `TurnStart` — captures the conversation ID; in `--verbose` mode also prints
  the user-message UID.
- `ThinkingChunk` — streamed in bright-black (`\033[90m`) inline; on the final
  chunk (which carries `DurationMs`), resets ANSI and prints
  `[thinking: <ms>ms]`. SGR 2 (dim) is intentionally avoided because `agg`
  doesn't honor it in asciinema GIFs.
- `TextChunk` — printed as-is; first chunk records TTFT.
- `ToolCallStart` / `ToolCallResult` — `query_time_series` results route to a
  table renderer (`displayTimeSeriesResult`); other tools print a one-line
  status with the result truncated to 200 chars.
- `TurnComplete` — prints conversation ID + token totals; in `--verbose` adds a
  timing summary line: `ttft | total | tools (Nms) | thinking (Nms)`.
- `Error` — prints to stderr without aborting the REPL.

Each turn runs under its own cancellable context wrapped in
`signal.NotifyContext` for `SIGINT`/`SIGTERM`. Ctrl-C cancels the turn, which
closes the HTTP/2 stream; the server observes `ctx.Done()` and drops the entire
turn (no user message, no partial assistant persisted). `signal.NotifyContext`
is stopped immediately after the first signal so a second Ctrl-C kills the
process instead of being swallowed. See [[chat-service-goroutine-safety]] for
the server-side cancellation contract.

When stdin is a pipe (driven by [[chat-e2e]]), the CLI echoes each typed line
back after `> ` so recorded transcripts show the user message next to its
prompt.

## Conversation picker

`showConversationPicker` lists the 10 most recent conversations via
`ListConversations` and prompts for a number; `0` (the default) starts a new
conversation. If `ListConversations` fails (e.g. persistence isn't configured),
it logs a note and falls back to a new conversation rather than exiting.

Selecting an existing conversation calls `loadAndDisplayConversation`, which
fetches via `GetConversation` and renders prior messages with
`writeConversationHistory`. The history renderer:

- Walks `ToolCalls` and `ToolResults` per-message, keeping a
  `toolUseID -> toolName` map so result lines can show the originating tool
  name rather than the opaque tool-use ID.
- Skips printing anything for `MESSAGE_ROLE_TOOL_RESULT` rows (their tool
  results are rendered via the prior assistant message's `ToolResults` loop).
- Errors on `MESSAGE_ROLE_UNSPECIFIED`; that path is asserted by
  `TestWriteConversationHistoryErrorsOnUnknownRole`.

## Personalities and EvalConfig

`--personality <terse|verbose|pirate>` reads the `reactor-base.md` module from
the embedded `services/chat/prompt` FS, appends an additive override, and sends
it as `EvalConfig.prompt_overrides["reactor-base"]`. The server enforces
`CHAT_EVAL_MODE_ENABLED=true` before honoring overrides — without it, the call
will fail.

## Verbose mode

`--verbose` surfaces stable UIDs from `TurnStartEvent`, per-assistant-message
boundaries, and per-tool `msg=<uid>` suffixes. The history renderer also
prepends `[user: <uid>]` / `[assistant: <uid>]` headers so the persisted
history can be diffed against what was streamed live. The
`verbose-ids.txt` scenario in [[chat-e2e]] is the verification harness for
this behavior.

## Tool-result dump

`--dump-tool-results <dir>` writes each tool result's raw JSON to
`<dir>/NNN-<tool_name>.json` (1-indexed counter on the `chatCLI` struct).
Useful when debugging a malformed tool payload — the streamed line truncates
at 200 chars.

## Display helpers (`display.go`)

- `displayTimeSeriesResult` renders rows as a fixed-width table, capped at 20
  rows and 40-char columns, with a `(N of M rows shown)` footer.
- `displayToolInput` / `displayToolResult` unwrap the `ToolInput` / `ToolOutput`
  oneofs and emit just the inner proto as JSON (`UseProtoNames: true`). Falls
  back to marshalling the envelope for unknown variants.
- `summarizeResources` produces `"3 assets, 2 runs, 1 channel"` style strings
  for `--verbose` resource footers; covered by `TestSummarizeResources`.

## Auth interceptor (`auth.go`)

Client-only Connect interceptor that stamps `Authorization: Bearer <token>`
on unary and streaming-client headers. Empty token is a no-op so unit tests
and unauthenticated calls pass through. `WrapStreamingHandler` is a passthrough
since the interceptor only runs client-side.

## Related

- [[chat-event-types]] — the ChatResponse event taxonomy this CLI renders.
- [[chat-service-goroutine-safety]] — server-side rules for the cancellation
  semantics this CLI relies on.
- [[chat-e2e]] — scenario runner that drives this CLI under `asciinema`.
- [[reactor-adding-tools]] — when a new tool needs custom rendering, the
  hook point is `displayToolInput`/`displayToolResult` and the
  `query_time_series` branch in `chatCmd`'s event loop.
