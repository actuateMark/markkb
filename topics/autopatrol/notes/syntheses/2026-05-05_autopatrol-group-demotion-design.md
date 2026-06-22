---
title: "Design: demote autopatrol-created groups to sub-groups (drop parent_account=True)"
type: synthesis
topic: autopatrol
tags: [autopatrol, admin, design, parent-account, group-hierarchy]
jira: "CS3-416"
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
incoming_updated: 2026-05-08
---

## TL;DR

After the [[2026-05-05_admin-deploy-customer-name-incident|2026-05-05 admin deploy]] created 5 redundant top-level customer-account groups (`[56365-56369]`), the chosen direction is: **stop creating autopatrol-flow groups as top-level customer accounts.** Autopatrol-created groups become regular sub-groups under the existing "Auto Patrol" holding group, not their own `parent_account=True` customer accounts. Ops manually promotes a sub-group out of "Auto Patrol" when it should be its own customer account. This matches the team's prior manual workflow (which has always treated existing customer accounts as canonical and viewed autopatrol groups as drop boxes).

## Decision (2026-05-05 PM)

This pivot **reverses the original [[CS3-416]] case-2c choice**, which created each autopatrol tenant as its own `parent_account=True` customer account. The email-based lookup fallback considered earlier is **deferred** in favor of this smaller change: just stop creating top-level customer accounts via autopatrol sync.

### Why the smaller fix

- The dupe groups were a symptom of the lookup not finding pre-existing customer accounts that have `tenant_id=NULL`. Fixing the lookup is complex (email fallback, `parent_account` ancestor walk, adoption logic). Demoting new groups to sub-groups sidesteps this entirely — autopatrol deposits new tenants in a holding bucket; ops sorts them out when needed.
- Operational cost of manual user re-association after every onboarding (the original case-2c assumption) turned out higher than initially estimated. Keeping new groups as sub-groups defers that work until/unless the customer is genuinely promoted to independent account status.

## Code changes

All in `actuate_admin/api/serializers/integrations/autopatrol/autopatrol_base_sync.py`:

### 1. `process_tenant_data` (≈ line 442)

- **Filter**: drop `"parent_account": True` from `filter_params`. New filter becomes `{"tenant_id": item.get("tenant_id")}` only — matches whatever Group exists for this `tenant_id`, regardless of where it sits in the tree (so manual ops promotions don't cause duplicate creation on next sync).
- **Defaults**: change `"parent_account": True` → `"parent_account": False`. New tenant groups become regular sub-groups under "Auto Patrol", not customer accounts.

### 2. (no change) `get_top_group` (≈ line 392)

The "Auto Patrol" holding group itself stays `parent_account=True` (it's still the top-level customer account that owns the bucket).

## Companion change: `list_patrol_group_ids` filter

In `actuate_admin/api/serializers/group/group_view.py:63`:

```python
def list_patrol_group_ids(self, qs):
    patrol_groups_ids = (
        qs.filter(tenant_id__isnull=False, parent_account=True)
        ...
    )
```

This classifies groups by type (`patrol` vs. `connector`). Dropping `parent_account=True` from autopatrol groups means **they'll no longer be classified as Patrol groups**, incorrectly falling into the "connector" category.

**Required change**: relax this filter to `qs.filter(tenant_id__isnull=False)` — remove the `parent_account=True` condition — since `tenant_id` is the autopatrol-specific marker. Not all `parent_account=True` groups are autopatrol, and not all autopatrol groups are top-level accounts anymore.

**Test impact**: existing fixtures in `api/tests/test_group_user.py:361` and `api/tests/test_tenant_filter.py` that create `parent_account=True, tenant_id=...` groups may need updating depending on what they're verifying.

## Cleanup management command

New file: `actuate_admin/inframap/management/commands/demote_autopatrol_dup_groups.py`

**Purpose**: idempotent command to flip the 5 duplicate groups created on 2026-05-05 from `parent_account=True` to `parent_account=False`.

**What it does**:
- Finds Groups matching the 2026-05-05 dupe pattern: name ends with " - Patrol", `parent_account=True`, `tenant_id` set, parent is the "Auto Patrol" top group, `id` in range `[56365-56369]` OR `created` timestamp on 2026-05-05.
- Dry-run (default): prints candidate groups with context (tenant_id, child site count).
- `--apply` mode: sets `parent_account=False`, saves each match.
- Idempotent — running twice has no effect.

**Sample output**:
```
Found 5 candidate groups:
  [56365] Rapid Response - Patrol (tenant_id=69e1fb38..., 1 site)
  [56366] Eyeforce - Patrol (tenant_id=7b533b5a..., 27 sites)
  [56367] TriCorps Security - Patrol (tenant_id=5dd01973..., 0 sites)
  [56368] Live Patrol - Patrol (tenant_id=74cf336c..., 5 sites)
  [56369] Vector Security - Patrol (tenant_id=f858b03b..., 1 site)

Run with --apply to demote to sub-groups.
```

**What this does NOT do**:
- Does not move sites onto pre-existing customer accounts — that's manual ops work (possibly batched with future auto-adoption logic).
- Does not reassociate users to new groups — manual ops work or deferred to future workflow.
- Does not soft-delete or hard-delete the groups — they continue to exist as sub-groups of "Auto Patrol".

## Test plan

Unit tests in `actuate_admin/api/tests/test_autopatrol_*.py`:

1. **`process_tenant_data` with pre-existing group**: `tenant_id=X` exists as `parent_account=False, parent=auto_patrol_top` → returns existing, no new group created.
2. **`process_tenant_data` with manually promoted group**: `tenant_id=X` exists as `parent_account=True, parent=other_account` (ops manually promoted it) → returns existing, no new group created.
3. **`process_tenant_data` with new tenant**: `tenant_id=X` does not exist → creates new with `parent_account=False, parent=auto_patrol_top`.
4. **`list_patrol_group_ids` filter**: autopatrol-created sub-group with `tenant_id` set is included in patrol-group results (not demoted to connector).
5. **Mgmt command**: dry-run identifies 5 dupes correctly; `--apply` flips all 5; idempotent on re-run.

## Rollout sequence

1. Create PR off `staging` with: (a) `autopatrol_base_sync.py` code change, (b) `group_view.py:63` filter fix, (c) new mgmt command + tests.
2. CI green; code review.
3. Merge to staging; smoke test with a test contract — verify sync creates a sub-group under "Auto Patrol", not a top-level customer account.
4. Merge staging → main (standard release train).
5. In prod: run mgmt command with `--apply` to demote the 5 dupes. Verify in admin UI that their `parent_account` field flips.
6. Run [[2026-04-23_release-acceptance-criteria|acceptance criteria check]] on the onboarder Lambda — contract POST 400 rate should drop to 0. Customer POST 409 (dedup) rates should drop near 0 (occasional edge cases from concurrent runs remain acceptable).

## Future work

### Email-based lookup fallback (deferred)

Restore the email-based user lookup logic to find pre-existing customer accounts by `user.contact_email → Group.parent_account=True` walk. This would enable full adoption of orphaned groups (those with `tenant_id` but `parent_account=False`) onto their canonical customer accounts without manual ops intervention. **Deferred**: ops can handle the 5 dupes for now; revisit if autopatrol tenant creation frequency increases.

### User re-association automation (deferred)

Currently, when a new group is created under "Auto Patrol" and users exist on the old customer account, the Lambda warns but leaves users on the old group (sites attach to the new group, users lag behind). A future workflow could auto-move users during sync. **Deferred**: ops handles this case-by-case; monitor frequency to justify automation.

### Alert threshold for user mismatch (consider)

Should the autopatrol Lambda's `process_user_registration` warning ("user X already related to group Y") become higher-signal (Slack alert, Jira ticket) now that the new design assumes "ops will manually promote"? Currently every such case generates a log line; surfacing a sample weekly could improve visibility. **Decide based on frequency post-demotion.**

## Backward compatibility

The `list_patrol_group_ids` filter change to drop `parent_account=True` is safe — all existing autopatrol groups have `tenant_id` set. Removing the `parent_account=True` condition will not shrink the result set for existing data.

## See also

- [[2026-05-05_admin-deploy-customer-name-incident]] — incident that prompted this design
- [[autopatrol-onboarder]] — Lambda entity (no changes needed)
- [[2026-04-17_stale-schedule-cleanup-design]] — original CS3-416 feature spec
- [[2026-04-23_release-acceptance-criteria]] — post-deploy verification rule
