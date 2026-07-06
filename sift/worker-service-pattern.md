---
title: Worker Service Pattern
tags: [architecture, frontend, performance]
sources:
  - path: web-app/src/services/channelData/
    last_read: 2026-04-16
  - path: web-app/src/services/channelList/
    last_read: 2026-04-16
  - path: web-app/src/services/metricsData/
    last_read: 2026-04-16
  - path: web-app/src/services/tableData/
    last_read: 2026-04-16
  - path: web-app/src/services/annotations/
    last_read: 2026-04-16
  - path: web-app/src/services/storage/
    last_read: 2026-04-16
created: 2026-04-16
updated: 2026-04-16
last_accessed: 2026-05-07
---

Six services in the codebase follow the same structural pattern: a main-thread singleton
class owns a dedicated `Worker`, clients interact through the singleton, and the class
handles message routing, lifecycle, and bootstrap quirks. This page documents the
shared pattern so new worker services can be built without re-deriving it, and so you
know which details are invariants vs. per-service choices.

Concrete instances: [[channel-data-service]], [[storage-service]], `channelListService`,
`metricsDataService`, `tableDataService`, `annotationsListService`.

## When to Use a Worker

Put work in a worker when:
- It's CPU-bound and would block the main thread (Arrow decoding, FFT, geo projection).
- It needs synchronous OPFS access via `FileSystemSyncAccessHandle` (see [[opfs-service]]).
- It involves long-running streaming processing tied to a subscription lifetime.

Don't use a worker for simple async work (fetch + transform + dispatch) — the postMessage
overhead and dual-bundle cost outweigh any benefit.

## The Vite Worker Bootstrap Idiom

Every service instantiates its worker with the same call, which Vite recognizes and
bundles as a separate chunk:

```ts
this.worker = new Worker(
  new URL('./xService.worker.ts', import.meta.url),
  { type: 'module' }
);
```

The `new URL(..., import.meta.url)` form is load-bearing — Vite matches that literal
pattern to discover worker entry points. `{ type: 'module' }` enables ES modules inside
the worker (required for `import` statements). Don't refactor the URL construction.

## Singleton Export

Every service exports a single constructed instance:

```ts
export const metricsDataService = new MetricsDataService();
```

Never construct these yourself. The worker is shared across all consumers for the life
of the page. Subscription/request ids keep clients isolated inside the shared worker.

## Main-Thread Class Structure

```ts
class XService {
  private worker = new Worker(new URL('./x.worker.ts', import.meta.url), { type: 'module' });
  private subscriptions: XSubscription = {};   // OR pendingRequests: Map<id, {resolve, reject}>

  constructor() { this.initWorker(); }

  private initWorker() {
    this.worker.onmessage = this.handleWorkerMessage;
    this.postMessage({ type: 'init', id: '', appMeta });
  }

  public subscribe/unsubscribe/updateSubscription(...)
  private handleWorkerMessage = (event) => { switch (event.data.type) { ... } }
  private postMessage = (data) => this.worker.postMessage(data);
}
```

The worker side is a thin dispatcher:

```ts
self.onmessage = (event) => {
  switch (event.data.type) {
    case 'init': handleInit(event.data); break;
    // ...
  }
};
```

## Message Protocols (Two Variants)

The codebase uses two distinct protocols. Pick based on the caller's needs.

### A. Subscription + Callback Map (Streaming)

Used by: [[channel-data-service]], `channelListService`, `metricsDataService`,
`tableDataService`.

- Client registers a callback under a `subscriptionId`.
- Client calls `updateSubscription(id, options)` to trigger/replace work.
- Worker sends zero-to-many responses; each response carries the `id`, the main-thread
  handler looks up the callback and invokes it.
- Client calls `unsubscribe(id)` on unmount.

```ts
channelDataService.subscribe(id, callback, 'timeseries');
channelDataService.updateSubscription({ subscriptionId: id, options });
channelDataService.unsubscribe(id);
```

This protocol is the right choice when the result is a **stream over time** (cache
hit → API response → live updates) or when the same subscription can produce multiple
callbacks.

### B. Request/Response with Pending-Promise Map (One-Shot)

Used by: [[storage-service]].

- Each call gets a unique id (`${Date.now()}-${Math.random()...}`).
- A `pendingRequests: Map<id, {resolve, reject}>` stores the promise callbacks.
- Worker responds exactly once with the same id; handler resolves/rejects and deletes
  the entry.
- `worker.onerror` rejects all outstanding requests on worker crash.
- Each call has its own timeout (`setTimeout` → `reject`).

```ts
private sendMessage(message): Promise<unknown> {
  return new Promise((resolve, reject) => {
    this.pendingRequests.set(message.id, { resolve, reject });
    this.worker.postMessage(message);
    setTimeout(() => { this.pendingRequests.delete(message.id); reject(new Error('timeout')); }, this.maxTimeout);
  });
}
```

Right choice when the API is `async` and returns a single value per call.

### Escape Hatch: MessageChannel for One-Shots Inside a Subscription Service

[[channel-data-service]] and `annotationsListService` use `MessageChannel` to add
Promise-returning one-shot calls (cache invalidation, tree fetch) without adding a
global message type:

```ts
const channel = new MessageChannel();
channel.port1.onmessage = (event) => { resolve(event.data); channel.port1.close(); };
worker.postMessage(data, [channel.port2]);
```

The worker handler replies via `event.ports[0].postMessage(response)`. Each call is
fully isolated — no id management on the main thread.

`annotationsListService` wraps this in two generic helpers:

```ts
sendOneShot<TReq, TRes>(worker, data, signal?, timeoutMs?): Promise<TRes>
streamFromWorker<TReq, TRes>(worker, data, onMessage, signal?): Promise<void>
```

`sendOneShot` supports `AbortSignal` and a default 10s timeout. `streamFromWorker`
reuses the same channel but keeps the port open until a response includes
`isComplete: true`. Reusable in any worker service that wants one-shot-over-a-stream
ergonomics.

## Init Handshake

Two patterns seen in the codebase:

1. **Fire-and-forget init** — `tableDataService`, `metricsDataService`,
   `channelListService`. Constructor calls `postMessage({type: 'init', appMeta})` and
   trusts the worker is ready before the first real request lands. `channelListService`
   and `metricsDataService` wrap the init post in `setTimeout(0)` to let the
   `worker.onmessage` listener attach first in all environments.
2. **Await-worker-ready** — [[storage-service]] and `annotationsListService`. The
   constructor stores a `workerReadyPromise`; every public method `await`s it before
   posting. Annotations uses a MessageChannel round-trip (`port2` sent with init, `port1`
   resolves the ready promise when the worker replies). Storage Service's
   `ensureInitialized()` awaits the pending init's `sendMessage` promise.

Use pattern 2 when correctness depends on init completing (e.g. Storage Service needs
to ensure the `baseDirectory` namespace exists before reads hit it). Pattern 1 is fine
when the worker can safely queue and process messages in order, because `postMessage` to
a worker is already ordered.

## Main-Thread Globals Don't Exist in Workers

Workers have no `window`, so anything that reads from window globals on the main thread
must be **forwarded over postMessage**. In practice this is almost always `appMeta`
(holds `WebServiceHost` and feature flags):

```ts
// Worker file:
let appMeta: AppMeta;

self.onmessage = (event) => {
  if (event.data.type === 'init' && event.data.appMeta) {
    appMeta = event.data.appMeta;  // cache in module scope
  }
  // ...
};
```

The worker-side API helpers explicitly forbid the direct import:

```ts
// NOTE: Do not import appMeta directly. It uses data on the window
// which is not available in the worker. Instead, use the passed-in webServiceHost.
```

See [[storage-service]] for the full worker-auth story (OIDC token forwarded via OPFS,
`fetchWithAuth` reads it from storage on every call).

## Redundant-Request Guards

The subscription protocol deep-equals incoming options against the stored subscription
before posting:

```ts
const shouldUpdate = !existingSubscription.options || !deepEquals(existingSubscription.options, options);
if (!shouldUpdate) return;
```

This prevents thrashing when hooks re-render with structurally-equal option objects.
`channelDataService` has a dedicated `subscriptionHasChanged` with per-field logic;
`metricsDataService` uses a straight `deepEquals`. Every subscription-protocol service
should have some variant of this guard.

## AbortController per Subscription Id

`channelListService.worker` keeps a `Map<id, AbortController>`. When a new request
arrives for an id with an in-flight controller, the old one is aborted before the new
request starts. `AbortError` in the catch is swallowed (expected); anything else
re-throws. The controller is only removed if it's still the active one — a newer request
may have replaced it already.

Use this any time a subscription can be reissued faster than the backend responds.

## Transferable Buffers

Binary data (Arrow IPC, binary OPFS reads) is posted as a transferable to avoid the
structured-clone copy:

```ts
self.postMessage(data, [arrayBuffer]);
```

The second argument is typed incorrectly in the built-in DOM lib; the channelData
worker suppresses this with a `@ts-expect-error` and a link to MDN. `util/arrow/opfsExplorer.worker.ts`
posts the binary content this way for file reads.

## Worker-Only Import Convention

Some modules must never enter the main-thread bundle:

- `@services/opfs/*` — uses `FileSystemSyncAccessHandle`, which only exists in workers.
- `@util/worker.ts` — the file's header comment: *"Content in this file is for WORKERS
  ONLY! Do not import this file in the main thread, as it will cause all kinds of
  issues, build and otherwise."*
- `*.worker.ts` files themselves — imported by Vite via `new URL(..., import.meta.url)`,
  never by a regular `import` on the main thread.

If you need worker-only functionality from main-thread code, talk to a worker service
(usually [[storage-service]]) instead of reaching through.

## Per-Service Test Quirks

`channelDataService.worker.expression.utils.ts` exists as a sibling file specifically
because the worker's full import chain breaks vitest (imports `self.postMessage` calls
at module eval). Pure helpers get pulled out into their own file so tests can import
them without dragging in the worker module. Watch for this when adding tests for
worker-side logic — if a test fails trying to evaluate the worker entry point, split
the code under test into a pure helper file.

## Related

- [[channel-data-service]] — the richest instance (subscription + MessageChannel + cache).
- [[storage-service]] — the request/response instance; source of the worker-auth pattern.
- [[opfs-service]] — the worker-only primitive that motivates several services.
- [[performance-patterns]] — why workers are worth the complexity.
- [[data-pipeline]] — high-level flow that chains several worker services together.
