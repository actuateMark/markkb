---
title: "Billing Deferred Backlog"
type: entity
topic: billing
tags: [billing, backlog, deferred, mark, work-plan]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-27
---

# Billing Deferred Backlog

Work items related to billing reconciliation, cohort-F-style drift, and post-mortem follow-ups that have been **deferred** from active scope. Items live here when:

- a signal flags a trajectory that needs passive watching rather than immediate work
- the work is downstream of a Snowflake / data-team handoff (out-of-team-scope)
- decision is pending until a re-open trigger fires

Active billing work — anything still moving — stays in [[mark-todos]] under its own §N. This file holds the "decided to [[watch-entity|watch]]" tail. Promote back into mark-todos when a re-open trigger fires.

> Companion to: [[2026-05-11_billing-pain-post-mortem]] (root context), [[mark-todos]] (Mark's active workstreams), [[autopatrol-deferred-backlog]] (sibling backlog).

## Index

| Item | Source §N | Status | Decision Owner | Decision Trigger |
|------|-----------|--------|----------------|------------------|
| [billing_production_unbilled_cams trajectory watch](#billing_production_unbilled_cams-trajectory-watch) | dashboard signal investigation 2026-05-19 | [[watch-entity|Watch]] | Mark | Value >2,800 next week, OR `billing_reconcile_residual` goes non-zero |

---

## billing_production_unbilled_cams trajectory watch

Surfaced 2026-05-19 while root-causing the `billing_production_unbilled_cams=2331` RED signal that previously hid under `error` (sink renderer + missing dispatcher, both fixed 2026-05-19). Signal designed to catch the Cohort F missing-subscription class: production cameras (not trial/internal) running billable products but NOT in `usage_monthly`.

**Today's value:** 2,331 cams / 8,637,569 hours from `~/.local/state/minipc-tasks/billing/reconciliation-2026-05.json`. Signal's authored May 2026 baseline: 2,024 cams. **+307 cams (+15%) above baseline.** Reconciliation residual=0, balanced=true — so this is *accrued historical inventory*, not a new counting drift.

**Why deferred:**
- 2026-05-07 decision: NO BACKFILL for Cohort B; same logic applies to F's accrued residual ([[2026-05-07_cohort-b-no-backfill-decision]]).
- Connector emit fixes (PR #1675, #1680, #1682, #1688) are forward-only; the existing residual is by design.
- Data-team handoff (Snowflake F6/F5 ingestion gap) complete on our side per [[2026-05-11_billing-pain-post-mortem]].
- 15% drift in a week could be (a) normal accrual as new cameras hit production without subscription metadata, or (b) a regression in one of the forward-only emit paths. Distinguishing requires another week of data.

**Open work (when revived):**
- Pull `billing_production_unbilled_cams` weekly snapshots from the dashboard sink (Saturdays preferred — same reconcile cron run cadence)
- If trajectory plateaus near 2,300-2,400 over 3 consecutive weeks: confirmed as accrual; downgrade the signal threshold or accept as steady-state.
- If trajectory continues to climb monotonically: regression hunt — diff the daily reconciliation JSON week-over-week to find which customer/integration class is growing.
- Cross-check against the connector emit fix coverage: if a specific integration class (CHM/VCH/AP) accounts for the growth, that's an emit-path bug.

**Re-open trigger:**
- `billing_production_unbilled_cams` exceeds 2,800 next week (would imply +20% week-over-week, i.e. ongoing accretion not stabilization)
- `billing_reconcile_residual` goes non-zero (new counting drift surfaces a real bug)
- A customer-facing complaint about under-billing or over-billing

**Resources:**
- Daily reconciliation JSON: `~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM.json`
- `billing-reconcile-check.timer` on Firebat — daily cron that writes the JSON
- [[2026-05-11_billing-pain-post-mortem]] — full root-cause context
- [[2026-05-06_cohort-f-investigation]] — cohort-F reframe
- [[2026-05-07_cohort-b-no-backfill-decision]] — backfill-decision ADR (same logic)
- Signal definition: `~/.claude/skills/dashboard-check/config/signals.json` — `billing_production_unbilled_cams`

---

## Discipline

- **Don't accumulate.** Every entry should have a clear "decision trigger" so it doesn't rot. If an entry has been here >60 days without a trigger move, sweep it to a closed-with-reason archive or fold into the parent topic synthesis.
- **Promote back to mark-todos** when the trigger fires — don't half-resurrect items in this file.
- **Cross-link with [[mark-todos]] §N** when an item is mid-flight. The active surface is mark-todos; this file is the parking lot.

## Related

- [[mark-todos]] — Mark's active workstreams
- [[autopatrol-deferred-backlog]] — sibling backlog (autopatrol scope)
- [[2026-05-11_billing-pain-post-mortem]] — root-cause context
- [[billing-events-catalog]] — billing-event entity
- [[snowflake-billing-tables]] — Snowflake-side entity (data-team-owned)
