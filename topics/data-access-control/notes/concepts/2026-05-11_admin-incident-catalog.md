---
title: "Admin Incident Catalog (12-month look-back)"
type: concept
topic: data-access-control
tags: [postmortem, incidents, reliability, phase-0, release-gate, rds]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
incoming:
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_admindao-call-site-inventory.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-reliability-fix-plan.md
  - topics/data-access-control/notes/syntheses/2026-05-13_dig-followups.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/daily/2026-05-11.md
incoming_updated: 2026-05-27
---

# Admin Incident Catalog — 12-Month Look-back

Catalog of admin-side production incidents (`actuate_admin` Django + `actuateadminprodcluster` Postgres) over the last ~12 months. Inputs to **Phase 0 release-gate hardening** in [[2026-05-11_admin-db-access-hardening|the admin DB access hardening plan]] — for each recurring failure mode, identify the pre-merge / canary / rollback control that would have caught or contained it.

## Headline

**5 admin incidents identified in ~3 months (Feb–Apr 2026).** Three failure-mode categories, with **runaway-query / N+1** as the dominant pattern (2 of 5 incidents, including the worst — 15 min at 98.7% RDS CPU).

**Top 3 recurring failure modes (ranked by frequency + severity):**

1. **Runaway query / N+1 / unoptimized CTE** (2 incidents) — BT-926, BACK-623
2. **Schema/validation regression (bad data persisted)** (1 incident) — BACK-648
3. **RDS resource exhaustion (CPU / autovacuum)** (1 incident) — BACK-622

Schema/migration regressions (BACK-604/605, Django + Postgres upgrades) recur as a multi-month theme without producing a single sharp outage, but with repeated failed migration attempts requiring rollback.

## Incident Summary

| Date | Ticket | Title | Failure Mode | Root Cause | Recommended Control |
|---|---|---|---|---|---|
| 2026-04-12 | BT-926 | Recursive CTE CPU spike — 15 min, 98.7% DB CPU | Runaway query | 10 concurrent recursive CTEs from `Group.get_descendants()`; API endpoints fan out per-group from a single dashboard load | Slow-query log monitoring in canary; code-review estimation of CTE depth × fan-out; per-endpoint query-count threshold; cache group hierarchy (rarely changes) |
| 2026-04-17 | BACK-648 | Silent [[evalink-components|Evalink]] alert drops (88 HTTP 400/hr) | Schema/validation regression | Camera saved with 11-char display name in [[evalink-components|Evalink]] `deviceId` (needs 32 chars); no server-side validation on save; downstream fails silently | Schema-level field validators tied to integration type; pre-merge audit for new integration-linked fields; post-deploy data-quality checks before mark-live |
| 2026-03-27 | BACK-604/605 | Django + Postgres major version upgrade — multiple failed migration attempts | Schema/migration regression | Major version upgrades validated in staging but not against prod traffic patterns; Postgres migration not validated against prod snapshot | Dry-run migrations on restored prod snapshot in pre-prod; 48h staging soak with 10% prod traffic mirrored; explicit rollback plan coded + tested before deploy |
| 2026-02-20 | BACK-623 | N+1 queries in admin list views (Group/Customer/GroupUser changelist) | Runaway query | Admin list display methods call `.get_descendants()` per row; Customer admin subqueries not indexed; no prefetch/select_related | Query-count assertion in integration tests; django-silk or similar in staging; code-review checklist on admin list views |
| 2026-02-20 | BACK-622 | Autovacuum CPU spike after bulk deletes | RDS resource exhaustion | Bulk delete of 500+ Streams cascades to ~5K+ child rows → autovacuum cleanup → CPU spike for minutes post-script | Pre-merge schema review of CASCADE relationships; ops runbook for triggers during bulk deletes; tune `autovacuum_vacuum_scale_factor` on high-churn tables; CloudWatch alerts on vacuum duration |

## Top 3 Failure Modes — Recommended Controls

### 1. Runaway query / N+1 / unoptimized CTE (most frequent + most severe)

**Pattern:** A query that's fine in isolation becomes catastrophic under fan-out from a real dashboard load or scheduled job. The same recursive CTE that's <100ms by itself becomes a 15-min DB freeze when 10 of them stack.

**Controls to add to admin's release process:**

- **CI: query-count assertion.** Integration tests run under a query logger; failing if a baseline + margin is exceeded for a given test. Catches new N+1s before merge.
- **Code review: explicit checklist** for any change to admin list views, recursive queries, or per-row computations. "Does this use `.select_related()` / `.prefetch_related()` / annotation?" "Is the recursion bounded?"
- **Canary: slow-query log monitoring.** New code runs in canary for N minutes; alerts on any query > threshold or any endpoint that fires > 10 DB queries per invocation.
- **Cache rarely-changing hierarchies.** `Group.get_descendants()` is the canonical offender. Group hierarchy changes infrequently; caching it at admin's process level (or in Redis) eliminates the recursion path on the hot read path.
- **Connection-level statement_timeout** for the read-replica role used by the connector fleet. Prevents one runaway from cascading to everyone.

### 2. Schema/validation regression (bad data persisted)

**Pattern:** A new field or integration adds a new format requirement; admin accepts whatever's posted; downstream fails — sometimes silently — instead of admin rejecting at the boundary.

**Controls to add:**

- **Schema-level field validators tied to integration type.** When `integration_type='evalink'`, `deviceId` must match a specific format. Enforced on save, not at downstream consumption time.
- **Pre-merge audit:** any PR adding a new integration-linked field must include a validator.
- **Post-deploy data-quality gates.** Before marking a deploy "live," run a sample audit query for any new/changed integration data (e.g., distribution of `deviceId` lengths per [[evalink-components|Evalink]] customer). Sign-off requires the audit to look right.
- **Downstream defense in depth:** consumers should never silently drop on a 400. Structured WARNING + DLQ + alert. This is a queue-consumer concern but the catalog surfaced it.

### 3. RDS resource exhaustion (CPU / autovacuum)

**Pattern:** A maintenance script's footprint on the DB isn't just its visible work — it includes the cascade-delete row count, the autovacuum work afterwards, the trigger fires. Cost analysis at code-review time tends to miss this.

**Controls to add:**

- **Pre-merge schema review for bulk operations.** Document all CASCADE relationships and estimate post-operation autovacuum cost.
- **Maintenance window ops runbook.** Disable triggers during bulk deletes where feasible; schedule autovacuum explicitly afterwards.
- **Autovacuum tuning per table.** High-churn tables (stream, metrics) need lower `autovacuum_vacuum_scale_factor` than the default. Set via Terraform.
- **Observability:** CloudWatch / NR alerts on autovacuum duration > 2 min. (Aligns with the §5d NR-primary observability decision.)

## Gaps & meta-observations

- **No production canary or traffic-replay testing** before major version upgrades. Staging traffic is synthetic; prod patterns differ. The Django + Postgres upgrade pain over Jan–Mar 2026 is the directly attributable cost.
- **No automated N+1 / query-cost analysis in CI.** Code review depends on manual inspection of ORM patterns. We caught BACK-623 only after it was already a recurring incident contributor.
- **No post-deploy data-quality gates.** Bad data persisted for an unknown duration before BACK-648 surfaced via downstream HTTP 400 logs.
- **No integration-specific field validation at schema level.** Defensive validation lives in consumers, where failures can be silent.

## Phase 0 starter set (recommended)

From this catalog, the highest-ROI initial controls for the Phase 0 reliability baseline:

1. **CI query-count assertion** for admin's integration tests. One-time setup; ongoing benefit per PR.
2. **Slow-query log → NR alert** on admin's prod RDS. Catches runaway queries the moment they appear, not 15 min into a real outage.
3. **statement_timeout on the read-replica role** that the connector fleet uses. Bounds the blast radius of any single bad read.
4. **Read replica for inframap-heavy reads** (Phase 0 of the parent plan already specifies this).
5. **Postgres dry-run migration on prod snapshot** before any major version upgrade. One-time tool, big payoff at upgrade time.

## Cross-references

- [[2026-05-11_admin-db-access-hardening]] — parent synthesis (§5b reliability workstream)
- [[2026-05-11_admindao-call-site-inventory]] — Phase 2 migration scope, complement to this catalog
- [[database-performance]] — pre-existing admin-api topic note on Aurora CPU work (BACK-623 / BT-926)
