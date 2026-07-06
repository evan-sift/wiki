---
title: Rich Text Editor Options
tags: [frontend, architecture]
sources:
  - path: web-app/src/componentsV2/ui/commentEditor/
    last_read: 2026-04-17
  - path: web-app/src/pages/reactor/
    last_read: 2026-04-17
created: 2026-04-17
updated: 2026-04-17
last_accessed: 2026-05-20
---

Azimuth already has one real rich-text surface: the Lexical-based `CommentEditor` under `web-app/src/componentsV2/ui/commentEditor/`. The main practical lesson is that editor choice should follow the document model and interaction needs, not the visual size of the input. For lightweight agent/chat composers, a plain textarea behind a stable adapter boundary is the safest default; richer editors only start paying for themselves once mentions, inline entities, or document-like structure become first-order requirements.

This page complements [[component-patterns]] by focusing specifically on editor selection and the tradeoffs between textarea-first, Lexical, Tiptap, and raw ProseMirror.

## Current Baseline In Azimuth

The existing `CommentEditor` is built on Lexical (`CommentEditorRoot` uses `LexicalComposer`, and `CommentEditorTextArea` wires `PlainTextPlugin`, `HistoryPlugin`, `OnChangePlugin`, and the local mentions plugin). The important architectural detail is not just "Azimuth uses Lexical" but that the editor is already wrapped behind an adapter boundary:

- the editor emits generic `CommentBodyElement[]`
- adapters translate that payload into domain-specific API types
- submit/loading behavior is injected through `CommentEditorAdapter`

That pattern is reusable outside comments. It keeps editor concerns local while letting product surfaces evolve independently from transport or API shapes.

## Option Summary

### Textarea

Use a textarea when the interaction model is still basically plain text:

- chat prompts
- agent commands
- simple multi-line notes
- inputs where `Enter` / `Shift+Enter` semantics matter more than formatting

Strengths:

- lowest implementation and testing cost
- easiest to style and keep fast
- simplest undo/selection/paste behavior
- easiest to replace later if the boundary is clean

Weaknesses:

- no structured inline entities
- no real schema for mentions, attachments, or embeds
- richer behavior eventually becomes string parsing and ad hoc state

Best use in Azimuth: early-stage chat or agent surfaces, especially when the surrounding shell is still changing.

### Lexical

Lexical is the best "compact rich input" option already present in the repo. It works well when the UI still looks like a chat composer but the product needs structured inline behavior:

- user mentions
- inline tokens/entities
- controlled submit shortcuts
- richer paste handling
- deterministic serialization into app-specific data structures

Strengths:

- already used in Azimuth
- existing mentions infrastructure reduces adoption cost
- good fit for bounded, app-specific editors rather than full document authoring
- plugin model maps well to incremental capability growth

Weaknesses:

- more moving parts than a textarea
- more editor-state ceremony for tests and serialization
- still requires deliberate schema/adapter design to avoid leakage into product code

Best use in Azimuth: chat inputs or comment-like editors that need structured inline entities soon, but do not yet need a full document editor model.

### Tiptap

Tiptap is the strongest "headless editor platform" option when the product is moving toward richer authoring rather than a chat box. It sits on top of ProseMirror and is most compelling when the future roadmap includes things like slash commands, embeds, tables, and more document-like composition.

Strengths:

- large extension ecosystem
- headless model works well with custom UI
- good long-term fit for document-style editing
- free/open-source core is enough for substantial use cases

Weaknesses:

- introduces more framework than a simple composer needs
- some higher-level features are commercial
- migration cost is harder to justify if the real need is still "nice textarea plus a few entities"

Best use in Azimuth: document-like authoring surfaces, not first-pass chat foundations.

### ProseMirror Directly

Using ProseMirror without Tiptap is the lowest-level option. It offers maximum control over schema, transactions, and plugins, but that control comes with the highest implementation cost.

Strengths:

- most flexible document model
- best option when highly custom editor semantics matter

Weaknesses:

- highest engineering cost
- most framework surface to own directly
- not justified unless Tiptap/Lexical abstractions are actively in the way

Best use in Azimuth: only if a future product surface needs deep custom document behavior that higher-level wrappers cannot express cleanly.

## Licensing Notes

Tiptap should not be treated as "paid-only." The practical split is:

- core editing stack: free / open source
- advanced hosted or productized capabilities: paid

That means Tiptap is viable from a cost perspective for many teams, but the license model matters if the roadmap assumes built-in collaboration, comments, AI features, or other premium extensions.

## Selection Heuristic

Use this rule of thumb:

1. Start with a textarea if the product only needs text entry plus keyboard semantics.
2. Move to Lexical if the input still behaves like a compact composer but now needs structured inline entities.
3. Move to Tiptap if the surface is becoming a real authoring environment.
4. Reach for raw ProseMirror only when the product needs editor primitives below what Tiptap or Lexical make ergonomic.

## Recommendation

For new agent/chat work in Azimuth, default to a textarea-first composer behind an adapter boundary. Keep the interface shaped so the value can later become structured data, but do not pay rich-text complexity before the product proves it needs mentions, attachments-as-nodes, or document-style editing.

If richer chat composition becomes necessary in the near term, Lexical is the most pragmatic upgrade path because the repo already has working editor primitives, an adapter pattern, and mention-specific infrastructure.
