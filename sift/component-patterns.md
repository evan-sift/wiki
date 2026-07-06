---
title: Component Patterns
tags: [frontend, styling]
sources:
  - path: internal-docs/src/web-app/04-components.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/05-hooks.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/11-styling-and-ui.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/18-modals.md
    last_read: 2026-04-12
  - path: internal-docs/src/web-app/22-icons.md
    last_read: 2026-04-12
created: 2026-04-12
updated: 2026-07-06
last_accessed: 2026-07-06
---

Sift has two component directories: `componentsV2/` (modern, preferred) and `components/`
(legacy, migrating). All new components go in `componentsV2/`, organized in three tiers:
`ui/` (primitives), `complex/` (domain-specific), `layout/` (page structure).

## Compound Component Pattern

The standard pattern for new UI primitives. A parent exposes sub-components as static
properties for flexible, declarative composition:

```tsx
<SiftSelect.Root items={items} selectedItem={selected} onSelectedItemChange={handleChange}>
  <SiftSelect.Trigger>
    <SiftSelect.TriggerButton placeholder="Select item" />
  </SiftSelect.Trigger>
  <SiftSelect.Dropdown>
    <SiftSelect.Options>
      {items.map((item, i) => (
        <SiftSelect.Option key={item.id} item={item} index={i}>{item.name}</SiftSelect.Option>
      ))}
    </SiftSelect.Options>
  </SiftSelect.Dropdown>
</SiftSelect.Root>
```

The anatomy: define a Context type, create the context, Root provides it, child components
consume it via a `useXxx()` hook, export as `{ Root, Child1, Child2 }`.

The chart legend (`legendV2`) is a real example of this pattern — query codegraph
for its current structure.

## Radix UI Themes

Radix is the base component library. Use as many out-of-the-box Radix props as possible
before reaching for Tailwind.

**Styling priority**: Radix props > Tailwind classes > Custom CSS > Inline styles (last resort)

**`asChild` pattern**: Radix compound components merge event handlers onto child elements
via `cloneElement`. Custom children **must spread `...props`** onto their root DOM element
or triggers will silently break.

## Hooks Conventions

- Hooks live alongside their components: `component.hooks.ts`
- Names must start with `use` (linter-enforced)
- **Memoize aggressively** (until React 19 compiler): use `useMemo` for derived values,
  `useCallback` for stable function references
- Use `useRef` for mutable values that don't trigger re-renders (DOM refs, flags, abort controllers)
- Always clean up effects: remove listeners, cancel timers, abort fetches

## Modals

Prefer **Radix Dialog** for new modals (co-located trigger + content). Legacy store-driven
modal registry exists at `src/modals/modal_root.tsx` but should not be used for new work.

## Tables

Three table types:
1. **Data Tables** — telemetry data, Arrow-powered, TanStack Table + Virtuoso
2. **Search Tables** — entity listings, compound component pattern with built-in filters
3. **Radix Tables** — lightweight, < 50 rows, no virtualization

## Tailwind Color System

Radix colors exposed as Tailwind utilities with `sift_` prefix:
- `sift_accent` (indigo), `sift_brand` (tomato/#ee4220), `sift_gray`, `sift_blue`,
  `sift_green`, `sift_yellow` (amber), `sift_red` (ruby), `sift_orange`, `sift_slate`
- 12-step scale: `bg-sift_gray-1` (lightest) to `bg-sift_gray-12` (darkest)
- Alpha variants: `bg-sift_accent-a3`
- Semantic utilities: `bg-sift_gray-normal`, `bg-sift_gray-subtle`, `bg-sift_accent-interactive`

## Key Rules

- Prefer `type` over `interface` for TypeScript
- Named exports over default exports
- Use aliased imports (`@componentsV2/*`)
- Don't reorder imports in existing files
- FontAwesome via wrapper; use `<IconButton>` for icon buttons
