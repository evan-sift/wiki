---
title: Explore 2 Slice
tags: [architecture, frontend, domain-concepts]
sources:
  - path: web-app/src/store/explore2Slice/
    last_read: 2026-04-13
created: 2026-04-13
updated: 2026-04-13
last_accessed: 2026-05-07
---

The `explore2Slice` is the largest Redux slice in the app (~4,100 lines in the main
slice file) and powers the primary Explore 2 data exploration experience: multi-panel
layouts, time-synced charts, compare/alignment across runs, calculated channels,
annotations, and sharelinks.

## Top-Level State

```ts
type Explore2State = {
  version: string;                              // schema version for migrations
  mode: 'initializing' | 'panels' | 'spotlight';
  allPanelSettings: Record<string, PanelSettings>;
  previousSyncAndPanelSettingsSnapshot?: {...}; // undo buffer for entering E2-wide sync
  followModeMetricsPanelIds: string[];
  timeseriesXAxisSelection: TimeseriesXAxisSelection | null;
  dockviewLayout: SerializedDockview | null;    // resizable/dockable panel layout
  spotlight: { panel, calculatedChannel };
  rightSidebar: RightSidebarState;
  dataSources: { selectedRuns, selectedAssets, selectedFamilies, ... };
  leftSidebar: LeftSidebarState;
  unpublishedCalculatedChannels: Record<...>;
  searchFilters: Filters;
  channelSelectorDisplayType: ChannelDisplayType;
  filterToPlottedChannels: boolean;
  annotationsVisible: boolean;
  selectedChartTool: 'zoomX' | 'zoomRect' | 'pan' | 'selectRect' | 'selectX';
  syncMode: SyncMode;
  liveMode: LiveMode;
  compareSettings: { alignments: AlignmentsMap };
  filterPanelConfigHasMatchingChannels: boolean;
  filterPanelConfigIncludeArchived: boolean;
  annotationsTree: { viewState, refreshKey };
  panelChannelStatuses: Record<panelId, Record<channelKey, ChannelStatus>>;
  lastUsedChannelColors: Record<PlottedChannelKey, string>;  // session memory
  focusedTime: PanelTimestamp | null;
};
```

## Modes

- **`Initializing`** — page load, state hydration in progress
- **`Panels`** — normal multi-panel view (most common)
- **`Spotlight`** — focus on a single panel or calculated-channel editor

## Panels (Dockview Layout)

Panels are arranged via the **`dockview`** library, which provides resizable/dockable
tabs. The layout is serialized into state as `dockviewLayout: SerializedDockview | null`.

Panel types are discriminated by `.type` — see [[panel-types]] for the 9 types and their
settings shapes.

## Sidebar States (Discriminated Unions)

**Right sidebar:**
```ts
| { mode: 'closed' }
| { mode: 'createAnnotation', panelId }
| { mode: 'createCalculatedChannel', dataSource, intent?: 'create', panelId?, seed? }
| { mode: 'createCalculatedChannel', dataSource, intent: 'edit', panelId, initialChannel }
```

**Left sidebar:**
```ts
{
  mode: 'data' | 'runDetails' | 'assetDetails' | 'annotationDetails' | 'fileViewer',
  entityDetailId: string | null,
  entityDetailFamilyId: string | null,
  dataSelectorTab: 'channel' | 'calculatedChannel' | 'view' | 'panelConfiguration' | 'annotation' | 'fileViewer',
}
```

## Data Sources

Three independent kinds can be selected simultaneously:

- `selectedRuns: V1ExtendedRunRead[]`
- `selectedAssets: Assetsv1Asset[]`
- `selectedFamilies: V1FamilyDetailsRead[]`

Plus pre-fetched metadata so it's immediately available:
- `familyRunsById`, `familyAnnotationsById`
- `selectedAssetTimeRangesById`, `selectedRunTimeRangesById`, `selectedFamilyTimeRangesById`
- `hiddenRunIds`, `hiddenAssetIds`, `metadataFilters`

## Sync Mode & Live Mode

Global modes that affect every panel:

- **`syncMode`** — E2-wide sync of chart time ranges across panels
- **`liveMode`** — auto-refresh with live data (see [[channel-data-service]] for the 5-min cache cutoff)

When entering E2-wide sync, `previousSyncAndPanelSettingsSnapshot` captures the pre-sync
state so the user can cancel and restore. Live mode auto-disables when entering E2-wide
relative alignment mode (captured in the same snapshot).

## Compare & Alignment

`compareSettings.alignments: AlignmentsMap` holds time alignments for comparing runs
across families/sessions. Types:
- Absolute alignment — panels share a wall-clock time range
- Relative alignment — panels align on an alignment point (family-based or session-based)

Per-channel relative alignment overrides allow individual channels to opt out of the
panel's alignment. `calculateRelativeAlignmentOverrides()` computes these for
[[channel-data-service]] requests.

`followModeMetricsPanelIds` — metrics panels that follow another panel's time range
(updated on zoom/pan without being the source of truth).

## Calculated Channels

- `unpublishedCalculatedChannels` — locally created, not yet persisted to backend
- `Spotlight.calculatedChannel` — spotlight mode for creating/editing a calculated channel
- `RightSidebarMode.CreateCalculatedChannel` with `intent: 'create' | 'edit'` — editor UI
- See [[channel-data-service]] for the `uuid|resolvedRef1|resolvedRef2` channel ID format

Calculated channels can reference other calculated channels (nested adhoc refs) — the
slice has logic to update nested references when a parent expression changes.

## Drag & Drop

`DraggableChannels` discriminated union for the two drag sources:

```ts
type TreeNodeDragItem = { kind: 'treeNode', node: TreeNode };
type PlottedChannelDragItem = {
  kind: 'plottedChannel',
  plottedChannel: PlottedChannel,
  sourcePanelId: string,
  plottedChannelKey: PlottedChannelKey,
};
type DraggableChannels = TreeNodeDragItem[] | PlottedChannelDragItem[];
```

Type guards `isTreeNodeDragItem` / `isPlottedChannelDragItem` discriminate.

## Unplot Payloads

Three ways to unplot channels (discriminated union):
- **Specific channels** — by `plottedChannels[]`, optional `panelId`
- **All panel channels** — by `panelId`
- **All data source channels** — by `dataSourceId` + `dataSourceType: 'run' | 'asset' | 'family'`

## URL Syncer

`explore2StateSyncer` (at `explore2Slice.syncer.ts`) syncs ~18 fields to the URL hash.
Most are base64-encoded JSON (`b64EncodeUnicode(JSON.stringify(value))`):

- `version`, `mode`, `panelSettings`, `dockviewLayout`, `spotlightPanelId`
- `selectedRuns`, `selectedAssets`, `selectedFamilies`
- `leftSidebarMode`, `leftSidebarEntityId`, `leftSidebarDataSelectorTab`
- `syncMode`, `liveMode`
- `unpublishedCalculatedChannels`
- `compareSettings`
- `annotationsTreeViewState`, `annotationsVisible`
- `lastUsedChannelColors`
- `focusedTime` (selector returns `null` — hydrated on initialize, not tracked)

**`generateExplore2UrlWithFocusedTime(state, focusedTime)`** — helper for sharelinks
that include a specific focused time without persisting focusedTime to regular URL sync.

Actions that accept `ignoreCleanup: true` are dispatched during URL hydration to skip
derived-state cleanup logic (which runs on normal user actions).

## Migrations

Schema versioning via `version: string` in state plus `explore2Slice.migrations.ts`.
`EXPLORE_2_CURRENT_VERSION` in `explore2Slice.config.ts` is the current version.

- `explore1Migration/` — one-way migration from the old Explore slice
- `sharelinkRegression/` — regression tests for share link URL compatibility (important
  because sharelinks are persistent artifacts users share externally)

## Directory Structure

```
explore2Slice/
  explore2Slice.ts              (4,157 lines — main reducer)
  explore2Slice.type.ts         (state + payload types)
  explore2Slice.selector.ts     (822 lines — memoized selectors)
  explore2Slice.syncer.ts       (URL hash sync config)
  explore2Slice.hooks.ts        (component-facing hooks)
  explore2Slice.util.ts         (pure helpers)
  explore2Slice.config.ts       (constants, EXPLORE_2_CURRENT_VERSION)
  explore2Slice.migrations.ts
  explore1Migration/            (migration from old slice)
  sharelinkRegression/          (sharelink URL compatibility tests)
  panels/
    panels.type.ts              (PanelType enum, PanelSettings union)
    panels.util.ts
    panels.config.ts
    sharedPanels/               (cross-panel shared settings)
      dateTime.*                (time range / single time / utc offset / live mode)
      timeAlignment/            (absolute/relative alignment)
      legend/
      plotStyle/
      channelName/
      tooltip/
      settings.*                (panel settings hooks/utilities)
    specificPanels/             (one subdirectory per panel type)
      timeseries/ fft/ histogram/ scatter/ geoMap/ table/ metrics/ fileViewer/
```

See [[panel-types]] for details on each panel type.

## Related

- [[state-management]] — general Redux/slice patterns; this is the canonical example
- [[panel-types]] — the 9 panel types and their settings
- [[channel-data-service]] — consumes panel settings to fetch data
- [[data-visualization]] — charts render based on panel settings
- [[legend-v2]] — legend displays values for the `focusedTime`
