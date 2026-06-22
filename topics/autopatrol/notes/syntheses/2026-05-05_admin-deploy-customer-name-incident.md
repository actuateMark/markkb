---
title: "AutoPatrol admin deploy: customer_name fix exposes lookup + dedup bugs (2026-05-05)"
type: synthesis
topic: autopatrol
tags: [autopatrol, admin, incident, sync, postmortem]
jira: ""
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-05_autopatrol-group-demotion-design.md
incoming_updated: 2026-05-08
---

## TL;DR

US `immix-autopatrol-onboarding` Lambda reported 100% contract POST failures for at least 7 days due to `customer_name=auto_patrol` unique-constraint collision in admin's `/auto_patrol_contract/` endpoint. Admin deployed a fix at ~16:04 UTC switching to per-tenant `customer_name`. The new flow created 5 redundant `parent_account=True` tenant groups (`[56365-56369]`) instead of reusing pre-existing groups for the same companies. Then a second admin-side bug surfaced: `ProtectedError` on dedup delete when child Groups reference the duplicate via `Group.parent` with `on_delete=PROTECT`. **No data has been deleted** — Django blocks the write before commit. The Lambda is correct throughout; both bugs are admin-side.

## Timeline (2026-05-05)

| Time | Event |
|------|-------|
| **~7+ days prior** | Every contract POST 400s with `duplicate key value violates unique constraint "inframap_group_customer_name_15f2346e_uniq"` for `customer_name=auto_patrol`. ~1152 failures in a 6h window. EU healthy throughout. |
| **~16:04 UTC** | Admin deploys fix switching per-tenant Group `customer_name` from `"auto_patrol"` to slugified value (e.g. `auto_patrol_rapid_response_-_patrol_<id>`). |
| **16:04–16:18 UTC** | Three Lambda runs succeed; 5 new `parent_account=True` groups (`[56365-56369]`) created + ~32 sites. Slack: "Created new tenant group" + "user X already related to group Y, not related to contract tenant Z" warnings. |
| **16:18+ UTC** | `Cannot delete some instances of model 'Group' because they are referenced through protected foreign keys: 'Group.parent'` from `get_best_candidate_and_delete_duplicates`. Child site Groups block delete. Lambda stops syncing contracts. |

## Root Cause: Two Admin-Side Bugs

### 1. Lookup misses pre-existing groups

In `process_tenant_data` (`api/serializers/integrations/autopatrol/autopatrol_base_sync.py`):

```python
Group.objects.filter(tenant_id=X, parent_account=True)
```

Pre-existing groups for the same companies have `tenant_id=NULL` because they pre-date autopatrol onboarding. Lookup misses → `get_object_with_deleted` falls through to creation → duplicate `parent_account=True` group exists alongside the original. Users stay associated with the old group; new sites attach to the new group → manual re-association required.

### 2. Dedup `.delete()` unprotected against `ProtectedError`

In `get_best_candidate_and_delete_duplicates` (same file), when `MultipleObjectsReturned` returns duplicates:

```python
duplicate.delete()  # ← no try/except
```

Child Groups reference the duplicate via `Group.parent` with `on_delete=PROTECT` (see `inframap/group/group_model.py`). Django raises `ProtectedError` before any DB write; the 400 propagates to the Lambda. The dedup helper has no error handling.

## Why CS3-416 doesn't cover this

[[2026-04-17_stale-schedule-cleanup-design|CS3-416 — Develop user and group creation workflow for AP/VCH]] explicitly addressed case 2c ("active user exists, linked to another group") with the decision: "link them to the new group automatically and proceed." That's current behavior — warn-only on user/group mismatch, sites attach to the new group. The 2026-05-05 incident exposed that manual re-association cost is higher than the design assumed. Decision pending on whether to reverse case-2c (reuse old group, don't create new) or stay with current design + automate user re-association.

## Lambda's role (none)

The Lambda surfaced admin errors correctly via log-and-continue HTTP handling. No Lambda-side code changes needed. Site sync (`/auto_patrol/sync/`) and schedule sync remain working — only contract metadata POST is blocked. EU Lambda completed all runs without error throughout.

## Outstanding work

- **Decision**: reverse case-2c (reuse old group when user exists) vs. keep current design + automate user re-association? Pending team alignment.
- **Code fix (paused)**: three-part fix in [[actuate_admin]] — (1) lookup fallback by `contact_email` → user's `parent_account=True` ancestor with `tenant_id` adoption, (2) `try/except ProtectedError` in `get_best_candidate_and_delete_duplicates`, (3) management command with `--apply` flag to merge 5 redundant groups onto pre-existing counterparts.
- **Manual ops cleanup**: 5 user-group re-associations + 5 redundant `[56365-56369]` groups to clean up in admin once the merge mgmt command lands.

## Tracking artifacts (KB data dir)

- [[2026-05-05_autopatrol_admin_deploy_groups_created]] — 5 new groups + user-already-exists conflicts (`topics/autopatrol/notes/data/2026-05-05_autopatrol_admin_deploy_groups_created.csv`)
- [[2026-05-05_autopatrol_admin_deploy_sites_created]] — 32 sites created in the 14-min good window (`topics/autopatrol/notes/data/2026-05-05_autopatrol_admin_deploy_sites_created.csv`)
- [[2026-05-05_autopatrol_admin_deploy_README]] — incident notes + follow-ups (`topics/autopatrol/notes/data/2026-05-05_autopatrol_admin_deploy_README.md`)

## See also

- [[autopatrol-onboarder]] — the Lambda entity
- [[2026-04-23_release-acceptance-criteria]] — the rule requiring post-deploy verification (admin team should retroactively run for 16:04 deploy)
- [[2026-04-23_postmortem-onboarder-healthcheck]] — prior incident that motivated acceptance criteria
