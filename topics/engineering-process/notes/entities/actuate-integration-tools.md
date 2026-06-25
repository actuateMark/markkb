---
title: "actuate-integration-tools (ait)"
type: entity
topic: engineering-process
tags: [tooling, debugging, integration-tests, actuate-config, autopatrol, vch, vms-connector, cli]
created: 2026-05-19
updated: 2026-05-20
author: mark
[]
incoming:
  - topics/engineering-process/notes/syntheses/2026-04-14_connector-library-deployment-lifecycle.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-extensions-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-1-diff.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-2-validate.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-20
---

# actuate-integration-tools (`ait`)

Standalone Python package that loads a real connector deployment's `settings.json` from S3, parses it through the production `actuate-config` library, and exposes derived properties via a CLI. The point is to **answer a config question about a live deployment in seconds, without spinning up the connector, without reading NR logs, and without manually re-implementing the parse path.**

## Location

`/home/mork/work/actuate-integration-tools/` — local-only repo currently. Promotion criteria for moving it to `aegissystems/actuate-integration-tools` on GitHub: 3+ subcommands in active use AND a second contributor wants to extend it. Until then, the surface is small enough that local-only is fine.

## Why it exists (origin story)

Created 2026-05-19 during the VCH multi-frame entropy + AutoPatrol tier work. The recurring question — *"what tier does AutoPatrol patrol X actually compute today?"* — was being answered by either reading code + S3 settings manually, waiting for the cronjob to fire and reading NR logs, or spinning up a local connector. None of those scale.

The first real-customer query (`ait detections connector-35831-autopatrol-259`) surfaced a silent under-classification bug in `actuate-config`'s `METRIC_KEY_TO_AUTOPATROL_CODE` table on the first try — the seven branded vehicle ID metric keys (`ups`, `fedex`, `dhl`, `amazon`, `usps`, `fire_truck`, `school_bus`) were missing, and a patrol whose configured set contained only branded vehicle IDs would have computed Tier 1 instead of the spec-correct Tier 3. Fix shipped same day via [actuate-libraries#353](https://github.com/aegissystems/actuate-libraries/pull/353). Without the tool we'd either have shipped the gap to production or only caught it after a customer-facing tier-mis-emission.

Full story: [[2026-05-18_libav-decoder-warmup-frame-fix]] (the broader work this tool was built to support).

## Commands today

```bash
# Show configured detection codes + computed tier for an AutoPatrol deployment
uv run ait tier connector-35831-autopatrol-259

# Per-camera detection metrics (raw plain_metrics keys per feature deployment)
uv run ait detections connector-35831-autopatrol-259

# Dump the parsed config (`--raw` for the un-parsed settings.json)
uv run ait dump connector-35831-autopatrol-259

# Phase 1 diff modes — all share one renderer. See [[2026-05-19_ait-phase-1-diff]].
uv run ait diff <deployment_a> <deployment_b>                              # Mode A — site vs site
uv run ait diff <deployment_id> --library actuate-config --from 1.10.0 --to 1.10.1  # Mode B — library bump
uv run ait history <deployment_id>                                         # list S3 versions
uv run ait diff <deployment_id> --last 1                                   # Mode C — current vs previous
uv run ait diff <deployment_id> --from-version <vid> [--to-version <vid>]  # Mode C — explicit pair

# Phase 2 validate — semantic-invariant battery. See [[2026-05-19_ait-phase-2-validate]].
uv run ait validate <deployment_id>                                        # full battery
uv run ait validate <deployment_id> --strict                               # warnings fail too
uv run ait validate <deployment_id> --check <name>                         # single validator
uv run ait validate --list                                                 # catalog
```

`deployment_id` is the value of the `DEPLOYMENT_ID` env var on the connector pod — easiest way to find one is `kubectl get cronjob -n rearchitecture <cronjob-name> -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[*].env}'` and grep for `DEPLOYMENT_ID`. Conventional form: `connector-<site_id>-<integration>-<schedule>` for AutoPatrol/VCH.

## When to use it

**Pre-merge.** Any library change that touches config parsing (`actuate-config` constructors, `*ConnectorConfig` subclasses, the metric-key / detection-code tables) should be smoke-tested with `ait` against 2-3 representative real deployments before stage promotion. See [[pre-merge-workflow]] / `/pre-merge-workflow`.

**During library bumps.** When bumping `actuate-config` or `actuate-integration-calls` in the connector, `ait` against a known-good site is the fastest way to verify the new version parses the existing config correctly. See `/library-update`.

**Operational triage.** When triaging a site-specific issue, `ait dump <deployment_id>` is the fastest path to the current customer config without paging through admin UI or waiting for the next cronjob log dump. See `/operational-triage`.

**Validation after a tier-change deploy.** Re-run `ait tier <deployment_id>` after a library bump that touched the tier mapping — if the configured-codes set changes, that's a behaviour delta worth knowing about *before* it shows up in NR.

## Auth + setup

Standard `uv sync` + AWS SSO. The package depends on `actuate-config` and `actuate-integration-calls` from CodeArtifact, so CodeArtifact auth is required for setup but not for runtime (everything's cached in `.venv` after first install). Boto3 picks up credentials from the default chain — `aws sso login` is the only thing needed for the S3 fetches.

```bash
cd /home/mork/work/actuate-integration-tools
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TOKEN=$(aws codeartifact get-authorization-token --domain actuate --domain-owner "$ACCOUNT_ID" --region us-west-2 --query authorizationToken --output text)
UV_INDEX_CODEARTIFACT_USERNAME=aws UV_INDEX_CODEARTIFACT_PASSWORD=$TOKEN uv sync
```

## What it deliberately does NOT do

- **No connector pipeline.** No camera pullers, no inference calls, no alert sending. If you need real frame flow, run `vms-connector` itself.
- **No writes.** Read-only against S3. No mutation of customer config, no NR posting, no Immix calls.
- **No integration-test execution.** "Integration tools" in the name is about *exposing the same parse surface* the integration uses, not *running an integration end-to-end*. A separate test harness would be its own follow-up.

## Roadmap of next-tools to consider

Tracked in `mark-todos` under the "actuate-integration-tools — what else should live here?" backlog subsection (added 2026-05-19). Two arcs:

**Inspection arc (Phases 1–3)** — exposing facts about a live deployment's config and emissions.

- **Phase 1** ✅ shipped 2026-05-19 — `ait diff` (site / library / time). See [[2026-05-19_ait-phase-1-diff]].
- **Phase 2** ✅ shipped 2026-05-20 — `ait validate <deployment_id>`: 9-invariant battery + `--strict`. See [[2026-05-19_ait-phase-2-validate]].
- **Phase 3** sketched — `ait audit-tier-emissions`: predicted-vs-actual tier from NR logs. Needs NRClient module. ~3-4h. See [[2026-05-19_ait-phase-3-audit-tier-emissions]].

**Brain-in-jar arc (Phases 4–10)** — capturing in-memory state of a running connector, persisting it, and replaying components against it. See parent: [[2026-05-20_ait-brain-in-jar-spec]].

- **Phase 4** ✅ shipped 2026-05-20 — `ImageDataPacket` serializer (keystone). See [[2026-05-20_ait-phase-4-idp-serializer]].
- **Phase 5** ✅ shipped 2026-05-22 — `DumpReplayPuller`. See [[2026-05-20_ait-phase-5-dump-replay-puller]].
- **Phase 6a + 6b** ✅ shipped 2026-05-21/22 — `ait replay` CLI + pipeline-step replay via `MockStepRunner`. See [[2026-05-20_ait-phase-6-pipeline-replay]].
- **Phase 7** ✅ shipped 2026-05-22 — alert sender capture/replay (env-var-gated; 1:1 off-default). See [[2026-05-20_ait-phase-7-alert-capture-replay]].
- **Phase 8** sketched — camera `from_dump` constructor. Blocked on integration-plan Plays B+C. See [[2026-05-20_ait-phase-8-camera-from-dump]].
- **Phase 9** sketched (perf-discipline-reworked 2026-05-22) — site manager dump + crash hook. Signal-only triggers, no polling. See [[2026-05-20_ait-phase-9-site-dump-crash-hook]].
- **Phase 10** sketched — S3 sink + AIT review UX. See [[2026-05-20_ait-phase-10-s3-sink-review-ux]].
- **Phase 11** ✅ shipped 2026-05-20 — `ait simulate` synthetic-IDP generator + Hypothesis-driven fuzzing. See [[2026-05-21_ait-phase-11-simulate]].

**QA-driven arc**

- **Phase 12** sketched — `ait sweep`: parameter search for QA workflows ("given video + expected, find a config"). Drives actuate-validator harnesses. See [[2026-05-22_ait-phase-12-sweep]]. Depends on integration-plan Plays A + B.

**Unifying view**

- [[2026-05-22_actuate-testing-toolkit-overview]] — master synthesis mapping all five tools (AIT validate/replay/simulate/diff/sweep + actuate-validator) into one toolkit, with per-persona workflows.
- [[2026-05-27_brain-in-jar-handoff]] — handoff doc with repo state + test totals + resumption checklist.
- [[2026-05-27_zack-coordination-brain-in-jar]] — coordination message for Zack on validator-side integration.

**Other candidates** (no phase yet):

- `ait scan-fleet --metric-key foo` — fleet-wide query for which deployments configure X.
- Add a `logging.info` in `autopatrol_api.get_patrol_stream` so the `Tier=N` query param becomes NR-observable (closes the stream-fetch tier validation gap).

## Cross-references

- [[2026-05-18_libav-decoder-warmup-frame-fix]] — the VCH validation cycle this tool was built to support.
- [[2026-05-14_autopatrol-tier-model-and-detection-types]] — Immix tier spec the tool surfaces compliance against.
- [[2026-05-14_autopatrol-tier-api-cross-reference]] — code-side gap analysis for the tier work.
- [[vch-components]] — VCH integration entity.
