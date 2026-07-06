---
title: Data Pipeline (Workers, Arrow, OPFS)
tags: [architecture, frontend, performance]
sources:
  - path: internal-docs/src/web-app/08-services-and-workers.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/09-opfs.md
    last_read: 2026-04-12
  - path: web-app/src/services/channelData/readme.md
    last_read: 2026-04-13
created: 2026-04-12
updated: 2026-04-16
last_accessed: 2026-05-07
---

Sift processes telemetry data through a pipeline that keeps heavy computation off the main
thread: backend returns Apache Arrow IPC files, Web Workers decode and process them, OPFS
caches the results, and datasets are posted back for chart rendering.

## Architecture

```
Backend (/api/v1/structured-data)
  → base64-encoded Arrow IPC records
    → Web Worker (channelDataService.worker.ts)
      → Decode Arrow → Process → Cache in OPFS
        → Post datasets back to main thread
          → ECharts renders
```

## Channel Data Service

The primary service for processing telemetry data, at `src/services/channelData/`.
See [[channel-data-service]] for the full architecture: subscription API, per-channel
cache class, quantized intervals, `highestUnsampledMs` tracking, initial-response
strategy, live mode, and calculated channel key format.

High-level:
- **Hooks** — React hooks consumed by components
- **Main-thread service** — singleton owning a shared Worker, subscription API
- **Worker** — dispatcher + per-chart-type handlers + `ChannelCache` + OPFS access

## Apache Arrow IPC

The structured data endpoint returns data as **Arrow IPC** (base64-encoded in JSON).
Arrow is used because:
- **Columnar format** — efficient for time-series (separate time/value columns)
- **Zero-copy reads** — no deserialization overhead
- **Compact** — binary format much smaller than JSON
- **Type-safe** — schema embedded in the file

Conversion: `structuredDataResponseToArrowTable()` decodes base64 → Arrow table.
Then `arrowTablesToEChartsDataset()` converts Arrow tables to ECharts dataset format.

## OPFS (Origin Private File System)

OPFS provides fast, private file storage for caching channel data. Advantages over
IndexedDB: much faster, synchronous access in workers, large storage capacity.

**Cache structure (current, v2):**
```
channel-data-cache/v2/
  [runId | assetId]/[channelId]/[sampleMs]/
    startTimeISO|endTimeISO.arrow
  [runId | assetId]/[channelId]/highestUnsampledMs.json
```

See [[channel-data-service]] for the cache strategy details — quantization, merging,
`highestUnsampledMs` tracking, and the calculated-channel key format.

**Key constraint:** OPFS synchronous access only works in workers. See [[opfs-service]]
for the primitive API (retry loop, read deduplication, best-effort eviction semantics).
For main-thread access and general K/V storage, go through [[storage-service]].

## Other Services

- **[[storage-service]]** — namespaced K/V store built on [[opfs-service]]; used by
  TabState persistence and worker-side auth (OIDC token).
- **Feature Flags** — Amplitude Experiment (see [[feature-flags-and-analytics]])
- **Events** — Amplitude analytics tracking

See [[worker-service-pattern]] for the shared architecture across all services that own
a dedicated Worker.
