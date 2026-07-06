---
title: Sift MCP, CLI & API Surfaces
tags: [tooling, domain-concepts]
sources:
  - path: rust/crates/sift_cli  # sift repo; sift-cli subcommands, `mcp`, `install`
    last_read: 2026-06-17
  - path: rust/crates/sift_cli/assets/skills/claude-code/SKILL.md  # agent orientation, order of preference
    last_read: 2026-06-17
  - path: rust/crates/sift_mcp/src/tool  # MCP tool defs + annotations
    last_read: 2026-06-17
  - path: rust/crates/sift_mcp/src/service  # MCP service logic, CEL filter fields
    last_read: 2026-06-17
  - path: rust/crates/sift_stream/README.md  # Rust streaming library
    last_read: 2026-06-17
  - path: python/lib/sift_client  # Python library; see also python/pyproject.toml
    last_read: 2026-06-17
created: 2026-06-17
updated: 2026-07-06
last_accessed: 2026-07-06
---

How an agent or developer works with Sift programmatically. There are five surfaces — the MCP server, `sift-cli`, the REST API, the `sift_client` Python library, and the `sift_stream` Rust library — and a clear order of preference between them. All of this lives in the `sift` repo (`~/code/sift`, crates under `rust/crates/`, Python under `python/`), not in `azimuth`. See [[project-overview]] for product context and [[sift-domain-concepts]] for what assets, runs, channels, rules, and reports mean.

## The five surfaces and when to use each

The canonical guidance is in the agent skill at `rust/crates/sift_cli/assets/skills/claude-code/SKILL.md` (its body is kept in lockstep with the `agents-md/AGENTS.md` variant). Order of preference, stopping at the first that does the job:

1. **MCP server** — preferred for agents. Structured, authenticated, purpose-built tools. Started by `sift-cli mcp`.
2. **`sift-cli`** — terminal use and operations MCP does not cover (importing extra file types, exporting, config).
3. **REST API over cURL** — the complete API surface; reach for it when MCP and CLI do not expose what you need. Docs: `https://docs.siftstack.com/api/rest`.
4. **`sift_client` (Python)** — when the task needs a script: custom streaming, transformation, programmatic logic. Prefer `sift_client` over the deprecated `sift_py`.
5. **`sift_stream` (Rust)** — high-throughput streaming ingestion.

Rough mapping: MCP for agents, CLI for the terminal, REST for raw coverage, `sift_client` for Python scripts, `sift_stream` for heavy ingest.

## MCP tool catalog and safety classification

Tools are defined in `rust/crates/sift_mcp/src/tool/` across three routers — `list_router` (`list/mod.rs`), `data_router` (`data/mod.rs`), and `explore_router` (`explore/mod.rs`) — merged in `src/server/mod.rs`. Server identifies as `SiftMcp` with instructions `"Sift MCP Server"`. Each tool carries a long natural-language `description` (output shape, parameters, errors, guidance) plus an `annotations(...)` block.

**Important on classification:** the only MCP safety hint set in the code is `read_only_hint`. There is no `destructive_hint`, `idempotent_hint`, or `open_world_hint` anywhere in `sift_mcp`. So the catalog splits cleanly into read-only and not-read-only; "destructive" and "idempotent" are not asserted by the tools themselves.

| Tool | Router | `read_only_hint` | Purpose |
|------|--------|------------------|---------|
| `list_assets` | list | `true` | List assets; CEL `filter`, `order_by`, `limit` |
| `list_runs` | list | `true` | List runs |
| `list_channels` | list | `true` | List channels |
| `list_reports` | list | `true` | List reports (extra optional `organization_id`) |
| `list_rules` | list | `true` | List rules |
| `get_data` | data | `true` | Download channel data for an asset/run to a Parquet file |
| `sql` | data | `true` | Run Polars SQL over Parquet file(s), write a new Parquet file |
| `explore_url` | explore | `true` | Build a Sift Explore deep-link; pure URL construction, no API call |
| `upload_dataset` | data | `false` | Stream a Parquet dataset into Sift's ingest service |

`upload_dataset` is the one write/ingest tool and the only one marked not read-only. `get_data` is marked read-only against Sift even though it writes a local Parquet file (the hint describes the effect on Sift, not the filesystem); same for `sql`, which only touches local files. The `upload_dataset` and `sql` descriptions instruct the agent to confirm the destination asset/run with the user before ingesting — a prompt-level guardrail, not a machine annotation.

### Typical pipeline

`get_data` → `sql` → (optionally) `upload_dataset`. `get_data` writes Parquet with column 0 = `timestamp_unix_nanos` (Int64, non-null) and one column per channel named `<channel_name> {channel_id="...", run="...", units="..."}`; enum/bit-field decode config rides in Arrow field metadata. `sql` registers the inputs as one table and emits Parquet. `upload_dataset` requires that same `timestamp_unix_nanos`-first schema, so SQL that aggregates must still emit it.

For "see / view / graph / plot / visualize / open" requests, call `explore_url` (not `get_data`) — it returns a deep-link to render inline. Panel types: `timeseries` (default), `histogram`, `table`, `fft`, `metrics`, `scatter-plot`, `geo-map` (from `service/explore/mod.rs`). Channel prefixes bind axes/roles: `L1:`/`L2:` for multi-axis, `x:`/`y:`/`color:` for scatter, `lat:`/`lon:`/`color:` for geo.

## Filters and queries

The list tools take a `filter` string that is a **CEL expression**, plus an optional `order_by` (comma-separated `FIELD_NAME[ desc]`) and `limit`. An empty `filter` string lists everything. `limit` in `1..=1000` caps the result set; omitting it or passing above 1000 returns all matches (paginated server-side). These are full descriptions in `rust/crates/sift_mcp/src/tool/list/mod.rs`; they enumerate the exact filterable and orderable fields per resource.

Filterable fields by resource (from the tool descriptions):

- **assets:** `asset_id`, `name`, `name_lower`, `tag_id`, `tag_name`, `created_date`, `modified_date`, `archived_date`, `is_archived`, `created_by_user_id`, `modified_by_user_id`, `metadata`.
- **runs:** `run_id`, `organization_id`, `asset_id`, `asset_name`, `client_key`, `name`, `description`, `start_time`, `stop_time`, `duration`, `duration_string`, `tag_id`, `asset_tag_id`, `annotation_comments_count`, `annotation_state`, `created_date`, `modified_date`, `archived_date`, `is_archived`, `created_by_user_id`, `modified_by_user_id`, `metadata`.
- **channels:** `channel_id`, `asset_id`, `name`, `description`, `run_id`, `run_name`, `run_client_key`, `created_date`, `modified_date`, `created_by_user_id`, `modified_by_user_id`.
- **reports:** `report_id`, `report_template_id`, `tag_name`, `name`, `run_id`, `is_archived`, `archived_date`, `created_date`, `created_by_user_id`, `metadata`, `modified_date`, `modified_by_user_id`.
- **rules:** `rule_id`, `client_key`, `name`, `description`, `is_external`, `asset_id`, `tag_id`, `created_date`, `created_by_user_id`, `metadata`, `modified_date`, `modified_by_user_id`, `deleted_date`, `is_archived`, `archived_date`, `is_live_evaluation_enabled`.

Conventions worth knowing:

- Reference metadata entries as `metadata.{key}`, e.g. `metadata.vehicle_type == "rover"`.
- Scope `list_channels` with `asset_id == "..."` — channel namespaces are per-asset, so unscoped queries return cross-asset results.
- Default sort differs by resource: assets/runs/reports/rules default to `created_date desc` (newest first); **channels default to `created_date` ascending** (oldest first).
- Run durations: `duration` is numeric seconds; `duration_string` accepts the `duration('10h')` helper with `h`/`m`/`s`/`ms` suffixes.

These descriptions call the grammar "CEL" and give equality/comparison examples (`==`, `>`, the `duration(...)` helper). I did not find a formal CEL grammar document or the server-side parser in this repo; the authoritative field lists are the tool descriptions above and the gRPC `List*Request.filter` fields. Treat exotic CEL operators as unverified until checked against the API. The MCP `sql` tool is a separate query surface — **Polars SQL** over local Parquet files (`service/data/mod.rs` uses `polars::sql::SQLContext`), not CEL and not server-side.

## sift-cli

Built in `rust/crates/sift_cli`; binary name `sift-cli`. Subcommands (from `src/cli/mod.rs` and `src/main.rs`):

- **`config`** — `show`, `where`, `create`, `update` (`--grpc-uri`, `--rest-uri`, `--api-key`, or `-i` interactive). Profiles live in a TOML config file; each profile needs `grpc_uri`, `rest_uri`, and `apikey`.
- **`import`** — `csv`, `parquet flat-dataset`, `parquet cpr` (channel-per-row), `tdms`, `hdf5`, `backups` (re-ingest `sift_stream` disk backups). HDF5 supports bool, int/uint 8–64, float32/64.
- **`export`** — `run` and `asset` to a file via `--format`, with channel/calculated-channel selection and regex filters.
- **`mcp`** — start the Sift MCP server (gated behind the `mcp` cargo feature). `src/cmd/mcp.rs` calls `sift_mcp::run(...)`.
- **`ping`** — verify credentials and connectivity.
- **`install`** — `completions` (shell completions) and `agent-skills <agent>` (writes the bundled Sift skill for an agentic assistant; `--print`/`--output`).
- **`doc`** — serve bundled CLI docs over HTTP.

Global flags: `--profile <name>` and `--disable-tls` (for non-cloud Sift environments).

## Setup (running the MCP server)

`sift-cli mcp` loads the active profile (gRPC URI, REST URI, API key) via `cmd::Context` and starts the server over stdio. To register it with an agent host, point the host at `sift-cli mcp` as the MCP command. `sift-cli install agent-skills <agent>` drops the orientation skill (the SKILL.md above) so the agent knows the order of preference and pipelines. Verify connectivity first with `sift-cli ping`.

## sift_client (Python)

Library module is `sift_client`, living at `python/lib/sift_client` (`client.py`, `config.py`, `resources/`, `transport/`, `sift_types/`). The published package is `sift_stack_py` (`python/pyproject.toml`, currently v0.17.1). The older `sift_py` module is **deprecated** — use `sift_client` and fall back to `sift_py` only when `sift_client` lacks a capability. Reach for Python when the task is a script: custom streaming, transformation, or logic the MCP/CLI/REST surfaces cannot express. Reference: `https://sift-stack.github.io/sift/python/latest/reference/sift_client/`.

## sift_stream (Rust)

`rust/crates/sift_stream` — a Rust telemetry streaming library for high-throughput ingestion (`README.md`). Task-based async architecture over bounded channels. Entry points: `SiftStreamBuilder` → `SiftStream<E, T>`, where the encoder is separated from the transport. Transport modes: `LiveStreamingOnly` (real-time gRPC, direct backpressure, no checkpointing/backups), `LiveStreamingWithBackups` (adds checkpointing, retry, disk backups), and `FileBackup` (rolling disk files, no live network). The CLI's `import backups` re-ingests files produced by the backup modes. Reference: `https://docs.rs/sift_stream/latest/sift_stream/`.

Sift's product documentation is itself queryable through the API: the `/api/v1/docs:search` and `/api/v1/docs:read` endpoints (surfaced to the Reactor agent as the `search_sift_docs` / `read_sift_doc` tools, `services/chat/tools/` + `services/repo/docs/v1/` in azimuth — query codegraph) answer "how does Sift work" questions.

See [[data-fetching]] for how the frontend consumes channel data (a different, RTK-Query path), distinct from these agent/programmatic surfaces.
