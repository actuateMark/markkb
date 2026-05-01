---
title: "Cleanup Lambda stage verification (2026-04-21)"
type: concept
topic: autopatrol
tags: [autopatrol, lambda, cleanup, stage, verification, rollout]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
jira: ""
incoming:
  - topics/personal-notes/notes/daily/2026-04-21.md
incoming_updated: 2026-05-01
---

# Cleanup Lambda stage verification (2026-04-21)

Verification pass on the AutoPatrol stale-schedule cleanup pipeline ~22h after vms-connector PR #1657 merged to `stage` (2026-04-20T22:24Z). All pre-Step-E gates are green. Reclaimed after the `stage-regression` session went stale.

## What I verified and how

AWS CLI against prod-acct (388576304176) / us-west-2, plus [[nrql-investigator]] for connector-side emit activity.

### Lambda state

```bash
aws lambda get-function-configuration --function-name immix-autopatrol-schedule-cleanup
```

- State: `Active`, LastUpdateStatus: `Successful`
- Runtime: py3.13 | Memory: 512MB | Timeout: 60s | Reserved concurrency: none (removed since KB entity was written)
- **`CLEANUP_ENABLED=false`** — correct for pre-Step-E; Lambda observes + counts but does not disable
- `AUTOPATROL_ENV` unset — note, may want to confirm this is the intended default

Reenable Lambda: `Active`, 256MB / 30s.

### Queues

```bash
aws sqs get-queue-attributes --queue-url <cleanup_dev.fifo> --attribute-names ApproximateNumberOfMessages…
```

- Main queue `autopatrol_stale_schedule_cleanup_dev.fifo`: 0 messages (draining cleanly)
- DLQ `autopatrol_stale_schedule_cleanup_dlq_dev.fifo`: 0 messages
- No backpressure, no poison messages

### Invocations / errors (CloudWatch metrics, last 24h)

```bash
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations \
  --dimensions Name=FunctionName,Value=immix-autopatrol-schedule-cleanup --period 86400 --statistics Sum
```

- Invocations: **21**
- Errors: **0**

### DDB counter table (`autopatrol_cleanup_counters-dev`)

5 rows. Two bucket types observed, both from the [[2026-04-17_stale-schedule-cleanup-design#Second signal: `SiteDisabledOrDisarmed`]] routing:

| schedule_id | bucket | count / threshold | first_* | last_* | admin_pk |
|---|---|---|---|---|---|
| `1e2ee05f-…` | `site_disabled` | 3 / 56 | 2026-04-21T00:38Z | 2026-04-21T12:38Z | 234 |
| `c3808175-…` | `patrol_exit` (no_patrols) | 3 / 8 | 2026-04-21T01:56Z | 2026-04-21T13:56Z | 223 |
| `fbdfdba6-…` | `patrol_exit` (no_patrols) | 3 / 8 | 2026-04-21T03:40Z | 2026-04-21T15:40Z | 159 |
| `ee1822f1-…` | `patrol_exit` (no_patrols) | 3 / 8 | 2026-04-21T00:04Z | 2026-04-21T12:04Z | 138 |
| `636be1ba-…` | `patrol_exit` (no_patrols) | 3 / 8 | 2026-04-21T01:09Z | 2026-04-21T13:09Z | 235 |

Cadence is ~6h apart per schedule (3 hits over ~12h each), consistent with patrol cron frequency. At current rate each `patrol_exit` row crosses its 8-hit threshold in ~24-48h more wall-clock time.

### Connector-side emit activity (NR)

Scoped to `cluster_name = 'Connector-EKS'` on `:stage` images, last 24h:

- 6 `emit_no_patrols_signal` events (2 staging containers: `staging-connector-35277-vch-16-chm-cronjob` and `staging-connector-35277-vch-43-chm-cronjob`, 3 emits each)
- 697 WARNING-level `no patrols to run due to error, exiting.` lines from staging connectors (superset of the successful emits — the per-pod gating in `should_emit_cleanup_signal` filters this down)
- Queue name in INFO logs matches the target: `autopatrol_stale_schedule_cleanup_dev.fifo`

### Handle-deleted-sites fix working in the wild

Recent log sample:

```
INFO:cleanup_lambda invoked: enabled=False dry_run=False records=1
INFO:processing schedule_id=798e6dde-… tenant_id=24fb29fd-… site_id=19 reason=error bucket=patrol_exit target_hours=48 integration=vch
INFO:admin has no schedule with scheduleId=798e6dde-… — nothing to do, ACKing the message
END RequestId: fa04d8ef-4a69-50ed-98e5-ba8ec9e37cea
```

The `not_found → ACK` explicit path (fixed during the 2026-04-20 local smoke test — see [[2026-04-17_stale-schedule-cleanup-design#Bugs the smoke test caught (now fixed)]]) is handling deleted-upstream schedules without retry storms. No DLQ entries, confirming the fix is live.

## What this satisfies

Maps to yesterday's deferred §3 items:

- [x] **§3 stage deploy verified** — Lambdas + SQS + DDB live, 0 errors
- [x] **§3 observe successful cleanup run E2E** — up through counter-increment. Past-threshold legs (Immix confirm → admin PATCH → Slack) pending Step E + time
- [x] **§3 NR sanity check** — invocations visible via CloudWatch (21/24h), DLQ empty, no error pattern

## What's still pending

From [[2026-04-17_stale-schedule-cleanup-design#Rollout steps]]:

- **Step C** — provision dev/EU infra via [ds-terraform-eks-v2#69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) (OPEN, MERGEABLE, no drafts)
- **Step D** — un-draft [autopatrol_onboarder#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3) (currently marked `[STAGE BAKE ONLY — DO NOT MERGE YET]`). Merging to `master` deploys all 6 Lambdas with shared zip, `CLEANUP_ENABLED=false` default keeps cleanup dark
- **Step E** — flip stage `CLEANUP_ENABLED=true`. Bake 1 week. Gate to prod = ≥5 clean disables, 0 false positives, 0 DLQ depth

## Decision point for today

Currently counters are accumulating but Lambda is dark (`CLEANUP_ENABLED=false`). Two possible next moves:

1. **Flip stage `CLEANUP_ENABLED=true` now (Step E start)** — begins the 1-week bake window. First actual disable would fire within ~24-48h as `patrol_exit` counters cross 8/8. Gate to Step F requires ≥5 clean disables + 0 false positives + 0 DLQ over 7 days.
2. **Hold Step E, advance Step C instead** — merge the dev/EU terraform PR first so that when Step E starts, the dev-EU region follows on the same clock. Delays prod-US bake by ~1 day but keeps the regional rollouts in sync.

Either is defensible; the writeup records current state so either path is pickup-able without re-deriving this ground truth.

## Related

- [[autopatrol-cleanup-lambda]] — entity note (status: rollout-in-flight)
- [[2026-04-20_cleanup-lambda-runbook]] — ops commands
- [[2026-04-17_stale-schedule-cleanup-design]] — architecture + rollout plan
- [[2026-04-20_streamid-null-patrol-alert-bug]] — source of the `SiteDisabledOrDisarmed` second-signal routing visible in counter Row 1
- [[mark-todos]] §3
