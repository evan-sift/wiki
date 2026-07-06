---
title: OPFS Service (Primitive Layer)
tags: [architecture, frontend, performance, data-pipeline]
sources:
  - path: web-app/src/services/opfs/
    last_read: 2026-04-16
created: 2026-04-16
updated: 2026-07-06
last_accessed: 2026-07-06
---

Low-level primitives for reading, writing, and deleting files in the Origin
Private File System (`web-app/src/services/opfs/`). API surface, concurrency
model, and config: query codegraph. This page keeps the caller contracts.

## Worker-only invariant

All public functions are worker-only — they use `FileSystemSyncAccessHandle`
for fast synchronous I/O, which the browser only exposes inside
`WorkerGlobalScope`. Every exported function calls `checkWorker()` first and
no-ops (returning early or returning `[]` / `0` / `false`) if invoked from the
main thread.

Consequence: any code path that might run on the main thread must go through
[[storage-service]] (which forwards main-thread calls into its own dedicated
worker) rather than importing from `@services/opfs` directly. `@services/opfs/*`
must never enter the main-thread bundle — see [[worker-service-pattern]].

## Eviction: OPFS is best-effort cache, not storage

The service uses best-effort persistence mode (the default). The browser may
evict OPFS contents at any time to free space — typically by deleting
everything when quota is exceeded, not by deleting individual files.

Rules for callers:

- **Never assume a file you wrote exists.** Always use `fileExistsInOPFS` or
  treat `undefined` from `readJSONFromOPFS` / `readBinaryFromOPFS` as a normal
  case.
- **Always attach a TTL.** The module-level comment makes this explicit:
  "Users of the OPFS must add a ttl to the files to avoid running out of
  space." Use `getLastModified` for TTL-based eviction, or
  [[storage-service]]'s `cleanupItems(namespace, maxNumItems)` for LRU
  trimming.

## Error semantics: silent by design

- Writes are effectively silent on failure — handle-acquisition errors are
  caught and the write skipped with no log, no throw. Only BigInt/circular-ref
  `TypeError` from `JSON.stringify` produces a `console.error`.
- Reads return `undefined` on any failure (directory missing, file missing,
  handle acquisition failure, read throw, `JSON.parse` error).
- Deletes are idempotent — `NotFoundError` is treated as success.

This is intentional: OPFS is a cache, and callers must treat every read as
potentially returning nothing. Propagating errors would force every caller to
branch on the same "just re-fetch from API" fallback.

## Related

- [[storage-service]] — namespaced K/V layer built on top of this service; the
  only path for main-thread access.
- [[state-management]] — TabState persistence uses [[storage-service]], which
  uses OPFS.
- [[worker-service-pattern]] — how OPFS's worker-only constraint shapes the
  rest of the codebase's worker architecture.
