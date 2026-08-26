---
title: Development Commands
tags: [tooling]
sources:
  - path: web-app/package.json
    last_read: 2026-08-25
  - path: makefile
    last_read: 2026-08-25
created: 2026-04-12
updated: 2026-08-26
last_accessed: 2026-08-26
---

Common development commands and workflows for the azimuth project.

## TypeScript

| Command | Purpose |
|---------|---------|
| `cd web-app && npx tsc --noEmit` | Type check the frontend |

## Testing

| Command | Purpose |
|---------|---------|
| `cd web-app && npx vitest run <path>` | Run specific tests |
| `cd web-app && npm run ci` | Full CI check (format check + lint + types + tests under coverage) |

For Go integration tests (real Postgres + S3 backend, `//go:build integration`),
see [[integration-tests]] — they require switching Docker stacks and passing
connection env vars.

## Linting & Formatting

| Command | Purpose |
|---------|---------|
| `cd web-app && npm run lint` | Lint the frontend |
| `cd web-app && npm run format` | Format with Biome (`biome format --write ./src`; there is no Prettier config) |

## Code Generation

| Command | Purpose |
|---------|---------|
| `make generated` | Run all code generation (protobuf, flatbuffers, etc.) |
| `make generated-local` | Same, but for local development |

## Environment

| Command | Purpose |
|---------|---------|
| `make up` | Start the full dev environment |

## Reference

- Style guide: `internal-docs/src/web-app/llms.md`
