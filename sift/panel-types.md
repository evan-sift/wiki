---
title: Panel Types
tags: [frontend, charts, domain-concepts]
sources:
  - path: web-app/src/store/explore2Slice/panels/
    last_read: 2026-04-13
created: 2026-04-13
updated: 2026-04-13
last_accessed: 2026-05-07
---

Explore 2 supports 9 panel types, each with its own settings shape. Panel settings are
stored in `explore2Slice` (`allPanelSettings: Record<panelId, PanelSettings>`) as a
discriminated union over `.type`.

## The 9 Panel Types

| Type | Label | Icon | Purpose |
|------|-------|------|---------|
| `empty` | — | — | Placeholder when no chart type is selected |
| `timeseries` | Timeseries | ChartLineIcon | Time-series line/step charts |
| `histogram` | Histogram | ChartIcon | Distribution charts |
| `fft` | FFT | ChartFftIcon | Fast Fourier Transform |
| `scatter-plot` | Scatter Plot | ScatterPlotIcon | XY scatter plots |
| `geo-map` | Geo Map | GeoMapIcon | Geographic maps (MapLibre GL) |
| `metrics` | Metrics | TallyIcon | Numeric metrics / KPIs |
| `table` | Table | TableViewIcon | Telemetry data tables |
| `file-viewer` | File Viewer | FileIcon | File preview panel |

`PanelTypeOptions` exposes label + icon for UI; `isPanelType()` narrows a string.

## Discriminated Union

```ts
type PanelSettings =
  | EmptyPanelSettings
  | TimeseriesPanelSettings
  | TablePanelSettings
  | FileViewerPanelSettings
  | ScatterPlotPanelSettings
  | FFTPanelSettings
  | HistogramPanelSettings
  | GeoMapPanelSettings
  | MetricsPanelSettings;
```

Each variant has type-guard helpers (`isTimeseriesPanelSettings`, `isTablePanelSettings`, etc.)
for narrowing.

All panel settings extend **`BasePanelSettings`**:
```ts
type BasePanelSettings = {
  panelId: string;
  name: string;
  description: string;
  type: PanelType;
  lastAppliedPanelConfigurationId?: string;
};
```

## Composition Pattern

Panel types are built by intersecting `BasePanelSettings` with **shared** settings
fragments (time range, plot style, tooltip, channel name, legend, time alignment) and
**specific** settings for that panel type.

Example: `TimeseriesPanelSettings` is:
```ts
type TimeseriesPanelSettings = {
  type: 'timeseries';
  plottedChannels: PlottedChannel[];
  plottedChannelsSettings: Record<PlottedChannelKey, TimeseriesSpecificChannelSettings>;
  plottedAnnotations: PlottedAnnotation[];
  showPhaseTimeline?: boolean;
  showDataReviewTimeline?: boolean;
  timelineViewModeByRow?: Record<AnnotationTimelineRow, AnnotationTimelineViewMode>;
  timelineSelectedRuleVersionIdsByRow?: RuleSelectionByRow;
  yAxesDataZooms: YDataZoomOptions;
  yAxesLabels?: YAxesLabels;
  yAxesScaleTypes?: YAxesScaleTypes;
} & BasePanelSettings
  & PlotStyleSettingsState
  & TimeRangeSettingsState
  & ChannelNameSettingsState
  & TooltipSettingsState
  & TimeseriesSplitSettingsState
  & TimeAlignmentSettingsState
  & LegendSettings;
```

This lets the same time range / tooltip / alignment logic apply across panel types
without duplicating fields.

## Shared Panel Settings

`panels/sharedPanels/` — settings fragments reused across panel types:

| Fragment | Purpose |
|----------|---------|
| `dateTime` | `TimeRangeSettingsState` (start/end, zoom, UTC offset, liveMode) OR `SingleTimeSettingState` (for geo-map-style panels with one time point) |
| `timeAlignment` | Absolute vs relative alignment, alignment points, per-channel overrides |
| `legend` | Legend config for chart panels |
| `plotStyle` | Plot style settings (line thickness, scale type, etc.) |
| `channelName` | How channels are named in UI (per-panel overrides) |
| `tooltip` | Tooltip behavior and formatting |
| `settings` | Shared hook/utility layer for panel settings |

Type guards like `hasTimeRangeSettings(settings)` and `hasTimeAlignmentSettings(settings)`
narrow a generic `PanelSettings` to the fragments that apply.

## Panel-Specific Settings

`panels/specificPanels/` — one subdirectory per panel type with `.type.ts`, `.util.ts`,
`.config.ts`, and tests.

### Per-Channel Override Settings

Each chart panel type has a **specific channel settings** type for per-channel overrides.
Example for timeseries:

```ts
type TimeseriesSpecificChannelSettings =
  ChannelNameSettingsOverrides
  & TimeseriesYAxisSettingsState      // yAxis: 'L1'..'L4' | 'R1'..'R4' | 'BG'
  & TraceStyleSettingsState
  & TooltipSettingsOverrides
  & PlotStyleSettingsOverrides
  & { samplingMethod?: SamplingMethod };
```

Stored in `plottedChannelsSettings: Record<PlottedChannelKey, TimeseriesSpecificChannelSettings>`
on the panel settings.

### Timeseries Y-Axis Layout

Timeseries panels support **9 Y-axes**: 4 left (`L1`-`L4`), 4 right (`R1`-`R4`), and
`BG` (background/hidden). `YAxisDataZoomId = 'dz-y-L1' | 'dz-y-L2' | ...` identifies
per-axis data zoom state.

Split style: `'single'` (all on one axis) or `'split'` (per-channel axes).

### Sampling Methods (Timeseries)

```ts
type SamplingMethod = 'lttb' | 'changedOnly' | 'changedOnlyOld' | 'minMax';
```

Per-channel override via `samplingMethod?` on `TimeseriesSpecificChannelSettings`. Sent
to the backend as `perChannelSamplingMethod` through [[channel-data-service]].

## Update Payloads

Generic update functions for settings and channel overrides:

```ts
type UpdateSettingsFn<T extends Partial<PanelSettings> = PanelSettings> =
  <K extends keyof Omit<T, 'type'>>(key: K, value: T[K]) => void;

type UpdateChannelOverrideSettingsFn<P, CS> =
  <K extends keyof CS>(channelKey: PlottedChannelKey, settingKey: K, value: CS[K]) => void;
```

Reducer payloads mirror these:
- `UpdatePanelSettingsKeyValuePayload<T>` — single field update
- `UpdatePanelChannelOverrideSettingsPayload` — single per-channel override
- `BatchUpdatePanelChannelOverrideSettingsPayload` — batch per-channel overrides for one panel

## Related

- [[explore2-slice]] — how panel settings fit into overall state
- [[data-visualization]] — how chart panels render via ECharts
- [[channel-data-service]] — consumes panel settings (channels, sampleMs, alignments, samplingMethod)
