---
title: Routing
tags: [frontend, routing]
sources:
  - path: internal-docs/src/web-app/06-routing.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-04-28
last_accessed: 2026-05-07
---

Sift uses TanStack Router with file-based routing. Files in `src/routes/` automatically
become routes; the route tree is auto-generated (never edit `routeTree.gen.ts`).

## Conventions

- Files starting with `_` are layouts (e.g. `_manageLayout.tsx`)
- `index.tsx` maps to the parent route
- Nested folders create nested routes
- Routes are thin — they import page components from `src/pages/`

## Route Configuration

**Search params** are validated using `validateSearch` with type guards from `@util/typeGuards`:
```tsx
export const Route = createFileRoute('/explore')({
  component: ExplorePage,
  validateSearch: (search): ExploreSearchParams => ({
    assets: isStringArray(search?.assets) ? search.assets : [],
    run: isString(search?.run) ? search.run : undefined,
  }),
});
```

**`beforeLoad`** runs logic before component mounts — used for auth checks, state
hydration from TabState/OPFS, and redirects.

## Document Titles

Route `head` entries should use `pageTitle({ prefix, title, suffix, section })`
from `@util/pageTitle`. Map action words such as `New`, `Editing`, or `Assign`
to `prefix`, entity/resource names to `title`, subviews or versions such as
`Logs`, `Filter`, or `v3` to `suffix`, and the Sift product area/entity type to
`section`.

Use these title shapes for entity routes:

- Named overview route: `{Entity Name} · Sift {Entity Type}`, e.g.
  `Q4 Run For Record · Sift Campaign`
- Generic overview route: `Sift {Entity Type}`, e.g. `Sift Family`
- Create route: `New · Sift {Entity Type}`
- Other action routes: `{Action} · Sift {Entity Type}` or
  `{Action} {Entity Name} · Sift {Entity Type}`
- Subview/version routes: `{Entity Name} · {Subview} · Sift {Entity Type}`,
  e.g. `Alerts Webhook · Logs · Sift Webhook`

Use `||` when deriving title names from loader data so empty strings fall
through to the generic fallback. For in-page edits where the entity name can
change without a route transition, call
`usePageTitle({ prefix, title, suffix, section })` from the page component with
live page state; TanStack route `head` is the navigation-time fallback.

## Navigation

Use Radix `Link` with `asChild` wrapping TanStack `Link` for styled navigation:
```tsx
<RadixLink asChild color="blue" underline="always">
  <Link to="/explore" search={{ run: 'run-123' }}>Go to Explore</Link>
</RadixLink>
```

Programmatic navigation via `useNavigate()` — avoid for simple click-navigate since
customers prefer middle-click → new tab on `<Link>` elements.

## URL State

See [[state-management]] for `StateSyncer` and TabState/OPFS persistence patterns.
Most features hydrate state in `beforeLoad` from either the URL hash or TabState.
