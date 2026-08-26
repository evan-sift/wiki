---
title: Sift Domain Concepts
tags: [domain-concepts, architecture]
sources:
  - path: protos/sift/assets/v1/assets.proto  # Asset, ListAssets
    last_read: 2026-08-25
  - path: protos/sift/runs/v2/runs.proto  # Run, ListRuns
    last_read: 2026-08-25
  - path: protos/sift/families/v1/families.proto  # Family, FamilyRun, ListFamilies
    last_read: 2026-08-25
  - path: protos/sift/channels/v3/channels.proto  # Channel, ListChannels
    last_read: 2026-08-25
  - path: protos/sift/ingestion_configs/v2/ingestion_configs.proto  # IngestionConfig, FlowConfig, ChannelConfig
    last_read: 2026-08-25
  - path: protos/sift/rules/v1/rules.proto  # Rule, RuleCondition, RuleAction, AnnotationActionConfiguration
    last_read: 2026-08-25
  - path: protos/sift/annotations/v1/annotations.proto  # Annotation, AnnotationType
    last_read: 2026-08-25
  - path: protos/sift/reports/v1/reports.proto  # Report, ReportRuleSummary
    last_read: 2026-08-25
created: 2026-06-17
updated: 2026-08-26
last_accessed: 2026-08-26
---

The data model an agent must understand to answer questions about Sift and operate the product. An asset is the physical or logical system under observation; its telemetry arrives on channels, organized into time windows called runs. Rules evaluate channel conditions and produce annotations; reports aggregate rule results over a run. Definitions below are grounded in the public protos under `protos/sift/`; see [[project-overview]] for the system architecture. For how channel data is served in the frontend or for ingestion internals, query codegraph.

## Asset

An asset is the system being monitored (a vehicle, engine, satellite, test stand, etc.). It is the top-level grouping for telemetry: channels belong to an asset, and runs reference one or more assets.

Source: `protos/sift/assets/v1/assets.proto`, message `Asset`. Key fields: `asset_id`, `name`, `organization_id`, `tags`, `metadata`, `is_archived`. Listed via the `ListAssets` RPC ("Retrieves assets using an optional filter") and the `list_assets` MCP tool.

## Channel

A channel is a single named time-series stream on an asset (one sensor or signal). It carries a typed sequence of timestamped values.

Source: `protos/sift/channels/v3/channels.proto`, message `Channel`. Key fields: `channel_id`, `name` (full channel name), `asset_id`, `description`, `unit_id`, `data_type` (`sift.common.type.v1.ChannelDataType`), `enum_types`, `bit_field_elements`, `active`. Listed via `ListChannels` ("Retrieve channels using an optional filter") and the `list_channels` MCP tool. The v2 message additionally carries `component` and `organization_id` fields that v3 drops; v3 is the current version.

## Run

A run is a bounded time window of data on one or more assets (for example, a single test, mission, or session). Data is queried and exported per run.

Source: `protos/sift/runs/v2/runs.proto`, message `Run`. Key fields: `run_id`, `name`, `description`, `start_time` and `stop_time` (both optional; `start_time` to current time for an ongoing run), `duration` (computed from stop minus start, or start to now if ongoing), `asset_ids` (a run can span multiple assets), `tags`, `metadata`, `is_adhoc`, `is_pinned`, `default_report_id`, `is_archived`. Listed via `ListRuns` ("Retrieve runs using an optional filter") and the `list_runs` MCP tool.

## Family

A family groups related runs for cross-run comparison and aggregate statistics (for example, every run of the same test procedure). Families are versioned: each family has a `current_version_id`, and a family version holds the set of member runs.

Source: `protos/sift/families/v1/families.proto`, messages `Family` and `FamilyRun`. `FamilyRun` "represents a run which is either included in the family or explicitly excluded." Key `Family` fields: `family_id`, `client_key`, `current_version_id`, `is_archived`, `organization_id`. Listed via `ListFamilies` ("Retrieves families using an optional filter"). Families also define time alignments (`FamilyAlignment`) so member runs can be compared on a shared relative time base. The unstable/pre-release marker was removed from the proto in 2026-07 (`e3938ba606`), so the family API is public.

## Run group

Not a distinct entity in the Sift data model. No proto under `protos/` defines a `RunGroup` message, field, or service, and the eval ground-truth set does not reference it. The run-grouping primitive in the product is the Family (above). "Run group" appears only as an incidental phrase in a web-app UI comment, not as a modeled concept; treat it as informal language for a family or for a set of runs, not as a separate resource.

## Ingestion config

An ingestion config is the per-asset schema that declares what data Sift expects to receive. It is the contract a producer ingests against and is tied to a single asset.

Source: `protos/sift/ingestion_configs/v2/ingestion_configs.proto`, message `IngestionConfig`. Fields: `ingestion_config_id`, `asset_id`, `client_key` (a user-defined unique key for retrieval; creating two configs with the same `client_key` errors). An ingestion config contains flows, supplied at creation via `repeated FlowConfig flows` or added later via `CreateIngestionConfigFlows`. Listed via `ListIngestionConfigs` ("List ingestion configs using an optional filter").

## Flow

A flow is a named group of channels within an ingestion config that are ingested together as one record. Flows must have unique names within their ingestion config.

Source: `protos/sift/ingestion_configs/v2/ingestion_configs.proto`, message `FlowConfig`: `name` (required) and `repeated ChannelConfig channels`. Each `ChannelConfig` declares a channel by `name`, `unit`, `description`, and `data_type` (plus `enum_types` / `bit_field_elements`). Listed via `ListIngestionConfigFlows` ("List ingestion config flows using an optional filter"). The v1 `ChannelConfig` also carries a `component` field that v2 drops.

## Rule

A rule defines conditions over channel data and an action to take when those conditions hold. Rules are evaluated on live data (when `is_live_evaluation_enabled`) and during report generation.

Source: `protos/sift/rules/v1/rules.proto`, message `Rule`. Key fields: `rule_id`, `name`, `description`, `is_enabled`, `conditions` (`repeated RuleCondition`), `rule_version` / `current_version_id`, `asset_configuration`, `contextual_channels`, `is_live_evaluation_enabled`, `client_key`, `folder_ids`, `is_archived`. Conditions are expressed via `RuleConditionExpression`: the current form is a `CalculatedChannelConfig` carrying a CEL `expression` plus `channel_references` that bind channel names; an older deprecated `SingleChannelComparisonExpression` used a single channel, a `ConditionComparator` (e.g. `LESS_THAN`, `GREATER_THAN`, `EQUAL`), and a threshold; a third unstable variant, `PythonCode`, also exists. When a condition fires, the rule's `RuleAction` (action type `ANNOTATION`) runs an `AnnotationActionConfiguration` that creates an annotation with a specified `annotation_type`, `tag_ids`, `assigned_to_user_id`, and `metadata`. Listed via `ListRules` ("Retrieves a list of rules") and the `list_rules` MCP tool.

## Annotation

An annotation marks a time interval on a run, optionally linked to channels and assigned to a user. Annotations are either authored manually or created automatically when a rule condition fires.

Source: `protos/sift/annotations/v1/annotations.proto`, message `Annotation`. Key fields: `annotation_id`, `name`, `description`, `start_time`, `end_time`, `run_id`, `annotation_type`, `state`, `tags`, `assigned_to_user_id`, `linked_channels`, `asset_ids`, `created_by_condition_id` and `created_by_rule_condition_version_id` (set when a rule produced it), `report_rule_version_id`, `pending` (set while a rule violation is ongoing and the `end_time` is not yet finalized). The `AnnotationType` enum is the type discriminator:

- `ANNOTATION_TYPE_UNSPECIFIED = 0`
- `ANNOTATION_TYPE_DATA_REVIEW = 1`
- `ANNOTATION_TYPE_PHASE = 2`

A data review annotation (`ANNOTATION_TYPE_DATA_REVIEW`) carries a review `state` and is the type rules emit when a condition is violated; a phase annotation (`ANNOTATION_TYPE_PHASE`) marks a named segment of a run and must have `state` unset. Listed via `ListAnnotations` ("Retrieves annotations using an optional filter").

## Report

Reports come in two types, discriminated by `report_type` (`ReportType` enum, merged from the former canvas reports in 2026-07): `REPORT_TYPE_RULE_EVALUATION` is the result of evaluating a set of rules against one run and aggregates per-rule outcomes and annotation counts; `REPORT_TYPE_CANVAS` is a saved canvas, has an empty `run_id`, and uses its own canvas-specific fields.

Source: `protos/sift/reports/v1/reports.proto`, message `Report`. Key fields: `report_id`, `report_type`, `run_id` (the run evaluated; empty for canvas reports), `report_template_id`, `name`, `summaries` (`repeated ReportRuleSummary`, one line per rule, ordered by `display_order`), `tags`, `job_id`, `rerun_from_report_id`, `is_archived`. Each `ReportRuleSummary` records a `rule_id` / `rule_version_id`, a `ReportRuleStatus`, and annotation counts `num_open`, `num_failed`, `num_passed`. `RerunReport` "will create a new report with the same rule versions and run as the original report and run the evaluation again using the most up-to-date set of data." Listed via `ListReports` ("List reports") and the `list_reports` MCP tool.

## Relationships

- An **asset** owns **channels**; runs reference assets via `asset_ids` (a run can span multiple assets).
- A **run** is a time window over an asset's channels; data is queried and exported per run.
- A **family** groups related runs (via versioned `FamilyRun` membership) for cross-run comparison; it is the only run-grouping primitive. "Run group" is not a modeled entity.
- An **ingestion config** belongs to one asset and contains **flows**; each flow contains **channel configs** that declare the channels ingested together. This is the producer-side schema that backs the channels read above.
- A **rule** evaluates conditions over channel data (CEL expressions binding channel references, or legacy threshold comparisons) and, on a fire, runs an annotation action that creates an **annotation** of a given `annotation_type`. Rule-created annotations carry `created_by_condition_id` and `created_by_rule_condition_version_id`.
- A **data review annotation** (`ANNOTATION_TYPE_DATA_REVIEW`) is the type rules emit; a **phase annotation** marks a named run segment.
- A **rule-evaluation report** evaluates a set of rules against one **run** and aggregates each rule's status and annotation counts (`num_open` / `num_failed` / `num_passed`) into `ReportRuleSummary` lines. A **canvas report** shares the `Report` type but represents a saved canvas, not a rule evaluation.

For agents, discovery is exposed as MCP tools: `list_assets`, `list_channels`, `list_runs`, `list_rules`, `list_rule_versions`, `list_reports`, `list_report_rule_summaries`, `list_report_templates`, `list_annotations`, `list_users` (per the live Sift MCP catalog, 2026-08-25). There is no `list_families` or `list_ingestion_configs` MCP tool; reach those via the REST API or `sift_client`.
