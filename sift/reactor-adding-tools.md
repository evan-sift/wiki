---
title: Adding Sift Agents Tools
tags: [chat, backend, frontend, tooling, architecture]
sources:
  - path: services/chat/tools/list_rules.go
    last_read: 2026-05-05
  - path: services/chat/tools/list_calculated_channels.go
    last_read: 2026-05-06
  - path: services/chat/tools/metadata_querier.go
    last_read: 2026-05-20
  - path: services/chat/tools/tool.go
    last_read: 2026-05-20
  - path: services/chat/tools/write/
    last_read: 2026-05-21
  - path: services/chat/tools/write/selectors.go
    last_read: 2026-05-21
  - path: services/chat/tools/resources.go
    last_read: 2026-05-06
  - path: services/chat/context/profile.go
    last_read: 2026-05-20
  - path: services/chat/v1/tool_proto_converter.go
    last_read: 2026-05-06
  - path: services/chat/v1/tool_approval.go
    last_read: 2026-05-21
  - path: web-service/main.go
    last_read: 2026-05-20
  - path: web-app/src/componentsV2/complex/agent/rightPanel/collectResources.ts
    last_read: 2026-05-05
  - path: web-app/src/componentsV2/complex/agent/tool/agentResourceChips.tsx
    last_read: 2026-05-05
  - path: web-app/src/componentsV2/complex/agent/rightPanel/agentResourcesPanel.tsx
    last_read: 2026-05-05
  - path: protos/sift_internal/chat/v1/chat.proto
    last_read: 2026-05-21
created: 2026-05-05
updated: 2026-05-21
last_accessed: 2026-05-21
---

Checklist for adding a new Sift Agents tool end to end, including typed proto
payloads, backend tool registration, resource refs, and frontend resource chips.
Use [[chat-event-types]] for the parallel recipe when the change is a streaming
chat event rather than a tool/resource surface.

## Backend (Go)

### 1. Proto (`protos/sift_internal/chat/v1/chat.proto`)

- Add `*Input` and `*Output` messages near the other `*Input`/`*Output` types.
- Add the new `*Ref` message near `ChannelRef` / `RuleRef`.
- Add the input to `ToolInput.input` oneof. Existing field numbers are
  assets=1, runs=2, channels=3, query_time_series=4, calculated_channels=5,
  rules=6; continue from 7.
- Add the output to `ToolOutput.output` oneof using the same numbering.
- Add the ref variant to `ResourceRef.ref` oneof. Existing field numbers are
  assets=1, runs=2, channels=3, calculated_channel=4, rule=5; continue from 6.
- Run `make generated-local` after changes.

### 2. `services/chat/tools/metadata_querier.go`

- Add a narrow interface, e.g. `RuleLister`, with only the service methods the
  tool needs.
- The interface should be satisfied by the existing service implementation.
- Write tools use the same narrow-interface pattern, but include both read and
  mutation methods plus non-mutating validation methods. For calculated
  channels this is `CalculatedChannelWriter`, which embeds
  `CalculatedChannelReader` and adds validate/create/update methods.

### 3. `services/chat/tools/resources.go`

- Add a builder function such as `RuleRef(ruleID string) *ichatv1pb.ResourceRef`.
- Add the matching `case *ichatv1pb.ResourceRef_Rule:` to `refKey()` so
  deduplication works.

### 4. `services/chat/tools/list_*.go`

- Implement the `Tool` interface: `Name()`, `Description()`, `Guide()`,
  `InputSchema()`, and `Execute()`.
- `Execute` returns `*Result{Data, Resources}`. `Resources` should be
  `dedupRefs(refs)`.
- Use a trimmed output struct, not the full proto, and serialize it with
  `json.Marshal`.
- Do not expose tenant IDs, user IDs, user notes, metadata, or other service
  fields that are not needed by the Sift Agents model.
- For list tools, keep lookup behavior on the same filtered `List` path. Direct
  ID and client-key lookups should be expressed as CEL filters such as
  `rule_id == "<id>"` or `calculated_channel_id == "<id>"`; do not add
  `BatchGet`, `Get`, or version-list escape hatches to the tool interfaces.
- Deduplicate explicit identifiers before service calls and enforce a local
  maximum so model-generated input cannot fan out into unbounded RPCs.
- Treat every model-controlled selector list as a paging/bounding problem, even
  when the tool only builds URLs or `ResourceRef`s. Cap run IDs, asset IDs,
  channel IDs, calculated-channel IDs, and similar inputs after deduplication
  before constructing URLs, resource events, or downstream fetches; oversized
  tool outputs are streamed, persisted, and can later trigger frontend batched
  requests.
- Write tools share a stricter cap (`write.MaxWriteSelectorEntries`, currently
  20) applied per selector list — asset/tag IDs, annotation tag IDs,
  notification user IDs, webhook IDs, and channel references on rule and
  calculated-channel writes. Over-cap input is rejected at `Stage` with an
  `InvalidArgument` error so the model can split the work into smaller turns.
- Use the constructor pattern `NewListRulesTool(lister RuleLister) Tool`.

### 4a. `services/chat/tools/write/*`

- Write tools implement both `Tool` and `WriteTool`. `Execute` must return an
  approval-required error; the chat loop calls `Stage` first and calls `Commit`
  only after an approved `ToolApprovalResponse`.
- `Stage` should validate the exact mutation payload using the authoritative
  service validation path without mutating data, then return a `PendingAction`
  with a concise summary, preview map, optional warnings, validated payload,
  and rationale.
- The chat approval layer persists staged write payloads on the
  `MESSAGE_ROLE_TOOL_APPROVAL_REQUEST` row's server-only
  `ChatMessageInternalMetadata.tool_approval_actions`; there is no separate
  pending-action table. Resume validates the latest message is still the
  matching approval request before committing any approved actions.
- Preview values may use normal Go typed slices, structs, or generated proto
  structs, but they must JSON-marshal into the compact shape the frontend should
  render. The chat approval layer normalizes this JSON shape before creating the
  streamed `google.protobuf.Struct`.
- Mutable write tools must guard commits with the entity version captured at
  stage time. Re-read the latest entity immediately before mutation and reject
  the writeback if the current rule or calculated-channel version differs from
  the staged version.
- Re-read rules and calculated channels through the same list-only service
  surface used by Sift Agents read tools: exact CEL filters with a tiny page size,
  not `BatchGetRules` or `GetCalculatedChannel`.
- `Commit` should deserialize only the staged validated payload, stamp the
  `conversationID` and `actionID` parameters onto the entity (audit prefix on
  `user_notes`, `client_key` for replay protection), execute the service
  mutation, and return a `CommitResult` with a resource ID, summary, and
  resource refs.
- Calculated-channel write tools are registered as
  `create_calculated_channel`, `update_calculated_channel`, and
  `archive_calculated_channel`; archive uses `UpdateCalculatedChannel` with
  `is_archived=true` and an `is_archived` update mask.
- Rule write tools are registered as `create_rule`, `update_rule`, and
  `archive_rule`; create/update stage through `BatchUpdateRules` with
  `validate_only=true`, commit through `BatchUpdateRules` with
  `validate_only=false`, and archive commits through `ArchiveRule`.

### 5. `services/chat/tools/list_*_test.go`

Use `//go:build unit`.

- Mock the service interface.
- Test both list and batch paths.
- Test that the archive filter is applied on list and not applied on batch.
- Test that resource refs are emitted per returned record.
- Test service error branches for every backend call path.
- Test over-cap rejection for every model-controlled selector dimension, not
  just the selector that drives the obvious backend `List` or `BatchGet` call.

### 6. `services/chat/v1/tool_proto_converter.go`

Add cases in `inputProtoByName`, `outputProtoByName`, `toolInputToJSON`, and
`toolOutputToJSON`.

### 7. `services/chat/context/profile.go`

Add `"list_*": true` to `AgentProfile.Tools`.
For write tools, add the write action names as well; registration alone is not
enough because profile filtering controls what Sift Agents can see and invoke.

### 8. `web-service/main.go`

- Add the new service interface to the `newChatService` signature.
- Pass the concrete service implementation at the call site.
- Register `chattools.NewList*Tool(service)` in `chattools.NewRegistry(...)`.
- Add a focused regression test for the production registry helper so profile
  availability and executable tool registration cannot drift.

## Frontend (TypeScript)

After adding a new `ResourceRef` variant, such as `RuleRef` or
`CalculatedChannelRef`, and running proto codegen, wire the variant into these
files.

### `rightPanel/collectResources.ts`

- Add the new ref type to `CollectedResources`, e.g. `rules: RuleRef[]`.
- Add a `case 'rule':` branch in `absorb()` deduplicating by the ID field.

### `tool/agentResourceChips.tsx`

- Add `RuleResourceChip` / `CalculatedChannelResourceChip` components following
  the `prefetched` pattern: skip per-chip fetch when `prefetched=true` and use
  the panel's batched lookup name instead.
- Add cases in the `ResourceChipForRef` switch and `chipKey` function.
- Use `useRuleDetailsForRuleId` from `@api/hooks/rules.hook` or
  `grpcApi.useCalculatedChannelServiceGetCalculatedChannelQuery` for per-chip
  fetches.

### `rightPanel/agentResourcesPanel.tsx`

- Add the new ID key memos, `useLazy*Query` hook, fetch callback, and
  `useBatchedFetch` call.
- Add the new resource to `ResourceLookups` and `LoadingFlags` types.
- Add a new `SectionDescriptor` in `buildSections()` with icon, label, count,
  and `renderList`.

### `collectResources.test.ts`

Add helper functions and test cases for the new resource types.

## Key patterns

- Icons: `RuleIcon`, `CalculatedChannelsIcon` from `@common/icons/fa`.
- Filter field names for `useBatchedFetch`: `rule_id` for rules and
  `calculated_channel_id` for calculated channels.
- Route paths: `/rules/$ruleId` and
  `/calculated-channels/$calculatedChannelId`.
- The `$typeName` proto field is stripped in `agentToolBlock.tsx` using a
  JSON replacer: `(k, v) => (k === '$typeName' ? undefined : v)`.
- The scroll container (`.agent-resources-scroll`) needs
  `flex: 1; min-height: 0; overflow-y: auto`.

## See also

- [[chat-event-types]] - parallel recipe for adding streaming event types
- [[skills]] - the `load_skill` tool and the skills entity follow these typed-tool conventions
