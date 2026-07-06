---
title: Skills
tags: [backend, chat, domain-concepts]
sources:
  - path: services/chat/skills/
    last_read: 2026-06-19
  - path: services/chat/tools/load_skill.go
    last_read: 2026-06-19
  - path: web-service/main.go
    last_read: 2026-06-19
created: 2026-06-19
updated: 2026-07-06
last_accessed: 2026-07-06
---

Skills are named, reusable instruction sets for the Sift chat agent (ENG-12120).
Data model, `SkillService` CRUD, and the `load_skill` tool implementation:
query codegraph. The one thing worth remembering:

## Maturity gotcha: two layers, not wired together

The feature has two layers that are **independent** (as of 2026-06-19):

- The user-facing **skill entity** — per-org DB rows (`skills` table) managed
  by `SkillService`, with a web-app table UI. Per-user privacy (author or org
  admin only) is enforced in the service layer, not in the RLS policy (which is
  org-level only).
- The chat agent's **`load_skill` tool** — backed by a registry that
  `web-service/main.go` builds solely from embedded `.md` skills
  (`DefaultSkills()`).

User-created DB skills are NOT loaded into the agent's `load_skill` registry —
`load_skill` only resolves embedded skill names. Treat the two layers as
separate until that wiring lands. ([[scv]] uses a parallel, file-based skill
mechanism baked into its VM image, distinct from both.)
