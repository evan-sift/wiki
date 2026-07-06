---
title: Frontend Directory Structure
tags: [architecture, frontend]
sources:
  - path: internal-docs/src/web-app/02-directory-structure.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/15-style-guide.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-07-06
last_accessed: 2026-07-06
---

Naming and layout conventions for the Sift frontend (`web-app/src/`). The
directory tree and import-alias table: query codegraph (aliases are defined in
the Vite/TS config). What follows are the rules to conform to.

## File naming

All code files use **camelCase**: `myComponent.tsx`, `myService.ts`.
Component/type names inside files use **PascalCase**: `function UserProfile()`.

Use dot notation for related files:
```
channelCard.tsx
channelCard.test.tsx
channelCard.types.ts
channelCard.hooks.ts
channelCard.util.ts
```

Redux slice directories follow the same dot notation
(`{name}Slice.ts`, `{name}Slice.type.ts`, `{name}Slice.selector.ts`,
`{name}Slice.util.ts`, `{name}Slice.config.ts`, `{name}Slice.test.ts`).

Exception: TanStack Router route files under `src/routes/` follow TanStack
conventions (`_` layouts, `-` dashes, `$param` segments).

## Key conventions

- **Routes vs pages**: routes (`src/routes/`) define URL structure only and
  stay thin; pages (`src/pages/`) contain the actual components and business
  logic.
- **`componentsV2/`** for all new components (three tiers: ui → complex →
  layout); `components/` is legacy.
- **`gen/`**: never edit manually — regenerate with `npm run gen:rtk`.
- **Aliased imports** (`@store/*`, `@componentsV2/*`, …) over relative paths,
  always.
- **Barrel files**: allowed for utility modules and compound components, but
  avoid in heavily-mocked modules — they break `vi.mock()` path resolution.
