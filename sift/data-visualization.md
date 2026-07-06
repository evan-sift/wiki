---
title: Data Visualization
tags: [frontend, charts]
sources:
  - path: internal-docs/src/web-app/10-data-visualization.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/20-tables.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/19-datetime.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-04-12
last_accessed: 2026-05-07
---

Sift uses ECharts for charts and MapLibre GL for geographic maps. Chart data originates as
Arrow IPC from the backend, processed through Web Workers (see [[data-pipeline]]).

## Chart Types

| Type | Hook | Location |
|------|------|----------|
| Timeseries | `useOptions` | `src/charts/timeseries/timeseriesChart.hooks.ts` |
| Histogram | `useHistogramOptions` | `src/charts/histogram/histogram.hook.ts` |
| FFT | `useFFTOptions` | `src/charts/fft/fft.hook.ts` |
| Scatter | `useScatterChartOptions` | `src/charts/scatter/scatterChart.hooks.ts` |
| GeoMap | MapLibre GL | `src/charts/geoMap/` |
| TableView | TanStack Table + Virtuoso | `src/charts/tableView/` |

See [[panel-types]] for the 9 panel types in Explore 2 and how their settings are shaped.

## Composable Hooks Pattern

Each chart type builds its ECharts options from specialized sub-hooks:
- `useGrid` — chart grid layout and padding
- `useSeries` — series config (type, colors, encoding)
- `useXAxis` / `useYAxis` — axis config
- `useTooltip` — tooltip formatting
- `useDataZoom` — zoom/pan behavior
- `useBrush` — selection tool config

A main hook composes them into the final `EChartsOption` object.

## Data Flow: Arrow to Chart

1. Worker calls structured-data endpoint → receives paginated Arrow IPC (base64)
2. Worker decodes Arrow: `structuredDataResponseToArrowTable()`
3. Arrow tables → ECharts datasets: `arrowTablesToEChartsDataset()`
4. Datasets passed to options hook, embedded in the options object
5. `<ECharts>` component receives complete options with data

ECharts' dataset component separates data from visual config — series reference data
by `datasetId` and use `encode` to map columns to visual channels.

See [[channel-data-service]] for the full fetching/caching architecture behind step 1-3.

## ECharts Merge Strategies

- `notMerge: false` + `replaceMerge: ['series', 'dataset']` — data updates (better perf)
- `notMerge: true` — structural changes (axis count changed, full re-render)

## Right-Click Prevention

ECharts uses ZRender which doesn't distinguish left/right clicks. Two layers prevent
right-clicks from triggering brush/zoom:

1. **Global**: `useEnforceRightClickOnlyForContextMenu(chart)` — capture-phase handlers
   on the chart container block right-click `pointerdown`/`mousedown` before ZRender sees them
2. **Closest-point marker**: `ClosestPointTooltip.ContextMenu` — capture-phase handlers
   within a hit radius of the marker, intercepts `contextmenu` for channel-specific menus

Both must intercept `pointerdown` AND `mousedown` in capture phase.

## SiftDateTime

All timestamps use `SiftDateTime` (ms + zs BigInts for high precision) instead of
JavaScript `Date` or Luxon. `SiftDateTimeUtils` provides creation, formatting,
manipulation, and comparison. `SiftInterval` represents time ranges.

Legacy Luxon usage exists but new code should use `SiftDateTime` at boundaries (API,
Redux state, chart time math).
