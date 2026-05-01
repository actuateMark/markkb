---
title: "AutoPatrol Sync Endpoint: Create/Update Only, No Deletions"
type: concept
topic: autopatrol
tags: [autopatrol, admin-api, sync, deletion-safety, dead-code]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# AutoPatrol Sync Endpoint: Create/Update Only, No Deletions

The `/api/auto_patrol/sync/` endpoint on the admin API **creates and updates sites but never deletes them**. This is a critical asymmetry for planning stale-schedule cleanup.

## What the endpoint does

**File:** `actuate_admin/api/serializers/integrations/autopatrol/autopatrol_sync.py`

The sync serializer processes two inputs:
- **Sites** (`autopatrol_sync.py:148-155`) — calls `get_object_with_deleted(model=Customer, filter_params={"group": site_group, "immix_site_id": ...})`. Sites in admin are `Customer` rows keyed by `immix_site_id` — this is the **only** code path that creates them. Also sets up CHM, relates site to contract (`contract.customer.add(site)` at line 171).
- **Devices** (`process_devices_data()` at `:198-236`) — creates/updates camera rows under each site.

Neither POST `/api/auto_patrol_contract/` (creates contracts/users only) nor POST `/api/auto_patrol_schedule/` (fails without a pre-existing site — `autopatrol_schedule_sync.py:223-226`) creates sites. If you remove the sync call, new sites don't get onboarded.

**The endpoint never calls deletion logic.** There are three cleanup methods defined — `cleanup_sites()`, `cleanup_cameras()`, `cleanup_old_sites()` (`autopatrol_sync.py:237,248,276`) — but grep confirms **zero callers** anywhere in `actuate_admin`. Dead code.

## The misleading `allow_deletion` flag

The onboarder Lambda's `fix/handle-deleted-sites` branch added an `allow_deletion` field to the sync payload. Admin-side grep confirms: **this field is never read anywhere**. It's a no-op payload field that the serializer ignores.

This flag was added defensively on the assumption that the sync endpoint was a deletion path. It isn't.

## Why this matters

**Future readers and planners will assume the safety flag works.** When designing per-schedule cleanup logic, you must not rely on the admin sync endpoint for deletions. The actual deletion path is:

1. Cleanup Lambda detects a stale schedule via SQS emit + counter threshold
2. Cleanup Lambda confirms via Immix API that the schedule is gone
3. Cleanup Lambda directly PATCHes the schedule on admin (`is_deleted=True`)

See [[2026-04-17_stale-schedule-cleanup-design]] for the full architecture.

## Related

- [[autopatrol-onboarder]] — the Lambda that calls sync (deletion safety section updated)
- [[2026-04-17_stale-schedule-cleanup-design]] — the actual cleanup path
