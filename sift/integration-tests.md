---
title: Running Integration Tests
tags: [testing, backend, tooling]
sources:
  - path: web-service/model/integration_test_suite_base.go
    last_read: 2026-08-25
  - path: services/chat/v1/chat_service_integration_test.go
    last_read: 2026-08-25
  - path: docker-compose.base.yml
    last_read: 2026-08-25
  - path: docker-compose.integration-test.yml
    last_read: 2026-08-25
  - path: web-service/docker.local.env
    last_read: 2026-08-25
  - path: makefile
    last_read: 2026-08-25
created: 2026-04-24
updated: 2026-08-26
last_accessed: 2026-08-26
---

How to run Go integration tests against a Postgres + S3-compatible backend.
These tests use the `//go:build integration` build tag and connect to running
services via env vars.

## TL;DR — run against the already-running local dev env

If `make up` is already running, **you do not need to tear it down**. The local
dev postgres (`azimuth/postgres18`) is the same image the integration env uses,
and `make up` provisions the integration users (`read_write_user`, etc.) via
its `create-users` step — they are not baked into the image itself. Run tests
directly against `localhost:5433`:

```bash
PG_HOST=localhost PG_PORT=5433 PG_USER=read_write_user PG_PASSWORD=temp_password \
PG_DB=azimuth CHANNEL_SEARCH_REPLICA_HOST="" \
  go test -tags=integration -timeout 180s -count=1 \
  ./services/chat/v1/...
```

`CHANNEL_SEARCH_REPLICA_HOST=""` skips the read-replica connection — set it
only for suites that exercise the replica path.

`PG_USER=postgres PG_PASSWORD=password` (the superuser) also works against the
local dev postgres if you'd rather not match the integration-env credentials.

Verified 2026-05-07: ran `TestChatServiceIntegrationTestSuite` (then 9
sub-tests, 11 as of 2026-08-25, including `TestChat_MultiToolRound_EndToEnd`)
directly against the running local dev postgres in 1.4s.

## Build tags

| Tag | Files | Run with |
|-----|-------|----------|
| `unit` | `*_unit_test.go` and any file with `//go:build unit` | `go test -tags=unit ./...` |
| `integration` | `*_integration_test.go` and any file with `//go:build integration` | `go test -tags=integration ./...` |

Without the matching tag the build excludes those files and reports
`[no tests to run]`. The repo ships `.vscode/settings.json` with
`"go.buildTags": "integration,unit"`, so VS Code users get gopls coverage of
tagged files; other editors may still show a benign `No packages found for
open file` warning — ignore it, the tests run fine from the CLI.

## Switching to the dedicated integration env (only if local dev isn't running)

The integration env publishes postgres on host port 5433 and s3 on 9090 — the
same ports the local dev env uses, so the two cannot coexist. Bring up the
integration env only when local dev is down:

```bash
make down                          # tear down normal local dev containers
make integration-env-setup-quick   # start containers, create users, run migrations
```

Do not use the bare `make integration-env-up-quick` — it only runs
`docker compose up` and skips `create-users` and the goose migrations, so
`read_write_user` won't exist and `db.Ping()` fails in the suite base.

After testing, switch back:

```bash
make integration-env-down          # note: runs `down --volumes`, wipes the DB
make up
```

## Connection env vars

The test suite base (`web-service/model/integration_test_suite_base.go`)
opens postgres from these:

```
PG_HOST=localhost
PG_PORT=5433
PG_USER=read_write_user      # or postgres
PG_PASSWORD=temp_password    # or password (matches PG_USER)
PG_DB=azimuth
CHANNEL_SEARCH_REPLICA_HOST=  # empty to skip replica
```

Replica suites additionally use:

```
CHANNEL_SEARCH_REPLICA_HOST=channel-search-replica  # inside the compose network
CHANNEL_SEARCH_REPLICA_PORT=5432
CHANNEL_SEARCH_REPLICA_USER=readonly_app_user
CHANNEL_SEARCH_REPLICA_PASSWORD=temp_password
CHANNEL_SEARCH_REPLICA_DB=azimuth
```

From the host, the replica is only reachable under the local dev stack, on
port 5434 (`CHANNEL_SEARCH_REPLICA_HOST=localhost`,
`CHANNEL_SEARCH_REPLICA_PORT=5434`). The integration env publishes no host
port for it.

Some suites also expect an S3 endpoint and `AZIMUTH_ENVIRONMENT=local|test`.
The canonical S3 var is `AWS_ENDPOINT_URL_S3=http://localhost:9090`
(`S3_ENDPOINT` still works as a fallback). Check the suite's setup if a test
fails on S3 or env-aware code.

## make integration-test-quick (Docker-in-Docker run)

`make integration-test-quick` brings the integration env up (via
`integration-env-setup-quick`) and runs the full suite inside a
`sift/base:latest` container on the `azimuth_test_default` network — the
docker-native path. It runs with `-timeout 30s` and injects
`AZIMUTH_ENVIRONMENT=test`. Use this for the canonical run, but for iteration
prefer the host-side `go test` approach above (faster, native debugger, no
docker rebuild).

## Running a single test or suite

```bash
PG_HOST=localhost PG_PORT=5433 PG_USER=read_write_user PG_PASSWORD=temp_password \
PG_DB=azimuth CHANNEL_SEARCH_REPLICA_HOST="" \
  go test -tags=integration -timeout 180s -count=1 \
  -run TestChatServiceIntegrationTestSuite/TestChat_MultiToolRound_EndToEnd \
  ./services/chat/v1/...
```

`-count=1` disables Go's test cache so reruns actually re-execute.

## Related

- [[dev-commands]] — general development commands (unit tests, lint, codegen)
- [[testing-patterns]] — frontend Vitest conventions
