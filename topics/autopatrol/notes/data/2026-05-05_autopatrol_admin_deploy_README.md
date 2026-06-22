---
title: "AutoPatrol admin-side deploy 2026-05-05 — incident tracking notes"
type: data
topic: autopatrol
tags: [autopatrol, admin, incident, sync, tracking]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
---

# 2026-05-05 — AutoPatrol admin-side deploy: tracking the side effects

## What happened

Around **16:04 UTC** an admin-side change went out that altered the
`/api/auto_patrol_contract/` POST handler. Before the change, every contract
POST from the onboarder Lambda was failing with:

    duplicate key value violates unique constraint
    "inframap_group_customer_name_15f2346e_uniq"
    DETAIL: Key (customer_name)=(auto_patrol) already exists.

i.e. all autopatrol contracts were being upserted into a single shared group
named `auto_patrol`. The DB had one row, the second contract POST failed,
nothing else got through. (1152 failures over 6h; failure rate was ~100% for
days. We have not bisected when it started.)

After the deploy, the handler now creates a **per-tenant** group whose
`customer_name` is derived from the tenant. The first run that hit the new
code path created **5 new tenant groups** and **~32 new sites** in admin.
That is the source of the Slack burst at 12:08 PM ET / 16:08 UTC.

Subsequent Lambda invocations are now failing with a **second** error:

    Cannot delete some instances of model 'Group' because they are
    referenced through protected foreign keys: 'Group.parent'.
    {connector-46733, connector-46734, ...}

Root cause: in `autopatrol_base_sync.get_object_with_deleted`, when looking
up the tenant group, multiple matches are found (the legacy singleton
`auto_patrol` group + the new per-tenant group). It calls
`get_best_candidate_and_delete_duplicates` which tries to delete the older
duplicate, but child `connector-XXXX` Groups have `parent=` pointing at it,
and `on_delete=PROTECT` raises before any delete happens.

**No data has been deleted.** Django raised before the DB operation.

## Files in this directory

- `2026-05-05_autopatrol_admin_deploy_groups_created.csv` — the 5 new groups
  + the user-already-exists conflict for each (5 users currently in 5 old
  groups that need to be re-associated to the new groups, per the team's
  manual workflow).
- `2026-05-05_autopatrol_admin_deploy_sites_created.csv` — the 32 sites
  that were created during the 14-min window when the deploy worked.

## Follow-ups (for the team to decide)

1. **Manual user re-association** — for each row in groups_created.csv,
   move the user from `existing_user_group_id` to `new_group_id`. This is the
   team's standard manual workflow when the onboarder creates a new group
   for an already-known user.

2. **Decide fate of the orphan `auto_patrol` singleton group(s)** — they
   still exist in admin DB (FK protection blocked delete). Either:
   - migrate the child `connector-XXXX` groups to point at the new
     per-tenant groups via SQL/mgmt-command, then the next Lambda run
     will delete the orphan cleanly, OR
   - change the dedup logic in `autopatrol_base_sync.py` so the legacy
     and new groups are not considered duplicates.

3. **File a bug** on [[actuate_admin]] for the FK delete failure — the new
   contract POST handler doesn't survive a re-run after first success.
   Right now the Lambda is firing every 5 min and getting 400s; the
   `auto_patrol/sync/` site-sync path is still working so sites/schedules
   are getting through, but the contract metadata POST is broken.

4. **Verify the coworker's site is now visible in admin** — should be
   under the appropriate `[5636X]` group above. (Original report:
   "site onboarded on immix, never hit admin" — almost certainly fixed
   by the 16:04 deploy.)

## Lambda status (as of generation)

- US `immix-autopatrol-onboarding`: **partially broken**. Site sync OK,
  schedule sync OK, contract POST 400ing on every call → contract metadata
  in admin is stale for all 18 contracts.
- EU `immix-autopatrol-onboarding`: **healthy**. 0 contract POST failures.
- Cleanup Lambda: not affected (uses different code path).
- Re-enable Lambda: not affected.

## Source data

The Slack messages this CSV was built from were posted to the channel
between 12:08 PM and 12:13 PM ET on 2026-05-05. The `connector-XXXX` IDs
that show up in the FK error message (34 distinct, ranging 46733..46766)
are the child site/customer groups that block the legacy `auto_patrol`
group delete.
