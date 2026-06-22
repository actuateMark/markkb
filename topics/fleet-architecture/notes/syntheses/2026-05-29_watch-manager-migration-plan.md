---
title: Watch Manager Migration Plan — Cutover from Django-Q Constellation
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, manager-service, migration, cutover, shadow-mode]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
  - "[[2026-05-29_watch-manager-failure-modes]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-failure-modes.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
incoming_updated: 2026-05-30
---

# Watch Manager Migration Plan — Cutover from Django-Q Constellation

## Why this note exists

The May 28 master design said "we're rewriting from scratch" and explicitly cut the migration question from the briefing's decisions list. That answer is correct in *scope* (clean [[watchman-repo|Watchman]] model, not patching Django-Q) but **not in implementation strategy** — we still have live customer schedules running on the existing constellation that must keep working through the cutover. This note covers how the new manager service goes live without dropping arms.

## Scope of the cutover

What gets replaced:
- `actuate_admin` Django-Q chain (`schedule_processor.py`, `override_timer.py`, `schedule_deployer.py`)
- `ConnectorController.start/stop/reboot_connector` HTTP path
- `connector_deployer` is **kept** as the K8s actuator (manager calls into it for the first phase; manager talks K8s directly later)
- Per-pod schedule evaluation inside `vms-connector`
- VCH + AP CronJob owners (`Healthcheck.handle_healthcheck_cronjob`, `AutoPatrolSchedule.deploy/undeploy`)

What stays untouched:
- The existing `ScheduleV2` / `FlexSchedule` / `Calendar` tables — they remain the admin-side authoring surface during transition; the manager reads from them. Eventually they get replaced by `Watch` / `CalendarSet` / `ManualOverride` tables, but not on day one.
- `connector_deployer` API (`POST /start /stop /reboot /chm /delete`) — manager becomes its only client; deployer otherwise unchanged.
- Customer onboarding flow in admin UI.

## Five-phase cutover

### Phase M1 — Shadow read (no mutations)

- Deploy the manager as a continuous daemon in the cluster.
- Manager reads `ScheduleV2` + `FlexSchedule` + `Calendar` + `Customer.timezone` + Redis `MotionStatus.manual_start/_stop` on its own tick (30–60s).
- Manager evaluates desired armed-state per [[watch-entity|Watch]] (Watches are derived in-manager from `(customer, product)` projection over `FlexSchedule.product` M2M).
- Manager **does not** call `connector_deployer`. It logs desired-state deltas vs. observed K8s state.
- **Observability gate:** manager's desired-state must match the existing Django-Q chain's actual K8s mutations within ±60s (one tick), measured by audit-log diff for ≥7 days across all customers.

Exit criterion: ≥99.9% agreement over 7d × 100% of active customers. Disagreements investigated and resolved before M2.

### Phase M2 — Dual-write (manager + Django-Q both mutate)

- Manager begins issuing K8s mutations (via `connector_deployer`) **with an idempotency key**. Django-Q chain continues issuing its own mutations.
- `connector_deployer` is patched to dedupe by `(deployment_id, idempotency_key, observed_generation)` — second mutation in a 60s window is a no-op.
- Manager's reconcile loop catches anything Django-Q misses; Django-Q catches anything manager misses. Belt-and-suspenders.
- Audit log shows which writer initiated each mutation.
- **Observability gate:** every K8s mutation must show one writer of record (no double-writes that aren't deduped); SLO breaches investigated.

Exit criterion: ≥7 days clean dual-write at 100% of active customers, with ≥99% of mutations initiated by manager (Django-Q catches only marginal cases).

### Phase M3 — Manager-primary, Django-Q failover only

- Django-Q chain switched to a 5-minute lag tick (manager runs at 30–60s).
- Manager owns all mutations; Django-Q only fires if manager's last reconcile tick is > 5 min stale (heartbeat in Redis).
- Failover triggered automatically; admin UI shows "manager unhealthy, schedule fallback active" if engaged.
- **Observability gate:** Django-Q failover firings = 0 per 30d.

Exit criterion: ≥30 days with zero Django-Q failover firings.

### Phase M4 — Django-Q decommissioned

- Django-Q schedule tasks deleted from `django_q.Schedule` table.
- `shortcuts.container_command`, `ConnectorController.start_connector/stop_connector`, `schedule_processor.py`, `override_timer.py`, `schedule_deployer.py` removed from admin.
- Admin retains `ScheduleV2` + `FlexSchedule` + `Calendar` write paths but no longer fires K8s mutations.

Exit criterion: code removed, deploys pass, no production incident attributed to the removal.

### Phase M5 — Schema migration to Watch / CalendarSet / ManualOverride

- New tables introduced in manager's state store (Postgres / Raft / wherever the [[cardinality-decision|cardinality decision]] lands per [[2026-05-28_watch-management-service-design]] Open Q1).
- Dual-write at the admin layer: every change to `ScheduleV2`/`FlexSchedule`/`Calendar` also writes to the new tables.
- Dual-read in manager: prefer new tables; fall back to old.
- Backfill: one-shot script projects existing `(Customer, FlexSchedule, ScheduleV2, Calendar)` into `(Watch, CalendarSet, ManualOverride)` per the projection rules in [[2026-05-28_watchman-scheduling-brainstorm-correlation]].
- Cut admin UI over to new tables.
- Old tables become read-only artifacts for 6 months, then dropped.

Exit criterion: new tables sole source of truth; admin UI fully on new schema; old tables read-only.

## Per-proposal migration interaction

| Proposal | Migration impact | Notes |
|---|---|---|
| A — Minimal Split | Smallest data-plane change; M1–M4 land cleanly with no change to pod topology | M5 still applies (schema). |
| B — Stage Fleets | Data plane changes in parallel with migration. Sequence: M1–M3 first (manager going live against current connector), then stage-fleet rewrite, then M4+M5. | Don't try to do both at once. |
| C — Camera-Worker | Manager IS the Assignment Controller. M1–M3 must wait for Assignment Controller to be online (otherwise no controller to extend). | Phase order: C build → M1–M3 → M4 → M5. |
| D — Event-Driven | Manager rides JetStream. JetStream cluster must be online before M1. | Phase order: D infra → M1–M3 → M4 → M5. |
| E — Hybrid Sidecar | Manager IS Site Context Service. Same as C. | |
| B′ — Stateless+Coordinator | Manager IS FleetCoordinator. Raft StatefulSet must be online before M1. | Phase order: B′ infra → M1–M3 → M4 → M5. |

**Common pattern.** For C/D/E/B′, the new fleet topology lands *before* manager cutover. For A/B, manager cutover can come first (smaller delta) and the data-plane rework follows.

## Rollback decision points

At each phase boundary, define a rollback trigger:

| Phase | Rollback trigger | Action |
|---|---|---|
| M1 → M2 | Shadow agreement < 99% | Stay in M1; investigate; do not promote |
| M2 → M3 | Dual-write deadlock or repeated dedupe failures | Roll back to M1 (manager read-only) |
| M3 → M4 | Any Django-Q failover firing in 30d | Stay in M3; tune manager reliability |
| M4 → M5 | Production incident attributed to Django-Q removal | Restore admin code from git, re-enable Django-Q tick |
| M5 | Backfill produces wrong projections | Roll back to dual-read with old tables primary; fix projection |

## Risks

1. **Customer manual-override edge cases.** Existing customers may have manual overrides applied through paths that bypass `MotionStatus` (e.g. Alarmwatch direct calls). Manager must subscribe to those write paths in M1 — see [[2026-05-28_watchman-scheduling-brainstorm-correlation]] partner integrations.
2. **DST cutover timing.** Don't promote phases across a DST boundary (M1→M2, M3→M4, etc.). Schedule promotions for at-least-2-weeks away from any DST transition in any IANA zone we serve.
3. **Django-Q hidden timing assumptions.** `was_redeployed_today` Redis flag, `is_done_for_today` check, `delete_duplicate_schedules` — these are bandaids that may mask manager bugs during dual-write. M2 must instrument both writers and never trust either as ground truth.
4. **`current_schedule_override_start/_end` denormalization drift.** Today's display-only fields fall out of sync with reality. Don't fix during cutover — patch them at M5 schema migration as part of the projection rewrite.
5. **Schema migration during active patrol/healthcheck runs.** Backfill projection runs against live data; long-running transactions may block VCH/AP cronjob ticks. Run backfill in batches per-customer, off-hours per-customer-tz.

## Cross-references

- [[2026-05-28_watch-management-service-design]] — master (open Q4 was the migration question)
- [[2026-05-28_watchman-scheduling-brainstorm-correlation]] — projection rules for old → new schema
- [[2026-05-29_watch-manager-failure-modes]] — what happens during M2 if manager partitions
- [[topics/admin-api/notes/syntheses/2026-05-13_customer-model-dissection]] — existing field reference
