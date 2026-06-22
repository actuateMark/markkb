---
title: "Admin data model — cascade and soft-delete semantics (seed)"
type: concept
topic: admin-api
tags: [data-model, cascade, soft-delete, autopatrol, customer, schedule, camera, group, propagation, sticky-state, immix, billing]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - topics/admin-api/notes/concepts/release-flow-stage-first.md
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/personal-notes/notes/concepts/2026-04-30_admin-propagation-handoff.md
  - topics/personal-notes/notes/concepts/2026-05-01_pre-endrun-crashes-handoff.md
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/admin-api/notes/concepts/release-flow-stage-first.md
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/autopatrol/notes/syntheses/2026-05-01_pre-endrun-crashes-resolution.md
  - topics/autopatrol/notes/syntheses/2026-05-01_silent-cameras-diagnosis.md
  - topics/billing/_summary.md
  - topics/billing/_todos.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/syntheses/2026-05-11_billing-pain-post-mortem.md
  - topics/billing/notes/syntheses/2026-05-12_week-in-review-non-technical.md
  - topics/billing/reading-list.md
incoming_updated: 2026-05-27
---

# Admin data model — cascade and soft-delete semantics (seed)

> **Status:** SEED. This is the first pass of a deep-dive that needs to grow as we touch more of the data model. Mark flagged 2026-04-30 that the autopatrol-related models are "intricate and tricky and sticky." This note inventories what we've learned through the §16 cascade rollout, and is the home for future findings.
>
> **Audience:** anyone touching schedule/customer/camera/group state from cleanup Lambda, onboarder Lambda, admin endpoint, or admin UI.

## TL;DR — what's load-bearing

- **`active` vs `is_deleted` are independent.** A row can be `active=False AND is_deleted=False`, `active=True AND is_deleted=True`, or any other combination. They do NOT propagate to each other automatically. The §16 cascade endpoint uses `is_deleted=True` exclusively; `active` is set by other code paths.
- **Soft-delete cascades DOWN, but not UP.** `Customer.delete()` cascades to cameras and (under conditions) to the parent Group. Schedule.delete() does NOT cascade up to mark the customer as inactive when it's the last schedule. This is the "schedule → customer → site" gap surfaced 2026-04-30.
- **Cascade-restore is partial.** `customer.restore()` un-soft-deletes the Customer + (under conditions) the parent Group, but does NOT reactivate the cameras that were cascade-deleted via the customer's earlier delete. The current §16 reenable path leaves cameras dependent on the onboarder's normal sync to re-create them.

## Models in scope

| Model | Path | Soft-delete? | Has `active` field? | Has `disabled_by`/`reenabled_by`? |
|---|---|---|---|---|
| `Group` | `inframap/group/group_model.py` | yes (SoftDeleteMixin) | no | no |
| `Customer` | `inframap/sites/customer/customer_model.py` | yes | yes | no |
| `AutoPatrolSchedule` | `inframap/sites/autopatrol/autopatrol_schedule_model.py` | yes | derived (via `is_active`) | **yes** |
| `Camera` (per-site) | `inframap/cameras/...` | yes | yes (`is_deleted_event`) | no |
| `Contract` | `inframap/sites/autopatrol/contract_model.py` | (TBD) | TBD | no |

## Cascade behavior — what we've verified through the §16 work

### Customer.delete() — DOWN cascade

`Customer.delete()` is the soft-delete entrypoint and is the same path used by the admin UI's "Delete site" action. Per the disable_tenant cascade endpoint comments and the model code:

- Sets `is_deleted=True`, `deleted_date=now()`
- Cascades through **cameras**: each camera under the customer gets `is_deleted_event=True` (to prevent "cameras disabled" warnings) and is soft-deleted
- Triggers `delete_immediate_group()` IFF the customer's parent Group has only this one (or zero) active customer left → the Group itself gets soft-deleted
- Fires the schedule processor / camera disable hook chain

This is the verified cascade-down path. Reverse-engineered from the §16 cascade rollout 2026-04-29 (RSS: 12 customers + 12 schedules → admin OK in 12s, all rows soft-deleted including parent Groups).

### AutoPatrolSchedule.delete() — DOWN cascade

- Sets `is_deleted=True`, `deleted_date=now()`
- Calls `undeploy()` (per `autopatrol_schedule_model.py:391-394`) which issues HTTP DELETE to the connector_deployer to tear down the K8s cronjob
- **Does NOT propagate up.** The customer is unaware of its schedules being deleted.

### `Customer.restore()` — UP (partial)

`customer.restore()` (admin/sites/customer/customer_model.py:875):
- Calls `super().restore()` → `is_deleted=False`, `deleted_date=None`
- Fires `event.send_event("site_restored", self)` event
- IF `self.group.group_customer.filter(is_deleted=False).count() <= 1 AND self.group.is_deleted` → calls `self.group.restore(save=True)` to revive the cascade-deleted parent Group

**What it does NOT do:**
- Does not reactivate cameras that were cascade-deleted via the prior `Customer.delete()` chain. Cameras stay `is_deleted=True` with `is_deleted_event=True`.
- Does not propagate to AutoPatrolSchedule rows under the customer.

This is the critical asymmetry — Customer.delete() cascades down to cameras, but Customer.restore() does NOT. Today's `auto_patrol/reenable_tenant/` admin endpoint relies on the onboarder's subsequent `auto_patrol/sync/` flow to handle camera re-creation. Whether that's enough is an open question.

### Soft-delete vs active

**Observed in prod 2026-04-30**: customer pk=40803 has `active=False AND is_deleted=None`. This is a state our cascade does not produce — it must come from another code path (manual admin edit, or the onboarder marking customers inactive without soft-deleting).

**Implication for cleanup design:** when reasoning about "is this customer/schedule actually in use", you must check BOTH `active` AND `is_deleted`. Filtering on just `is_deleted=False` is incomplete.

## Schedule statuses

Per `actuate_integration_calls.autopatrol.autopatrol_enums.ScheduleStatusEnum`:

| Status | Meaning (Immix) | Admin-side reaction |
|---|---|---|
| `Awaiting` | Schedule created in Immix but not yet activated | onboarder POSTs + activates |
| `Active` | Running on Immix | normal state |
| `Suspended` | Customer-controlled non-running state | cleanup Lambda treats as "active" for its purposes (won't disable per §17 fix 2026-04-27) |
| `Paused` | Customer-controlled non-running state | same as Suspended |
| `Removed` | Tenant gone — schedule no longer accessible | cleanup Lambda treats as "gone" → disable |
| `Deleted` | Schedule deleted on Immix | cleanup Lambda treats as "gone" → disable; cascade endpoint sets this on cascade-disable |

The cascade-reenable endpoint resets `schedule_status="Awaiting"` so the onboarder's normal sync picks the row up on next run.

**Orphan rows observed 2026-04-30:** schedules with `schedule_id=None` (no Immix ID) and `schedule_status=None`. These predate our cascade infrastructure. They appear in the default-manager view but have no provenance. The one-time DB patch task captures this.

## Propagation gaps observed 2026-04-30

The cascade rollout surfaced three concrete propagation failures in prod admin:

1. **Customer pk=40803 ("ABC Liquor Store 23"):** `active=False`, `is_deleted=None`, has 1 schedule (`Visual Camera Health`, `schedule_id=None`), cameras still active. The customer was deactivated through some path other than our cascade. Cameras should follow customer.active.
2. **Customer pk=39221 ("Victoria - EE Demo"):** `active=True`, has 4 schedules with `schedule_id=None` (orphans). User reports all schedules are deleted on Immix side. Cameras + site still active. Should propagate up: schedules deleted → customer inactive → cameras inactive.
3. **Customer pk=41260 ("Cimino Electric"):** `active=True`, has 1 schedule with `schedule_id=None`. User reports running but no patrols. The cleanup Lambda's per-schedule path can't address this because the schedule has no Immix `schedule_id` to query.

**Common thread:** the data model has no automatic propagation hooks for these state transitions. We rely on the onboarder Lambda's sync flow and the cleanup Lambda's per-schedule cleanup, but neither addresses the "all schedules gone → mark customer inactive" case.

## Verified findings (2026-04-30 deep dive)

A code-level pass through `actuate_admin` resolved each of the seed's open questions. Citations are file:line on `master`.

### 1. `Customer.save()` does NOT propagate `active` to cameras ✓

The only field that propagates from Customer to its cameras is `server_ip`, via `propagate_changes_to_cameras()` at `inframap/sites/customer/customer_model.py:969-988`:

```python
def propagate_changes_to_cameras(self):
    if (
        self.server_ip
        and self.__original_server_ip != self.server_ip
        and self.onboarding.propagate_site_host
    ):
        for camera in self.cameras.filter(is_deleted=False):
            if camera.ip != self.server_ip:
                camera.ip = self.server_ip
                camera.deployed = False
                camera.save()
```

Called from the `save()` override (line 944). `active` and `is_deleted` are NOT propagated to cameras here. **Customer.active flipping False does not turn off cameras.** This is why prod customer 40803 has `active=False` while its cameras stay active.

There IS a Customer pre_save signal at `inframap/sites/customer/customer_model.py:2212`:

```python
@receiver(pre_save, sender=Customer)
def on_change(sender, instance: Customer, **kwargs):
    if instance.id is not None:
        previous = Customer.objects.with_deleted().get(id=instance.id)
        if instance.active != previous.active and not instance.active:
            event.send_event("site_disabled", instance)
```

But it only broadcasts a `site_disabled` event for downstream consumers — no DB cascade. **This is the natural extension point for a new propagation hook** ("when active flips False, cascade to cameras").

### 2. `delete_immediate_group()` fires when `count(non-deleted customers) ≤ 1 AND not parent_account` ✓

`inframap/sites/customer/customer_model.py:1023-1030`:

```python
def delete_immediate_group(self):
    if (
        not self.group.parent_account
        and self.group.group_customer.filter(is_deleted=False).count() <= 1
    ):
        self.group.delete()
```

Confirms:
- Filter: `is_deleted=False` (only counts non-deleted customers; `active` is irrelevant)
- Threshold: `<= 1` (last or only)
- Excludes tenant root (`parent_account=True` groups never auto-delete)
- **Only one level up.** No recursion to grandparent.

Called at the end of `Customer.delete()` (line 1053), after soft_delete + cascade-to-cameras + event.

### 3. `AutoPatrolSchedule` has ZERO signal wiring ✓

`AutoPatrolSchedule.delete()` at `inframap/sites/autopatrol/autopatrol_schedule_model.py:391-394`:

```python
def delete(self, *args, **kwargs):
    self.soft_delete(save=True)
    self.undeploy()
```

No `pre_save` / `post_save` / `pre_delete` / `post_delete` receivers exist for `AutoPatrolSchedule`. (The `AutoPatrolSchedulePreset` model has signals at `inframap/camera/preset/auto_patrol_schedule_preset_model.py:43-44`, but that's a different model.)

**This means a "last-schedule-on-customer-deleted → cascade-disable customer" hook has to be added — it doesn't exist anywhere.** The natural location is a new `@receiver(post_delete, sender=AutoPatrolSchedule)` near the existing `delete()` method.

### 4. `is_deleted_event=True` on Camera suppresses **only** the post_save "all cameras inactive" warning ✓

Definition at `inframap/camera/camera_setup/camera_model.py:397-399`:

```python
is_deleted_event = (
    False  # flag to indicate change event was triggered by the site being deleted
)
```

Runtime-only attribute (NOT a model field, NOT in DB). Read site is the Camera `post_save` handler — when set, it skips the warning that would otherwise fire when the last camera under a site is disabled.

Set site is `Customer.delete()` at line 1036, before each camera's `delete()`:

```python
for camera in self.cameras.filter(is_deleted=False):
    camera.is_deleted_event = True
    camera.delete()
```

**Implication:** new propagation hooks that delete cameras should set `is_deleted_event=True` first to avoid a flood of "all cameras inactive" warnings. This is non-obvious and easy to forget.

### 5. `Contract` has ZERO cascade. ✓

`inframap/sites/autopatrol/contract_model.py:19-98`:

```python
class Contract(models.Model):
    customer = models.ManyToManyField(Customer, related_name="contracts", blank=True)
    contract_status = models.CharField(max_length=500, blank=True, null=True)
    tenant = models.ForeignKey(
        "Group", on_delete=models.SET_NULL, related_name="tenant_contracts",
    )
```

- No `save()` or `delete()` override
- No signal handlers
- M2M to Customer (deletion of Contract does NOT cascade)
- FK to Group is `SET_NULL` (deletion clears the link)

**A contract going `Cancelled` is a no-op for Group/Customer.** This is the data path behind the "tenant has both Cancelled + Active contracts and Group stays" pattern observed for the 2 EU bilateral cases.

### 6. Group hierarchy — `parent_account=True` marks tenant root, 2-level by convention, MPPT-arbitrary depth permitted ✓

`inframap/group/group_model.py:129`:

```python
parent_account = models.BooleanField(default=False, null=False)
```

Validation at `inframap/group/group_model.py:475-496`:

```python
@staticmethod
def top_parent_validation(data, instance=None):
    # ... only enforced for top groups (no parent)
    if "parent_account" in data and not data.get("parent_account"):
        raise ValidationError("Top parent group must be a parent account")
```

Top-level groups (no parent FK) **must** have `parent_account=True`. Subgroups can have `parent_account=False`. The Group model uses MPPT (`lft`/`rght`/`tree_id`), so arbitrary depth is permitted — but the design intent is 2-level: tenant root + child groups + customers.

`delete_immediate_group()` (above) honors this: it deletes the immediate parent only, never the tenant root.

### 7. Admin UI "Delete site" calls `Customer.delete()` — same path as `disable_tenant` ✓

`CustomerAdmin.delete_model()` (in `customer_view.py`) is the standard Django admin hook and dispatches to `Customer.delete()` at `customer_model.py:1032`. **No alternative cascade path.**

This means the §16 cascade endpoint and the admin UI's "Delete site" share the exact same code path. New propagation hooks added to `Customer.delete()` will be exercised from both surfaces — good for coverage, but also means cosmetic admin-UI deletes will trigger the same downstream behavior.

### 8. Existing signal wiring (where new hooks should live)

| Model | File:line | Signal | Behavior |
|---|---|---|---|
| `Customer` | `customer_model.py:2212` | `pre_save` | Fires `site_disabled` event when `active` flips True→False |
| `Camera` | `camera_setup/camera_model.py` | `pre_save` + `post_save` | Camera enable/disable events; gated by `is_deleted_event` |
| `Group` | `group_model.py` (~line 1000+) | `post_save` | Invalidates descendant cache (Redis) |
| `AutoPatrolSchedulePreset` | `auto_patrol_schedule_preset_model.py:43-44` | `post_save` + `post_delete` | Updates schedule cascade on preset changes |
| `AutoPatrolSchedule` | (none) | — | **No signals — propagation hook needed here** |
| `Contract` | (none) | — | **No signals — propagation hook needed here if contract status should cascade** |

**No central `signals.py`.** Handlers are inline in their respective model files using `@receiver`. New propagation receivers should be added in the same style and same file as the model they listen on.

## Where new propagation hooks should live (design implications)

Based on the signal-wiring inventory, the §16 follow-up propagation hooks naturally land as:

1. **"Last active schedule on customer deleted → cascade-disable customer"**
   - Add `@receiver(post_delete, sender=AutoPatrolSchedule)` in `autopatrol_schedule_model.py`
   - Body: `if not customer.autopatrolschedule_set.filter(is_deleted=False).exists(): customer.delete()`
   - Risk: `customer.delete()` cascades to cameras + group. Make sure schedule deletes from inside `customer.delete()` don't loop. The current `Customer.delete()` chain does NOT delete schedules (only cameras), so the loop risk is low — but verify.

2. **"Customer.active flips False → cascade-disable cameras"**
   - Extend the existing `pre_save` `on_change()` handler in `customer_model.py:2212`
   - Body: when `active` flips True→False, set `is_deleted_event=True` on each non-deleted camera and either `active=False` or `delete()` them (which path matches operator intent? — open design question)
   - Risk: this is asymmetric with the `restore()` path. Re-enabling a customer does NOT auto-revive cameras. Need to either also propagate restore() down OR document the asymmetry.

3. **"Contract status flips Cancelled → propagate to tenant"**
   - Add `@receiver(post_save, sender=Contract)` in `contract_model.py`
   - Body: query `Group.tenant_contracts.filter(contract_status='Active').exists()`. If False AND tenant Group exists, soft-delete the tenant. (Or: just mark tenant inactive somehow — there's no `active` on Group.)
   - This one is the murkiest because Group has no `active` field. Tenant-level disable currently goes through `Customer.delete()` per-customer in the §16 endpoint, not through Group. **Don't design a Contract→Group hook without first deciding what Group-level "inactive" even means.**

All three hooks should be feature-flagged (default off) for safe rollout, with the same gradual-enable pattern used by §16 (`TENANT_CASCADE_ENABLED`, `ONBOARDER_TENANT_LIFECYCLE_ENABLED`).

## Cross-references

- [[2026-04-28_tenant-status-sync-gap]] — original §16 design (cascade-disable)
- [[2026-04-29_immix-zombie-tenants]] — [[immix-vendor-api|Immix API]] contract violations causing some of the orphan-row class
- `actuate_admin/api/serializers/integrations/autopatrol/autopatrol_view.py` — `disable_tenant` and `reenable_tenant` action methods (the cascade endpoints)
- `actuate_admin/inframap/sites/customer/customer_model.py:875` — `Customer.restore()` partial-cascade logic
- `actuate_admin/inframap/sites/autopatrol/autopatrol_schedule_model.py:391-394` — schedule.delete() → undeploy()
- `actuate_admin/inframap/utils/soft_delete_manager.py` — the SoftDeleteMixin / SoftDeleteManager base classes
