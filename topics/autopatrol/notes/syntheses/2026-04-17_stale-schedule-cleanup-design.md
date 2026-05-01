---
title: "AutoPatrol Stale-Schedule Cleanup — Event-Driven Design"
type: synthesis
topic: autopatrol
tags: [plan, autopatrol, sqs, lambda, dynamodb, cleanup, immix, admin-api]
jira: ""
created: 2026-04-17
updated: 2026-04-20
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-04-17_autopatrol-sync-endpoint-behavior.md
  - topics/autopatrol/notes/concepts/2026-04-17_no-patrols-emit-points.md
  - topics/autopatrol/notes/concepts/2026-04-17_onboarder-nr-instrumentation-gap.md
  - topics/autopatrol/notes/concepts/2026-04-20_cleanup-lambda-runbook.md
  - topics/autopatrol/notes/concepts/2026-04-21_cleanup-lambda-stage-verify.md
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/autopatrol/notes/concepts/2026-04-24_morning-watch-list.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/autopatrol/notes/entities/todo-list.md
incoming_updated: 2026-05-01
---

# AutoPatrol Stale-Schedule Cleanup — Event-Driven Design

Design record for a new per-schedule cleanup Lambda that soft-deletes autopatrol schedules after Immix confirms they're gone. Replaces no existing component — this is the first actual deletion path; today nothing disables stale schedules.

**Plan file:** `/home/mork/.claude/plans/sequential-questing-creek.md`

## Problem

AutoPatrol (immix) cronjobs keep firing after Immix-side schedules are deleted. The pod logs "no patrols to run, exiting" and terminates. ~24,590 such events per week across 186 schedules (NR 7-day). No admin-side code ever sets `AutoPatrolSchedule.is_deleted=True` in response — stale schedules linger indefinitely.

## Why not fix the existing sync

The onboarder's `auto_patrol/sync/` call was the suspected deletion path. Investigation shows otherwise — see [[2026-04-17_autopatrol-sync-endpoint-behavior]]. Sync is create-only; the `allow_deletion` flag added defensively in branch `fix/handle-deleted-sites` is unread on admin side. Bulk "fetch everything, sync everything" semantics also don't scale: one flaky run could in theory trigger mass action if deletion ever gets wired up there.

## Design

```
┌──────────────────┐   SQS FIFO   ┌─────────────────┐
│ vms-connector    │─────────────▶│ Cleanup Lambda  │
│ (6 exit sites)   │              │                 │
└──────────────────┘              │  ┌──────────┐   │
                                  │  │ DynamoDB │   │
                                  │  │ counters │   │
                                  │  └──────────┘   │
                                  │        │        │
                                  │        ▼        │
                                  │  Immix check    │
                                  │  (get_schedule) │
                                  │        │        │
                                  │        ▼        │
                                  │  Admin PATCH    │
                                  │  is_deleted=T   │
                                  └─────────────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │ Re-enable       │   ◀─ IAM-auth'd
                                  │ Lambda (URL)    │      POST from
                                  └─────────────────┘      admin UI
```

1. Connector pod exits with "no patrols to run" → emits one SQS FIFO message with `schedule_id`, `tenant_id`, `site_id`, `actuate_customer_id`. See [[2026-04-17_no-patrols-emit-points]] for emit sites and available context.
2. Cleanup Lambda consumes the message, looks up the admin PK + cadence on first sighting (cached in the DDB row after), and increments the DynamoDB counter keyed on `schedule_id` with a refreshed TTL.
3. When the counter reaches a **cadence-aware threshold** (see below), the Lambda calls Immix `get_schedule` for confirmation.
4. If Immix returns `404` OR scheduleStatus ∈ {Suspended, Paused, Removed, Deleted} (anything other than Active / Awaiting), the Lambda PATCHes admin: `{is_deleted: True, disabled_by: "cleanup_lambda", disabled_at: <ts>}`. Counter cleared.
5. If Immix reports Active or Awaiting, Lambda logs an anomaly (connector + Immix disagreement), clears the counter, returns.
6. Disable is reversible: an admin UI list shows schedules with `disabled_by=cleanup_lambda`; the "Re-enable" button POSTs to a sibling Lambda's IAM-auth'd Function URL, which verifies Immix has the schedule in an active state and PATCHes `is_deleted=False` + `reenabled_by`/`reenabled_at`.

**Important:** the connector does NOT ship cron in the SQS payload today. The Lambda resolves cadence from the admin schedule's `checksPerDay` field on first sighting (falls back to daily if missing). See "Cadence resolution" below.

## Cadence-aware threshold

```
N = max(3, CLEANUP_TARGET_HOURS / cadence_hours)
```

`CLEANUP_TARGET_HOURS` defaults to 48. Hourly schedules need 48 consecutive emits (~2 days). Daily schedules need 3 emits (~3 days). Floor of 3 so very-frequent schedules still get some buffer.

## Cadence resolution

The Lambda queries the admin API on first sighting:

```
GET /api/auto_patrol_schedule/?customer=<actuate_customer_id>&scheduleId=<schedule_id>
```

Client-side filters on `scheduleId` from the returned list (handles the case where admin's server-side `scheduleId` filter isn't yet deployed — silently returns all customer schedules). Reads `checksPerDay` from the matching record and computes `cadence_hours = 24 / checksPerDay`. If `checksPerDay` is missing / null, falls back to **daily cadence (24h)** as a safe default. Admin PK + cadence are cached on the DDB counter row so subsequent emits for the same schedule skip the admin lookup.

## SQS payload (FIFO, connector emits)

```json
{
  "tenant_id": "...",
  "site_id": "...",
  "schedule_id": "...",
  "subscription_id": "...",
  "integration_type": "autopatrol | vch",
  "reason": "no_patrols | error | exception",
  "actuate_customer_id": 1234,
  "connector_version": "<git sha>",
  "emitted_at": "<ISO-8601>"
}
```

`MessageGroupId = schedule_id` (per-schedule ordering). `MessageDeduplicationId = schedule_id:<floor(emitted_at, 1 min)>`.

## Counter reset strategy — TTL only

TTL = `max(threshold × cadence_hours × 2, 72h)` from the last emit. A genuinely active schedule produces at least one successful patrol inside the TTL window, so the emissions stop and the counter ages out. No explicit "I succeeded, reset me" path from the connector — keeps the pod stateless and avoids doubling SQS traffic.

## Admin-side provenance fields

New on `AutoPatrolSchedule`:
- `disabled_by` (`"cleanup_lambda"` or `"user:<email>"`)
- `disabled_at`
- `reenabled_by`
- `reenabled_at`

All nullable, no backfill. Serializer exposes them r/w; viewset filter adds `disabled_by` so the admin UI can list cleanup-disabled rows.

## Failsafes

- **`CLEANUP_ENABLED=false`** default. Code ships dark; flip on per-env after stage bake.
- **`DRY_RUN`** logs every would-disable without calling admin.
- **Live Immix confirmation** required — transient Immix errors leave the counter untouched and retry via SQS.
- **Reserved concurrency = 2** on the cleanup Lambda — prevents runaway disables from a flooded queue.
- **Idempotent disable** — if admin already has `is_deleted=True`, no-op and clear counter.
- **DLQ alarm** — depth > 0 pages oncall.
- **Re-enable blocked on Immix-absent** — can't re-enable something still gone from Immix; admin re-adds in Immix first.

## Observability

Both onboarder and cleanup Lambdas get NR instrumentation — the onboarder currently has **zero NR visibility** (see [[2026-04-17_onboarder-nr-instrumentation-gap]]). Custom events: `AutoPatrolScheduleDisabled`, `AutoPatrolScheduleReenabled`. Slack audit to `#autopatrol-sync` on every disable/re-enable.

## Where things live

| Piece | Location |
|---|---|
| Connector emit helper | `vms-connector/connector_factories/shared/cleanup_emitter.py` |
| Cleanup Lambda | `autopatrol_onboarder/cleanup_lambda.py` + `cleanup_dao.py` |
| Re-enable Lambda | `autopatrol_onboarder/reenable_lambda.py` |
| Admin schedule fields | `actuate_admin/inframap/sites/autopatrol/autopatrol_schedule_model.py` |
| Terraform (SQS, DDB, IAM, Lambdas) | `ds-terraform-eks-v2` — confirmed IaC home for autopatrol infra |

## Rollout state (as of 2026-04-20)

Four PRs open across four repos. Stage-first, prod separate.

| Repo | PR | Target | State |
|---|---|---|---|
| vms-connector | [#1657](https://github.com/aegissystems/vms-connector/pull/1657) | `stage` | open — today's merge target |
| [[actuate_admin]] | [#2361](https://github.com/aegissystems/actuate_admin/pull/2361) | `develop` | open |
| [[ds-terraform-eks-v2]] | [#69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) | `main` | open (dev/EU only; prod deferred) |
| autopatrol_onboarder | [#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3) | `master` | **draft, DO NOT MERGE** (master auto-deploys prod) |

### Rollout steps (multi-step, each gated)

- [x] **Step 0a** Create stage SQS queue + DLQ in **prod account (388576304176) / us-west-2** (manual CLI 2026-04-20): `autopatrol_stale_schedule_cleanup_dev.fifo` + `autopatrol_stale_schedule_cleanup_dlq_dev.fifo`, `maxReceiveCount=3`, 60s visibility, 4-day retention. Must be in the prod account because that's where stage pods run and where the existing `autopatrol_jobs*.fifo` queues live; an earlier attempt in dev-EU was deleted as wrong.
- [x] **Step 0b** Create stage DDB counter table in **prod account / us-west-2** (manual CLI 2026-04-20): `autopatrol_cleanup_counters-dev`, PK `schedule_id`, pay-per-request, TTL on `ttl` attribute enabled.
- [x] **Step A (2026-04-20 22:24Z):** merged `vms-connector#1657` to `stage` as `4f08afc4`. Stage ECR build succeeded in 3m25s; pods auto-emit into prod-account/us-west-2 queue on next cron cycle.
- [x] **Step B (2026-04-20 22:24Z):** merged `actuate_admin#2361` to `develop` as `aa2cbdfd`. `Dev CI` pipeline in flight; migration `0543_autopatrolschedule_cleanup_provenance.py` applies ~14 min post-merge to the stage DB.
- [ ] **Step C:** provision cleanup + reenable Lambda functions in dev/EU (`ds-terraform-eks-v2#69` once plan bugs resolved, or CLI).
- [ ] **Step D:** un-draft `autopatrol_onboarder#3`, merge to `master`. All 6 Lambdas get the shared zip; `CLEANUP_ENABLED=false` default keeps cleanup dark.
- [ ] **Step E:** flip stage `CLEANUP_ENABLED=true`. Bake 1 week. Gate to prod = ≥5 clean disables, 0 false positives, 0 DLQ depth.
- [~] **Step F (partial, 2026-04-21):** prod US (us-west-2) infra provisioned — prod-tier queue `autopatrol_stale_schedule_cleanup.fifo` + DLQ + alarm, cleanup Lambda event source mapping added for the prod queue. `autopatrol_onboarder#3` merged to master as `6baed9a7` → onboarder + cleanup + reenable Lambdas deployed to prod/us-west-2 via the release workflow. **Prod pods NOT YET opted in** — they stay silent via the connector's `use_dev_queue`-based default gating until `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` is set on their pod spec. Terraform for this tier is a follow-up (see `ds-terraform-eks-v2#69` annotation).
- [ ] **Step G:** prod EU — same cadence.

### Stage rollout gating detail

The connector emitter uses layered gating so stage and prod are decoupled:

```
AUTOPATROL_EMIT_CLEANUP_SIGNALS=false → hard off (kill switch)
AUTOPATROL_EMIT_CLEANUP_SIGNALS=true  → hard on
unset (default)                       → on for stage (use_dev_queue=True), off for prod
```

This means Step A is "merge to stage" and emits begin — no connector_deployer change needed. Prod pods stay silent until their queue is provisioned and the env var is flipped.

## Local testing insights (surfaced during 2026-04-20 smoke test)

End-to-end dry-run against live data works. Blockers + fixes:

- **Admin token Secrets Manager lookup** is hardcoded to prod account. Local `AdminApiHandler` now respects `ADMIN_API_TOKEN` env var override. Pre-fetch with `scripts/fetch_local_test_env.sh` using `AWS_PROFILE=prod`.
- **DDB + SQS region mismatch** — boto3 defaults to `us-west-2`; cleanup table lives in `eu-west-1`. Local invocation must set `AWS_REGION=eu-west-1`.
- **S3 pod settings** (`s3://actuate-settings/connector-<id>-autopatrol-<pk>/settings.json`) are the practical source for `tenant_id` + `site_id` since the admin API's schedule serializer doesn't surface those nested fields. Requires `AWS_PROFILE=prod` read access.
- **Pre-existing admin `scheduleId` filter missing** — our PR adds it, but until it deploys, the client-side filter match in the Lambda is load-bearing.

See [[2026-04-17_local-testing-strategies-per-repo]] for the full per-repo testing ceiling.

### Bugs the smoke test caught (now fixed)

1. **Wrong `scheduleStatus` constant** — was comparing to `"DEACTIVATED"` (doesn't exist in `ScheduleStatusEnum`). Real values: `Active | Awaiting | Suspended | Paused | Removed | Deleted`. Fixed to "Active/Awaiting → keep, everything else → treat as gone." Caught `autopatrol-597` which is Paused-but-still-firing — exactly our target.
2. **"Schedule not in admin DB" was retried as transient** — now returns explicit `not_found` status → ACKs the message.
3. **`schedule_id` filter didn't exist server-side** — Lambda now filters client-side on the returned list; works whether or not the filter is deployed.

## Second signal: `SiteDisabledOrDisarmed` (added 2026-04-20)

A separate failure class surfaced by [[2026-04-20_streamid-null-patrol-alert-bug]]: Immix returns 400 with `SiteDisabledOrDisarmed` on `get_patrol_stream` when the customer has disabled/disarmed their site (legitimately transient for sites armed only during business hours). The existing [[connector-factory|connector factory]]'s retry loop doesn't see this — it's in the downstream puller path.

### Implementation

Added a second emit point in the puller library:
- `actuate_pullers.AutopatrolWebSocketStreamPuller` gained `last_init_error_class` + `on_init_error` callback (dev version `1.17.12.dev1+feature.autopatrol.puller.error.classification`)
- Callback classifies response text into `site_disabled | deleted | pending | no_stream | transient`
- vms-connector's `AutoPatrolCamera` / `VCHCamera` wire the callback via `make_puller_error_callback` after puller construction
- Callback translates class → SQS `reason` and emits through the existing cleanup queue

### Reason-scoped DDB buckets

Same counter table, separate bucket per signal type:

| Reason | Bucket | Target hours | Threshold (daily cadence) |
|---|---|---|---|
| `no_patrols` | `patrol_exit` | 48h | 3 |
| `error` | `patrol_exit` | 48h | 3 |
| `exception` | `patrol_exit` | 48h | 3 |
| `site_disabled` | `site_disabled` | 336h (14 days) | 14 |

Bucket fields on the DDB row are parallel (`count` / `threshold` / `first_failure_at` / `last_failure_at` vs `count_site_disabled` / `threshold_site_disabled` / ...). Shared fields (`admin_pk`, `cadence_hours`, `ttl`) stay schedule-level.

Immix verdict on threshold applies to both — Active/Awaiting keeps the schedule (resets that bucket only via `clear_bucket`, not full row delete). Gone/Paused/Suspended/Removed/Deleted triggers the full disable path.

`deleted` and `no_stream` classifications emit for observability but the Lambda drops them today (policy TBD).

### Why 14 days for site_disabled

A site disabled during off-hours (e.g. armed only during business hours) is a legitimate transient state. 14 days of continuous `SiteDisabledOrDisarmed` with zero successful patrols is strong signal that it's permanent and not a nightly arm/disarm cycle. The Re-enable Lambda is the safety net if a user re-arms a disabled site later.

### Verified 2026-04-20

- `reason=no_patrols` routes to `patrol_exit` bucket, target_hours=48, threshold=3 (for daily cadence)
- `reason=site_disabled` routes to `site_disabled` bucket, target_hours=336, threshold=14
- Both reasons on the same DDB row; each bucket independent. Shared `admin_pk`, `cadence_hours`.

### Verified dry-run results (2026-04-20)

- `autopatrol-597` (Immix `Paused`, 672 "no patrols" emits in NR 7d) → 3 Lambda invocations → Immix check fires → `would PATCH auto_patrol_schedule/597/ is_deleted=True`. Gated by `DRY_RUN=true CLEANUP_ENABLED=false`, no actual PATCH.
- `autopatrol-309` (Immix `Active`, known-active control) → 3 Lambda invocations → Immix says active → counter reset, no disable.

## Related

- [[2026-04-17_autopatrol-sync-endpoint-behavior]] — why the existing sync can't be the deletion path
- [[2026-04-17_no-patrols-emit-points]] — connector exit sites + NR baseline
- [[autopatrol-cleanup-lambda]] — entity (rollout in flight)
- [[autopatrol-onboarder]] — sibling Lambda this cleanup augments
- [[2026-04-17_onboarder-nr-instrumentation-gap]] — observability gap being closed concurrently
- [[2026-04-17_local-testing-strategies-per-repo]] — local-test ceiling per repo
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — general playbook distilled from this work
- [[2026-04-20_streamid-null-patrol-alert-bug]] — origin of the `SiteDisabledOrDisarmed` signal
