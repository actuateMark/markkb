---
title: "Handoff — Admin-side state propagation + DB patch + data model deep dive"
type: concept
topic: personal-notes
tags: [handoff, admin-api, autopatrol, cascade, data-model, propagation, planning, multi-pr, immix, immix, immix, immix, immix, immix, immix, immix, immix, immix]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/autopatrol/notes/syntheses/2026-05-01_silent-cameras-diagnosis.md
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

# Handoff — Admin-side state propagation + DB patch + data model deep dive

> **Purpose:** kick off a planning session in a new conversation. This doc has enough context for the next session to understand WHERE we are after today's cascade rollout, WHAT the user surfaced as the next problem class, and WHAT a planning session needs to produce.

## TL;DR

Today (2026-04-30) we shipped the §16 cascade-disable + cascade-reenable infrastructure end-to-end:
- `actuate_admin` PR #2376/#2384 — `disable_tenant` + `reenable_tenant` endpoints in prod
- `autopatrol_onboarder` PR #11/#13 — onboarder lifecycle pass that calls those endpoints organically every 5 min
- Live-fired test: RSS (12+12) + Legacy (74+73) successfully cascaded

The user then surfaced **a different gap** that today's work doesn't address: the admin DB has rows with intricate state mismatches that the cleanup pipeline can't reach because they predate our cascade infrastructure. **They asked us to plan, not implement, in this session.**

The next session needs to design and ship:
1. **Admin-side state-propagation hooks** — when schedules under a customer all go away, the customer (and its cameras/site) should follow. When a customer goes inactive, the cameras should follow.
2. **One-time admin DB patch** (`manage.py reconcile_autopatrol_state`) for the existing left-behind rows.
3. **A deep-dive doc on the admin autopatrol data model** — too sticky to design without it.

A seed of (3) is at [[2026-04-30_data-model-cascade-semantics]] — start there.

## Where we got to today (the rollout that shipped)

**Three PRs merged + deployed to prod:**

| Repo | PR | Commit | What it does |
|---|---|---|---|
| [[actuate_admin]] | [#2376](https://github.com/aegissystems/actuate_admin/pull/2376) → [#2377](https://github.com/aegissystems/actuate_admin/pull/2377) v2.7.1 | merged 2026-04-29 | `PATCH /api/auto_patrol/disable_tenant/` — soft-deletes all schedules + customers under a tenant_id |
| [[actuate_admin]] | [#2384](https://github.com/aegissystems/actuate_admin/pull/2384) → [#2385](https://github.com/aegissystems/actuate_admin/pull/2385) v2.7.2 | merged 2026-04-30 | `PATCH /api/auto_patrol/reenable_tenant/` — sister endpoint with `valid_site_ids` whitelist; only revives rows Immix still acknowledges |
| autopatrol_onboarder | [#10](https://github.com/aegissystems/autopatrol_onboarder/pull/10) | 2026-04-29 | Cleanup Lambda's reactive cascade trigger (gated on connector emits + DDB threshold ≥ 2) |
| autopatrol_onboarder | [#11](https://github.com/aegissystems/autopatrol_onboarder/pull/11) | 2026-04-30 | Onboarder Lambda's PROACTIVE lifecycle pass — every 5 min poll grouped by `tenantStatus` → cascade Suspended/Removed, reenable Active |
| autopatrol_onboarder | [#12](https://github.com/aegissystems/autopatrol_onboarder/pull/12) | 2026-04-30 | PHASE diagnostic logs + try/except around lifecycle pass |
| autopatrol_onboarder | [#13](https://github.com/aegissystems/autopatrol_onboarder/pull/13) | 2026-04-30 | Logging fix: removed runtime's root handler so INFO logs actually emit (root cause of the silent-log mystery) |

**Two Lambda env flags flipped on prod:**
- `TENANT_CASCADE_ENABLED=true` on `immix-autopatrol-schedule-cleanup` (cleanup Lambda's reactive cascade)
- `ONBOARDER_TENANT_LIFECYCLE_ENABLED=true` on `immix-autopatrol-onboarding` US + EU (onboarder's proactive lifecycle pass)

**Confirmed firing:**
- RSS (`0ee7cb3f-...`) cascaded 14:55Z via cleanup-Lambda manual SQS test → 12 schedules + 12 customers soft-deleted
- Legacy (`ac399cd6-...`) cascaded 16:05Z–19:01Z somewhere (organically, by onboarder lifecycle pass) → 74 schedules + 73 customers soft-deleted
- The "silent log" issue (PR #13) had been hiding the lifecycle pass's success messages all along — the pass HAS been firing, we just couldn't see it

## The new gap the user surfaced (this is what the planning session is for)

User flagged 3 prod customers in inconsistent states that today's cascade infrastructure does NOT address:

| Customer | URL | Symptom | Why our cascade can't reach it |
|---|---|---|---|
| pk=40803 | https://admin.actuateui.net/inframap/customer/40803/change/ | `active=False` but cameras still active | Customer was deactivated through some non-cascade path. Cameras don't follow `active`. |
| pk=39221 | https://admin.actuateui.net/inframap/autopatrolschedule/?customer__id__exact=39221 | All schedules deleted on Immix side, but admin shows 4 orphan rows + cameras + site still active | Schedules have `schedule_id=None` (no Immix ID) — orphans from before our cascade infra. Cleanup Lambda's per-schedule path keys on `schedule_id` so it can't query Immix. |
| pk=41260 | https://admin.actuateui.net/inframap/customer/41260/change/ | `active=True` but no patrols | Same orphan-schedule pattern — `schedule_id=None`, no provenance |

**Common thread:** the admin DB has no automatic propagation:
- Schedule.delete() does NOT cascade UP to customer/site
- Customer.active=False does NOT cascade DOWN to cameras
- Customer.restore() does NOT cascade DOWN to revive cameras (asymmetric with Customer.delete() which DOES cascade-delete cameras)

**User's exact words:**
> "we probably need to adjust our admin side to do things like 'check if all schedules are now deleted and propagate that change up and down'"
> "for these ones that were left behind we'll need to do a one-time patch on the DB to get everything set up and synced"
> "Make sure to keep and add to the admin topic about the data model in it and interacting with the data model. It's very intricate and tricky and sticky and we probably need a separate deep dive."

## Three deliverables for the planning session

### 1. Admin-side state-propagation hooks (PR-shaped)

**Design questions to resolve:**
- Hook on `AutoPatrolSchedule.save()` post-save signal? Django signal? Custom save method?
- When a schedule's `is_deleted` flips True, check: are there any other active schedules under this customer? If no → soft-delete the customer (which already cascades to cameras + group via existing `Customer.delete()` chain). If yes → no-op.
- Mirror on `Customer.save()`: when `active` flips False, propagate to cameras (set `is_deleted_event=True`?). Or is there a different field that's the right axis?
- What about schedules that come back to life (Awaiting → Active)? Should the customer auto-revive? Probably not — let the onboarder's sync drive that.
- **Critical:** must NOT introduce infinite recursion. If `customer.delete()` already cascades to schedule deletes, those schedules saving must not re-trigger a customer.delete() loop.
- Bound the new logic with a feature flag (default off) for safe rollout.

**Suggested approach:**
- Django post_delete signal on AutoPatrolSchedule that checks `customer.autopatrolschedule_set.filter(is_deleted=False).count() == 0` → cascade-disable customer.
- Use the same `disabled_by` marker convention as the §16 cascade (`auto_propagation_last_schedule_deleted` or similar) so the reenable filter `LIKE 'immix_tenant_%'` doesn't accidentally revive these.
- Tests parallel to test_autopatrol_disable_tenant.py / test_autopatrol_reenable_tenant.py — covering "last active schedule deletion → customer cascades", "non-last schedule deletion → no-op", isolation between customers, idempotency.

**Risk:** the existing data model's interactions are complex enough (per [[2026-04-30_data-model-cascade-semantics]]) that the planning session should NOT design hooks without first reading that note + doing the deep dive. Hooks fired without understanding the full cascade chain WILL cause regressions.

### 2. One-time admin DB patch (`manage.py reconcile_autopatrol_state`)

**Design questions to resolve:**
- Filter strategy: which rows are "left behind"? Candidates:
  - Customers with `active=False AND is_deleted=False` (40803-style)
  - Customers with `active=True AND no active schedules under them` (39221-style)
  - Schedules with `schedule_id=None` (orphans)
  - Customers under tenants absent from Immix `/Contracts` (zombie tenants from [[2026-04-29_immix-zombie-tenants]])
- Action policy per filter: blanket cascade-disable? Per-customer Immix verification? Manual review required?
- Dry-run output format — what should the operator see before applying?
- Idempotency — running it twice should be safe.
- Rollback path — if a customer was incorrectly cascade-disabled, the §16 reenable_tenant endpoint can restore (with `valid_site_ids` whitelist).

**Suggested approach:**
- `python manage.py reconcile_autopatrol_state --dry-run --check=all` — runs all checkers, reports what WOULD change
- `--check=all` flag to enumerate all checkers; `--check=orphan_schedules` etc. for targeted runs
- `--apply` flag (vs `--dry-run`) to commit changes
- Each check tagged with a `disabled_by` marker that's distinct from cascade markers (e.g., `db_reconcile_orphan_schedule`, `db_reconcile_inactive_customer_propagation`)

**Pre-step:** run an audit query to size the population. How many 40803-style? 39221-style? 41260-style? Without numbers we can't even prioritize which checker to build first.

### 3. Admin data model deep-dive doc (KB)

**Seed already exists** at [[2026-04-30_data-model-cascade-semantics]]. The seed covers what we learned through the §16 work — but only the surface. Open questions listed at the bottom of that note:
- How does `Customer.save()` interact with cameras?
- `delete_immediate_group()` exact firing condition (≤1 vs ==1)
- AutoPatrolSchedule.delete() signals
- `is_deleted_event=True` semantics on Camera
- Contract ↔ Group interaction (esp. multi-contract tenants like the 2 EU `Cancelled/Active` cases)
- Group hierarchy depth + topology
- The canonical entry point the admin UI's "Delete site" action calls

**The deep-dive should be required reading for any subsequent admin-side cascade work.** Without it, hook designs will keep hitting "wait, what about X?" surprises.

## State of the cleanup pipeline (for context)

- **Cleanup Lambda** (US prod, eu-west-1 future) — `immix-autopatrol-schedule-cleanup`:
  - `CLEANUP_ENABLED=true`, `TENANT_CASCADE_ENABLED=true`, `CLEANUP_TARGET_HOURS=18`
  - Reactive: only fires on connector `no_patrols` SQS emits
  - Limitation surfaced 2026-04-30: doesn't catch already-Suspended tenants (their connectors are quiescent → no emits → no trigger)
- **Onboarder Lambda** (US + EU) — `immix-autopatrol-onboarding`:
  - `ONBOARDER_TENANT_LIFECYCLE_ENABLED=true` (US + EU)
  - Proactive: every 5 min, polls Immix `/Contracts`, calls `disable_tenant`/`reenable_tenant`
  - Closes the "already-Suspended" gap
- **Reenable Lambda** (US prod) — `immix-autopatrol-schedule-reenable`:
  - IAM-auth Function URL for individual schedule reenables (older mechanism)
  - Tenant-level reenable now goes through the new admin endpoint instead

**EU admin endpoint:** `auto_patrol/reenable_tenant/` is live on `admin.actuateui.eu` after PR #2384/#2385 merged to main (deploy auto-fans to both regions per EMISC-22 EU CD pipeline).

## Outstanding items still in mark-todos that touch this

- §16 sub-step "Step 6 — harden disable_tenant permission_classes" (post-#2377 follow-up). Same hardening should apply to `reenable_tenant`. Currently both endpoints inherit default auth (any authenticated session can hit them — same posture as `sync_site` so not a regression but worth tightening).
- `connector-11202` 26k-error/24h spike — separate workstream, not tied to this
- `connector-14170` regressed OOM offender — promotion target decision (new fleet memory-limit-drift workstream)
- Comprehensive Immix tenant-failure census — expand [[2026-04-29_immix-zombie-tenants]] into external-audience report

## Key references for the planning session

- [[2026-04-30_data-model-cascade-semantics]] — **READ FIRST** — the seed of the deep-dive (expanded 2026-04-30 with verified findings + signal-wiring inventory)
- [[2026-04-30_autopatrol-state-audit]] — Django shell snippets to size cohorts A/B/C/D/E (run before designing hooks/patch)
- [[2026-04-28_tenant-status-sync-gap]] — original §16 design (cascade-disable)
- [[2026-04-29_immix-zombie-tenants]] — [[immix-vendor-api|Immix API]] contract violations (some of the orphan-row class)
- [[2026-04-29_cleanup-handoff]] — yesterday's handoff doc (origin of today's work)
- `actuate_admin/api/serializers/integrations/autopatrol/autopatrol_view.py` — `disable_tenant` + `reenable_tenant` action methods (the cascade endpoints)
- `actuate_admin/inframap/sites/customer/customer_model.py:875` — `Customer.restore()` partial-cascade
- `actuate_admin/inframap/sites/autopatrol/autopatrol_schedule_model.py:391-394` — `schedule.delete()` → undeploy()
- `actuate_admin/inframap/utils/soft_delete_manager.py` — SoftDeleteMixin / SoftDeleteManager base classes

## Suggested order for the planning session

1. Read [[2026-04-30_data-model-cascade-semantics]] (15 min)
2. Open the 3 admin URLs the user shared and use the admin UI to explore the actual state (10 min) — this is the quickest way to ground the design in real data
3. Run an audit query to size the affected population (the DB patch's pre-step) — 30 min, gives concrete numbers before designing
4. Sketch the propagation-hook design as an ADR (90 min) — Django signal vs save method, infinite-recursion guard, feature flag
5. Sketch the DB patch as a management-command spec (30 min) — checker interface, dry-run output format, audit trail
6. Spike the deep-dive doc — fill in the open questions from the seed (ongoing)

## What this session DID NOT do

- Did NOT implement any of the propagation hooks
- Did NOT write the `manage.py reconcile_autopatrol_state` command
- Did NOT do the deep-dive expansion — only seeded it
- Did NOT investigate the 3 customers further than confirming their state mismatches

That's all on the planning session's plate. This handoff is the bootstrap.
