---
title: Channel Data Service
tags: [architecture, frontend, data-pipeline, performance, charts]
sources:
  - path: web-app/src/services/channelData/
    last_read: 2026-04-13
created: 2026-04-13
updated: 2026-04-13
last_accessed: 2026-05-07
---

The Channel Data Service is the main-thread ↔ Web Worker interface for all telemetry
data fetching, processing, and caching. It owns a single shared Worker and exposes a
typed subscription API. Every chart panel in the app flows through this service.

## Architecture Layers

```
React hooks                  Main thread                   Worker thread
-----------                  -----------                   -------------
channelDataService.hooks.ts  channelDataService.ts  <-->   channelDataService.worker.ts
  useTimeseriesDataset...    singleton class                dispatcher
  useGeoMapDataset...        subscribe/unsubscribe          ├── handlers (per chart type)
  useScatterPlotDataset...   updateSubscription             ├── ChannelCache (per channel)
  useFFTDataset...           postMessage/handleWorkerMessage├── Arrow helpers
  useHistogramDataset...                                    └── OPFS access
```

The main-thread `channelDataService` is a **singleton** that owns one shared `Worker`.
All chart panels in the app multiplex through that single worker via a subscription ID.

## Subscription API

Typed overloads on `subscribe()` enforce the callback type per chart type at compile time:

```tsx
channelDataService.subscribe(subscriptionId, callback, 'timeseries'); // callback: ChannelDataCallback<'timeseries'>
channelDataService.subscribe(subscriptionId, callback, 'geoMap');
channelDataService.subscribe(subscriptionId, callback, 'scatterPlot');
channelDataService.subscribe(subscriptionId, callback, 'fft');
channelDataService.subscribe(subscriptionId, callback, 'histogram');
```

**Lifecycle**: components subscribe in `useEffect`, call `updateSubscription` when options
change, and unsubscribe on unmount. The service deep-compares subscription options to
avoid redundant worker messages (see `subscriptionHasChanged`).

## Worker Message Types

| Type | Purpose |
|------|---------|
| `init` | Initialize worker with app metadata |
| `timeseries-data` | Timeseries chart data request |
| `geo-map-data` | Geo map data request |
| `scatter-plot-data` | Scatter plot data request |
| `fft-data` | FFT data request |
| `histogram-data` | Histogram data request |
| `legend-data` | Fire-and-forget legend values at a timestamp |
| `clear-cache-by-channels` | One-shot cache invalidation by channel IDs |
| `clear-all-cache` | One-shot full cache wipe |

## One-Shot Messages (MessageChannel Pattern)

Cache invalidation uses a **`MessageChannel`** for promise-based completion with a 15s
timeout. This is separate from the subscription system — each call gets its own port pair:

```tsx
const channel = new MessageChannel();
channel.port1.onmessage = () => resolve();
this.worker.postMessage(data, [channel.port2]);
```

Used by `clearCacheAndReloadChannels`, `clearAllCache`, and `clearScatterPlotCacheAndReload`.

## Legend Data (Separate API)

Legend values at a specific timestamp are fetched via `requestLegendData` — a
fire-and-forget call with its own callback map, **not** the subscription system. Used
by the chart legend to display channel values at the current hovered time.

## OPFS Cache

```
channel-data-cache/
  v2/
    [runId | assetId]/
      [channelId]/
        [sampleMs]/
          startTimeISO|endTimeISO.arrow
        highestUnsampledMs.json
```

**Cache version is `v2/`**. Each chart panel's data is keyed by `runId|assetId →
channelId → sampleMs`, with one Arrow file per cached interval.

For **calculated channels**, `channelId` uses the format:
`calculatedChannelUuid|resolvedRef1|resolvedRef2|...` where each `resolvedRef` is the
first 8 chars of a resolved reference channel ID.

## Cache Strategy: Quantized Intervals

Requests are **quantized** to the smallest interval that encompasses the actual zoom
range. This guarantees no gaps between abutting cached intervals and keeps filenames
human-readable. Without quantization, zooming would produce cached ranges that don't
align, making merges and reads more complex.

When a new request overlaps existing cached intervals, `mergeChannelTablesByTime()`
merges the overlapping Arrow tables into a single file. The service always expands to
the widest possible quantized range on write.

## highestUnsampledMs Tracking

When the backend returns data that it didn't need to downsample (full fidelity), it
responds with `sampleMs: 0`. The worker saves this interval's data in the `0/` dir and
records the originally-requested sampleMs in `highestUnsampledMs.json`:

```json
[
  { "highestUnsampledMs": 50,
    "interval": { "start": { "ms": "1747000000100", "zs": "0" },
                  "end":   { "ms": "1747000000400", "zs": "0" } } }
]
```

On subsequent requests at the same or lower sampleMs within that interval, the cache
serves from the `0/` dir directly — avoiding a redundant API call.

## Initial Response Strategy

When panning or zooming, ECharts retains its in-memory data until new data arrives —
but as soon as something comes back from the service, it **overwrites everything**.
Naively returning an empty array while the API call is in flight would cause the chart
to briefly go blank.

The service avoids this by checking **other sampleMs caches** for data overlapping the
current request, preferring **higher sampleMs** (less data) over lower (more data):

```
50ms request   |--------------------|
20ms cache         |---------|
50ms cache            empty
100ms cache        |---------|

Initial response:  |--100ms--|     ← sent immediately
Then API call:     |----------full 50ms---------|
```

If the cache has partial current-sampleMs data plus broader other-sampleMs data, the
service sends a **mixed response** using the most appropriate per-interval cache, then
triggers API calls only for the gaps. This gets more complex when `highestUnsampledMs`
is involved — the service splits intervals accordingly.

## Live Mode

To accommodate late-arriving telemetry data, **the last ~5 minutes of data is not cached**.
This also prevents thrashing OPFS with writes during live streaming.

The cutoff is synced to 5-minute wall-clock boundaries:
```
cutoff = now - 2.5min - (now % 5min)
```

## ChannelCache Class (Per-Channel Singleton)

Each channel gets a dedicated `ChannelCache` instance in the worker:

- **In-memory cache** backed by OPFS — reads OPFS on miss, writes to memory on update
- **Periodic OPFS flush** — writes `entriesToWrite` and deletes `entriesToDelete` in batches
- **Scoped per worker** — each browser tab's worker has its own memory cache
- **Shared OPFS backing** — the OPFS files are visible across all workers/tabs in the origin

The cache tracks `lastModified` per entry for TTL-based eviction.

## Key Files

| File | Purpose |
|------|---------|
| `channelDataService.ts` | Main-thread singleton, subscription API, message routing |
| `channelDataService.hooks.ts` | React hooks (`useTimeseriesDatasetFromChannelDataService`, etc.) |
| `channelDataService.worker.ts` | Worker entry point — thin dispatcher |
| `channelDataService.worker.handlers.ts` | Per-chart-type message handlers |
| `channelDataService.worker.cache.ts` | `ChannelCache` class, quantization, merging |
| `channelDataService.worker.timeseries.ts` | Timeseries data processing |
| `channelDataService.worker.{fft,geoMap,histogram,scatter}.ts` | Chart-specific processing |
| `channelDataService.worker.utils.ts` | OPFS path helpers, interval utilities |
| `channelDataService.worker.expression.utils.ts` | Pure helpers (avoid worker import chain for tests) |
| `channelDataService.config.ts` | Constants (TTL, flush interval, debounce) |
| `readme.md` | The canonical cache design doc in the repo |

## Related

- [[worker-service-pattern]] — the generalized structure this service instantiates
  (subscription protocol, MessageChannel escape hatch, `appMeta` forwarding)
- [[opfs-service]] — OPFS primitive API used directly by this service's worker
- [[data-pipeline]] — high-level pipeline overview (Arrow IPC, OPFS, Storage Service)
- [[data-visualization]] — how charts consume this data
- [[performance-patterns]] — why Web Workers for this work
- [[state-management]] — TabState also uses OPFS via [[storage-service]]
- [[explore2-slice]] + [[panel-types]] — source of panel settings that drive subscription options
  (channels, sampleMs, alignments, perChannelSamplingMethod)
