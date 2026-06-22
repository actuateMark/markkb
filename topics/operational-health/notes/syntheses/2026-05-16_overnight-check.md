---
title: "Overnight Health Check 2026-05-16"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-16
updated: 2026-05-16
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-17
---

# Overnight Health Check 2026-05-16

## Summary

Degraded — 2 autopatrol sites silent (41158, 45061), `queue-evalink-consumer` at 340 errors, full connector fleet running hot (15 containers >100 errors), 4 NR criticals still active.

## Issues Found

- **Sites 41158 and 45061: zero autopatrol logs in 12h** — cronjobs may not be firing, pods unscheduled, or sites paused/decommissioned. Needs kubectl follow-up.
- **`queue-evalink-consumer`: 340 ERRORs in 12h** (threshold >20). Only active alert-delivery error source — investigate dominant failure pattern.
- **Connector fleet: all top 15 containers >100 errors.** `create-detection-window` leads at 8,548; connectors 47116/11202/36681/40439 each above 3,300. Likely platform-wide noise floor + a few outliers.
- **4 NR Issues still ACTIVATED:** [[frame-fetcher-v3|Frame Fetcher V3]] Lambda errors (CRITICAL), Genesis unmapped failover (CRITICAL), ip-10-10-52-193 High CPU (CRITICAL), YOLO inference error spike (HIGH).
- **autopatrol-server restarted** in window (startup logs at 08:34 UTC, no preceding activity). No ERRORs but worth checking restart count.

## AutoPatrol

**Window:** last 12 hours, cluster `Connector-EKS`.

| Site | Patrol log count (12h) | CNCTNFAIL count | Status |
|------|------------------------|-----------------|--------|
| 40672 | 432 | 0 | OK |
| 41178 | 264 | 0 | OK |
| 37837 | 240 | 0 | OK |
| 41158 | 0 | 0 | ALERT — no logs |
| 45061 | 0 | 0 | ALERT — no logs |

**autopatrol-server:** 29 log lines in 12h, all startup/init (SQS listener coming up, S3 handler registrations). 0 ERRORs. Server appears to have restarted once and is currently idle (no jobs dispatched in window).

**Connector-side autopatrol errors:** none. No `*autopatrol*` container emitted ERROR-level logs.

**CNCTNFAIL:** zero across all sites — clean.

**Methodology note:** site IDs do not appear in `autopatrol-server` messages — they live in per-site cronjob container names (`connector-{site_id}-autopatrol-*-chm-cronjob`). Queries faceted on `container_name LIKE '%{site_id}%'` rather than `message LIKE`.

## Connector Fleet

| Container | ERROR count (12h) |
|---|---|
| create-detection-window | 8,548 |
| connector-47116 | 4,896 |
| connector-11202 | 4,880 |
| connector-36681 | 4,518 |
| connector-40439 | 3,337 |
| connector-36679 | 1,705 |
| connector-17331 | 1,509 |
| connector-12686 | 1,508 |
| connector-17328 | 1,500 |
| connector-35025 | 1,428 |
| connector-19527 | 1,414 |
| connector-17379 | 1,413 |
| connector-23430 | 1,407 |
| connector-36381 | 1,405 |
| connector-34144 | 1,188 |

**Verdict:** All top-15 containers exceed the 100-error threshold. `create-detection-window` (platform service) leads at 8,548; the top four site connectors (47116, 11202, 36681, 40439) clear 3,300+. The cluster of ~1,400-1,500 errors across 10 connectors suggests a shared floor-level noise pattern. Investigate `create-detection-window` and the top-four connectors first.

## Alert Delivery

| Container | ERROR count (12h) | Flag |
|---|---|---|
| queue-evalink-consumer | 340 | YES — >20 threshold |
| queue-eagle-eye-consumer | 1 | ok |
| smtp-frame-receiver | 0 (no logs) | — |
| cert-manager-webhook | 0 (no logs) | — |
| clips-smtp-worker | 0 (no logs) | — |

**Verdict:** `queue-evalink-consumer` is the only active error source and is well above threshold. Drill into the dominant failure pattern next:

```sql
SELECT message, count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='queue-evalink-consumer' AND level='ERROR'
SINCE 12 hours ago FACET message LIMIT 10
```

The three zero-log containers (`smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`) may indicate quiet/idle services or may warrant a liveness check — no errors but also no activity.

## New Issues

**Total (last 12 hours):** 8 issues across 4 policies.

**Severity distribution:**
- Critical: 5
- High: 3
- Medium: 0
- Low: 0

**Currently ACTIVATED (still open):** 4

**Top 3 by impact:**

1. **[[frame-fetcher-v3|Frame Fetcher V3]] Lambda Errors** — CRITICAL, ACTIVATED. Lambda unhandled exceptions >50/hr for 60+ minutes. Ongoing since ~00:03 UTC.
2. **Genesis unmapped failover** — CRITICAL, ACTIVATED. Unmapped failover server check firing >5/min for 5 minutes. Ongoing since ~16:09 UTC prior day.
3. **ip-10-10-52-193.us-west-2.compute.internal High CPU** — CRITICAL, ACTIVATED. Host CPU >85% for 5+ minutes (Golden Signals). Fired twice in 12h window; current instance still open since ~02:14 UTC.

Also worth watching: **YOLO inference error spike** (HIGH, ACTIVATED) on clips-prod, alongside the recurring clips `POST /analyze` 499 errors pattern (2x HIGH, both CLOSED but recurring).

**Caveat:** `list_recent_issues` returns a fixed 24h window; the 12h filter was applied by `createdAt` timestamp.

## Raw NRQL

<details>
<summary>Queries used</summary>

**AutoPatrol — patrol counts per site:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND message LIKE '%patrol%'
SINCE 12 hours ago
FACET cases(WHERE container_name LIKE '%41158%' as '41158',
            WHERE container_name LIKE '%41178%' as '41178',
            WHERE container_name LIKE '%40672%' as '40672',
            WHERE container_name LIKE '%45061%' as '45061',
            WHERE container_name LIKE '%37837%' as '37837')
```

**AutoPatrol — autopatrol-server errors:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago
```

**AutoPatrol — CNCTNFAIL per site:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago
FACET cases(WHERE container_name LIKE '%41158%' as '41158',
            WHERE container_name LIKE '%41178%' as '41178',
            WHERE container_name LIKE '%40672%' as '40672',
            WHERE container_name LIKE '%45061%' as '45061',
            WHERE container_name LIKE '%37837%' as '37837')
```

**AutoPatrol — connector-side errors:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 10
```

**Connector Fleet:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15
```

**Alert Delivery:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
                         'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name LIMIT 10
```

**Issues:** `list_recent_issues` (24h window, manually filtered to 12h by `createdAt`).

</details>

## End
