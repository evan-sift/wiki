---
title: Docs Search & Read Tools
tags: [backend, chat, tooling]
sources:
  - path: services/chat/tools/docs_search.go
    last_read: 2026-06-17
  - path: services/chat/tools/docs_read.go
    last_read: 2026-06-17
  - path: services/chat/tools/docs_embed.go
    last_read: 2026-06-17
  - path: services/repo/docs/v1/docs_service.go
    last_read: 2026-06-17
  - path: protos/sift/docs/v1/docs.proto
    last_read: 2026-06-17
created: 2026-06-17
updated: 2026-06-17
last_accessed: 2026-06-17
---

Two Reactor tools, `search_sift_docs` and `read_sift_doc`, let the agent answer "how does Sift work" questions from Sift's own product documentation (docs.siftstack.com) instead of guessing. The docs are embedded into the binary at build time, and the same backing functions are also exposed as a public HTTP API (`DocsService`) so the [[sift-mcp-and-cli|Sift MCP server]] can search and read docs behind normal API-key auth. This is the mechanism behind the docs-answering evals (see [[reactor-eval-runner]]).

## The two tools

- **`search_sift_docs`** (`services/chat/tools/docs_search.go`) — keyword search over the bundled docs. Input: `query` (required), `max_results` (default 10, hard cap 25). Returns ranked `hits`, each with `path`, `title`, `score`, and a ~200-character `snippet`, plus `total_scanned`.
- **`read_sift_doc`** (`services/chat/tools/docs_read.go`) — full markdown of one page by `path` (the path from a search hit, e.g. `documentation/ingest/asset-channels.mdx`). Optional 1-indexed `offset`/`limit` slice long reference pages. Output lines are prefixed `<line_number>\t` so a follow-up read can target a range.

The intended loop, stated in each tool's description: `search_sift_docs` to find a page, then `read_sift_doc` on the promising hit.

## Bundled docs

`docs_embed.go` does `//go:embed all:docs_content`, so the docs tree is compiled into the binary (`docsFS` rooted at `docsRoot`). There is no runtime fetch from docs.siftstack.com; the bundled copy is the source of truth, refreshed when `docs_content/` is updated and rebuilt.

## Shared backing + public HTTP API

The chat tools and the HTTP API are thin wrappers over the same transport-agnostic functions `tools.SearchDocs` / `tools.ReadDoc`. `services/repo/docs/v1/docs_service.go` implements the gRPC `DocsService` by delegating straight to them, and `protos/sift/docs/v1/docs.proto` maps it to:

- `GET /api/v1/docs:search` → `SearchDocs`
- `GET /api/v1/docs:read` → `ReadDoc`

Per the proto, the service is read-only and uses "the same bearer token / API key used for the rest of the Sift API" (added in ENG-12213 / #12148 for MCP access behind auth). The proto file is marked `unstable_file`.

## Search scoring and snippets

`scoreDoc` tokenizes the query (lowercased, punctuation-trimmed words) and sums per-token counts weighted by location: title ×5, `##`/`###` headings ×3, body ×1. Pages with score 0 are dropped; ties break by path. Before scoring and snippet extraction, `cleanBodyForScoring` strips fenced code blocks and MDX/JSX tags so a stray `<Tabs>` can't dominate ranking — except table-style components (e.g. `<MintTable columns={...} rows={...}>`), which are rendered to Markdown, and other multi-line tags, whose quoted prop string literals are kept (the props are the content). Snippets are a ~200-char window centered on the first matching token, snapped to whitespace.

## Read behavior

`readDoc` validates the path with `fs.ValidPath` (rejects `..`/absolute paths; returns a clean "doc not found" rather than leaking `io/fs` errors), then slices by `offset`/`limit`. `stripMDXKeepingLines` removes MDX/JSX tags while preserving the original line count, so the line numbers in the output map cleanly back to the source file and to search snippets. Fenced code blocks are left intact, since they are often the most useful part of a docs page.

## In-flight refinement (ENG-12265, unmerged)

A branch (`eng-12265-search_docs-add-match-line-and-surrounding-context-to-search`) replaces the flat snippet with a match line plus a surrounding context window and propagates `match_line` / `total_lines` / `content` onto the `DocHit` HTTP shape. Not merged to main as of this writing; the behavior described above is what ships on `main`.

## See also

- [[reactor-adding-tools]] — how Reactor tools like these are defined and registered
- [[sift-mcp-and-cli]] — the MCP server that consumes the `DocsService` HTTP API
- [[sift-domain-concepts]] — what the docs themselves describe (assets, channels, rules, CEL)
