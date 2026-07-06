---
title: Testing Patterns
tags: [frontend, testing]
sources:
  - path: internal-docs/src/web-app/12-testing.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-05-01
last_accessed: 2026-05-07
---

Sift uses Vitest with Testing Library. Tests are co-located with source files as
`*.test.tsx` / `*.test.ts`.

## Core Utilities

- `renderWithProviders(<Component />)` — renders with Redux + Theme providers
- `setupStoreWrapperForHook()` — wrapper for `renderHook()` with store
- `vi.fn()` not `jest.fn()` — Vitest, not Jest
- `vi.fn<(value: string) => void>()` — type the mock signature (Vitest 4+)

## Key Rules

| Rule | Detail |
|------|--------|
| `userEvent` | Do NOT wrap in `act` |
| `fireEvent` | DO wrap in `act` |
| Selectors | Prefer regex: `screen.getByText(/my text/i)` |
| Describe blocks | All test files must have at least one `describe` |
| Mock paths | `vi.mock()` path must match the source import path exactly |
| Constructor mocks | Must use `function` keyword, not arrow functions |

## Gotchas

**`pointer-events: none` leak**: Radix `DismissableLayer` sets `pointer-events: none` on
`document.body` when open. If unmounted without closing, it leaks to subsequent tests.
Handled globally in `setupTests.ts` via `afterEach`.

**Duplicate Radix versions**: Multiple versions of `react-focus-scope` cause infinite
focus recursion (stack overflow). Fix with npm `overrides` to force a single version.

**Fake timers**: Configured globally with `shouldAdvanceTime: true`. Prefer `vi.waitFor`
over testing-library `waitFor` when using fake timers — it's fake-timer-aware.

**`renderHook` infinite loops**: Inline array/object literals in `renderHook` callbacks
create new references on every render → infinite `useEffect` loops → OOM. Use
`initialProps` or stable variables outside the callback.

**Worker import side effects**: Pure utility tests that transitively import worker modules
(which instantiate `Worker` at module load) fail in isolation. Extract pure helpers into
separate modules without worker dependencies.

**Flaky parallel tests**: Modules with import-time side effects (FontAwesome registration,
global singletons) race across threads. Refactor import chains, add to
`server.deps.inline`, or mock the heavy dependency.

**Slow UI interaction tests**: Measure render, open, waits, interactions, timer
flushes, and assertions before changing the test. Fake timer advancement is not
necessarily what Vitest reports as duration; the expensive part is often real
jsdom/React work from Radix focus management, portals, downshift, `userEvent`,
and accessibility queries. Use
`userEvent.setup({ advanceTimers: vi.advanceTimersByTime })` with fake timers,
advance only the actual debounce interval, scope repeated queries with
`within(...)`, and split parent payload tests from lower-level widget behavior
when a full Dialog + portal + combobox path is not the behavior under test.

## Playwright Selectors

Priority: `getByRole`/`getByLabel` > `id` > `data-testid`. Namespace selectors by
surface (e.g. `navbar-user-menu-trigger`, `explore-live-mode-button`). Avoid selectors
derived from mutable UI state.
