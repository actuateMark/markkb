---
title: "AutoPatrol state-mismatch audit — manage.py audit_autopatrol_state"
type: synthesis
topic: admin-api
tags: [autopatrol, audit, db, customer, schedule, propagation, planning, mgmt-command, immix]
created: 2026-04-30
updated: 2026-05-01
author: kb-bot
---

# AutoPatrol state-mismatch audit — `manage.py audit_autopatrol_state`

> **Purpose:** size the population affected by the propagation gaps surfaced 2026-04-30 ([[2026-04-30_admin-propagation-handoff]]) before designing the propagation hooks or the `manage.py reconcile_autopatrol_state` patch.
>
> **Status (2026-05-01):** Command is **deployed on stage admin** (Staging CI run 25217418573 succeeded 2026-05-01T14:21Z). Awaiting (a) stage validation `kubectl exec` to confirm the command runs end-to-end, then (b) staging→main release-train cut, then (c) prod deploy, then (d) prod run for cohort sizing.
>
> **How to run (once deployed):**
>
> ```bash
> python manage.py audit_autopatrol_state                      # all cohorts
> python manage.py audit_autopatrol_state --cohort A,C          # subset
> python manage.py audit_autopatrol_state --customer_id 40803   # verify named
> python manage.py audit_autopatrol_state --limit 50            # raise sample cap
> ```
>
> The command is read-only (no `save()` / `delete()` calls), code-reviewed before it touches prod, and becomes the dry-run skeleton of the eventual `reconcile_autopatrol_state` patch (deliverable #2). This decision came out of the 2026-04-30 planning session — the user vetoed running ad-hoc Django shell queries on prod admin; Path 2 (mgmt command) was chosen over Path 1 (existing REST endpoints + post-process) and Path 3 (new REST audit endpoint) because it's the smallest new surface and converges with deliverable #2.
>
> **The cohort-filter snippets below are the design reference** — they document each cohort's filter logic for anyone reading the command source. The canonical implementation lives at `inframap/management/commands/audit_autopatrol_state.py` in [[actuate_admin]], with tests at `api/tests/test_audit_autopatrol_state.py`.

## PR chain — how the command shipped (2026-04-30 → 2026-05-01)

| Step | PR | What it did | Why |
|---|---|---|---|
| 1 | [#2388](https://github.com/aegissystems/actuate_admin/pull/2388) (closed) | Initial PR | Wrong base (`main`) and wrong branch parent (`origin/main`); see [[release-flow-stage-first]] for the lesson |
| 2 | [#2389](https://github.com/aegissystems/actuate_admin/pull/2389) | Re-opened off `staging` with the same code | Replaced #2388 cleanly. Merged but failed Staging CI on `test_cohort_b_counts_orphan_schedules` |
| 3 | [#2390](https://github.com/aegissystems/actuate_admin/pull/2390) | `schedule_id="" \| IS NULL` defensive filter | Discovered: model declares `schedule_id` non-null CharField, so prod orphan rows are empty-string (not NULL). Test fixture also fixed to use `""` |
| 4 | [#2391](https://github.com/aegissystems/actuate_admin/pull/2391) | `tier=1` on test fixture | Discovered: `tier` is `IntegerField()` with no default. Django auto-defaults missing CharFields to `""` but doesn't auto-default IntegerFields |
| 5 | (Aziz, `293f7039`, on PR #2393's merge train) | Reshape cohort B/C fixtures to one-orphan-per-customer | Discovered: `UniqueConstraint(customer_id, schedule_id)` from migration 0482 prevents seeding multiple `("", same-customer)` rows. My PR #2394 was the same fix; closed as redundant when Aziz's landed first |

**The journey itself was a deep-dive.** Each iteration revealed another constraint on `AutoPatrolSchedule`:
- `schedule_id` — `CharField(max_length=36)`, NOT NULL since migration 0476
- `tier` — `IntegerField()`, NOT NULL, no default since 0476
- `(customer_id, schedule_id)` — `UniqueConstraint` since 0482 (2025-06-24)

This is now captured in [[2026-04-30_data-model-cascade-semantics]] for future reference.

## Open question — prod orphan-state shape

The handoff doc reported customer 39221 has 4 orphan schedules with `schedule_id=None`. But:
- The model declares `schedule_id` as `NOT NULL` — `None` is rejected at insert
- The unique constraint `(customer_id, schedule_id)` since 2025-06-24 prevents 4 rows with `("", customer=39221)`

So either:
1. The constraint isn't actually enforced in prod (would require `NOT VALID` clause; usually that's reserved for known-violating data)
2. The 4 "orphan" rows have **distinct non-empty** `schedule_id`s that the user perceived as orphans by some other criterion (e.g., status, missing checks, schedule deleted on Immix side but row persisted with old schedule_id)
3. The handoff doc was imprecise about the field

The audit command's defensive `Q(schedule_id__isnull=True) | Q(schedule_id="")` filter handles cases 1 and 3. If case 2 is the truth, **Cohort B/C will return zero on prod** — and we'll need to redefine "orphan" by a different signal (`schedule_status="Removed"`? schedule absent from Immix `/Schedules`? something else).

**Resolution path:** when the prod run lands (see "TBD" section below), either:
- Cohort B has rows → the filter caught the orphans, my model holds, proceed to ADR design
- Cohort B is empty AND user can still point to 39221's "orphan" rows in admin UI → re-define the filter against actual data

Hold the propagation-hook ADR + reconcile-patch design until this resolves.

## Cohorts to size

The 3 named prod customers are the visible tip. We don't yet know how big each class is. The audit defines five cohorts; the first three correspond directly to the named customers and are the priority for sizing.

| Cohort | Filter | Named example | Why it matters for design |
|---|---|---|---|
| A | `active=False AND is_deleted=False AND integration.is_autopatrol` | pk=40803 | Customer was deactivated outside the cascade path; cameras still active |
| B | `AutoPatrolSchedule.schedule_id IS NULL AND is_deleted=False` | (population, not a customer) | The orphan-schedule universe — the cleanup Lambda's per-schedule path is blind to these |
| C | Customers where **all** non-deleted schedules are orphans (Cohort B) | pk=41260, pk=39221 | "Site running but no patrols" — `manage.py reconcile_autopatrol_state` must address these |
| D | `active=True AND zero non-deleted schedules AND integration.is_autopatrol` | (none observed yet) | Customer marked active but Immix has no schedules at all — propagation gap variant |
| E | Tenant Group active-customer counts | (context) | Sanity-check overall tenant population vs the cohorts above |

Cohort A's count tells us how big the "deactivated outside cascade" gap is. Cohort B+C tell us the orphan-schedule pollution and how many customers it traps. Cohort D is a watch-stat — we don't expect many but if it's > 0 the propagation hook design needs to handle it.

## Pre-flight — verify the 3 named customers

Run this first to confirm the seed-data assumptions are still true on prod (a few hours have passed since the handoff was written, and onboarder lifecycle pass might have moved some of these):

```python
from inframap.sites.customer.customer_model import Customer

for pk in [40803, 39221, 41260]:
    c = Customer.objects.with_deleted().filter(pk=pk).first()
    if not c:
        print(f"pk={pk}: NOT FOUND"); continue
    print(f"pk={pk} name={c.name!r}")
    print(f"  active={c.active} is_deleted={c.is_deleted} group_id={c.group_id}")
    cams_active = c.cameras.filter(is_deleted=False).count() if hasattr(c, 'cameras') else 'n/a'
    cams_total = c.cameras.with_deleted().count() if hasattr(c.cameras, 'with_deleted') else cams_active
    print(f"  cameras: active={cams_active} total_incl_deleted={cams_total}")
    schedules = c.autopatrolschedule_set.with_deleted().all() \
        if hasattr(c.autopatrolschedule_set, 'with_deleted') else c.autopatrolschedule_set.all()
    print(f"  schedules: count={schedules.count()}")
    for s in schedules:
        print(f"    - pk={s.pk} schedule_id={s.schedule_id} status={s.schedule_status} is_deleted={s.is_deleted}")
    print()
```

Expected: each customer matches its row in the [[2026-04-30_admin-propagation-handoff]] table. If something has moved, update the handoff before designing.

## Cohort A — active=False, not-deleted, autopatrol

```python
from inframap.sites.customer.customer_model import Customer

a = Customer.objects.filter(
    active=False,
    is_deleted=False,
    integration__is_autopatrol=True,
)
print(f"Cohort A (active=False, is_deleted=False, autopatrol): {a.count()}")
print("Sample (first 20):")
for c in a[:20]:
    parent = c.group.parent_account if c.group else None
    cams_active = c.cameras.filter(is_deleted=False).count() if hasattr(c, 'cameras') else 'n/a'
    print(f"  pk={c.pk} name={c.name!r} cams_active={cams_active} group_parent_account={parent}")
```

**What the count tells us:**
- 0 → the 40803 case is a one-off, no general fix needed beyond the one-time DB patch
- 1–10 → small, can be hand-resolved + propagation hook is nice-to-have not urgent
- 10+ → there's a systemic pattern; design the propagation hook (Customer.active=False → cascade cameras) as a priority

## Cohort B — orphan schedules (schedule_id IS NULL)

```python
from collections import Counter
from inframap.sites.autopatrol.autopatrol_schedule_model import AutoPatrolSchedule

b = AutoPatrolSchedule.objects.filter(
    schedule_id__isnull=True,
    is_deleted=False,
)
print(f"Cohort B (orphan schedules, no Immix ID): {b.count()}")

per_customer = Counter(b.values_list('customer_id', flat=True))
print(f"  Distinct customers carrying orphans: {len(per_customer)}")
print(f"  Customers with ≥3 orphans: {sum(1 for v in per_customer.values() if v >= 3)}")
print(f"  Top 20 customers by orphan count: {per_customer.most_common(20)}")
```

**What the count tells us:**
- Total orphan rows is the upper bound on how many `AutoPatrolSchedule` rows the DB patch will touch
- Distinct-customer count is the lower bound on how many customers Cohort C affects
- The histogram (≥3 orphans) flags clusters worth investigating manually before the bulk patch

## Cohort C — customers with only orphan schedules

```python
from django.db.models import Count, Q, F

c_qs = Customer.objects.filter(is_deleted=False).annotate(
    total_active_schedules=Count(
        'autopatrolschedule',
        filter=Q(autopatrolschedule__is_deleted=False),
    ),
    orphan_schedules=Count(
        'autopatrolschedule',
        filter=Q(autopatrolschedule__is_deleted=False,
                 autopatrolschedule__schedule_id__isnull=True),
    ),
).filter(
    total_active_schedules__gt=0,
    total_active_schedules=F('orphan_schedules'),
)

print(f"Cohort C (customers with ONLY orphan schedules): {c_qs.count()}")
for c in c_qs[:20]:
    print(f"  pk={c.pk} name={c.name!r} active={c.active} "
          f"total_schedules={c.total_active_schedules}")
```

**What the count tells us:**
- This is the population the DB patch's "orphan-schedule" checker has to cascade-disable
- If 39221 + 41260 are the only ones, the patch is small + low-risk
- If there are 50+, we need feature-flagged batch processing + dry-run first

## Cohort D — active customers with zero schedules

```python
from django.db.models import Count, Q

d_qs = Customer.objects.filter(
    is_deleted=False,
    active=True,
    integration__is_autopatrol=True,
).annotate(
    total_active_schedules=Count(
        'autopatrolschedule',
        filter=Q(autopatrolschedule__is_deleted=False),
    ),
).filter(total_active_schedules=0)

print(f"Cohort D (active autopatrol customers with zero schedules): {d_qs.count()}")
for c in d_qs[:20]:
    print(f"  pk={c.pk} name={c.name!r} group_id={c.group_id}")
```

**What the count tells us:**
- Should be near zero — onboarder is supposed to keep schedule rows in sync with Immix
- > 0 means there's an onboarder bug OR new propagation gap not in cohort B/C
- Surface counts > 0 to the user; investigate per-customer before deciding patch policy

## Cohort E — tenant-level sanity-check

Heavier query (touches MPPT descendants), run only if you want to size by tenant. Skip if Cohort B+C numbers are already conclusive.

```python
from inframap.group.group_model import Group

tenants = Group.objects.filter(parent_account=True, is_deleted=False)
print(f"Total tenant-root groups: {tenants.count()}")

print("Per-tenant autopatrol customer breakdown (first 20):")
for t in tenants[:20]:
    descendants = t.get_descendants(include_self=True)
    base = Customer.objects.filter(
        group__in=descendants,
        is_deleted=False,
        integration__is_autopatrol=True,
    )
    active = base.filter(active=True).count()
    inactive = base.filter(active=False).count()
    print(f"  tenant pk={t.pk} name={t.name!r} active={active} inactive_present={inactive}")
```

## What the audit numbers will inform

| Numbers | Implication |
|---|---|
| Cohort A small (0–5) + Cohort C small (0–5) | One-time DB patch is small and low-risk; ship without batch protections |
| Cohort A or C in the tens-or-hundreds | Need feature-flagged batch processor with dry-run, audit log, rollback plan via `reenable_tenant` |
| Cohort B per-customer histogram skewed (one customer with 50 orphans) | Manual review of the outlier before patch; may indicate a broken onboarder run we should investigate first |
| Cohort D > 0 | Onboarder bug — investigate before the propagation hook design (hook would mask it) |

## TBD — prod run results (paste here)

> Structural placeholder. Fill in once `python manage.py audit_autopatrol_state` has been run on prod admin (after the staging→main release-train cut). Until this section has numbers, treat the propagation-hook ADR and reconcile-patch design as **blocked**.

```
# paste raw command output here

# also fill in:
# Cohort A count: ...
# Cohort B count + distinct_customers: ...
# Cohort C count: ...
# Cohort D count: ...
# Tenant-root summary (cohort E): ...
```

**Then:** resolve the [[#Open question — prod orphan-state shape]] above against the actual numbers, decide whether the orphan filter holds or needs redefining, and only then proceed to the propagation-hook ADR and reconcile-patch design.

## Cross-references

- [[2026-04-30_admin-propagation-handoff]] — the handoff this audit is the pre-step for
- [[2026-04-30_data-model-cascade-semantics]] — model-level semantics that motivate each cohort filter
- [[2026-04-29_immix-zombie-tenants]] — separate but adjacent cohort (tenant-level Immix absence)

## Status

Queries drafted 2026-04-30. **Numbers not yet collected** — user to run on prod admin shell at next opportunity. Update this note with results once collected; that becomes the sizing input for the propagation-hook ADR + DB-patch spec.
