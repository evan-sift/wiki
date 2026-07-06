---
title: Data Visualization
tags: [frontend, charts]
sources:
  - path: internal-docs/src/web-app/10-data-visualization.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/19-datetime.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-07-06
last_accessed: 2026-07-06
---

Sift uses ECharts for charts and MapLibre GL for geographic maps, with chart
data arriving as Arrow IPC processed in Web Workers. Chart types, hook
composition, and the Arrow-to-chart flow: query codegraph (`web-app/src/charts/`).
The conventions and gotchas below are what code reading won't tell you.

## SiftDateTime over Date/Luxon

All timestamps use `SiftDateTime` (ms + zs BigInts for high precision) instead
of JavaScript `Date` or Luxon. `SiftDateTimeUtils` provides creation,
formatting, manipulation, and comparison; `SiftInterval` represents time
ranges. Legacy Luxon usage exists, but new code must use `SiftDateTime` at
boundaries (API, Redux state, chart time math).

## ECharts merge strategies

- `notMerge: false` + `replaceMerge: ['series', 'dataset']` — data updates
  (better perf)
- `notMerge: true` — structural changes (axis count changed, full re-render)

## Right-click prevention (ZRender capture-phase gotcha)

ECharts uses ZRender, which doesn't distinguish left/right clicks. Two layers
prevent right-clicks from triggering brush/zoom:

1. **Global**: `useEnforceRightClickOnlyForContextMenu(chart)` — capture-phase
   handlers on the chart container block right-click
   `pointerdown`/`mousedown` before ZRender sees them
2. **Closest-point marker**: `ClosestPointTooltip.ContextMenu` — capture-phase
   handlers within a hit radius of the marker, intercepts `contextmenu` for
   channel-specific menus

Both must intercept `pointerdown` AND `mousedown` in capture phase.
