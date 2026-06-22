---
title: "actuate-integration-tools extensions — spec for next-tools to consider"
type: synthesis
topic: engineering-process
tags: [tooling, debugging, integration-tests, actuate-config, vms-connector, cli, spec, roadmap]
created: 2026-05-19
updated: 2026-05-19
author: mark
[]
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-1-diff.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-2-validate.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-20
---

# actuate-integration-tools extensions — spec for next-tools to consider

The [[actuate-integration-tools|`ait`]] CLI was created 2026-05-19 to answer "what does this deployment's config actually look like?" in seconds, by loading real customer `settings.json` from S3 and parsing it through the production `actuate-config` library. Its first real-customer query surfaced a tier-mapping bug that would otherwise have shipped to prod.

The win came from a simple pattern: **load real config → parse through actual library code → expose derived properties as a CLI**. The pattern generalises. This note catalogues candidate next-tools to consider once the first three subcommands (`tier`, `detections`, `dump`) prove their value over a few weeks of usage.

The framing for prioritisation: each candidate must answer a question that's currently being answered by either (a) reading code + S3 settings manually, (b) waiting for a cronjob to fire and reading NR logs, or (c) spinning up a local connector. If a candidate doesn't replace one of those three workflows it's probably not worth building.

## Phase notes (work tracking)

Each Tier 1 candidate has its own synthesis note with detailed TODOs:

- **Phase 1** — [[2026-05-19_ait-phase-1-diff|`ait diff`]] — three modes (site-vs-site, library-version, time-version). Foundational; ship first.
- **Phase 2** — [[2026-05-19_ait-phase-2-validate|`ait validate`]] — assertion battery, pre-deploy gating.
- **Phase 3** — [[2026-05-19_ait-phase-3-audit-tier-emissions|`ait audit-tier-emissions`]] — config-vs-runtime drift detection via NR.

## Tier 1 — Likely high-impact, near-term

### `ait diff <deployment_a> <deployment_b>`

Side-by-side comparison of two deployments' parsed configs. Useful for:

- "Why is site A flagging X but site B isn't?" — the *config* difference is often the answer.
- "Did this customer's settings drift after the admin re-deploy?" — diff today's vs yesterday's S3 object version.
- "Is this site configured the same as its known-good twin?"

Output shape: structured diff over `integration_type`, `patrol_type`, per-camera `feature_deployments[].plain_metrics`, `customer.healthcheck.*` flags, recipient lists. Default to "only show differences" with a `--full` flag for everything.

Implementation cost: low. Load both configs, walk the parsed objects, emit a unified-diff-style report via `rich`.

### `ait validate <deployment_id>`

Beyond "did it parse without exception", run a battery of semantic invariants:

- `patrol_type` matches `integration_type` (no `VisualCameraHealth` on a non-VCH integration)
- Branded vehicle ID feature_deployments are paired with a base `intruder` / `vehicle` deployment if the model expects them
- Every camera's `frontel_area` / `frontel_zone` is non-empty if a Lisa recipient is configured
- All `recipients[]` URLs have valid schemes; tokens are present
- No `.devN+` library pins in any feature deployment's `model_name` chain

Effectively a pre-flight checklist for customer-facing deploys. Wires into [[pre-merge-workflow|/pre-merge-workflow]] as a gating step on config-touching library bumps.

Implementation cost: low-medium. Each invariant is a small assertion; the table grows over time as we learn new failure modes.

### `ait audit-tier-emissions <deployment_id>`

Compute the *predicted* tier from the parsed config (`highest_tier_for(configured_detection_codes)`), then NR-query the deployment's recent `raise_patrol_alert` log lines and assert the observed `tier` field matches. Closes the gap actuate-pr-reviewer flagged on PR #1699 — config-time tier vs runtime tier drift detection.

Detects: library bumped on one branch but not another (config-time says Tier 3, runtime still says Tier 1), feature_deployment removed without restart, race between admin re-deploy and connector pod refresh, etc.

Implementation cost: medium. Needs an NR query layer in the tool (likely via the `nrql-investigator` agent or a thin wrapper), plus the tier prediction is already exposed via `ait tier`.

## Tier 2 — Useful but bigger scope

### `ait scan-fleet --metric-key <key>` / `ait scan-fleet --library <lib>=<version>`

Sweeps every deployment in `actuate-settings/` and reports which configure a given metric key, or which would have library compatibility issues at a given version.

Use cases:

- "How many sites have CROWD enabled?" — feeds product/cost discussions.
- "Which sites are still on the old `intruder` model name we deprecated?" — cleanup audits.
- "If I bump `actuate-config` to X.Y.Z, will any existing settings.json fail to parse?" — fleet-wide compat check before stage merge.

Risk: bucket-scale (~thousands of deployments) means lots of S3 calls. Bound it with prefix-listing + parallel batched fetches + a result cache.

Implementation cost: medium. The bucket-listing + parallel fetch infrastructure is reusable across other tools.

### Library compatibility check

A specialised subset of `scan-fleet`: given a target library + version, sweep the fleet, fail-fast log every deployment whose settings.json doesn't parse cleanly under that library. Replaces the manual "spot-check 2-3 representative deployments" step in [[pre-merge-workflow]] with a comprehensive run.

Could surface as `ait validate-fleet --against actuate-config==1.10.1` or similar.

## Tier 3 — Specialised, defer until demand exists

### Mock Immix endpoint

A FastAPI server that exposes the same interface Immix does on `get_patrol_stream` / `raise_patrol_alert`. Lets you point a feature-deployment at it and exercise AutoPatrol end-to-end without touching live Immix.

Larger scope than the CLI tools (server lifecycle, fake video frames, etc.). Defer until there's an active test case demanding it — most config-level questions don't need this.

### Property-based testing harness

Hypothesis-style: given a real `settings.json`, generate mutations (drop cameras, swap detection types, mutate feature deployments) and assert that library invariants hold across the variations. Catches "configured set is empty → tier defaults to 1" / "unknown metric key silently dropped" classes of bug *before* shipping.

Implementation cost: high (Hypothesis strategy design is non-trivial), but the payoff is large if we keep finding bugs of the "empty edge case" variety.

### Settings snapshot diff over time

S3 versioning is enabled on `actuate-settings`. Pull historical object versions for a deployment and surface a timeline of changes. Useful for incident reconstruction ("when did this customer enable CROWD?").

Implementation cost: low-medium. Needs a `boto3` `list_object_versions` call + a UI for browsing the timeline.

## Tier 4 — Adjacent / non-CLI

### Add a `logging.info` in `autopatrol_api.get_patrol_stream`

Not a tool per se but a one-line library change that would close a real validation gap: today the puller doesn't log the `Tier=N` query param it sends to Immix's `/videostream` endpoint, so the stream-fetch tier surface isn't NR-observable. Adding a `logging.info(f"get_patrol_stream tier={tier} duration={duration} patrol={patrol_id}")` in `actuate-integration-calls/.../autopatrol_api.py` line ~344 would unblock `ait audit-tier-emissions` and any future runtime-vs-config drift checks.

## Promotion criteria

`actuate-integration-tools` is currently a local-only repo under `/home/mork/work/`. Promote to `aegissystems/actuate-integration-tools` on GitHub when:

1. Three or more subcommands are in active use across multiple sessions (currently 3 — `tier`, `detections`, `dump` — so this criterion is almost met).
2. A second contributor (Brad / Andrew / etc.) wants to extend it.
3. The fleet-scan capability lands (because that one's likely to need CI / scheduled runs).

Until then, keep it local to avoid premature governance overhead (CI setup, code review process, release versioning).

## Anti-roadmap

Things explicitly NOT in scope for this tool:

- **No connector pipeline.** No camera pullers, no inference, no alert sending. If you need real frame flow, run `vms-connector`.
- **No writes.** Read-only against S3. No mutation of customer config, no NR posting, no Immix calls.
- **No "settings editor".** Editing settings.json is the admin API's job — this tool reads what the admin produced and surfaces what the connector will see.

## Cross-references

- [[actuate-integration-tools]] — the tool entity itself.
- [[2026-05-18_libav-decoder-warmup-frame-fix]] — the VCH work that spawned the tool.
- [[2026-04-14_connector-library-deployment-lifecycle]] — release process the tool integrates into (Phase 2.5).
- [[mark-todos]] — backlog tracking of tier-1 candidates.
- `~/work/vms-connector/.claude/skills/pre-merge-workflow.md` — Step 3.5 references `ait`.
- `~/work/vms-connector/.claude/skills/library-update.md` — Phase 2.5 references `ait`.
- `~/work/vms-connector/.claude/skills/operational-triage.md` — "Quick Config Inspect" section references `ait`.
