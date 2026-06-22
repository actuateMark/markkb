---
title: "Admin schedule->customer->cameras cascade design"
type: synthesis
topic: autopatrol
tags: [autopatrol, actuate-admin, design, cascade, cohort-b, plan, billing]
jira: "AUTO-568"
created: 2026-05-04
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-05-05_cohort-b-backfill-runbook.md
  - topics/autopatrol/notes/concepts/2026-05-06_cohort-f3a-deactivate-runbook.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-06_cohort-f-investigation.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/billing/reading-list.md
  - topics/personal-notes/notes/daily/2026-05-04.md
  - topics/personal-notes/notes/daily/2026-05-05.md
incoming_updated: 2026-05-12
---

> **Status (2026-05-05):** PR 1 implementation landed — [[actuate_admin]] [#2405](https://github.com/aegissystems/actuate_admin/pull/2405), AUTO-568, 9 unit tests. Behind `AUTOPATROL_SCHEDULE_CASCADE_ENABLED=False`. Awaiting review + stage merge → 24h soak (flag OFF, zero behavioural drift) → PR 2 (flag flip on staging) → PR 3 (prod US+EU).

# Admin schedule -> customer -> cameras cascade design

Design note for the [[actuate_admin]] change that closes the **Cohort B silent-camera gap**: 31 customers / 353 cameras as of 2026-05-04 audit ([[2026-05-04_silent-camera-diagnosis]]). The cleanup Lambda correctly disables the schedule when Immix says it is gone, but admin-side cameras stay `active=True` because there is no per-customer cascade hook. Mirror image of the same gap exists for re-enable.

Priority #1 for 2026-05-05.

## Existing patterns to mirror, not reinvent

The [[actuate_admin]] codebase **already** has the cascade machinery — at the **tenant level** via `disable_tenant` / `reenable_tenant`. The new hook is the **per-customer** version of the same pattern.

### `disable_tenant` — `api/serializers/integrations/autopatrol/autopatrol_view.py:91-186`

```python
# For every cascade-affected schedule:
schedule.schedule_status = "Deleted"
schedule.disabled_by = reason            # e.g. "immix_tenant_suspended"
schedule.disabled_at = now
schedule.deleted_date = now
schedule.delete()                         # -> soft_delete(save=True) + undeploy()

# For every cascade-affected customer:
customer.delete()                         # cascades to cameras via existing
                                          # Customer.delete signal chain in
                                          # customer_model.py:1032-1036
```

Customer.delete() **already** sets `is_deleted_event=True` on each camera and soft-deletes them. We do not need to re-implement the camera cascade — only trigger `customer.delete()`.

### `reenable_tenant` — same file, lines 195-310

Identifies cascade-affected schedules via `disabled_by__startswith="immix_tenant_"`, then walks the schedule trail to find their customers. Restores schedules (`is_deleted=False`, `reenabled_by=reason`, `schedule_status="Awaiting"`), then restores customers via `customer.restore(save=True)` which fires `site_restored` and restores the parent Group if cascade-deleted.

### `AutoPatrolSchedule.delete()` — `inframap/sites/autopatrol/autopatrol_schedule_model.py:391-394`

```python
def delete(self, *args, **kwargs):
    self.soft_delete(save=True)
    self.undeploy()
```

This is where the per-customer cascade hook should live. The `disable_tenant` endpoint's intra-loop ordering (schedule_status -> disabled_by -> deleted_date -> .delete()) is already the canonical "disable a schedule" sequence — re-use it.

## Recommended implementation

### Disable path

Override `AutoPatrolSchedule.delete()` to add a post-soft-delete cascade check:

```python
def delete(self, *args, **kwargs):
    self.soft_delete(save=True)
    self.undeploy()
    self._maybe_cascade_to_customer()

def _maybe_cascade_to_customer(self):
    """If this was the last alive AP schedule for the customer, soft-delete
    the customer (which cascades to cameras via Customer.delete signal chain).
    Mirrors disable_tenant pattern but per-customer."""
    if not getattr(settings, "AUTOPATROL_SCHEDULE_CASCADE_ENABLED", False):
        return  # feature flag for safe rollout
    cust = self.customer
    if cust.is_deleted:
        return  # already disabled, nothing to cascade
    alive_count = AutoPatrolSchedule.objects.filter(
        customer=cust,
        is_deleted=False,
        schedule_status__in=["Active", "Awaiting"],
    ).exclude(pk=self.pk).count()
    if alive_count == 0:
        logger.info(
            f"schedule cascade: customer_id={cust.id} has 0 alive AP schedules "
            f"after disabling schedule_pk={self.pk}; cascading to cameras"
        )
        cust.delete()  # -> existing camera cascade
```

The exclude(pk=self.pk) protects against the soft-delete signal not having committed yet. Behaviour is idempotent: if the cascade already ran, the second call sees `cust.is_deleted=True` and short-circuits.

### Re-enable path

Override `AutoPatrolSchedule.save()` to detect the is_deleted=True -> False transition. Use Django's `tracker` field pattern OR fetch the prior value via `_state` introspection. On transition:

```python
def save(self, *args, **kwargs):
    is_being_revived = self._is_revival_save()
    super().save(*args, **kwargs)
    if is_being_revived:
        self._maybe_cascade_revive_customer()

def _maybe_cascade_revive_customer(self):
    if not getattr(settings, "AUTOPATROL_SCHEDULE_CASCADE_ENABLED", False):
        return
    cust = self.customer
    if not cust.is_deleted:
        return
    # Only auto-revive if every cascade-disabled schedule under this customer
    # was disabled by a recognised cascade source (cleanup_lambda, immix_tenant_*).
    # If user manually deleted the customer in admin UI, leave it alone.
    cascade_only = AutoPatrolSchedule._objects.filter(
        customer=cust,
        is_deleted=True,
    ).exclude(
        disabled_by__in=["cleanup_lambda", None]
    ).exclude(
        disabled_by__startswith="immix_tenant_"
    ).exists()
    if cascade_only:
        return  # at least one schedule was non-cascade-disabled; do not auto-revive
    cust.restore(save=True)
    logger.info(f"schedule cascade: restored customer_id={cust.id} on schedule revive pk={self.pk}")
```

## Edge cases the design must handle

| Case | Behaviour |
|---|---|
| User manually deletes customer in admin UI, then schedule is later re-enabled by cleanup_lambda's reenable Function URL | Do NOT auto-revive — `cascade_only` check fails. |
| Customer has multiple integrations (e.g. AP + [[rtsp-deep-dive|RTSP]]) — only AP schedules go away | Customer should still be soft-deleted (but cameras for other integrations may still be running independently — out of scope for this PR; raise as a follow-up). |
| Cleanup Lambda disables schedule, then immediately the onboarder's tenant lifecycle pass cascade-reenables the same tenant | The reenable_tenant flow already handles this — schedules get `is_deleted=False`, `schedule_status="Awaiting"`. Our `_maybe_cascade_revive_customer` would re-fire and restore the customer. Idempotent. |
| Schedule transitions Awaiting -> Deleted directly without going through Active | `_maybe_cascade_to_customer` keys off `schedule_status` filter, so it fires the same way. |
| Race: two schedules under the same customer get disabled simultaneously (different threads) | `alive_count == 0` is only true for the LAST one to commit, so only one cascade fires. Customer.delete() is idempotent. |
| Customer has zero schedules from inception (Cohort D / never-deployed) | Cascade does NOT fire from this hook — it only fires on the schedule's own delete. These customers stay as-is (handled via Cohort F investigation). |

## Tests required (TDD; ship as part of the PR)

1. Disable last schedule under customer -> customer.is_deleted=True, all cameras.is_deleted=True
2. Disable non-last schedule -> customer.is_deleted unchanged
3. Re-enable schedule on cascade-disabled customer (cleanup_lambda only) -> customer.is_deleted=False, cameras restored
4. Re-enable schedule on customer with manual disable in chain -> customer stays deleted
5. Idempotency: disable already-deleted schedule -> no error, no cascade re-fire
6. Idempotency: re-enable already-active schedule -> no error
7. Race: two threads each disable a different schedule simultaneously -> exactly one cascade fires
8. Feature flag OFF -> hooks are no-ops, no behavioural change

## Roll-out plan

1. **PR 1** — implementation behind `AUTOPATROL_SCHEDULE_CASCADE_ENABLED=False` flag. Tests pass green. Stage deploy. Soak 24h with flag off — confirms no behavioural drift.
2. **PR 2** — flip flag to `True` on staging. Manually trigger the path on a test customer (disable last schedule -> expect customer + cameras cascaded). Verify reenable on the same test customer.
3. **Audit gate** — re-run `scripts/ops/diagnose_silent_cameras.py` against a fresh Snowflake CSV; Cohort B count should drop to ~0 within 24h post-flip (cleanup_lambda's existing disables all retro-cascade).
4. **PR 3** — flip flag to `True` on prod (US + EU). Same audit gate.

## Non-goals (separately tracked)

- **Cohort F** subgroup classification (deployer/cronjob investigation) — this PR does not touch that population. They have alive schedules; this hook will not affect them.
- **Cohort C** (alive schedule with 0 devices) — admin UI warning is the right fix; not bundled here.
- **`deployment_phase=STAGE` in prod** — separate PR; some customers in prod admin have phase=STAGE/CUSTOM causing the deployer to assemble non-prod image tags. Unaffected by this cascade work.

## Related

- [[2026-05-04_silent-camera-diagnosis]] — the audit that quantified Cohort B
- [[2026-05-01_silent-cameras-diagnosis]] — original synthesis defining cohorts
- [[2026-04-28_tenant-status-sync-gap]] — the tenant-level cascade work (sibling pattern)
- [[autopatrol-cleanup-lambda]] — the upstream system that flags schedules as gone
- [[autopatrol-onboarder]] — the lifecycle pass that handles tenant-level cascade
