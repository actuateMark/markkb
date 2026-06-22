---
title: "Cohort B one-time backfill runbook (post-PR-#2406)"
type: concept
topic: autopatrol
tags: [autopatrol, actuate-admin, runbook, cohort-b, backfill, cascade, post-deploy, billing]
jira: "AUTO-568"
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-05-06_cohort-f3a-deactivate-runbook.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-06_cohort-f-investigation.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/billing/notes/syntheses/2026-05-11_billing-pain-post-mortem.md
  - topics/billing/reading-list.md
  - topics/personal-notes/notes/daily/2026-05-05.md
  - topics/personal-notes/notes/daily/2026-05-06.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming_updated: 2026-05-12
---

# Cohort B one-time backfill runbook

**Required follow-up after [actuate_admin#2406](https://github.com/aegissystems/actuate_admin/pull/2406) merges to main and the main → prod deploy completes.**

The §25 schedule→customer cascade hook (commit `08cd66a0` in #2406) only fires on **new** schedule transitions. The 31 customers / 353 cameras already in Cohort B (per the [[2026-05-04_silent-camera-diagnosis|2026-05-04 audit]]) have schedules that are already `is_deleted=True` — the hook would have caught them at the moment they were disabled, but those moments are in the past. Without this backfill, those 31 customers stay silent forever and Cohort B does not drop.

This is **not optional**. The hook plus the backfill are the two halves of the §25 fix; merging #2406 is only half the work.

> **Execution path update (2026-05-06):** US `prod-camera-admin` runs on ECS Fargate with `enableExecuteCommand: false` — `kubectl exec` is unavailable. Use the [`deactivate_customers_by_cids`](https://github.com/aegissystems/actuate_admin/pull/2408) management command via `aws ecs run-task --overrides` instead. See [[2026-05-06_cohort-f3a-deactivate-runbook]] for the run-task invocation shape (same pattern; just substitute the Cohort B cid list and `--reason cohort_b_backfill_<date>`). The Django-shell procedure below is kept for reference (and works on EU EKS) but is not the US prod path.

## When to run

**After:**
- PR #2406 is merged to `main`
- The main → prod deploy is live (verify in admin / NR)
- (Optional but recommended) The flag flip `AUTOPATROL_SCHEDULE_CASCADE_ENABLED=True` is **not** required for this backfill — `customer.delete()` runs the existing camera-cascade chain regardless.

Target window: 2026-05-06 evening or 2026-05-07 — anytime after #2406 lands and prod deploy is verified.

## Procedure

### Step 1 — kubectl exec into prod admin

```bash
AWS_PROFILE=prod aws eks update-kubeconfig --name <prod-cluster-name> --region us-west-2
kubectl -n <prod-admin-ns> get pods | grep admin   # find an admin pod
kubectl -n <prod-admin-ns> exec -it <admin-pod> -- python manage.py shell
```

If unsure of the pod / namespace, mirror what the existing audit-state command runs against — the prod admin app is the canonical exec target ([[2026-04-30_autopatrol-state-audit]] has prior examples).

### Step 2 — DRY-RUN: list candidates first

Inside the shell:

```python
from django.db.models import Q, Count
from inframap.sites.customer.customer_model import Customer

candidates = Customer.objects.annotate(
    alive_scheds=Count(
        "autopatrol_schedules",
        filter=Q(autopatrol_schedules__is_deleted=False)
             & Q(autopatrol_schedules__schedule_status__in=["Active", "Awaiting"]),
    ),
    total_scheds=Count("autopatrol_schedules"),
).filter(
    alive_scheds=0,
    total_scheds__gt=0,
    is_deleted=False,
)

print(f"Cohort B candidates: {candidates.count()}")
# Expected: ~31 (per 2026-05-04 audit). If significantly different, STOP and
# re-investigate before continuing — the audit may be stale or the cleanup
# Lambda may have changed scope.

for c in candidates:
    print(f"  {c.id:>6}  {c.connector_id or '<no-conn-id>':<22}  {c.name}")
```

**Sanity-check the list before continuing.** Cross-reference 2-3 entries against the 2026-05-04 audit JSON to confirm they're the same population. If the count is wildly different (e.g. 200+, or 0), abort and re-audit.

### Step 3 — APPLY: cascade-soft-delete each candidate

```python
import time

for c in candidates:
    print(f"[{time.strftime('%H:%M:%S')}] deleting customer_id={c.id} {c.name!r}")
    c.delete()      # soft-delete + cameras cascade + site_deleted event
    time.sleep(2)   # spread out EKS deployment teardown + SQS ops

print("done")
```

`Customer.delete()` (`inframap/sites/customer/customer_model.py:1032`) runs:
- Cameras `is_deleted_event=True` then soft-delete (the actual fix for the silent-camera state)
- `trigger_status_update`
- `sqs_client.delete_queue_if_exists(connector_id)`
- `delete_deployment(...)` — real EKS call in prod
- `site_deleted` event
- `delete_immediate_group()` if the parent group is now empty

The 2-second sleep spreads out the deployment teardowns. 31 customers × 2s ≈ 1 min total wall-clock.

### Step 4 — Verify

After the loop completes:

```python
# Confirm the candidates are now is_deleted=True
print(f"still-alive Cohort B: {candidates.count()}")  # expect 0
```

Outside the shell, after a few minutes:

```bash
# Re-run the audit against a fresh Snowflake CSV — Cohort B count should drop
cd /home/mork/work/autopatrol_onboarder
source scripts/fetch_local_test_env.sh prod
python3 scripts/ops/diagnose_silent_cameras.py --csv ~/Downloads/<latest>.csv
# Cohort B should be 0 (or very small — any residual is brand-new arrivals
# since the audit, which the §25 hook catches going forward).
```

Also spot-check 2-3 of the deleted customers in admin UI — confirm cameras are now `active=False` / soft-deleted.

### Step 5 — Flip the flag (optional, separate ticket)

Per the §25 three-PR rollout plan, the flag flip to `AUTOPATROL_SCHEDULE_CASCADE_ENABLED=True` was originally PR 2 of 3. With #2406 going direct to main, the flip is now an env-only change (terraform / k8s env update + redeploy of admin). Do this **after** the backfill verifies clean — this enables the cascade hook for **future** cleanup_lambda disables, so new customers entering Cohort B are caught automatically rather than accumulating until the next manual backfill.

The order is intentional: backfill clears the existing population, flag flip prevents the population from re-accumulating.

## Why a one-time script and not a management command

The cascade hook is the durable mechanism going forward. The 31-customer backfill is a one-time event by definition — every previously-stuck customer gets cleaned up once and the hook prevents accumulation thereafter. Wrapping this as a management command would imply we expect to run it again, which we don't. If for any reason a future audit surfaces a new Cohort B population (e.g. flag was OFF for a stretch and customers leaked through), this runbook is durable and re-usable.

## Rollback

`Customer.delete()` is a soft-delete — it sets `is_deleted=True` but doesn't drop rows. If the backfill is mistakenly run against the wrong population:

```python
# Restore — Customer.restore(save=True) is the symmetric inverse
for c in Customer._objects.filter(is_deleted=True, ...):  # narrow filter to your mistake
    c.restore(save=True)
```

`Customer.restore()` (`customer_model.py:875`) reverses `is_deleted` and re-fires `site_restored`. Cameras follow via the same chain.

## Related

- [[2026-05-04_admin-schedule-cascade-design]] — design for the §25 cascade hook
- [[2026-05-04_silent-camera-diagnosis]] — the audit that quantified Cohort B (31 customers / 353 cameras)
- [[2026-05-01_silent-cameras-diagnosis]] — original cohort scheme (A/B/C/D/E/F)
- [actuate_admin#2406](https://github.com/aegissystems/actuate_admin/pull/2406) — hotfix PR carrying the cascade hook + Tatiana's autopatrol sync ProtectedError fix
- [actuate_admin#2405](https://github.com/aegissystems/actuate_admin/pull/2405) — my standalone staging PR (redundant once #2406 lands; close)
- AUTO-568
- mark-todos §25
