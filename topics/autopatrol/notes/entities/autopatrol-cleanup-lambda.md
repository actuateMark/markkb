---
title: "AutoPatrol Cleanup Lambda"
type: entity
topic: autopatrol
tags: [autopatrol, lambda, cleanup, sqs, dynamodb, immix, admin-api, rollout, billing]
status: live-stage-enabled
created: 2026-04-17
updated: 2026-04-23
author: kb-bot
outgoing:
  - topics/actuate-platform/notes/entities/actuate-admin-api.md
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/autopatrol/notes/concepts/2026-04-17_no-patrols-emit-points.md
  - topics/autopatrol/notes/concepts/2026-04-17_onboarder-nr-instrumentation-gap.md
  - topics/autopatrol/notes/concepts/2026-04-20_cleanup-lambda-runbook.md
  - topics/autopatrol/notes/concepts/2026-04-21_cleanup-lambda-stage-verify.md
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/concepts/2026-04-24_morning-watch-list.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
incoming:
  - home/offboarding/2026-06-23_autopatrol-handoff.md
  - topics/actuate-platform/notes/entities/actuate-admin-api.md
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/autopatrol/notes/concepts/2026-04-17_no-patrols-emit-points.md
  - topics/autopatrol/notes/concepts/2026-04-17_onboarder-nr-instrumentation-gap.md
  - topics/autopatrol/notes/concepts/2026-04-20_cleanup-lambda-runbook.md
  - topics/autopatrol/notes/concepts/2026-04-21_cleanup-lambda-stage-verify.md
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/concepts/2026-04-23_immix-api-error-patterns.md
incoming_updated: 2026-06-25
---

# AutoPatrol Cleanup Lambda

SQS-driven AWS Lambda that soft-deletes `AutoPatrolSchedule` rows whose Immix-side schedules have been Paused / Suspended / Removed / Deleted / 404'd. Sibling to [[autopatrol-onboarder]] in the `autopatrol_onboarder` repo.

**Status (2026-04-23T18:12Z):** Live in stage with `CLEANUP_ENABLED=true`, `CLEANUP_TARGET_HOURS=18`. 0 disables all-time — every threshold hit so far has been anomaly-reset because Immix returns Active. Full audit: `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda` → 0 rows. Prod US scale-up (Step F) is scoped as a follow-up blocked on an ad-hoc pod redeploy mechanism. Prod EU (Step G) needs net-new regional infra.

## PRs (all merged)

| Repo | PR | Target | Purpose | Merged |
|---|---|---|---|---|
| vms-connector | [#1657](https://github.com/aegissystems/vms-connector/pull/1657) | `stage` | SQS emit from 6 patrol-exit sites (§2) | 2026-04-20 |
| [[actuate_admin]] | [#2361](https://github.com/aegissystems/actuate_admin/pull/2361) | `develop` | Provenance fields + `scheduleId` filter (§6) | 2026-04-20 |
| autopatrol_onboarder | [#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3) | `master` | Lambdas + deploy pipeline (§1, §4, §5, §8) | 2026-04-21 |
| autopatrol_onboarder | [#4](https://github.com/aegissystems/autopatrol_onboarder/pull/4) | `master` | HOTFIX: onboarder healthcheck silent-bail — see [[2026-04-23_postmortem-onboarder-healthcheck]] | 2026-04-23 |
| autopatrol_onboarder | [#5](https://github.com/aegissystems/autopatrol_onboarder/pull/5) | `master` | Retry-idempotency fix on DDB counter (guards against SQS-retry double-count) | 2026-04-23 |
| autopatrol_onboarder | [#6](https://github.com/aegissystems/autopatrol_onboarder/pull/6) | `master` | Deploy workflow hardening (fail on real errors, mask CodeArtifact token) + IAM policy v2 adding missing ARNs | 2026-04-23 |
| vms-connector | [#1660](https://github.com/aegissystems/vms-connector/pull/1660) | `rearchitecture` | stage → rearchitecture promotion (incl. emit code) | open (awaiting review) |
| [[ds-terraform-eks-v2]] | [#69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) | `main` | Dev/EU SQS + DDB + Lambda stanzas — **deferred**; prod/us-west-2 was provisioned manually via CLI | open |

## Provisioned stage infra (prod acct / us-west-2, 2026-04-20)

Manually via AWS CLI while the terraform `0 to add` + `core-lambdas` var-name bugs are resolved.

**Account:** `388576304176` (prod) — matches where existing `autopatrol_jobs.fifo` / `autopatrol_jobs_dev.fifo` live. Stage pods are deployed in this account and their default SQS client points here.

**Region:** `us-west-2` (US first per rollout; EU is a Step G follow-up).

| Resource | Identifier |
|---|---|
| SQS | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dev.fifo` |
| DLQ | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dlq_dev.fifo` (maxReceiveCount=3) |
| DDB | `autopatrol_cleanup_counters-dev` in us-west-2, PK=`schedule_id` (String), pay-per-request, TTL on `ttl` enabled |

**Earlier wrong attempt:** I originally provisioned these in the dev account (`558106312574`) / eu-west-1. That was wrong — stage pods can't reach dev-account resources. Those dev-EU resources have been deleted. Let this note save the next person the detour.

**Prod-tier queues also provisioned (2026-04-21)** — `autopatrol_stale_schedule_cleanup.fifo` + DLQ + DLQ alarm in prod acct / us-west-2. Lambda event source mapping added. Queue stays empty until prod pods explicitly opt in via `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` on their pod spec.

**Lambda functions provisioned** — `immix-autopatrol-schedule-cleanup` + `immix-autopatrol-schedule-reenable` live in prod/us-west-2, deploy wired via autopatrol_onboarder CI on merge-to-master (PR #3 merged as `6baed9a7` on 2026-04-21). Both regions run onboarder Lambda; EU lacks cleanup/reenable pending Step G.

## Why it exists

There is no existing path that flips `AutoPatrolSchedule.is_deleted` to `True` when an Immix schedule is deleted. See [[2026-04-17_autopatrol-sync-endpoint-behavior]] for why the bulk sync endpoint isn't that path and can't become it without more change than it's worth.

## Architecture

```
SQS FIFO (autopatrol_stale_schedule_cleanup.fifo)
  └─ Cleanup Lambda (immix-autopatrol-schedule-cleanup)
       ├─ DynamoDB counter (autopatrol_cleanup_counters, TTL)
       ├─ Immix confirmation (AutoPatrolAPI.get_schedule)
       ├─ Admin PATCH /api/auto_patrol_schedule/{id}/
       └─ Slack audit → #autopatrol-sync
```

Paired with:
- **Re-enable Lambda** — IAM-auth'd Function URL; admin UI "Re-enable" button POSTs here.
- **VMS-connector emit** — six exit sites push SQS messages on terminal "no patrols to run" (see [[2026-04-17_no-patrols-emit-points]]).

## Tech stack

- Python 3.12+ (`uv`), same deps as [[autopatrol-onboarder]] (`actuate-admin-api`, `actuate-integration-calls`)
- [[new-relic|New Relic]] Lambda instrumentation: custom-event emit wired in code (PR #3 commit `7dc6a13`); Lambda NR layer attachment still pending — tracked in Not-Yet-Prioritized. See [[2026-04-17_onboarder-nr-instrumentation-gap]].

## Function names

Mirrors onboarder naming:
- US (`us-west-2`): `immix-autopatrol-schedule-cleanup` ✓ live
- EU (`eu-west-1`): `immix-autopatrol-schedule-cleanup` — not yet provisioned (Step G)
- Re-enable sibling: `immix-autopatrol-schedule-reenable` ✓ live US only

## Current config (us-west-2, as of 2026-04-23T18:12Z)

| Env var | Value | Purpose |
|---|---|---|
| `CLEANUP_ENABLED` | **`true`** | Disable path active (flipped 17:59Z). Kill switch via flip back to `false`. |
| `CLEANUP_TARGET_HOURS` | **`18`** | Silence window (was 48; lowered 18:12Z to make cleanup more responsive). |
| `CLEANUP_SITE_DISABLED_TARGET_HOURS` | `336` | Unchanged (14d window for SiteDisabledOrDisarmed signal). |
| `DRY_RUN` | unset | Admin PATCH fires on disable decisions. |
| `DDB_COUNTERS_TABLE` | `autopatrol_cleanup_counters-dev` | Stage DDB table (prod uses same Lambda, same table — "stage vs prod" is only about which connector pods emit). |
| `AUTOPATROL_STAGE` / `AUTOPATROL_REGION` | `prod` / `US` | Routes admin + [[immix-vendor-api|Immix API]] calls to prod endpoints. |

**Rollback:** flip `CLEANUP_ENABLED=false` via `aws lambda update-function-configuration`. Instant effect, counters keep accumulating for resumption.

## Threshold math

```
N = max(3, CLEANUP_TARGET_HOURS / cadence_hours)
TTL = max(N * cadence_hours * 2, 72h) from last emit
```

Connector ships `cadence_hours` in the SQS payload. At `CLEANUP_TARGET_HOURS=18`:
- Hourly schedules → threshold=18 / 18h silence window
- 6h cadence schedules → threshold floor 3 / 18h window
- Daily → threshold floor 3 / 72h (24h × 3)

Threshold is stored on the DDB row on first sighting via `if_not_exists(threshold, :new)`. Changing the env var only affects newly-created rows (or rows whose threshold was cleared, e.g. by anomaly reset).

## Safety net

Every threshold hit → Lambda calls `AutoPatrolAPI.get_schedule(tenant_id, schedule_id)`:
- Immix returns 200 with `scheduleStatus ∈ {Active, Awaiting}` → **anomaly reset** (bucket cleared, no disable). Log: `"anomaly: bucket=… threshold hit but Immix reports schedule … still active — resetting … bucket"`
- Immix returns 200 with `scheduleStatus ∈ {Suspended, Paused, Removed, Deleted}` OR 404 → **disable fires**. Log: `"disabled admin schedule_pk=…"` + Slack post to `#autopatrol-sync` + NR custom event `AutoPatrolScheduleDisabled`.
- Immix returns 5xx / timeout → **transient** → SQS redelivers. PR #5's retry-idempotency guard (`last_message_id` + DDB `ConditionExpression`) prevents counter double-count on redelivery.

**Manager audit:** `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda` → returns all schedules ever disabled by this Lambda. **Currently 0 rows** (2026-04-23).

## Rollout status (2026-04-23T18:30Z)

| Step | Status | Notes |
|---|---|---|
| 0a/0b: stage SQS/DDB | ✅ 2026-04-22 | prod/us-west-2 (corrected from earlier wrong dev/EU provision) |
| A: vms-connector emit | ✅ merged 2026-04-20 | PR #1657 |
| B: admin migration | ✅ merged 2026-04-20 | PR #2361 |
| C: Lambdas provisioned | ✅ 2026-04-21 | via CLI; terraform deferred for prod |
| D: all Lambdas deployed (dark) | ✅ 2026-04-21 | PR #3 merged + CI deployed |
| **2026-04-23 hotfix day** | ✅ | PRs #4 (onboarder healthcheck), #5 (retry-idempotency), #6 (workflow hardening + IAM v2). See [[2026-04-23_postmortem-onboarder-healthcheck]]. |
| E.1: retry-fix organic exercise | follow-up | Not a gate (anomaly-reset is the safety net). Tracked as [[mark-todos]] task #19. |
| **E.2: CLEANUP_ENABLED=true** | ✅ **2026-04-23T17:59Z** | |
| E.2b: lower threshold 48→18h | ✅ **2026-04-23T18:12Z** | |
| E.3: 24-48h post-flip monitoring | in progress | Was "1 week bake" — reduced after realizing stage queue has been servicing real prod tenants the whole time. Gate to Step F on 0 DLQ growth, 0 false disables. |
| F: prod US scale-up | deferred | Needs `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` on prod connector pods. Blocked on ad-hoc pod redeploy mechanism — see [[2026-04-23_feature-request-ad-hoc-connector-redeploy-api]]. |
| G: prod EU | deferred | Needs EU SQS + DDB + Lambda mirrors. IAM policy v2 already has EU ARNs pre-granted. |

See [[2026-04-17_stale-schedule-cleanup-design#Rollout state]] for the historical multi-step plan.

## Local testing

- `scripts/fetch_local_test_env.sh` — pulls `ADMIN_API_TOKEN` + `AUTOPATROL_API_KEY` from prod Secrets Manager
- `scripts/local_smoke_test.py <admin_pk>` — resolves tenant_id from S3 pod settings, synthesises an SQS event, runs `cleanup_lambda.lambda_handler` in DRY_RUN mode against live AWS + admin + Immix

Verified 2026-04-20 against two live schedules. See the design synthesis for results and the three bugs the smoke test caught.

## Operations

- **Runbook**: [[2026-04-20_cleanup-lambda-runbook]] — command reference for queue depth, log tailing, DDB inspection, CLEANUP_ENABLED flip, kill switch, DLQ peek, re-enable flow.
- **Nightly check skill**: `/autopatrol-cleanup-lambda-check` — runs the full health sweep (queue + DLQ + Lambda metrics + log parsing + DDB state + connector-Lambda correlation). Distinct from `/autopatrol-check` which covers the patrol pipeline itself.
- **Meta-pattern**: [[2026-04-20_overnight-check-skill-pattern]] — how to build a check skill for a new service.

## Related

- [[autopatrol-onboarder]] — sibling Lambda this augments
- [[2026-04-17_stale-schedule-cleanup-design]] — full design
- [[2026-04-17_no-patrols-emit-points]] — SQS producer
- [[2026-04-17_autopatrol-sync-endpoint-behavior]] — why there's no existing path
- [[2026-04-17_onboarder-nr-instrumentation-gap]] — NR work bundled with this change
- [[2026-04-20_cleanup-lambda-runbook]] — ops runbook (threshold-math examples are pre-2026-04-23, rest current)
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — general Lambda playbook
- [[2026-04-23_postmortem-onboarder-healthcheck]] — 47h silent-failure post-mortem, sibling Lambda
- [[2026-04-24_morning-watch-list]] — tomorrow-morning check-in scaffold
- [[2026-04-23_feature-request-ad-hoc-connector-redeploy-api]] — Step F prerequisite
