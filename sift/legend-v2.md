---
title: Legend V2 Architecture
tags: [architecture, frontend, charts]
sources:
  - path: web-app/src/charts/timeseries/legendV2/
    last_read: 2026-04-12
  - path: web-app/src/charts/timeseries/timeseriesChart.tsx
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-04-12
last_accessed: 2026-05-07
---

The timeseries chart legend (`legendV2/`) was refactored from a ~2965-line monolith into
15 composable files using a compound component pattern.

## Pattern

Compound component with dot-notation API: `LegendV2.Root`, `LegendV2.Grid`,
`LegendV2.Item`, etc.

- **Root** is a pure context provider — no layout concerns
- **Grid** handles the tabular layout of legend items
- **Item** renders individual series entries

## Data Flow

The legend is fully prop-driven. All Redux dispatch/selectors live in the consumer
(`timeseriesChart.tsx`), not in the legend components. This keeps the legend reusable
and testable without Redux.

## Layout

The consumer (`timeseriesChart.tsx`) owns the resizable panel layout using `Group`,
`Panel`, and `ResizeHandle` from `react-resizable-panels`. The legend sits in one panel;
the chart in the other.

## Key Files

- Barrel export: `web-app/src/charts/timeseries/legendV2/legendV2.tsx`
- Consumer: `web-app/src/charts/timeseries/timeseriesChart.tsx`
- Component directory: `web-app/src/charts/timeseries/legendV2/`

## Related

- [[component-patterns]] — compound component pattern used here
- [[data-visualization]] — timeseries chart architecture and ECharts hooks
- [[state-management]] — Redux patterns (consumer owns dispatch/selectors)

## Notes

- Pre-existing TS errors exist in `ruleFamilyStatsConfiguration` files — unrelated to the
  legend refactor
