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
created: 2026-04-16
updated: 2026-07-06
last_accessed: 2026-07-06
---

A namespaced key-value store built on [[opfs-service]]. OPFS sync access is
worker-only, so this service owns a dedicated worker that holds the OPFS
access; everyone else (main thread and other workers) talks to it via
`postMessage`. It is the only sanctioned path for main-thread persistence —
TabState, the OIDC token used by worker-side `fetch`, and per-feature caches
all go through it. Protocol and API: query codegraph
(`web-app/src/services/storage/`); the message protocol is generalized in
[[worker-service-pattern]].

## Gotchas

- **Key sanitization is lossy.** `getItemFileName(key)` replaces any
  non-`[A-Za-z0-9._-]` character with `_` — so `foo/bar` and `foo_bar` collide
  — and `handleKeys` reverses the escaping with a blanket
  `.replace(/_/g, '/')`, lossy in the other direction. Avoid keys whose
  slashes and underscores are semantically meaningful.
- **`fetchWithAuth` only supports Keycloak.** The worker-side HTTP helper in
  `api/workers.ts` (auth header + JSON defaults + optional
  `current-organization-id` header) returns `undefined` if no user is in
  storage, and the file comment calls out Keycloak-only support explicitly.
- **Never import `appMeta` in a worker.** `appMeta` is read from `window` on
  the main thread; workers receive it through the `init` message. Use the
  passed-in `webServiceHost` instead — importing it directly breaks in worker
  contexts.
- **Worker-only file convention.** `util/worker.ts`'s header comment ("Content
  in this file is for WORKERS ONLY! Do not import this file in the main
  thread...") establishes the convention for any file that must not enter the
  main-thread bundle — violating it breaks the build. Applies to
  `@services/opfs/*` by extension (see [[opfs-service]]).

## Related

- [[opfs-service]] — the primitive layer this service wraps.
- [[worker-service-pattern]] — the request/response protocol, Vite worker
  idiom, and `appMeta` forwarding generalized.
- [[state-management]] — TabState persistence is the biggest consumer.
