---
title: Skills
tags: [backend, chat, domain-concepts]
sources:
  - path: database/migrations/20260612000000_eng_12120_create_skills_table.sql
    last_read: 2026-06-19
  - path: protos/sift_internal/skills/v1/skills.proto
    last_read: 2026-06-19
  - path: services/repo/skill/v1/
    last_read: 2026-06-19
  - path: services/chat/skills/
    last_read: 2026-06-19
  - path: services/chat/tools/load_skill.go
    last_read: 2026-06-19
  - path: web-service/main.go
    last_read: 2026-06-19
created: 2026-06-19
updated: 2026-06-19
last_accessed: 2026-06-19
---

Skills are named, reusable instruction sets for the Sift chat agent (ENG-12120,
merged to `main`). The feature has two layers that are **not yet wired
together**: a user-facing **skill entity** (per-org rows managed by a
`SkillService`, with a web-app table) and the chat agent's on-demand
**`load_skill` tool**, backed by a registry that — as of this commit — is seeded
only from built-in embedded skills, not from the DB entity.

## Data model & isolation

The `skills` table (migration `20260612000000_eng_12120_create_skills_table.sql`)
holds `skill_id`, `title`, `name`, `description`, `content`,
`created_by_user_id`, `organization_id`, `archived_date`, plus created/modified
audit columns, with FKs to `users` and `organizations`.

Row-level security `skills_isolation_policy` enforces **org-level** isolation
(`organization_id` in `app.current_organization_ids`, or `app.is_admin`).
**Per-user** privacy — a skill is visible only to its author or an org admin —
is enforced in the service layer, not in the RLS policy. Indexes: one on
`organization_id`, and a composite `(created_by_user_id, created_date, skill_id)`
that backs `ListSkills`'s keyset pagination.

## SkillService (`services/repo/skill/v1/`)

gRPC + REST (`/api/v1/skills`) CRUD defined in
`protos/sift_internal/skills/v1/skills.proto`: `GetSkill`, `CreateSkill`,
`ListSkills` (filtered by `created_by_user_id`, keyset-paginated by
`(created_date, skill_id)`), and `UpdateSkill`. The web-app surfaces these in a
skills table under `web-app/src/componentsV2/complex/table/search/skills/`. The
service follows the typed-tool / `pbmapper` conventions in [[reactor-adding-tools]].

## Agent skills: the `load_skill` tool (`services/chat/`)

A chat `Skill` is `{Name, Description, Body}` (`services/chat/skills/skill.go`),
held by name in a `Registry` (`registry.go`). `loader.go` parses skills from
embedded `.md` files (frontmatter `name`/`description` + markdown body) via
`DefaultSkills()`, and `web-service/main.go` builds the registry from those at
startup.

Skills load lazily: the system prompt lists each skill's name and one-line
description under `## Available Skills`, and the **`load_skill`** tool
(`services/chat/tools/load_skill.go`) returns a skill's full body by name. This
keeps the base prompt small — the agent pulls the detailed instructions only
when a request matches a skill's description. ([[scv]] uses a parallel,
file-based skill mechanism baked into its VM image, distinct from this.)

## Maturity / open link

Verified from source: the DB entity, `SkillService`, the RLS policy, and the
embedded-backed `load_skill` tool. **Not wired (as of this commit):** the chat
registry is built solely from embedded `.md` skills (`web-service/main.go` →
`DefaultSkills`), so user-created DB skills are not loaded into the agent's
`load_skill` registry — `load_skill` only resolves embedded skill names.
Connecting the user-facing library to the agent looks like a follow-up; treat
the two layers as separate until that wiring lands.
