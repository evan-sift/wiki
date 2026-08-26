---
title: Feature Flags & Analytics
tags: [frontend, operations]
sources:
  - path: internal-docs/src/web-app/13-feature-flags.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/14-analytics.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/25-amplitude-best-practices.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-08-06
last_accessed: 2026-05-07
---

Sift uses Amplitude for both feature flags (Amplitude Experiment) and analytics event
tracking.

## Feature Flags

Flags are defined in `src/services/featureFlags/featureFlags.ts`. Each flag is a string
constant added to the `FeatureFlag` type union.

**In components**: `useFeatureFlag(MY_FLAG)` returns boolean.
**Outside React** (workers/services): `isFeatureFlagOn('flag-name')`.
**Route guards**: `pollFeatureFlagValue({ featureFlag: MY_FLAG, redirectTo: '/' })` in `beforeLoad`.

Adding a new flag requires:
1. Add constant + type union entry in `featureFlags.ts`
2. Add to backend: `services/feature_flags/amplitude_feature_flags.go`
3. Coordinate deployment for on-prem customers

## Analytics

Events are tracked via `src/services/events/events.ts`.

**Naming convention**: `NOUN + VERB` in lowercase with spaces (e.g. `chart date time popover clicked`).

**Track user actions, not system results**:
```tsx
// Good: user action
events.annotationCreateClicked();
// Bad: system result
events.annotationCreated();
```

Analytics patterns are subject to change — consult the Product team before adding events.

## Backend client events API (ENG-12206)

`POST /api/analytics/v1/client-events` lets client libraries (the Sift MCP server
first) record Amplitude events with a Sift API key. Payload: `{"event"}`;
the reporting library self-identifies via the User-Agent header's first
product token (`name/version`, e.g. `sift_mcp/0.4.0`), emitted as
`client_library`/`client_version` (the `client` property stays the
server-derived origin; version may be empty). The handler
(`web-service/handlers/analytics_events.go`) validates `event` against
a closed allowlist of exact event-name strings (`allowedClientEventNames`) —
currently `User called MCP tool <tool>` for every tool in the sift MCP
catalog, mirrored from the sift repo's
`rust/crates/sift_mcp/src/tool/*/mod.rs`
(new MCP tools need a matching entry or their events get 400s). It then
calls `TrackClientEvent` on the backend `AnalyticsService`
(`web-service/services/analytics.go`), which decorates the event with
organization, user, client origin, and `environment` (`AZIMUTH_ENVIRONMENT`).
ONESHOT emission with the standard per-(org, event) hourly budget. Contract
doc: `internal-docs/src/amplitude/client-events-api.md`.
