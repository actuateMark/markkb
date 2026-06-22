---
title: "Cohort F investigation — billing-emit reality check (2026-05-06)"
type: synthesis
topic: autopatrol
tags: [autopatrol, cohort-f, billing, snowflake, immix, vms-connector, investigation]
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
workstream: "§26"
related:
  - "[[2026-05-04_silent-camera-diagnosis]]"
  - "[[2026-05-01_silent-cameras-diagnosis]]"
  - "[[autopatrol-cleanup-lambda]]"
  - "[[2026-05-04_admin-schedule-cascade-design]]"
  - "[[2026-05-05_cohort-b-backfill-runbook]]"
outgoing:
  - topics/autopatrol/notes/concepts/2026-05-06_cohort-f3a-deactivate-runbook.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/personal-notes/notes/daily/2026-05-06.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/vms-connector/notes/concepts/2026-05-07_site-product-started-deprecated.md
incoming:
  - topics/autopatrol/notes/concepts/2026-05-06_cohort-f3a-deactivate-runbook.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/autopatrol/notes/syntheses/2026-05-20_ap-summary-disable-plan.md
  - topics/billing/_summary.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/entities/billing-deferred-backlog.md
  - topics/billing/notes/entities/billing-events-catalog.md
  - topics/billing/notes/syntheses/2026-05-11_billing-pain-post-mortem.md
  - topics/billing/notes/syntheses/2026-05-12_week-in-review-non-technical.md
incoming_updated: 2026-05-27
---

# Cohort F investigation — billing-emit reality check

## Summary

Cohort F (45 customers / 642 silent cameras per the [[2026-05-04_silent-camera-diagnosis]] audit) decomposes into **22 customers / 392 cameras that ARE emitting billing events properly** (Snowflake-side ingestion gap, not connector) and **23 customers / 250 cameras that are real connector-side billing gaps**. Of the 23 real gaps, **9 customers / 102 cameras** have schedules already Deleted in Immix and just need a one-time admin-side deactivation patch (mirrors [[2026-05-05_cohort-b-backfill-runbook|§25 Cohort B backfill]] pattern). The other 14 customers / 148 cameras need a connector code change to emit `site_product_started` / `site_product_ended` at cronjob start/end regardless of patrol outcome.

## Method

Two NR + Immix probes against the 45-cohort-F customer list:

1. **NR — billing-event emit audit.** Per-cid `site_product_ended` count from `event_queue_analytics.fifo` SQS messages (logged at INFO via the connector's `Sending event_info: …` line). Cluster-wide finding: **330,859 `site_product_ended` events / 24h**, **0 `site_product_started` events / 24h** (the started event is *not* in the connector's vocabulary anywhere — `_ended` is the canonical billing event).
2. **Immix — schedule status spot-check.** Pulled all 18 contracts via `/v/Contracts` (paginated), then per-tenant queried `/v/Schedules?scheduleStatus=X` across {Active, Awaiting, Paused, Suspended, Removed, Deleted} to build a global schedule-UUID → status map (389 schedules across 18 tenants). Cross-referenced against the 27 schedule UUIDs covered by the 17 F3 cids in admin's cache.

Both probes are reproducible from the laptop with creds bootstrapped via `scripts/fetch_local_test_env.sh prod` (Postgres api-token + AUTOPATROL_API_KEY from `prod/actuate/postgres` + `prod/actuate/autopatrol` AWS Secrets Manager entries).

## Reframed cohort split

| Sub-cohort | Cids | Cams | Diagnosis | Action class |
|---|---:|---:|---|---|
| **F6** | 21 | 386 | Connector emits `site_product_ended` to `event_queue_analytics.fifo` correctly (range 8–208/24h, scaled to cam-count × 4 checks/day). 20 are ABC Liquor Stores running VCH-only health checks; 1 is RRMS Internal Testing. | **Snowflake-pipeline gap (downstream of SQS).** Connector portion DONE. |
| **F5** | 1 | 6 | hanwha 2 — actively patrolling, emitting both successful patrol summaries AND `site_product_ended` events (192/24h). | **Snowflake-pipeline gap.** Connector portion DONE. |
| **F4** | 6 | 75 | Connector cronjob fires but patrols-API errors out (no-response / timeout / authz / "no patrols to run due to error"). Mostly *not* emitting `site_product_ended` (1 of 6 partial — Tampa Office CS at 28/24h). | **Connector billing-emit fix:** emit on failure path. |
| **F3a** | 9 | 102 | Schedule **Deleted or NOT_FOUND in Immix**, admin still says Active. Connector cronjob fires, gets empty patrol list, logs `no_patrols`. | **One-time admin patch script** to deactivate the schedule (and cascade cameras). The §3 cleanup-Lambda + §25 cascade-hook pipeline would catch these once both flip — patch is the fast-track. |
| **F3b** | 4 | 40 | Schedule **Paused in Immix** (customer-controlled non-running state). Cleanup-Lambda explicitly treats Paused as `active` per the [[autopatrol-cleanup-lambda|cleanup-Lambda runbook]]. Not a deactivate candidate. | **Connector billing-emit fix.** Customer expects we're monitoring — bill on cronjob run. |
| **F3c** | 4 | 33 | Schedule **Active in Immix with non-empty device list**, but no `AWAITING` patrols at fetch time (normal idle state — connector queries `?scheduleStatus=AWAITING` by default). Logs `no_patrols` because no patrol is currently queued. | **Connector billing-emit fix.** Cronjob ran; bill it. |

The `(provisional)` markings on the 13 cids the subagent classified by K8s sample-count pattern (NRDB timed out on direct message inspection) didn't change in this round — the F3 Immix probe confirmed F3 status for all of them.

**Camera-count math:** 386 + 6 + 75 + 102 + 40 + 33 = **642** ✓.

## The cluster-wide `site_product_started` finding

A 24h cluster-wide query for `event_queue_analytics.fifo` events on Connector-EKS returned:

- 330,859 `site_product_ended` events
- **0 `site_product_started` events**
- 0 `subscription_started` / `subscription_ended` / `detection_started` events

So `site_product_started` is genuinely not in the connector's vocabulary. The billing system runs on `_ended` only (with `act_a` discriminating between `'patrol'`, `'healthcheck'`, etc.). When the user policy says "emit `site_product_started/ended`", the actual implementation today is `_ended`-only — the connector PR may need to also introduce `_started` if the new policy strictly requires it, or simply ensure `_ended` fires per cronjob run.

## F3 Immix spot-check raw output

The Immix `/Schedules/{schedule_id}` lookup uses a `tenantId` HEADER (not URL path). Without an admin-side cid → tenant mapping, the workaround is to enumerate all tenants from `/Contracts` and list each tenant's schedules across all statuses. With 18 tenants and 389 schedules total, this is a sub-minute probe.

Per-cid Immix verdict for the 17 F3 cids:

```
   cid  admin_sched   admin status   immix status  tenant prefix  title
 41266     337          Active        Deleted      7b533b5a       VCH Check                    ❌ F3a
 40672     1027         Active        Deleted      37575b9e       test1                        ❌ F3a
 41260     331          Active        Deleted      7b533b5a       VCH Check                    ❌ F3a
 41263     334          Active        Deleted      7b533b5a       VCH Check                    ❌ F3a
 38738     212          Active        NOT_FOUND    —              —                            ❌ F3a
 37742     143          Active        NOT_FOUND    —              —                            ❌ F3a
 41262     333          Active        Deleted      7b533b5a       VCH Check                    ❌ F3a
 41264     335          Active        Deleted      7b533b5a       VCH Check                    ❌ F3a
 44879     860          Active        Deleted      7b533b5a       VCH Check                    ❌ F3a
 37837     1028         Active        Paused       37575b9e       test5                        ⚠️  F3b
 38316     597          Active        Paused       dfda7621       AutoPatrol                   ⚠️  F3b
 38711     210          Active        Paused       f858b03b       Visual Camera Health         ⚠️  F3b
 35828     1, 125, 126  Active        Paused (3)   dfda7621       Acme Bank ATM (etc)          ⚠️  F3b
 37991     162          Active        Active       1419710a       VCH - Raise (13 devices)     ✓  F3c
 37989     161          Active        Active       1419710a       VCH - Raise (8 devices)      ✓  F3c
 38575     201          Active        Active       74cf336c       VCH Check (7 devices)        ✓  F3c
 37621     156, 139     Active        Active       1419710a       Open store / VCH Demo (10)   ✓  F3c
```

(`140` for cid=37621 was Deleted in Immix but already Deleted in admin — irrelevant.)

## Action surface

### 1. F3a patch script (9 cids / 102 cams) — high-confidence one-shot

Mirrors [[2026-05-05_cohort-b-backfill-runbook|§25 Cohort B backfill]] pattern: identify the 9 schedules with admin/Immix divergence, mark them `is_deleted=True` with audit fields (`disabled_by='patch_script_2026-05-06_F3_immix_gone'`), and let the §25 cascade hook (or a manual `customer.delete()` sweep) flip the cameras.

Dry-run + apply pattern, idempotent, runs in <1 min wall-clock. The 9 cids:

| cid | sched | Immix status | name | cams |
|---:|---:|---|---|---:|
| 41266 | 337 | Deleted | Advanced Security Systems - Eureka | 32 |
| 40672 | 1027 | Deleted | AutoPatrol-Live | 28 |
| 41260 | 331 | Deleted | Cimino Electric | 10 |
| 41263 | 334 | Deleted | Tate's Tire Pro's | 10 |
| 38738 | 212 | NOT_FOUND | 2 Fuller Road - Bergvliet | 9 |
| 37742 | 143 | NOT_FOUND | London | 5 |
| 41262 | 333 | Deleted | Link Housing | 4 |
| 41264 | 335 | Deleted | Mission Ace Hardware | 3 |
| 44879 | 860 | Deleted | Solful - Petaluma | 1 |

### 2. Connector billing-emit fix (148 cams across 14 cids)

Emit `site_product_ended` (and optionally `site_product_started`) at cronjob start/end **regardless of patrol outcome** (success / empty list / failure / error). Move the emit out of the patrol-success path.

Affects:
- F3b (4 cids / 40 cams) — Paused-in-Immix customers, admin Active, cronjob runs
- F3c (4 cids / 33 cams) — Active-in-Immix idle, no AWAITING patrols
- F4 (6 cids / 75 cams) — patrols-API error path (1 of 6 partial today)

Cronjob entrypoint code in vms-connector — needs probe to find the right insertion point.

### 3. Snowflake-pipeline gap (392 cams) — OUT OF SCOPE

F6 (386) + F5 (6) = 392 cams. Connector confirmed emitting `site_product_ended` properly to `event_queue_analytics.fifo`. Gap is downstream of SQS — likely the Lambda/Glue/Snowpipe consumer filters by event type, drops `act_a='healthcheck'` events, or maps to a different billing table than the silent-cameras query reads. **Hand off to data team / pipeline owner; not a connector workstream.**

## Tracker

`autopatrol_onboarder/scripts/ops/cohort_f_tracker.json` populated with 45 cids (status=`fixed` for 22 connector-OK / Snowflake-side, `diagnosed` for 23 needing connector or patch action). Pushed as follow-up commit on [autopatrol_onboarder#14](https://github.com/aegissystems/engineering/aegissystems/autopatrol_onboarder/pull/14).

## Open questions

1. Does the connector PR also need to emit a *new* `site_product_started` event (currently 0 cluster-wide), or is `_ended`-only acceptable as long as it fires every cronjob run? Check with billing-system stakeholder.
2. For F3c (Active-in-Immix idle), should the cleanup-Lambda eventually disable these too — or is "no AWAITING patrols at fetch time" expected long-term steady state for some sites? If always-idle is permanent, the `no_patrols` log noise should be downgraded to DEBUG.
3. Re-run NR probe in 7d to confirm the 22 "fixed" customers continue emitting at expected rates (regression check post-§3 Step F flip).

## Cross-refs

- §26 in [[mark-todos]] — parent workstream
- §3 in [[mark-todos]] — cleanup-Lambda Step F prod-US scale-up
- §25 in [[mark-todos]] — Cohort B cascade hook (pattern source)
- [[2026-05-04_silent-camera-diagnosis]] — original audit data
- [[autopatrol-cleanup-lambda]] — cleanup-Lambda entity + status policies
