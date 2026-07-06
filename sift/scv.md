---
title: SCV (Sift Coding Vehicles)
tags: [architecture, infrastructure, agents]
sources:
  - path: ops/scv/
    last_read: 2026-06-17
  - path: internal-docs/src/rfcs/rfc-0204-scv/
    last_read: 2026-06-17
created: 2026-06-17
updated: 2026-07-06
last_accessed: 2026-07-06
---

An **SCV** ("Sift Coding Vehicle") is a one-shot, ephemeral GCE VM that runs the
pi.dev coding agent against a pre-baked Azimuth dev environment: mention `@scv`
from Slack or Linear (or ask `@scv-sift` to review a GitHub PR), a VM spawns,
the agent does the work and opens a draft PR, and the VM self-destructs. This
is distinct from the in-product [[coding-sandbox]] (the `/agents` chat
backend); SCV is operator-facing infrastructure that produces PRs.

Lifecycle, ingress, image-bake, and harness architecture live in `ops/scv/` and
`internal-docs/src/rfcs/rfc-0204-scv/` — query codegraph / read the RFC. This
page keeps the operational knowledge and the code-vs-RFC divergences.

## Operational commands

From `ops/scv/Makefile`:

- `make foundation` — bake a new `scv-foundation` image (~52 min). Needed only
  for dep/toolchain/base-image changes.
- `make bake-canary` — bake a new **canary** app image (`scv-canary` family)
  off the latest foundation (~10 min). The local-dev default; needed for
  changes to the driver, `startup.sh`, `SCV.md`, skills, or app source.
- `make bake-stable` — same bake, published to the `scv` (stable) family the
  deployed ingress boots by default. Run it to promote a finalized image.
- `make deploy` — build `scv-ingress` at HEAD and roll out a new Cloud Run
  revision. No rebake needed for ingress-only changes.
- `make sweep` / `make logs` — fire and inspect the orphan-topic GC sweep.

For invoking and babysitting runs locally, `ops/scv/setup-local.sh` installs
`scv-list`, `scv-ssh`, `scv-logs`, `scv-tail`, and `scv-stop` shell aliases
(IAP-tunneled; needs `gcloud` auth to the SCV project and
`roles/iap.tunnelResourceAccessor`). See `ops/scv/README.md`.

## Canary/stable channel convention

The `image_channel` Packer var (default `canary`) selects the image family:
canary bakes never disturb the team's deployed images; the deployed ingress
boots the latest `scv` (stable) family member by default. A botched channel
value fails the bake (HCL validation) rather than silently clobbering stable.

To boot a canary VM, tag the spawn **`scv:canary`** — honoured in the @scv
instruction text, as a Linear issue label, or as a GitHub PR label. The VM
keeps its `scv-<run_id>` name and carries a `channel` GCE label
(`canary`/`stable`); `scv-list` shows it, and
`gcloud compute instances list --filter="labels.channel=canary"` filters by it.
Default (untagged) stays stable so the rest of the team is never affected.

Behavior-only changes to the agent mean editing `SCV.md`
(`ops/scv/pi-config/SCV.md`) and rebaking — no driver/ingress change.

## `docker compose stop`, not `down`

The image bake captures the seeded Postgres DB in the snapshot by stopping the
stack with `docker compose stop`, which preserves the named volume; `down -v`
would discard it (`rfc-0204-scv/02-vm-image-pipeline.md`). Keep this rule in
mind anywhere the bake scripts touch the stack.

## Trust code over RFC

SCV moves fast and the code currently leads several RFC chapters. Where they
disagree, trust the code:

- **TTL is 3h, not 6h.** `ingress/src/services/scheduler.ts` sets
  `TTL_WINDOW_MS = 3 * 60 * 60 * 1000` and `refreshTTLJob` slides it forward on
  every inbound publish so an active run never expires mid-conversation. RFC
  chapters 01 and 05 still say a flat 6h with no refresh.
- **Model names in the RFC are illustrative.** `01-architecture.md` labels the
  inference path "Claude Opus 4.7"; the running config is whatever
  `models.json` pins per request, with the vertex-proxy defaulting to
  `claude-sonnet-4-6`. Treat any single model name in the RFC as illustrative.
- Sessions, checkpoints, and the `question`/`awaiting_response` HITL pause are
  live beyond the early RFC chapters; several cleanup items remain open (see
  `08-followup.md`).

## See also

- [[coding-sandbox]] — the in-product agent for the `/agents` chat surface.
- [[dev-commands]], [[project-overview]] — general Azimuth dev workflow and
  product context.
