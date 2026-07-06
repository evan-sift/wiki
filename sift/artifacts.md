---
title: Artifacts
tags: [backend, chat]
sources:
  - path: web-service/model/chat_artifact.go
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: services/chat/artifacts/service.go
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: services/chat/artifacts/connectrpc_handler.go
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: protos/sift_internal/chat/v1/chat_artifacts.proto
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: database/migrations/20260613120000_eng_12189_create_chat_artifacts.sql
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: services/repo/remote_file/v1/authorization.go
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: web-service/authorization/authorization.go
    branch: ENG-10586-artifacts-v1
    last_read: 2026-06-17
  - path: internal-docs/src/rfcs/rfc-0193-sift-agents/12-artifacts.md
    last_read: 2026-06-17
created: 2026-06-17
updated: 2026-06-17
last_accessed: 2026-06-17
---

An artifact is a first-class file attached to a Sift Agents conversation, stored in S3 via `remote_files` and surfaced as a standalone object rather than inline transcript text. Each artifact is a container with append-only versions; the bytes of every version live in one `remote_files` row. The backend foundation (ENG-12189, under the ENG-10586 tranche) is built and tested but lives only on the unmerged feature branch `ENG-10586-artifacts-v1`.

## Maturity (read this first)

Artifacts are **not on `main`** as of 2026-06-17. The backend foundation is implemented on the branch `ENG-10586-artifacts-v1` (commits prefixed `ENG-12189:`), not pushed and with no open PR. Treat everything below as describing that branch, not shipped behavior.

What exists on the branch: the migration, the internal `ChatArtifactService` proto and ConnectRPC service, the data layer with append-only versioning, the `remote_files` integration, ABAC/RBAC download authz, and pb mappers. Server registration is behind the `ChatAgentsService` feature flag (`web-service/main.go`, `web-service/connectrpc.go`).

What does not exist yet: agent-facing tools (`read_artifact`, `update_artifact`), the frontend `artifact` stream event and UI drawer, user-upload UX, and the multipart upload path for large files. The RFC at `internal-docs/src/rfcs/rfc-0193-sift-agents/12-artifacts.md` frames these as future work. The RFC is design vision; the branch is the implemented subset.

## Data model

Two tables, mirroring the container/version split used by `rules`/`rule_versions` (`database/migrations/20260613120000_eng_12189_create_chat_artifacts.sql`):

- `chat_artifacts` — the container. Holds `chat_artifact_id`, `conversation_id` (FK to `chat_conversations`, `ON DELETE CASCADE`), `organization_id`, `kind`, `authoring_kind`, `created_by_user_id`. One per artifact, stable for its lifetime.
- `chat_artifact_versions` — one append-only row per revision. Holds `version` (monotonic per artifact), `title`, `summary`, `authoring_message_id` (FK to `chat_messages`), `source_tool_use_ids TEXT[]`, plus org and creator. No payload column. `UNIQUE (chat_artifact_id, version)` enforces version uniqueness and also serves artifact lookups and latest-version ordering, so no separate per-artifact index exists.

Both tables enable row-level security with the standard org-isolation policy (`app.is_admin` or `organization_id` in `app.current_organization_ids`).

`kind` is one of `MARKDOWN`, `CODE`, `IMAGE`, `PDF` (proto enum `ChatArtifactKind`). `authoring_kind` is `AGENT` or `USER` (`ChatArtifactAuthoringKind`). These are stored as the proto enum `.String()` value in the `TEXT` columns.

## Storage (S3 via remote_files)

Each version points 1:1 to a `remote_files` row, so artifact bytes ride the same S3 path as every other user file: same buckets, encryption, lifecycle, and signed-URL helpers (see [[storage-service]] for the frontend file-access side). The migration adds the enum value `'chat_artifact_versions'` to the `remote_file_entity` type. The reverse pointer is `remote_files.entity_id = chat_artifact_version_id` with `entity_type = 'chat_artifact_versions'` (`web-service/model/chat_artifact.go`, `insertChatArtifactVersion`). PostgreSQL cannot drop enum values, so the migration's down step leaves `'chat_artifact_versions'` in place and notes this.

Clients do not receive bytes inline on read. The version proto carries joined file facts (`remote_file_id`, `file_name`, `mime_type`, `file_size`) so the UI can render chrome, then fetches content through `RemoteFileService.GetRemoteFileDownloadUrl` (`protos/sift_internal/chat/v1/chat_artifacts.proto`).

## Service and RPCs

`ChatArtifactService` is an internal ConnectRPC service (`services/chat/artifacts/service.go`), not public and not part of `ChatService`. Methods: `CreateArtifact` (container + version 1), `CreateArtifactVersion` (append max+1), `GetArtifact` (by container ID for latest, or version ID for a pinned version, via a proto `oneof ref`), `ListArtifacts` (per conversation, latest version each, newest first), `ListArtifactVersions` (full history, newest first).

S3 upload happens at the **service layer**, not the data layer. `services/repo/remote_file` imports `web-service/model`, so model calling `S3Upload` would create an import cycle. The service computes the storage key via `remoteFiles.S3Upload` (using an arbitrary UUID decoupled from the version PK) and passes it into the data-layer create, which writes the version row and its `remote_files` row in one ambient transaction. If `S3Upload` fails, the store is never called — verified by unit tests on the branch.

## Conversation and org inheritance

Artifacts inherit org from the resolved conversation, **not** the caller's transaction org. `CreateArtifact` resolves the conversation, then persists with `OrganizationID: conv.OrganizationID`; `CreateArtifactVersion` resolves the parent container first and reuses `artifact.OrganizationID` (`services/chat/artifacts/service.go`). This keeps every version of an artifact in the conversation's org even if the caller's transaction org differs.

Write authorization is author-only, mirroring `UpdateConversation`: `requireAuthorConversation` returns NotFound if the conversation is not visible in the caller's org (cross-org reads are also RLS-filtered to NotFound), and PermissionDenied unless the caller is the conversation author or an admin. `requireMessageInConversation` rejects an `authoring_message_id` that does not belong to the conversation.

## Versioning and authz

Versions are append-only. `CreateChatArtifactVersion` takes a `FOR UPDATE` lock on the container row, computes `COALESCE(MAX(version), 0) + 1`, and inserts; the `UNIQUE (chat_artifact_id, version)` constraint is the backstop against concurrent appends (`web-service/model/chat_artifact.go`). Prior versions and their `remote_files` rows are never mutated. There is no edit-in-place path.

Download authz for artifact-version files resolves the owning artifact's org and compares it to the requesting org:

- RBAC (`services/repo/remote_file/v1/authorization.go`): the `RemoteFileEntityTypeChatArtifactVersion` case loads the artifact via `GetChatArtifactByVersionID` and, for `VIEW_DETAILS`/`VIEW_DATA`, denies if `artifact.OrganizationID != organizationId`.
- ABAC (`web-service/authorization/authorization.go`, `CanAccessRemoteFileEntityWithAbac`): artifacts are not associated with runs or assets, so policy-based ABAC does not apply; the case returns nil and relies on the RBAC org check.

The existence probe `GetChatArtifactVersionRow` (`web-service/model/remote_file.go`, `RemoteFileEntityExists`) deliberately queries the bare version row without joining `remote_files`, because `InsertRemoteFile` calls the probe before the owning `remote_files` row exists.

## pb mappers and entity wiring

The `remote_file_entity` type round-trips through the pb mappers (`services/repo/remote_file/v1/pbmapper.go`): `RemoteFileEntityTypeChatArtifactVersion` maps to `EntityType_ENTITY_TYPE_CHAT_ARTIFACT_VERSION` (public proto value `7` in `protos/sift/remote_files/v1/remote_files.proto`) and back. Without this, public `GetRemoteFile` on an artifact file would error.

## Upload guards

Inline content is capped two ways (`services/chat/artifacts/`):

- Per-field: `validateContent` rejects empty content, content over `maxArtifactContentBytes` (25 MiB), and missing `file_name`/`mime_type`.
- Transport: the ConnectRPC handler sets `connect.WithReadMaxBytes(maxArtifactContentBytes + 1 MiB)` so oversize bodies are rejected before connect buffers them into memory. The 1 MiB headroom covers other request fields.

Files larger than the cap are intended to use a multipart `/remote-files/upload` path, which is not wired on this branch.

## Related

- [[chat-event-types]] — the conversation streaming event taxonomy. The RFC specifies an `artifact` stream event for agent-authored artifacts, but that event is not implemented on this backend branch.
- [[storage-service]] — frontend file storage/fetch, the path artifact bytes follow once downloaded.
