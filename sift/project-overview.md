---
title: Sift Frontend Overview
tags: [architecture, frontend, domain-concepts]
sources:
  - path: internal-docs/src/web-app/01-index.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/llms.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-07-06
last_accessed: 2026-07-06
---

Sift is a hardware telemetry and observability platform used for mission-critical hardware
development across rockets, trains, renewable energy, satellites, and aviation. The frontend
is a React SPA that prioritizes correctness, performance (60fps), and handling large datasets.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Vite + React 18 + TypeScript |
| State | Redux Toolkit + React Context |
| Routing | TanStack Router (file-based) |
| UI | Radix UI Themes + Tailwind CSS |
| Data Viz | ECharts + MapLibre GL |
| Testing | Vitest + Testing Library |
| Data Fetching | RTK Query (auto-generated from OpenAPI) |
| Performance | Web Workers + OPFS + EventTarget patterns |
| Linting/Formatting | Biome (unified linter and formatter) |

## Frontend Priorities

1. **Correctness** — accurate data representation is paramount
2. **Performance** — handle high-frequency data (60fps updates, large datasets)
3. **Thoroughness** — comprehensive testing and error handling
4. **Developer Experience** — clear patterns and good tooling

## Key Architectural Patterns

- [[component-patterns]] — compound components for composable UI
- [[state-management]] — Redux slices with TabState/OPFS persistence
- [[worker-service-pattern]] — Arrow IPC from backend, processed in Web Workers, cached in OPFS ([[opfs-service]] / [[storage-service]])
- [[performance-patterns]] — E2Syncer escapes React lifecycle for 60fps
- [[data-visualization]] — SiftDateTime, ECharts merge strategy, chart gotchas
- [[routing]] — TanStack Router, file-based routes, URL state, page titles
- [[rich-text-editor-options]] — rich text editor tradeoffs and adapter boundaries

## Related Areas (beyond the frontend)

- [[scv]] — Sift Coding Vehicles: ephemeral GCE VM agents that run pi.dev to do coding tasks
- [[sift-domain-concepts]] — core data model: asset, run, family, channel, rule, annotation, report
- [[sift-mcp-and-cli]] — agent-facing surfaces: MCP server, sift-cli, REST, sift_client, sift_stream
- [[reactor-eval-runner]] — Notion-driven harness for evaluating the Sift agent
- [[artifacts]] — conversation-attached artifact entity, S3-backed (in-flight, ENG-10586)

## LLM Context Loading

The source docs at `internal-docs/src/web-app/llms.md` provide a task-to-documentation
mapping for LLMs. Load only the relevant doc files for your current task rather than
reading everything. See the source file for the full mapping table.
