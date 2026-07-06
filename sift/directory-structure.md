---
title: Frontend Directory Structure
tags: [architecture, frontend]
sources:
  - path: internal-docs/src/web-app/02-directory-structure.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/15-style-guide.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-04-12
last_accessed: 2026-05-07
---

The Sift frontend follows a domain-organized structure with clear separation between
presentation, business logic, data access, and utilities.

## Top-Level Layout

```
web-app/src/
  routes/            # TanStack Router file-based routes (thin — import from pages/)
  pages/             # Page-level components and business logic
  componentsV2/      # Modern components (preferred)
    ui/              # Reusable UI primitives
    complex/         # Domain-specific components
    layout/          # Page structure and panel management
  components/        # Legacy components (migrating to componentsV2/)
  store/             # Redux Toolkit slices organized by feature
  api/               # RTK Query hooks, generated API clients
    hooks/           # Custom API hooks (40+ files)
  gen/               # Auto-generated code (never edit manually)
  services/          # Web Workers, OPFS, feature flags, analytics
  charts/            # ECharts implementations by chart type
  common/            # Shared utilities (partially legacy)
  util/              # Newer utilities (SiftDateTime, SiftInterval)
  contexts/          # React context providers
  providers/         # Root provider composition
  types/             # Shared TypeScript types
  modals/            # Legacy modals (prefer Radix Dialog)
  testing/           # Test utilities and mocks
```

## File Naming

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

Exception: TanStack Router route files under `src/routes/` follow TanStack conventions
(`_` layouts, `-` dashes, `$param` segments).

## Import Aliases

| Alias | Path |
|-------|------|
| `@api/*` | `src/api/*` |
| `@charts/*` | `src/charts/*` |
| `@componentsV2/*` | `src/componentsV2/*` |
| `@store/*` | `src/store/*` |
| `@util/*` | `src/util/*` |
| `@services/*` | `src/services/*` |
| `@common/*` | `src/common/*` |
| `@components/*` | `src/components/*` |
| `@contexts/*` | `src/contexts/*` |
| `@gen/*` | `src/gen/*` |
| `@pages/*` | `src/pages/*` |
| `@testing/*` | `src/testing/*` |
| `@typedefs/*` | `src/types/*` |

Always use aliased imports over relative paths.

## Slice Directory Pattern

Each Redux slice follows a consistent structure:
```
store/{feature}Slice/
  {name}Slice.ts          # Slice definition
  {name}Slice.type.ts     # Types
  {name}Slice.selector.ts # Reselect selectors
  {name}Slice.util.ts     # Helpers
  {name}Slice.config.ts   # Constants
  {name}Slice.test.ts     # Tests
```

## Key Conventions

- **Routes vs Pages**: Routes define URL structure; pages contain actual components
- **componentsV2/**: Use for all new components (three tiers: ui → complex → layout)
- **gen/**: Never edit manually — regenerate with `npm run gen:rtk`
- **Barrel files**: Allowed for utility modules and compound components, but avoid in
  heavily-mocked modules (breaks `vi.mock()` path resolution)
