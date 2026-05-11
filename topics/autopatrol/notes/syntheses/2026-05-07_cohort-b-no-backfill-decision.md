---
title: "ADR: Cohort B — no backfill, cascade hook stays disabled"
type: synthesis
topic: autopatrol
tags: [autopatrol, cohort-b, adr, decision, deferred, billing]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
workstreams: ["§25"]
outgoing:
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming:
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cleanup-lambda-state-matrix-verify.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

# ADR: Cohort B — no backfill, cascade hook stays disabled

## Decision

**Do not backfill the 31 customers / 353 cameras in Cohort B.** The cleanup-Lambda-disabled schedules will remain admin-disabled with cameras left `active=True`. The cascade hook (`actuate_admin#2406`) stays merged but flag-gated `AUTOPATROL_SCHEDULE_CASCADE_ENABLED=False` in prod.

This closes §25 in [[mark-todos]]; the workstream is archived to today's daily note ([[2026-05-07]]) and tracked in the [[autopatrol-deferred-backlog]] under "decided / re-open conditions".

## Context

Cohort B was identified during the [[2026-05-01_silent-cameras-diagnosis|2026-05-01 silent-cameras audit]]: customers whose AutoPatrol schedules had ALL been cleanup-Lambda-disabled (because Immix said the schedules were gone), but whose admin DB still had `Camera` rows with `is_deleted=False`. By the [[2026-05-04_silent-camera-diagnosis|2026-05-04 audit]] this resolved to **31 customers / 353 cameras**.

The root cause is structural: the cleanup-Lambda hits `disable_schedule` on AutoPatrolSchedule rows but there's no Customer-level cascade hook in admin, so cameras stay active even after their parent customer's only AP schedule is disabled. [[2026-05-04_admin-schedule-cascade-design]] designed the cascade hook as a `post_save`/`post_delete` signal handler. [[actuate_admin#2406|actuate_admin#2406]] (Tatiana's hotfix bundle) merged the hook to `main` 2026-05-06T13:40Z, wired behind `AUTOPATROL_SCHEDULE_CASCADE_ENABLED` flag default `False`. PR #2405 (Mark's standalone version) became redundant.

The hook only catches **new** schedule transitions; the existing 31-customer / 353-camera Cohort B population needed a one-time `customer.delete()` sweep — runbook at [[2026-05-05_cohort-b-backfill-runbook]] (DRY-RUN + APPLY + verify + rollback). That backfill was the seeded REQUIRED morning-followup for 2026-05-07.

## Forces

- **Customer impact of backfill:** `Customer.delete()` cascades to all of that customer's `Camera` rows + tears down EKS deployment + emits `site_deleted` events. For all 31 customers, this would mean ~353 cameras going dark on the customer's admin UI; if any of those customers were intentionally configured for non-AutoPatrol products or had been re-configured outside the AutoPatrol-only audit lens, we'd silently turn them off.
- **Customer impact of leaving them:** No customer-facing alert traffic from cameras that were already silent for ~weeks-months. The cameras consume admin DB rows + small EKS cluster overhead but no inference compute (their schedules are cleanup-Lambda-disabled). Cost is minimal. They can't accidentally fire alerts because there's no schedule connecting them to inference.
- **Reversibility asymmetry:** A backfill is hard to reverse — `customer.delete()` cascades, and reviving 31 customers later would require a careful per-customer audit. Leaving them is trivially reversible — flip the flag and run the backfill if a problem surfaces.
- **Discovery confidence:** The cohort was identified from a Snowflake-vs-admin diff. The diff is correct as of its snapshot (2026-05-04) but the underlying classification of "gone on Immix" relied on cleanup-Lambda's prior DDB activity. We have high confidence these schedules really are gone on Immix, but lower confidence that the **customers** want the cameras gone — they may be in a "soft pause" state (intentional teardown delay, billing cycle alignment, partner-driven pause).
- **Pattern across cohorts:** The same pattern likely exists for Cohorts that haven't been classified yet. Backfilling Cohort B alone doesn't generalize; the better long-term answer is the propagation hooks ADR (in [[autopatrol-deferred-backlog]]), which is admin-team scope and not on Mark's plate.

## Considered

1. **Backfill all 31 (the runbook's APPLY path).** Clean state but high blast-radius. The cascade hook's flag-flip is then trivial because Cohort B is empty.
2. **Backfill a sub-set after manual customer-by-customer review.** Lower risk per row but ~31 admin UI sweeps + customer outreach. Doesn't scale; turns "audit hygiene" into "operations work".
3. **Defer indefinitely; leave the cascade hook flag-disabled.** Zero customer impact today. Cohort B sits as-is. Re-evaluate if the population grows or a customer asks why cameras show as active.
4. **Build the propagation hooks first (admin-team scope), then revisit.** Right long-term answer but multi-week effort with multiple stakeholders. Doesn't solve Cohort B today; addresses the structural class of which Cohort B is one instance.

## Choice

**Option 3 — defer indefinitely.** Cohort B stays as-is; the cascade hook remains shipped but flag-disabled.

This is consistent with the broader stance taken 2026-05-06: **deactivate nothing this week**. Customer-state changes have been the source of multiple incidents (the customer_name unique-constraint collision, the propagation gaps, the §16 cascade-on-suspended detection problem) and the right response is to slow down and let the propagation-hooks design land before any mass-mutation pass.

## Re-open conditions

Promote §25 back into [[mark-todos]] as an active workstream if any of the following becomes true:

1. **Population grows materially** — Cohort B reaches >50 customers or >500 cameras at the next audit (run [[autopatrol_onboarder|diagnose_silent_cameras.py]] periodically). The current size is small enough to ignore; growth implies a regression somewhere upstream.
2. **Customer-facing complaint** — a customer or partner notices that their admin UI shows cameras as active for a deletion they intended.
3. **Storage / cost pressure** from accumulated orphan camera state in admin DB.
4. **Propagation hooks ADR lands** (admin-team scope, see [[autopatrol-deferred-backlog]]) — at that point we can re-evaluate Cohort B in light of cleaner semantics.

## Consequences

- The cascade hook's first-fire moment shifts indefinitely. No regression risk since flag default is `False`.
- The backfill runbook ([[2026-05-05_cohort-b-backfill-runbook]]) stays alive in KB but is not on the active path; mark it "ready to run if reactivated" but don't execute.
- Mark-todos drops the §25 active section and the seeded morning-followup item.
- §26 Cohort F deactivate paths (e.g. F3a 9 cids / 102 cams Immix-Deleted) inherit this same posture — no deactivation pending team alignment.
- The `actuate_admin#2408` mgmt command (`deactivate_customers_by_cids`) sits drafted-but-not-merged. It's the same primitive that would back the backfill if the decision flips. Leave the PR open as a known-good capability.

## Resources

- [[autopatrol-deferred-backlog]] — parent backlog
- [[mark-todos]] — active workstream tracker (§25 archive entry there)
- [[2026-05-04_silent-camera-diagnosis]] — audit data
- [[2026-05-04_admin-schedule-cascade-design]] — hook design
- [[2026-05-05_cohort-b-backfill-runbook]] — DRY-RUN + APPLY procedure
- [actuate_admin#2406](https://github.com/aegissystems/actuate_admin/pull/2406) — merged hotfix (cascade hook flag-gated)
- [actuate_admin#2405](https://github.com/aegissystems/actuate_admin/pull/2405) — Mark's standalone PR; should be closed as redundant
- [actuate_admin#2408](https://github.com/aegissystems/actuate_admin/pull/2408) — `deactivate_customers_by_cids` mgmt command (drafted, paused)

## Related

- [[2026-05-01_silent-cameras-diagnosis]] — cohort scheme
- [[2026-05-06_cohort-f-investigation]] — Cohort F reframe (analogous "do nothing yet" stance)
- [[autopatrol-cleanup-lambda]] — cleanup-Lambda entity
