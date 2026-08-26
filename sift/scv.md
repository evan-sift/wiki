---
title: SCV (Sift Coding Vehicles)
tags: [architecture, infrastructure, agents]
sources:
  - path: ops/scv/
    last_read: 2026-08-19
  - path: internal-docs/src/rfcs/rfc-0204-scv/
    last_read: 2026-07-14
  - path: ops/terraform/scv/
    last_read: 2026-08-19
created: 2026-06-17
updated: 2026-08-19
last_accessed: 2026-08-19
---

**SCV** is a one-shot GitHub PR review bot. Add `scv-sift` as a reviewer on a
PR (or comment `@scv-sift review`), and an ephemeral GCE VM boots, reviews the
diff with pi.dev, posts inline comments, and deletes itself.
**Multi-repo since 2026-08 (branch `eng-0-scv-sift-repo`)**: a code registry
(`ingress/src/repos.ts`) services `sift-stack/azimuth` (private) and
`sift-stack/sift` (public). Both the trigger sender and the PR author must be
current sift-stack org members (live API check, fail-closed, only definitive
answers cached 5 min); non-members are silently ignored — the author gate
runs before ANY reply, including bad-flag help. One sender exemption:
`github-actions[bot]` on `review_requested` (the auto-request workflow);
the author gate still applies. Isolation is per-slug and IAM-enforced:
image family `scv-<slug>`, VM SA `scv-vm-<slug>` (reads only
`scv-github-token-<slug>`; Linear only for private repos), instance names
`scv-<slug>-pr<N>-<sha8>`, self-delete conditioned per slug. Every per-repo
token must belong to the `scv-sift` account (self-trigger filter), and
comment bodies carrying the summary's `<summary>SCV commands</summary>`
fingerprint never trigger. Public-repo VMs run `SCV_ENABLE_TICKET=0` and
`SCV_PUBLIC=1` (no Linear staging, no internal links, no spend/model stats
in comments), and azimuth's internal doc map lives in the
`ops/scv/repos/azimuth/` overlay so it never bakes into the sift image. The
checkout path is now `/scv/repo` (was `/scv/azimuth`), boot fetches
`refs/pull/N/head` so fork PRs by members work, and `repo_slug`/`public` are
required VM metadata. The nightly `scv_build.yml` bake matrixes over slugs.
**Implementation mode (Slack/Linear coding agents) was removed by
ENG-12894 (2026-07)** — RFC-0204 chapters 01–09 are historical; chapter 10
(`10-pare-down.md`) is the current architecture. **ENG-13153 (2026-07-24)
replaced the single-pass review with an adversarial attack→judge pipeline**, so
RFC-0204 ch. 04's `code-review` skill and ch. 01/05's "pi runs once" are also
historical. Follow-up explorations (`.github/scv.yml` auto-review opt-ins) live
in ENG-12897.

## Architecture in one breath

GitHub webhook → `scv-ingress` (Cloud Run, two routes, stateless; registry +
org-membership gate) → one GCE `instances.insert` named
`scv-<slug>-pr<N>-<headSha[0:8]>` on `e2-standard-8` with
`maxRunDuration=3600s` + `instanceTerminationAction: DELETE` and
`requestId=<X-GitHub-Delivery>` → VM clones the repo at the PR head into
`/scv/repo` (no repo in the image), stages
diff/context/threads/optional-Linear-ticket under `/scv/scv-review/inputs/`,
partitions the diff, runs several credential-less `scv-agent` pi passes,
rechecks the PR head, posts findings, self-deletes.

## The adversarial pipeline (ENG-13153)

`scripts/scv-pr-review.sh` is five stages: stage inputs → partition → attack →
judge → validate.

- **Why it exists.** The old single pass under-reported badly: across the 25
  runs before the change, zero `critical` findings, mostly `nice-to-have`, 8
  "No new findings", and PR 12805 (29 files, +1525) came back clean. One agent
  both proposed candidates and applied every filter that killed them, so `[]`
  was the cheapest outcome. The old prompt already ordered an adversarial pass
  and the model skipped it — which is why the fix is structural, not wording.
- **Partition is code, in `scv-driver/src/slice.ts`.** ~400 diff lines per
  slice, clamped to 2–6, generated/lock/binary dropped first, greedy
  bin-packing largest-file-first. `K` also clamps to the file count, so a
  one-file PR gets one slice and leans on the cross-cut pass.
- **Attackers have no confidence floor and never see `pr.review-threads.md`.**
  That file goes only to the judge. Giving it to a hunter makes it drop live
  issues on the strength of an old conversation. This is enforced by *staging
  order*, not by wording: `fetch_review_threads` runs in section 8, after the
  fan-out, because `inputs/` is world-readable and every pass shares one uid — so
  staging it up front would have made the split prompt-level. Side effect: the
  all-generated-files early exit never stages the thread map, so prior threads
  are neither resolved nor listed as unresolved on such a PR.
- **A failed coverage gate costs a pass its coverage claim, not its findings.**
  Failed passes' candidate files are still handed to the judge, labelled
  `COVERAGE GATE FAILED`. Dropping them silently discarded substantiated defects
  — the same under-reporting the role split exists to remove — and the judge
  prompt's "read every `out/candidates-*.json`" contradicted the task message
  that listed only `ok` passes.
- **Usage aggregation must not follow symlinks.** `cat out/usage-*.jsonl` runs as
  ubuntu over a directory the passes can write, so a planted symlink would copy
  `/home/ubuntu/.config/gh/hosts.yml` or the Linear token into an agent-readable
  path, and a link to a FIFO or `/dev/zero` would hang the review or fill the
  disk. The loop now takes regular files only, never symlinks.
- **`coverage.json` carries `candidatesRaised`.** Without it, "the attackers
  found nothing" and "the judge rejected everything" render identically, and the
  per-pass transcripts that would settle it die with the VM. The driver prints it
  next to the finding tally. Optional field — an older image omits it.
- **There is a dollar cap as well as a wall clock** (`SCV_COST_CAP_USD`, default
  15). Priced by `scv-driver/dist/cost.js`, which reuses `parseReviewUsage` +
  `MODEL_RATES` so bash never holds a second copy of the rate table, and which reads
  the per-pass `out/usage-*.jsonl` because the aggregate is not built until after the
  judge. Parallel passes cannot be metered mid-flight, so the cap gates the coverage
  re-prompts; the judge always runs even over cap, because skipping it spends the
  budget and posts nothing. An unpriced model prices as 0 rather than aborting.
- **A timed-out pass used to lose everything.** `timeout` SIGTERMs pi with no
  flush, so a cross-cut that ran to its 1485s cap produced no candidates file and
  its whole spend was wasted. The role prompts now require writing a valid object
  as soon as the first `files` entry exists and rewriting it per file; round 2's
  failed-pass handoff then carries the partial result to the judge.
- **Cost is output tokens, not token count.** Two measured reviews (7.9M tok/$13.76
  and 10.6M tok/$16.67, all opus at xhigh) solve to ~70% of spend being output —
  mostly thinking at $25/M — and only ~30% cache reads at $0.50/M. So the levers are
  the output *rate* and the thinking *volume*, not the context size. Defaults are now
  attackers on `claude-sonnet-4-6` at `high` and the judge on `claude-opus-4-8` at
  `xhigh`, projecting ~$6–8. **The two must move together:** sonnet's
  `thinkingLevelMap` declares only `max`, and `clampThinkingLevel` walks *forward*
  through `off…xhigh,max`, so leaving `xhigh` on sonnet resolves **up** to `max` and
  costs more than opus did.
- **The confidence floor is 50, with uniform 10-point bands.** 50–59 speculative,
  60–69 tentative, 70–79 mild, 80–89 medium, 90–99 strong, 100 absolute. The four
  bands at 70+ kept their original thresholds so no previously-postable finding
  changed label. The judge prompt says explicitly to use the whole range and not to
  round a 55 up to 70 — rounding into one band is the same under-reporting the role
  split exists to fix.
- **The cross-cut pass has no per-file ledger.** Its file coverage is guaranteed by
  the slice contracts, and `coverage.json` only ever read slice statuses
  (`unreviewedFiles` comes from failed slices), so requiring one `{path, hunks, risk,
  assessment}` object per reviewable file cost ~20k mandatory output tokens on a
  568-file range — the longest pole in the fan-out — for accounting nobody read.
- **The coverage gate is the load-bearing part.** Each attacker emits
  `{files, candidates}` and the wrapper checks `files[]` accounts for every path
  in its contract — one re-prompt, then the slice is marked failed. This is what
  stops skimming, and it is deliberately not a prompt instruction. The contract
  is a staged file so both sides spell paths identically: `inputs/slice-<id>.files`
  per slice, `inputs/crosscut.files` (manifest-derived) for the cross-cut pass,
  and the staging `git diff` runs under `-c core.quotePath=false` so a non-ASCII
  path is not C-quoted into a name the attacker cannot open.
  **It checks enumeration, not inspection** — only `.files[].path` is read, so a
  ledger of bare `{path}` entries passes even though the prompts demand
  `hunks`/`risk`/`assessment`. Extras are logged, never fatal.
- **`SCV_PR_REVIEW_TIMEOUT` is a hard wall clock, not just a split.** 55% per
  attacker / 35% judge / 10% reserved is the nominal share, but the serial
  coverage re-prompt sits outside that split, so re-prompts and the judge are
  each clamped to what remains of the total (floor 120s — `timeout 0` means *no
  limit*). Unclamped, attack + re-prompts + judge outran `maxRunDuration`, GCE
  deleted the VM mid-judge, and nothing was posted.
- **`run_pass` saves and restores errexit instead of re-enabling it.** `set -e`
  is shell-global, so a bare `set -e` before `return "$rc"` fires at the
  *caller* and killed every rc-inspecting salvage path — a judge that timed out
  after writing findings, and the coverage retry.
- **Empty slices are never emitted.** Zero-diff-line files (pure renames,
  mode-only changes) add no load, so the bin-packer leaves trailing buckets
  empty; `planSlices` filters them before assigning ids, or an attacker gets
  pointed at an empty file contract.
- **Role prompts arrive via `--append-system-prompt`**, not skills. Verified
  that it reads *file contents* and that `--no-skills` yields an empty skill
  set, so prompt delivery no longer depends on description matching.
- **Attackers get pi's `subagent` extension** plus three read-only recon agents
  in `~/.pi/agent/agents/`. Two things bound recursion depth: each agent pins a
  `tools:` allowlist omitting `subagent`, and the bake patches the extension so
  children spawn with `--no-extensions --no-skills --no-context-files` (the
  upstream example passes none of those, so an unpatched child could
  auto-discover the extension and get `subagent` back).
- **The extension is copied from the pinned npm install at bake time**
  (`$(npm root -g)/@earendil-works/pi-coding-agent/examples/extensions/subagent`),
  not vendored. A pi bump that drops the example fails the bake loudly.

## Non-obvious operational knowledge

- **The instance name IS the dedupe.** A 409 on insert = review already
  running for that exact head SHA (the bot comments "already running").
  Deletion is the release. There is no Firestore, no Pub/Sub, no Cloud
  Scheduler, no `--force` (it's parsed and ignored; preempt with
  `scv-delete <name>` if you must).
- **The VM's boot ack ("Reviewing this PR…") is the success signal.** No ack
  within ~2 min = the VM never started — just re-trigger. After the insert is
  accepted the ingress watches the zonal operation for 12 s (`OP_WAIT_MS`,
  branch `eng-0-scv-handle-force`): fast placement failures — the 2026-08-25
  `ZONE_RESOURCE_POOL_EXHAUSTED` stockouts reached DONE in ~9 s — now post a
  PR comment naming the op error code and the re-trigger remedy. Slow
  failures still pass silently: on 2026-08-24 three e2-standard-8 inserts
  failed placement with GCE `INTERNAL_ERROR` ~5.5 min later (healthy ops take
  17–28 s), and the fix (branch `eng-0-scv-insert-op-check`) was
  right-sizing, not recovery machinery: the VM is now `n2d-standard-8` (e2 is
  the oversubscribed pool with a stockout history here) on a 100 GB pd-ssd
  (16 GB capped I/O at ~7.7 MB/s). Residual slow drops keep the re-trigger
  remedy.
- **A push supersedes in-flight reviews (`eng-0-scv-handle-force`).** On
  `pull_request synchronize` the ingress lists the PR's active review VMs
  (name prefix `scv-<repoHash6>-pr<N>-` — GCE itself is the state store),
  deletes any whose `pr_head_sha` metadata no longer matches the head, and
  respawns one run at the new head seeded from the newest deleted VM's
  metadata (`pr_requested_by`, `model_advisor`, `model_subagent` — a forced
  opus run stays opus across pushes). Cancel-early also stops the superseded
  run's model spend. A PR with no in-flight review is untouched, so reviews
  stay opt-in; a 409 on the respawn (someone re-triggered at the new head
  first) is dropped silently. Before this, a mid-review push burned the run:
  the driver's stale-head gate (`prReview.ts` `shouldPost`) discarded the
  finished review and nothing respawned it (azimuth#13754, 2026-08-25). `startup.sh` also emits `[scv-timing]`
  milestones to /dev/console (durable in Cloud Logging serial output past
  self-delete), and the bake clones the repo into the image so boot
  delta-fetches instead of full-cloning ~612 MiB (needs an image bake; full
  clone remains the fallback).
- **`maxRunDuration` is the only backstop.** A hung VM self-deletes at 1 h via
  GCE, not via any scheduler job. A VM stuck *before* RUNNING needs a manual
  `scv-delete`.
- **Passes share one uid, so the wrapper must not trust `out/`.** Every pi pass
  runs as `scv-agent` and `out/` is group-writable by it, so an attack pass
  carrying PR-controlled text can pre-create any path the wrapper later writes.
  Two consequences, both handled: the judge's `findings.json`/`concerns.json`/
  `resolve.json` are cleared immediately before the judge runs (schema validation
  checks shape, not authorship, and the rc=124 salvage path accepts an existing
  findings.json — a planted one would post unjudged), and every wrapper write
  into `out/` unlinks first, because ubuntu can unlink an scv-agent-owned file
  through the group-writable directory but cannot truncate it in place. That
  includes `run_pass`'s own `usage-<name>.jsonl`, which is the subtle one: the
  redirect is the *last element of a pipeline*, so when it fails the closed pipe
  SIGPIPEs `tee` and then pi, and `${PIPESTATUS[0]}` comes back **141, not 124** —
  the judge's timeout-salvage path never fires and the whole review is lost to a
  single planted zero-byte file. Role prompts live in a root-owned
  `/opt/scv/prompts` for the same reason. The recon agent definitions do not: the
  fix is `chown -R root:root /home/scv-agent/.pi` (`.pi` itself, not just
  `.pi/agent`, or the directory can be renamed and replaced), which needs a bake
  plus a live run first because pi may write inside agentDir even under
  `--no-session`.
- **A planted `out/empty-diff` silences the whole review.** The driver checks that
  marker *before* it reads findings, so one `touch` from an attack pass makes a
  review that ran and found defects post nothing at all — no summary, no failure
  comment, and the "Reviewing…" ack deleted. The wrapper clears it after the judge.
- **Clearing an agent-planted path needs the agent's own `rm`.** ubuntu owns
  `out/` so it can unlink an agent-owned *file*, but it has no write permission
  *inside* an agent-owned *directory* — `rm -rf` as ubuntu gets EACCES on the
  entries and the directory survives. `clear_out_path()` has scv-agent remove it
  first — and chmod first, because rm never restores permissions it lacks, so a
  non-empty directory left mode 500 defeats even the owner's `rm -rf`. Check that
  the path is *gone* rather than that it had a particular shape, and fail loudly
  (`exit 8`) if it is not. **Four** consecutive review rounds each fixed one
  trigger of this class (`rm -f` → `rm -rf` → agent-first → chmod-first +
  post-condition) before the general rule got written down; the lesson is to
  assert the outcome, not to enumerate the ways an attacker can shape the input.
- **Validate the captured value, not the trigger.** `jq` prints its result
  *before* reporting that it could not read the input, and `[ -s ]` is true for a
  directory, so `$(jq … || echo 0)` yields a two-line `"0\n0"` for a missing file,
  a planted directory, *or* a chmod-000 file. The arithmetic that follows then
  errors and silently breaks out of the enclosing `for` loop, dropping every later
  pass from the published count. Guarding the trigger failed twice; the fix is
  `case $v in ''|*[!0-9]*) v=0 ;; esac` on the value, plus rejecting a multi-line
  capture in the concerns filter.
- **pi never activates `grep`/`find`/`ls`.** The default active set is
  `["read","bash","edit","write"]` plus extension tools, so the role prompts say
  `grep` (the bash fallback) rather than naming a tool pi does not offer. Adding
  `--tools` would fix it but also sets `allowedToolNames`, which filters
  *extension* tools — omit `subagent` and every attack pass silently loses its
  recon agents — so it needs a live run to confirm before it can be relied on.
- **pi's own config dir is a cross-pass attack surface, in three places.**
  (1) `<agentDir>/SYSTEM.md` **replaces** pi's built-in system prompt outright
  (`--append-system-prompt` is merely concatenated onto it), and agentDir is
  `$HOME/.pi/agent` for the uid every pass shares — so `run_pass` scrubs
  `SYSTEM.md`/`APPEND_SYSTEM.md`/`settings.json` before every pass. `models.json`
  is the bake's own config and must survive. (2) The subagent extension spawns
  children with only `["--mode","json","-p","--no-session"]`, so without a patch
  they load the PR's `AGENTS.md` as `<project_instructions>` — system-prompt
  authority for attacker-authored text. `install-pi.sh` sed-patches the copied
  extension to add `--no-context-files --no-skills --no-extensions` and fails the
  bake if pi moved the arg list. (3) The project-scope `<cwd>/.pi/SYSTEM.md` and
  `.pi/agents` are covered by deleting `/scv/azimuth/.pi` (below).
- **`out/` is ubuntu-owned, group scv-agent, mode 1775, with `out/logs`
  pre-created as ubuntu.** Agent ownership of the directory would let a pass
  `chmod 700` it or swap `out/logs`, and `tee "$log"` is the one wrapper write
  that cannot unlink first — it would die on EACCES, SIGPIPE pi, and return 141.
  The sticky bit lets passes replace their own files but not entries ubuntu owns.
- **`startup.sh` deletes `/scv/azimuth/.pi` after checkout.** pi's subagent
  extension resolves agent definitions from the nearest `<cwd>/.pi/agents`, and
  cwd is the attacker-controlled checkout. `agentScope` is a parameter *the model
  picks* — the tool description tells it to pass `"both"` — project definitions
  overwrite baked ones by name, a definition omitting `tools:` gets the full
  default tool set, and the extension's "run project-local agents?" confirmation
  is gated on `ctx.hasUI`, which is always false under `pi --print`. Verified
  against the pinned pi 0.81.1 (`index.ts:468,473,505`, `agents.ts:105-108`). So a
  PR could otherwise replace a recon agent's `tools:` allowlist — the only bound
  on fan-out depth.
- **The sandbox is real, not prompt-level.** `scv-agent` runs pi under
  `env -i` with UID-scoped iptables (loopback only — the metadata server
  169.254.169.254 is blocked, so it can't mint VM-SA tokens). The driver user
  (`ubuntu`) holds `gh` auth and does all GitHub mutations. Linear ticket
  context is fetched wrapper-side (static token) and staged as
  `inputs/pr.ticket.md`; pi has no Linear tools.
- **Prior review threads are context, never auto-resolved.** The old
  resolve-everything pass was deleted because it silently swallowed still-valid
  findings. Humans resolve threads. Since ENG-13153 only the judge reads them.
- **Empty diff posts nothing** (marker file `out/empty-diff`); zero findings
  on a real diff posts "No new findings ✅". A diff whose every file is
  generated, lock, or binary yields no slices, skips the model entirely, and
  says so via `out/coverage.json`.
- **`out/coverage.json` is the honesty mechanism.** The wrapper (not the model)
  records which passes completed; the driver turns a failed slice into a
  "Partial coverage" warning naming the unreviewed files. Without it a
  half-finished review renders identically to a clean one.
- **Two output tiers.** Confirmed findings become inline comments; candidates
  the judge found plausible but could not substantiate become an
  "Unconfirmed concerns" list in the summary, capped at 6. Concern tier is
  about the judge's *certainty*, not the defect's size. The wrapper filters
  concerns **per entry** rather than all-or-nothing, matching `readConcerns()` in
  the driver: one bad `lines` string used to discard the whole tier.
- **`vertex-proxy` must stay threaded.** It was a single-threaded
  `HTTPServer`; with concurrent passes one streaming generation blocked every
  other pass. It is now `ThreadingHTTPServer` with a 45-minute cached access
  token (six passes each forking `gcloud auth print-access-token` per request
  was its own bottleneck).
- **Do NOT add rate-limit retry to vertex-proxy.** pi retries overloaded, rate
  limit and server errors itself with exponential backoff
  (`agent-session.js:_isRetryableError` / `_prepareRetry`), so a second layer in
  the proxy would just double the delay. 429/529 are forwarded verbatim on
  purpose. Only 401 is retried, and only once.
- **`--thinking xhigh` clamps *upward* on sonnet.** `getSupportedThinkingLevels`
  treats `xhigh`/`max` as available only when the model's `thinkingLevelMap`
  names them, and `clampThinkingLevel` then walks forward through
  `off…xhigh,max`. Baked `claude-sonnet-4-6` maps only `max`, so an
  `SCV_ATTACK_MODEL=sonnet` pass runs at `max`, not reduced thinking — more
  expensive than the flag reads, never silently dropped.
- **The model name must stay an indirection, not a validated passthrough.**
  `proxy.py` maps the caller's model through `MODEL_MAP` and interpolates the
  *value* into the Vertex URL. A set-membership check that then reused the
  caller's own string is a CodeQL partial-SSRF finding, and because the map is
  currently identity no behavioural test can tell the two apart — keep the
  indirection even though it looks redundant. `MODEL_MAP` and `MODEL_RATES` in
  `scv-driver/src/reviewStats.ts` must stay in lockstep.
- **`vertex-proxy` has tests now**: `vertex-proxy/test_proxy.py`, stdlib
  `unittest`, loaded with `open` patched because the module reads its project
  number at import. `make -C ops/scv test` runs driver + ingress + proxy.
- **The token cache needs both an escape hatch and a fetch timeout.** The TTL is
  a guess at the token's real lifetime, so a 401/403 from Vertex invalidates the
  cache and the request is retried once with a fresh token — nothing has been
  written back to pi at that point, so the retry is invisible. The `gcloud`
  fetch runs under the cache lock, so it carries a 30s timeout; without one a
  hung `gcloud` stalls every concurrent pass until the VM deadline.
- **Diffs are three-dot** (`git diff base...head`) — two-dot was a real bug
  (flagged unrelated base-branch movement).

## Operational commands

From `ops/scv/Makefile`:

- `make bake REPO_SLUG=<slug>` — slim Packer bake per registry repo (~10 min,
  `scv-<slug>` image family, e2-standard-4 / 16 GB (measured: 4.2 GB image +
  ~3 GB boot clone) — no foundation tier, no Docker/Go/Rust, no repo).
  Cloud Build uploads the *local tree*, so a branch bakes without merging.
  `ops/scv/repos/<slug>/{prompts,agents}/` can overlay repo-specific files.
- `make deploy` — build + roll out the `scv-ingress` Cloud Run revision
  (`--min-instances=0`).

Operator CLI (`bash ops/scv/setup-local.sh`): `scv-list`, `scv-ssh <name>`,
`scv-tail <name>` (startup log), `scv-logs <name|all>` (journalctl unit is
`scv-driver`), `scv-delete <name|all>`. Commands take the deterministic
instance name — run ids and sessions no longer exist.

Rollback: roll back the Cloud Run revision; deprecate a bad image
(`gcloud compute images deprecate <name> --state=DEPRECATED` — `gce.ts` boots
the newest non-deprecated family member).

## Gotchas that survived the pare-down

- GCP e2 capacity stockouts in `us-central1-a`/`-b` happen (seen 2026-07-14);
  bake with `ZONE=us-central1-f make bake` when they do. See
  [[scv-bake-failure-modes]] for the historical two-tier failure modes (now
  mostly obsolete — kept for archaeology).
- VM-local logs die with the VM by design; the PR timeline + Cloud Run logs are
  the durable record. Since ENG-13153 each pass has its own transcript under
  `/scv/scv-review/out/logs/` (`slice-<N>.log`, `crosscut.log`, `judge.log`,
  plus `*-retry.log` when the coverage gate fired), so debugging "why did the
  attacker miss this" means `scv-ssh`-ing in before self-delete.
- Secrets: `scv-github-webhook-secret` (ingress, shared across repos),
  `scv-github-bot-token` (ingress org-read token — needs `read:org`),
  `scv-github-token-<slug>` (per repo: ingress + that repo's VMs),
  `scv-linear-api-token` (private-repo VMs only). Each `scv-vm-<slug>` SA's
  delete permission is IAM-conditioned to `scv-<slug>-*` instance names. The
  legacy `scv-vm` SA + `scv` image family stay until the multi-repo cutover
  is verified.

## See also

- [[coding-sandbox]] — the in-product `/agents` chat backend (unrelated
  infrastructure).
- [[dev-commands]], [[project-overview]].
