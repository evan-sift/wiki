---
title: OPFS Service (Primitive Layer)
tags: [architecture, frontend, performance, data-pipeline]
sources:
  - path: web-app/src/services/opfs/
    last_read: 2026-04-16
created: 2026-04-16
updated: 2026-04-16
last_accessed: 2026-05-07
---

Low-level primitives for reading, writing, and deleting files in the Origin Private
File System. All public functions are worker-only — they use `FileSystemSyncAccessHandle`
for fast synchronous I/O, which the browser only exposes inside `WorkerGlobalScope`.
Higher layers ([[storage-service]], [[channel-data-service]]) build on top of these
primitives. See [[worker-service-pattern]] for how consumers wire a worker up.

## Worker-Only Invariant

Every exported function calls `checkWorker()` first and no-ops (returning early or
returning `[]` / `0` / `false`) if invoked from the main thread. The check reads
`self.constructor.name` and succeeds only for `DedicatedWorkerGlobalScope`,
`SharedWorkerGlobalScope`, or `ServiceWorkerGlobalScope`.

**Why:** `fileHandle.createSyncAccessHandle()` is restricted to workers. The sync API is
dramatically faster than the async main-thread FS API, and the rest of the service is
structured around it (e.g. reading a file means allocating a `DataView`, calling
`accessHandle.read(dataView)` synchronously, then decoding).

Consequence: any code path that might run on the main thread must go through
[[storage-service]] (which forwards main-thread calls into its own dedicated worker)
rather than importing from `@services/opfs` directly.

## Public API

All functions are async (they internally `await` the directory/file handle acquisition)
but the actual read/write is synchronous once the access handle is held.

| Function | Purpose |
|----------|---------|
| `writeJSONToOPFS(dir, file, data)` | `JSON.stringify` + write; initializes BigInt serializer; swallows stringify errors |
| `writeBinaryToOPFS(dir, file, Uint8Array)` | Raw binary write |
| `readJSONFromOPFS(dir, file)` | Queued read; returns parsed object or `undefined` |
| `readBinaryFromOPFS(dir, file)` | Queued read; returns `DataView` or `undefined` |
| `deleteFromOPFSByName(dir, file)` | Delete a file (async `getDirectoryHandle`, retrying `removeEntry`) |
| `deleteFromOPFSWithDirectoryHandle(dirHandle, file)` | Same as above when you already have the handle |
| `deleteDirectoryFromOPFS(dir)` | Retrying recursive directory delete |
| `deleteEmptyDirectories()` | Recursive sweep of the whole OPFS removing empty dirs |
| `getFilesWithDirHandleFromDirectoryPath(dir, {recursive})` | Returns `{file, directoryHandle}[]` |
| `getFilesOrDirsFromOPFSDirectory(dir, 'file' \| 'directory')` | Names only |
| `getLastModified(dir, file)` | `file.lastModified` for TTL checks |
| `fileExistsInOPFS(dir, file)` | Existence probe |

Types (`opfs.types.ts`) declare `FileSystemSyncAccessHandle`,
`SecureFileSystemFileHandle`, and `SecureFileSystemDirectoryHandle` — the DOM types
don't surface the sync-handle API, so the service extends them locally.

## Concurrency Model

### Read Deduplication via In-Flight Promise Map

`operationsQueue: Map<string, Promise<unknown>>` is keyed by `directory/fileName`.
When a read starts, its promise is stored in the map; if a second caller requests the
same key while the first is still in flight, it awaits the existing promise instead of
opening its own access handle:

```ts
const existingOperation = operationsQueue.get(key);
if (existingOperation) {
  return (await existingOperation) as T;
}
```

The entry is cleared in a `finally` block once the operation settles.

**Why:** `createSyncAccessHandle()` currently takes an exclusive lock on the file (Firefox
and Safari don't yet support the `{mode: 'read-only'}` option). Deduping concurrent reads
avoids serial lock acquisition for identical reads. The service comment explicitly says
this queue can be removed once browsers support read-only mode.

**Writes are not queued.** `writeJSONToOPFS` has a commented-out `queueFileOperation`
wrapper — the queue is reads-only in current code. Writes rely on the handle-acquisition
retry loop to handle lock contention.

### Handle Acquisition Retry

`getSyncReadOnlyAccessHandle` and `getSyncReadWriteAccessHandle` both retry
`createSyncAccessHandle()` for up to `OPFS_SYNC_ACCESS_HANDLE_TIMEOUT_MS` (100ms) with 1ms
backoff between attempts. This covers:
- Cross-tab locks (another tab's worker holds the handle).
- Dangling handles from a worker that crashed without calling `close()`.

If the loop exhausts, it throws with the elapsed time and last error. Writes swallow the
throw; reads translate it to `undefined`.

### Delete Retry

`deleteDirectoryFromOPFS` wraps `parentDirectoryHandle.removeEntry(name, {recursive: true})`
in the same timeout loop. `NotFoundError` short-circuits to success (idempotent delete).

### Empty-Directory Cleanup Workaround

`deleteEmptyDirectoriesRecursive` returns `isEmpty` up the call stack, and the *parent*
directory calls `removeEntry(childName, {recursive: true})` on any subdirectory that came
back empty. Directories cannot delete themselves via the current FS API — the file's
comment notes this can be simplified once Firefox supports `directoryHandle.remove()`.

## Eviction & Persistence

The service uses **best-effort persistence mode** (the default). The browser may evict
OPFS contents at any time to free space — typically by deleting everything when quota is
exceeded, not by deleting individual files.

Consequences for callers:
- **Never assume a file you wrote exists.** Always use `fileExistsInOPFS` or treat
  `undefined` from `readJSONFromOPFS` / `readBinaryFromOPFS` as a normal case.
- **Always attach a TTL.** The module-level comment makes this explicit: "Users of the
  OPFS must add a ttl to the files to avoid running out of space." [[channel-data-service]]
  uses `getLastModified` for TTL-based eviction; [[storage-service]] exposes
  `cleanupItems(namespace, maxNumItems)` for LRU trimming.

## Error Semantics

Writes are effectively silent on failure — `writeJSONToOPFS` catches handle-acquisition
errors and returns early with no log, no throw. Only BigInt/circular-ref `TypeError`
from `JSON.stringify` produces a `console.error`.

Reads return `undefined` on any failure (directory missing, file missing, handle
acquisition failure, read throw). `JSON.parse` errors log and return `undefined`.

Deletes are idempotent — `NotFoundError` is treated as success.

This is intentional: OPFS is a cache, and callers must treat every read as potentially
returning nothing. Propagating errors would force every caller to branch on the same
"just re-fetch from API" fallback.

## Directory Path Handling

Paths are slash-delimited. `getDirectoryHandle('a/b/c', {create: true})` splits on `/`,
skips empty parts (so a leading `/` is harmless), and walks the tree calling
`getDirectoryHandle(part, options)` at each step. Same `options` applies at every level —
`{create: true}` creates the full chain.

## BigInt Serialization Hook

`writeJSONToOPFS` calls `initBigIntSerializer()` from `@util/bigIntSerializer` before
stringifying. This patches `BigInt.prototype.toJSON` so stored data can include 64-bit
timestamps (channel sample times often arrive as BigInt from Arrow). The call is
idempotent but must run at least once per worker context.

A `TypeError` from `JSON.stringify` (circular reference, or a BigInt that slipped past
the serializer) is logged and the write is skipped.

## Config

`opfs.config.ts`:
- `OPFS_SYNC_ACCESS_HANDLE_TIMEOUT_MS = 100` — retry budget for handle acquisition and
  directory deletes.
- `OPFS_SYNC_ACCESS_HANDLE_ATTEMPTS = 3` and `OPFS_SYNC_ACCESS_HANDLE_TIMEOUT = 10` are
  declared but unused in current code.

## Minor Duplication

`opfs.utils.ts` exports both `getCacheKey` and `getQueueKey` — both return
`directory + '/' + fileName`. Cosmetic only; worth collapsing next time the file is
touched.

## Related

- [[storage-service]] — namespaced K/V layer built on top of this service; the only path
  for main-thread access.
- [[channel-data-service]] — direct consumer via its own worker; reads/writes Arrow files.
- [[data-pipeline]] — higher-level view of OPFS as a cache tier.
- [[state-management]] — TabState persistence uses [[storage-service]], which uses OPFS.
- [[worker-service-pattern]] — how OPFS's worker-only constraint shapes the rest of the
  codebase's worker architecture.
