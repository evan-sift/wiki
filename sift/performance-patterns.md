---
title: Performance Patterns
tags: [frontend, performance]
sources:
  - path: internal-docs/src/web-app/16-performance.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/08-services-and-workers.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-04-16
last_accessed: 2026-05-07
---

Sift handles high-frequency telemetry data at 60fps. The key performance pattern is
escaping React's render cycle for hot paths while keeping React for everything else.

## E2Syncer (EventTarget Pattern)

The core performance primitive. `E2Syncer` extends `EventTarget` and dispatches custom
events for high-frequency state changes (hovered time, focused time) that would overwhelm
React's reconciliation if routed through Redux/setState.

```tsx
export class E2Syncer extends EventTarget {
  #hoveredTime: PanelTimestamp | null = null;

  set hoveredTime(time: PanelTimestamp | null) {
    this.#hoveredTime = time;
    this.dispatchEvent(new CustomEvent('hoveredTimeChange', { detail: { ... } }));
  }
}
```

Components subscribe via `addEventListener` in `useEffect` and update the chart/DOM
directly — no React re-render in the hot path. Redux is updated separately on a
throttled cadence for state that needs persistence.

Location: `src/store/syncers/E2Syncer.tsx`

## Web Workers

CPU-intensive data processing runs in Web Workers to avoid blocking the main thread.
The [[channel-data-service]] is the primary example: Arrow decoding, data transformation,
and OPFS caching all happen off-thread.

See [[worker-service-pattern]] for the shared structure across all six worker services
(singleton + dedicated Worker, message protocols, init handshake, `appMeta` forwarding,
transferables).

## OPFS Caching

Processed data is cached in OPFS for instant retrieval on subsequent requests.
OPFS is faster than IndexedDB with synchronous access in workers.
See [[opfs-service]] for the primitive API and [[storage-service]] for the namespaced
K/V layer. [[data-pipeline]] has the high-level cache structure.

## Memoization

Until React 19, memoize aggressively:
- `useMemo` for derived values (even simple ones)
- `useCallback` for stable function references passed to children
- `createSelector` for Redux derived state

See [[component-patterns]] for hook conventions.

## Key Principles

1. **60fps hot paths** bypass React (E2Syncer → direct DOM/chart updates)
2. **Heavy computation** runs in Web Workers (Arrow decoding, data transforms)
3. **Frequently accessed data** is cached in OPFS
4. **React state updates** are throttled for non-critical paths
5. **ECharts animations disabled** (`animation: false`) for performance
