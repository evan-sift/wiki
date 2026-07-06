---
title: State Management
tags: [architecture, frontend]
sources:
  - path: internal-docs/src/web-app/03-state-management.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/21-url-synchronization.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/09-opfs.md
    last_read: 2026-04-12
  - path: web-app/src/store/explore2Slice/explore2Slice.syncer.ts
    last_read: 2026-04-13
created: 2026-04-12
updated: 2026-04-16
last_accessed: 2026-05-07
---

Sift uses a layered state management approach: Redux Toolkit for global state, React
Context for localized component subtrees, and `useState` for component-local state.
State is persisted via TabState/OPFS and synchronized to URL hashes.

## State Decision Tree

- **`useState`**: Local to a single component (UI state, form inputs, ephemeral)
- **React Context**: Shared within a component subtree (compound components, theme)
- **Redux**: Global state shared across unrelated components, or state that needs persistence/URL sync

## Redux Toolkit

### Typed Hooks

Always use typed hooks:
```tsx
import { useTypedDispatch, useTypedSelector } from '@store/store';
```
`useTypedSelector` has built-in shallow equality checking for objects. Never use plain
`useDispatch`/`useSelector`.

### Slice Architecture

Each feature domain has its own slice directory with consistent file patterns.
See [[directory-structure]] for the naming convention.

Slices use Immer internally — write "mutating" code in reducers safely:
```tsx
reducers: {
  updateItem: (state, action) => {
    const item = state.items.find(i => i.id === action.payload.id);
    if (item) item.value = action.payload.value; // Immer makes this immutable
  },
}
```

### Selectors

Use `createSelector` for derived data so Redux can memoize results:
```tsx
export const selectedDataSelector = createSelector(
  [myFeatureSelector],
  (myFeature) => myFeature.data.find(d => d.id === myFeature.selectedId) ?? null
);
```

## Persistence: TabState via OPFS

State persistence has evolved through three approaches:
1. **URL params** — hit URL length limits as state grew
2. **IndexedDB** — caused gray-screen-of-death from excessive connections
3. **TabState/OPFS** (current) — fast, per-tab isolated, no size limits

The `slicePersistorMiddleware` automatically saves Redux state to OPFS based on an
allowList configuration. Each browser tab has independent state that survives page
refreshes and supports tab duplication. Persistence goes through [[storage-service]],
which wraps the [[opfs-service]] primitives.

## URL Synchronization

`StateSyncer` middleware syncs selected Redux state to the **URL hash** (not query params).
Each feature defines a `*.syncer.ts` file with encode/decode functions:

```tsx
export const reportsUrlSync = new StateSyncer<{ reports: ReportsState }>()
  .addState('runId', {
    selector: (state) => state.reports.runId,
    encode: (v) => v ?? '',
    decode: (v) => v,
    action: (v) => setRunId({ runId: v }),
  });
```

The syncer's `reduxMiddleware` updates the hash on state changes. On page load,
`syncer.initialize(...)` hydrates Redux from the URL hash.

Most future work should use the TabState/OPFS pattern instead of URL hash sync.

The canonical example is [[explore2-slice]], which syncs ~18 fields (most as
base64-encoded JSON) including panel settings, Dockview layout, selected data sources,
sync/live modes, and compare/alignment settings. Actions accept an `ignoreCleanup: true`
flag so URL-hydration dispatches skip the cleanup logic that runs for normal user actions.

## Store Reset

The store supports a `RESET` action that clears all state (used when switching between orgs):
```tsx
store.dispatch({ type: 'RESET' });
```
