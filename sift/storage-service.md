---
title: Storage Service (Namespaced K/V on OPFS)
tags: [architecture, frontend, data-pipeline]
sources:
  - path: web-app/src/services/storage/
    last_read: 2026-04-16
  - path: web-app/src/api/workers.ts
    last_read: 2026-04-16
  - path: web-app/src/util/worker.ts
    last_read: 2026-04-16
  - path: web-app/src/util/arrow/opfsExplorer.worker.ts
    last_read: 2026-04-16
created: 2026-04-16
updated: 2026-04-16
last_accessed: 2026-05-07
---

A namespaced key-value store built on [[opfs-service]]. It exists because OPFS sync
access is worker-only, but many callers (main thread, and other workers) need to
persist small structured values. Storage Service owns a dedicated worker that holds
the OPFS access; everyone else talks to it via `postMessage`. The TabState persistence
layer, the OIDC token used by worker-side `fetch`, and arbitrary per-feature caches all
go through this service.

## Architecture

```
Main thread                           Storage worker
-----------                           --------------
storageService (singleton)  <-->     storageService.worker.ts
  pendingRequests: Map              on('message', dispatch)
  sendMessage → postMessage          ├── create/delete namespace
  handleWorkerMessage                ├── set/get/remove item
                                     ├── keys/length/clear
                                     └── cleanup-items (LRU trim)
                                        └── calls @services/opfs
```

One `Worker` instance per page load, constructed with the Vite worker idiom:
`new Worker(new URL('./storageService.worker.ts', import.meta.url), { type: 'module' })`.
Exported as a singleton (`export const storageService = new StorageService()`).

## Request/Response Protocol

Unlike [[channel-data-service]]'s subscription model, Storage Service uses **id-based
request/response** — each call gets a unique id and a pending-promise entry:

```ts
private pendingRequests = new Map<string, {resolve, reject}>();

private sendMessage(message): Promise<unknown> {
  return new Promise((resolve, reject) => {
    this.pendingRequests.set(message.id, { resolve, reject });
    this.worker.postMessage(message);
    setTimeout(() => {
      this.pendingRequests.delete(message.id);
      reject(new Error(`Request timed out after ${this.maxTimeout}ms`));
    }, this.maxTimeout);
  });
}
```

Every worker response carries the same `id`; `handleWorkerMessage` looks up the pending
entry, resolves or rejects based on `response.success`, and deletes the map entry. A
`worker.onerror` handler rejects all outstanding requests if the worker crashes.

Default timeout: `DEFAULT_MAX_TIMEOUT = 10_000` ms, overridable via config.

See [[worker-service-pattern]] for how this protocol compares to the subscription model.

## Namespace Model

```
{baseDirectory}/               # 'storage-service' by default
  {namespace}/
    _namespace.json            # metadata (name, createdAt)
    {sanitized-key}.json       # one file per item
```

Each item is wrapped:

```ts
interface StorageItem<T> {
  data: T;
  timestamp: number;   // set on write, used by cleanup-items
}
```

**Key sanitization:** `getItemFileName(key)` replaces any non-`[A-Za-z0-9._-]` character
with `_`, then appends `.json`. Note: this is **lossy** — `foo/bar` and `foo_bar` collide,
and `handleKeys` reverses the escaping with a blanket `.replace(/_/g, '/')`, which is
likewise lossy in the other direction. Callers should avoid keys whose slashes and
underscores are semantically meaningful.

## Public API

`StorageServiceInterface`:
- `createNamespace(ns)` / `deleteNamespace(ns)`
- `hasItemByKey(ns, key) → boolean`
- `setItem<T>(ns, key, value)` / `getItem<T>(ns, key) → T | null`
- `removeItem(ns, key)`
- `clear(ns)` — deletes all items except `_namespace.json`
- `keys(ns) → string[]` / `length(ns) → number`
- `cleanupItems(ns, maxNumItems)` — LRU trim (see below)

All methods `await ensureInitialized()` first to guarantee the worker's `init` round-trip
has completed.

## LRU Trimming (`cleanupItems`)

When a namespace exceeds `maxNumItems`, the oldest entries by `file.lastModified` are
removed:

```ts
const files = await getFilesWithDirHandleFromDirectoryPath(ns, { recursive: true });
const sorted = files
  .filter(f => f.file.name !== '_namespace.json' && f.file.name.endsWith('.json'))
  .sort((a, b) => compare(a.lastModified, b.lastModified));
const toRemove = sorted.slice(0, sorted.length - maxNumItems);
await Promise.all(toRemove.map(f => deleteFromOPFSByName(ns, f.name)));
```

No-op if the namespace is already at or below the cap. Uses OPFS `lastModified` directly
(not the `timestamp` field inside `StorageItem`).

## Worker-Side API Helpers (`api/workers.ts`)

The worker-context half of the auth story. Lives outside `services/storage/` but is the
reason Storage Service exists in the form it does — workers need an HTTP client, and
the OIDC token has to live somewhere workers can read synchronously at request time.

### Token Exchange

Main thread on login:
```ts
await storageService.setItem('oidc-user', OIDC_USER_KEY, user);  // writeUserToStorage
```

Worker on API call:
```ts
const user = await getUserFromStorage();  // reads from 'oidc-user' namespace
headers.set('authorization', `${user.token_type} ${user.access_token}`);
```

### `fetchWithAuth(input, init, organizationId, body?)`

Wraps `fetch` with the auth header, JSON content-type defaults, and optional
`current-organization-id` header. Returns `undefined` if no user is in storage.
**Only supports Keycloak** — the file comment calls this out explicitly.

### Worker-Side Window Workaround

```ts
// NOTE: Do not import appMeta directly. It uses data on the window
// which is not available in the worker. Instead, use the passed-in webServiceHost.
```

`appMeta` is read from `window` on the main thread; workers receive it through the
`init` message. See [[worker-service-pattern]] for the general pattern.

### Channel & Calculated-Channel Helpers

`channelSearch`, `allCalculatedChannels`, `allResolvedCalculatedChannels`,
`resolveCalculatedChannels` — API wrappers called by `channelListService.worker` and
others. All page through results with a `while (pageToken !== undefined)` loop. The file
notes a TODO to auto-generate these from protobufs.

## Worker-Only Utilities (`util/worker.ts`)

A two-function file (`hashString` — SHA-1 via `crypto.subtle.digest`) whose only
purpose is to carry this header comment:

```ts
/*
NOTE: Content in this file is for WORKERS ONLY!
Do not import this file in the main thread, as it will cause all kinds of issues,
build and otherwise.
*/
```

This establishes the convention for any file that must not enter the main-thread bundle
— violating it breaks the build. Applies to `@services/opfs/*` by extension (via the
worker-only invariant documented in [[opfs-service]]).

## Debug Tool: OPFS Explorer (`util/arrow/opfsExplorer.worker.ts`)

A dedicated worker that scans the entire OPFS tree (`navigator.storage.getDirectory()` →
recursive `values()` iteration) and supports:
- `scan` — returns the full tree as `OpfsEntry[]`.
- `read-file` — returns `{content, contentType: 'text' | 'binary'}`. Text extensions
  (`json`, `txt`, `log`, `csv`, `xml`, `html`, `css`, `js`, `ts`, `tsx`, `md`, `yaml`,
  `yml`, `toml`, `ini`) are UTF-8 decoded; everything else returns an `ArrayBuffer`
  (posted as a transferable).
- `delete` — file or directory, via [[opfs-service]].

Not wired into production user flows — used by a dev/support UI for inspecting and
clearing OPFS state. If you need to debug what a tab has cached, this is the entry
point.

## Consumers

- **TabState** — Redux slice persistence uses `storageService` via the
  `slicePersistorMiddleware`. See [[state-management]].
- **OIDC auth** — `writeUserToStorage` / `getUserFromStorage` in `api/workers.ts`.
- **Feature-level caches** — anywhere you see `storageService.setItem(...)` in the
  codebase.

## Related

- [[opfs-service]] — the primitive layer this service wraps.
- [[worker-service-pattern]] — the request/response protocol, Vite worker idiom, and
  `appMeta` forwarding generalized.
- [[channel-data-service]] — uses `getOrganizationFromStorage()` (a sync main-thread
  storage reader, not via this service) per-message for the org header.
- [[state-management]] — TabState persistence is the biggest consumer.
