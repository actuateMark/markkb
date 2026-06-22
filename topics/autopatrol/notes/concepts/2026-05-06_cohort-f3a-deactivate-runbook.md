---
title: "Cohort F3a deactivation runbook (Immix-gone, admin-Active)"
type: concept
topic: autopatrol
tags: [autopatrol, actuate-admin, runbook, cohort-f, cohort-f3a, backfill, post-deploy, immix, billing]
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-05-05_cohort-b-backfill-runbook.md
  - topics/billing/reading-list.md
  - topics/personal-notes/notes/daily/2026-05-06.md
incoming_updated: 2026-05-12
---

# Cohort F3a deactivation runbook

**One-time admin-side cleanup for 9 customers (102 cameras) where the autopatrol schedule is `Deleted` or `NOT_FOUND` in Immix but still `is_deleted=False` in admin.** Mirrors the [[2026-05-05_cohort-b-backfill-runbook|§25 Cohort B backfill]] pattern — same `Customer.delete()` cascade, different population.

Identified by the [[2026-05-06_cohort-f-investigation|2026-05-06 cohort-F investigation]] Immix spot-check.

## Population

| cid | sched | Immix status | name | cams |
|---:|---:|---|---|---:|
| 41266 | 337 | Deleted | Advanced Security Systems - Eureka Office | 32 |
| 40672 | 1027 | Deleted | AutoPatrol-Live | 28 |
| 41260 | 331 | Deleted | Cimino Electric | 10 |
| 41263 | 334 | Deleted | Tate's Tire Pro's and Auto Service | 10 |
| 38738 | 212 | NOT_FOUND | 2 Fuller Road - Bergvliet | 9 |
| 37742 | 143 | NOT_FOUND | London | 5 |
| 41262 | 333 | Deleted | Link Housing - 550 M St, Eureka, CA | 4 |
| 41264 | 335 | Deleted | Mission Ace Hardware and Lumber | 3 |
| 44879 | 860 | Deleted | Solful - Petaluma | 1 |

**Total: 9 customers, 102 cameras.**

`NOT_FOUND` (cids 38738, 37742) means the schedule UUID returned no result when queried across all 18 active tenants — same operational meaning as `Deleted` (the schedule is gone from Immix).

## Pre-flight

This runbook is **independent** of the §25 Cohort B backfill ([[2026-05-05_cohort-b-backfill-runbook]]) — the populations don't overlap (Cohort B = admin-deleted-schedules; F3a = admin-active-schedules-Immix-deleted). Order doesn't matter; either can run first or both can run in the same admin shell session.

This runbook **does not require** PR #2406 to have merged. `Customer.delete()` runs the existing camera-cascade chain regardless of the §25 cascade hook (the hook is for the *schedule disable → customer delete* direction; we're skipping that and just deleting the customer directly).

## Procedure

**Important — execution path correction (2026-05-06):** `prod-camera-admin` runs on ECS Fargate with `enableExecuteCommand: false`, so `kubectl exec` is unavailable on US prod. Execution is via the [`deactivate_customers_by_cids`](https://github.com/aegissystems/actuate_admin/pull/2408) management command (PR #2408 against `staging`), invoked via `aws ecs run-task --overrides`. Same pattern reused for the [[2026-05-05_cohort-b-backfill-runbook|§25 Cohort B backfill]].

### Pre-requisite

PR [actuate_admin#2408](https://github.com/aegissystems/actuate_admin/pull/2408) merged through staging → main → prod deploy. Verify via `gh pr view 2408 --json mergedAt` and a prod admin task-definition revision bump.

### Step 1 — DRY-RUN via run-task

```bash
AWS_PROFILE=prod aws ecs run-task \
  --cluster prod-camera-admin \
  --task-definition prod_camera_admin \
  --launch-type FARGATE \
  --network-configuration '<copy-from-existing-service-config>' \
  --overrides '{
    "containerOverrides": [{
      "name": "prod-camera-admin",
      "command": [
        "python", "manage.py", "deactivate_customers_by_cids",
        "--cids", "41266,40672,41260,41263,38738,37742,41262,41264,44879",
        "--reason", "cohort_f3a_immix_gone_2026-05-06"
      ]
    }]
  }' \
  --region us-west-2
```

Output goes to firelens → [[new-relic|New Relic]]. Tail the run-task logs:

```sql
-- NRQL — find the dry-run output
SELECT message FROM Log
WHERE container_name = 'prod-camera-admin'
  AND message LIKE '%deactivate_customers_by_cids%'
SINCE 5 minutes ago
LIMIT 50
```

**Sanity-check:**

- The run-task log should show `mode=DRY-RUN` + `candidates=9` + `skipped_unknown=0` + `skipped_already_deleted=0` + `skipped_non_autopatrol=0`.
- Each cid line: `cid=<N> name=<...> integration='autopatrol' cams_active=<N> scheds_alive=<N>`.
- `cams_active` should match the per-cid camera count (32 / 28 / 10 / 10 / 9 / 5 / 4 / 3 / 1) within ±1. If any diverge significantly, **STOP** and re-investigate.

If any cid is already `is_deleted=True`, that's fine — it fell out of cohort F3a between 2026-05-06 and run-time. The command skips it.

### Step 2 — APPLY via run-task

```bash
AWS_PROFILE=prod aws ecs run-task \
  --cluster prod-camera-admin \
  --task-definition prod_camera_admin \
  --launch-type FARGATE \
  --network-configuration '<same-as-dry-run>' \
  --overrides '{
    "containerOverrides": [{
      "name": "prod-camera-admin",
      "command": [
        "python", "manage.py", "deactivate_customers_by_cids",
        "--cids", "41266,40672,41260,41263,38738,37742,41262,41264,44879",
        "--reason", "cohort_f3a_immix_gone_2026-05-06",
        "--apply"
      ]
    }]
  }' \
  --region us-west-2
```

The command (per `deactivate_customers_by_cids.py`) calls `Customer.delete()` per cid with a 2-second sleep, which cascades:

- Cameras `is_deleted_event=True` then soft-delete (the actual fix for the silent-camera state)
- `trigger_status_update`
- `sqs_client.delete_queue_if_exists(connector_id)`
- `delete_deployment(...)` — real EKS call in prod (terminates the connector pod / cronjob)
- `site_deleted` event
- `delete_immediate_group()` if the parent group is now empty

9 cids × 2s ≈ 20s task wall-clock. `mode=APPLY` + `deleted=9` + `errored=0` in the run-task log on success.

### Step 3 — Verify

```sql
-- NRQL — confirm the apply log
SELECT message FROM Log
WHERE container_name = 'prod-camera-admin'
  AND message LIKE '%mode=APPLY%' AND message LIKE '%cohort_f3a_immix_gone_2026-05-06%'
SINCE 30 minutes ago
LIMIT 5
```

After ~30 min, NR `K8sContainerSample` should drop:

```sql
-- F3a connector pods should stop appearing within ~10 min of EKS teardown
SELECT count(*) FROM K8sContainerSample
WHERE clusterName = 'Connector-EKS'
  AND containerName RLIKE '^connector-(41266|40672|41260|41263|38738|37742|41262|41264|44879)-.*'
SINCE 30 minutes ago
```

Expect 0 (or trailing tail from the last cronjob run before deletion).

Optional sanity ECS run-task with the read-only `audit_autopatrol_state` command for any of the 9 cids:

```bash
AWS_PROFILE=prod aws ecs run-task ... --command 'python manage.py audit_autopatrol_state --customer_id 41266'
```

The output should show `is_deleted=True` and `cameras_active=0`.

Outside the shell:

```bash
# Spot-check NR — the 9 connector containers should stop appearing in K8sContainerSample within ~10 min
# (deployment teardown removes the cronjob, scheduled pods stop spawning)
```

NRQL sanity check (run after ≥30 min):

```sql
SELECT count(*) FROM K8sContainerSample
WHERE clusterName = 'Connector-EKS'
  AND containerName RLIKE '^connector-(41266|40672|41260|41263|38738|37742|41262|41264|44879)-.*'
SINCE 30 minutes ago
```

Expect 0 (or trailing tail from the last cronjob run before deletion).

Also: re-run the cohort-F NR billing-emit query — these 9 cids should drop out of the `site_product_ended` count entirely, freeing up 102 cams from the silent-camera roster.

### Step 5 — Update the tracker

```bash
# Locally, on the laptop
cd /home/mork/work/autopatrol_onboarder
# Edit scripts/ops/cohort_f_tracker.json:
# For each of the 9 cids, set:
#   status: "fixed"
#   notes: "Deactivated via Customer.delete() per cohort-f3a-deactivate-runbook 2026-05-06"
#   updated: "2026-05-06"
```

Alternatively, the next `--cohort-f-deep` script run will auto-update `last_seen_silent` (or omit them entirely if they're not in the next CSV).

## Rollback

`Customer.delete()` is a soft-delete — sets `is_deleted=True` but doesn't drop rows. If the runbook is mistakenly run against a wrong cid:

```python
for c in Customer._objects.filter(id__in=F3A_CIDS, is_deleted=True):
    c.restore(save=True)
```

`Customer.restore()` (`customer_model.py:875`) reverses `is_deleted` and re-fires `site_restored`. Cameras follow.

**Note:** rollback restores admin state but does NOT recreate Immix schedules — those are gone on Immix's side and would need fresh onboarding flow. If a rollback is needed, talk to ops about the Immix re-onboarding path before restoring on our side.

## Why this is its own runbook (vs. waiting for §3 + §25)

The §3 cleanup-Lambda + §25 cascade-hook pipeline would catch these 9 once both flip:

1. §3 Step F flag flip → connector emits `no_patrols` → cleanup-Lambda → counter-tracks → after threshold (18h–48h cadence-aware), checks Immix → confirms gone → PATCH admin schedule `is_deleted=True` with `disabled_by='cleanup_lambda'`
2. §25 PR #2406 lands + flag flip → cascade hook fires on schedule disable → `Customer.delete()` → cameras soft-delete

So the pipeline does the same thing, just slower (multi-day) and dependent on both §3 + §25 being live in prod. This runbook is the fast-track for the 9 cids whose Immix-state is already confirmed Deleted today.

It's also a useful one-shot whenever a fresh audit surfaces a new F3a-shaped population (cleanup-Lambda hadn't fired yet, but Immix already says gone). Re-usable pattern.

## Related

- [[2026-05-06_cohort-f-investigation]] — the analysis that produced this list
- [[2026-05-05_cohort-b-backfill-runbook]] — sister runbook for Cohort B (§25 backfill)
- [[2026-05-04_admin-schedule-cascade-design]] — §25 cascade hook design
- [[autopatrol-cleanup-lambda]] — cleanup-Lambda entity (the mechanism this preempts)
- [[2026-05-04_silent-camera-diagnosis]] — original cohort F audit
