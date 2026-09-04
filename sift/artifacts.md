---
title: Artifacts
tags: [backend, chat, storage]
sources:
  - path: protos/sift/artifacts/v1/artifacts.proto
    branch: eng-0-generic-artifact-store
    last_read: 2026-09-04
  - path: database/migrations/20260813000000_eng_12189_create_artifacts.sql
    last_read: 2026-09-04
  - path: database/migrations/20260904120000_eng_0_generic_artifact_store.sql
    branch: eng-0-generic-artifact-store
    last_read: 2026-09-04
  - path: web-service/model/artifact.go
    branch: eng-0-generic-artifact-store
    last_read: 2026-09-04
  - path: services/artifacts/v1/artifact_service.go
    branch: eng-0-generic-artifact-store
    last_read: 2026-09-04
  - path: services/repo/remote_file/v1/authorization.go
    branch: eng-0-generic-artifact-store
    last_read: 2026-09-04
  - path: internal-docs/src/rfcs/rfc-0193-sift-agents/12-artifacts.md
    branch: al/ENG-0000/genericize-artifact-store
    last_read: 2026-09-04
created: 2026-06-17
updated: 2026-09-04
last_accessed: 2026-09-04
---

An artifact is an org-scoped, versioned output: a file (bytes in `remote_files`), an opaque blob, or a structured JSON payload. Artifacts are not owned by a conversation. Attachment to a conversation, a Canvas, or any other entity is a link row, and metadata rides the shared `entity_metadata_*` join like every other Sift entity.

## Maturity (read this first)

Two layers exist:

- **On `main`** (ENG-12189 #13487, promoted to the public API in #13894): tables `artifacts`, `artifact_versions`, and a `conversation_artifacts` link table; public `sift.artifacts.v1.ArtifactService` with Create/Get/List/ListVersions, Link/Unlink to a conversation, Archive/Unarchive; `remote_file_entity` value `artifact_versions`. Reads are org-wide, writes are creator-only, offset page tokens, no filter.
- **Branch `eng-0-generic-artifact-store`** (draft PR, stacked on the RFC revision in #13987): the generic store described below. Everything in the sections after this one describes that branch unless marked "main".

## Data model

`artifacts` (container): `artifact_id`, `organization_id`, `created_by_user_id`, `authoring_kind` (`agent` | `user`, who is accountable), `storage_class` (`file` | `structured` | `blob`), `created_via` (`chat` | `canvas` | `sdk` | `upload`, which surface wrote it), nullable `kind` (open semantic label such as `markdown`, `psd`, `table`), `created_date`, `archived_date`. Storage class and created-via are `TEXT` columns with CHECK constraints; existing rows backfilled to `file` and to `chat` when they had a conversation link, else `sdk`.

`artifact_versions` (append-only): `version` (`UNIQUE (artifact_id, version)`), `title`, `summary`, nullable `payload JSONB` (content for `structured`, GIN indexed), `authoring_message_id` (nullable FK to `chat_messages`), `source_tool_use_ids TEXT[]`, org, `created_date`. `MAX(version)+1` on insert with a retry on the unique violation.

`artifact_links`: `relation` (`attached_to` | `source` | `derived_from`), open `entity_type` (lowercase plural: `conversations`, `canvases`, `runs`, `assets`, `artifacts`, `tool_uses`), `entity_id`, nullable `artifact_version_id`. `attached_to` rows are artifact-level; `source` and `derived_from` rows created with a version pin it. Unique on `(artifact_id, relation, entity_type, entity_id, COALESCE(artifact_version_id, zero-uuid))`. No FK to the target: an `AFTER DELETE` trigger on `chat_conversations` removes `attached_to`/`conversations` rows, replacing the old cascade. Cap: 20 `attached_to` links per target entity (`MaxArtifactAttachmentsPerEntity`). `conversation_artifacts` was migrated into this table and dropped (the down migration recreates it).

Metadata: `metadata_entity_type` gains `artifact_version`; values attach to the version id and the CEL filter exposes them as `metadata["<key>"]`. All three tables carry the standard org RLS policy.

## Storage rule

Exactly one of `payload` or a `remote_files` row per version. The service enforces it: `STRUCTURED` requires a payload (protojson-serialized, 1 MiB cap) and the remote-file EDIT authorization rejects uploads for structured artifacts; `FILE` and `BLOB` reject payloads. Storage class is stored, not derived, so a client can decide "download button or payload viewer" without loading content.

## Service (`services/artifacts/v1`)

`NewService(store, metadataService)`. Create defaults: `storage_class` FILE, `created_via` SDK (old clients that send neither keep working). On append, container fields may be omitted or must match. `conversation_id` on create is sugar for a `links` entry `{ATTACHED_TO, conversations, id}`; attaching to a conversation requires being its author. `DERIVED_FROM` needs an in-org target artifact. `SOURCE` links are immutable (`UnlinkArtifact` rejects them). New RPCs: `LinkArtifact`, `UnlinkArtifact`, `ListArtifactLinks`; the conversation RPCs delegate to them.

`ListArtifacts` uses `api_filter` + `util.ListOrdered` (keyset tokens). Filterable: `artifact_id`, `organization_id`, `created_by_user_id`, `authoring_kind`, `storage_class`, `created_via`, `kind`, `title`, `version`, `created_date`, `archived_date`, the `include_archived` directive, `metadata["<key>"]`, and `links.exists(l, l.relation == "ATTACHED_TO" && l.entity_type == "conversations" && l.entity_id == "...")`. Enum values compare as proto names without the prefix (`storage_class == "STRUCTURED"`); the link `relation` sub-field is uppercased in SQL for the same reason. The legacy `include_archived` bool is folded into the filter string so the directive is the single source of truth. Ordering: `created_date` (default asc), `archived_date`, `title`, `version`, `kind`.

## Chat stream and frontend

The internal `ArtifactEvent` (`protos/sift_internal/chat/v1/chat.proto`) carries `storage_class`, `created_via`, `kind` next to the existing chrome. `services/chat/v1/sandbox_artifacts.go` relays artifacts announced by a `create_artifact` tool result: it links them to the conversation and, for a version-1 artifact still at the SDK default, flips `created_via` to `chat` in the same transaction (`model.SetArtifactCreatedVia`), an interim measure until the pod's MCP declares the surface. The web-app `ConversationArtifact` / `StreamedArtifact` types carry `storageClass`, `createdVia`, `kind`, `payload`; `artifactEnumMappers.ts` maps both the connect numeric enums and the OpenAPI string names; the artifact card shows `kind`, marks structured artifacts, and offers no download for them.

## Proto compatibility

All changes are additive (`buf breaking` FILE rules pass): new enums `ArtifactStorageClass`, `ArtifactCreatedVia`, `ArtifactLinkRelation`; new fields on `Artifact`/`ArtifactVersion`/`CreateArtifactRequest`; `filter`/`order_by` on the list request; nothing removed or renamed. The proto is mirrored (sanitized) into the public `sift-stack/sift` repo, where the MCP tools `list_artifacts` / `create_artifact` / `download_artifact` expose the same surface (branch `rust/artifact-store-generic`).

## Related

- [[chat-event-types]] for the conversation stream; agent pods are told to pass `created_via: chat` and `authoring_kind: agent` (`uce_runner/agent_server/resources/pod-environment.md`).
- [[storage-service]] for the frontend file path once bytes are downloaded.
