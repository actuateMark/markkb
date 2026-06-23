---
title: "Overnight Health Check 2026-06-17"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-17
updated: 2026-06-17
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-17

## Summary

Autopatrol pipeline is clean (0 server errors, 0 CNCTNFAILs), but the connector fleet is noisy — `connector-11202` alone logged 13,120 errors in 12h, 69 NR issues opened (52 CRITICAL, mostly unavailable-pod alerts), and `queue-evalink-consumer` is above its alert threshold at 320 errors.

## Issues Found

- **connector-11202: 13,120 ERRORs in 12h** — 5.6× the next-noisiest connector. Needs message-level drill-down and likely escalation.
- **69 NR issues opened in 12h (52 CRITICAL / 17 HIGH)** — dominated by "Deployment has unavailable pods" (CRITICAL) and "POST /analyze 499 errors" + YOLO inference spikes (HIGH).
- **queue-evalink-consumer: 320 ERRORs** — above the 20-error alert-delivery threshold; alert delivery path may be degraded.
- **Sites 41158 and 45061: very low patrol activity** — only 12 container-scoped patrol log records each in 12h (45061 had just 28 total log lines). No errors, but anomalously quiet; verify cronjobs are firing.
- **Whole fleet noisy:** all top-15 connector containers exceed 100 ERRORs in the window.

## AutoPatrol

NR-only check (no kubectl/kubefwd in this headless session). Account 3421145, `cluster_name='Connector-EKS'`, SINCE 12h.

**Patrol counts per site** (A = message-scoped, B = container-scoped/precise):

| Site | Message-scoped | Container-scoped | Flag |
|---|---|---|---|
| 40672 | 2,040 | 1,440 | OK |
| 37837 | 1,054 | 396 | OK |
| 41178 | 710 | 264 | OK |
| 41158 | 812 | 12 | LOW |
| 45061 | 106 | 12 | LOW |

**Autopatrol-server errors:** 0 — clean.

**CNCTNFAIL per site:** 0 across all five sites. Broader connection-failure marker scan also returned zero. No site exceeded the >5 threshold.

**Connector-side autopatrol errors** (`container_name LIKE '%autopatrol%' AND level='ERROR'`): only CHM cronjob containers, none of them sites of interest:

| Container | ERRORs |
|---|---|
| connector-46767-autopatrol-1102-chm-cronjob | 21 |
| connector-35832-autopatrol-260-chm-cronjob | 9 |
| connector-47738-autopatrol-1136-chm-cronjob | 8 |
| connector-35831-autopatrol-313-chm-cronjob | 1 |
| connector-35831-autopatrol-310-chm-cronjob | 1 |
| connector-35831-autopatrol-259-chm-cronjob | 1 |

**Verdict:** AutoPatrol pipeline itself is healthy. Follow-up: confirm cronjobs fired for 41158 and 45061 (low patrol volume, no errors).

## Connector Fleet

ERROR counts SINCE 12h, FACET container_name, top 15. **All 15 exceed the 100-error flag threshold.**

| Rank | Container | ERRORs |
|---|---|---|
| 1 | connector-11202 | **13,120** |
| 2 | connector-47464 | 2,361 |
| 3 | connector-31563 | 2,255 |
| 4 | connector-41028 | 1,876 |
| 5 | connector-35025 | 1,772 |
| 6 | connector-47778 | 1,760 |
| 7 | connector-21991 | 1,629 |
| 8 | connector-12686 | 1,510 |
| 9 | connector-17328 | 1,508 |
| 10 | connector-17331 | 1,507 |
| 11 | connector-19527 | 1,412 |
| 12 | sirix-volkswagen-boisbriand-1718 | 1,412 |
| 13 | connector-17379 | 1,412 |
| 14 | connector-39780 | 1,412 |
| 15 | connector-23430 | 1,411 |

`connector-11202` is a clear outlier (5.6× #2) and the priority drill-down. LIMIT 15 means additional >100-error containers exist beyond this list.

## Alert Delivery

ERROR counts SINCE 12h for canonical alert-delivery containers (NR omits zero-count facets; absent = 0):

| Container | ERRORs | Flag |
|---|---|---|
| queue-evalink-consumer | 320 | ABOVE THRESHOLD (>20) |
| queue-eagle-eye-consumer | 3 | OK |
| smtp-frame-receiver | 0 | OK |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

`queue-evalink-consumer` is the only flagged container. Recommend a `FACET message` drill-down to identify the dominant error pattern and confirm whether evalink alert delivery is impaired.

## New Issues

69 NR issues opened SINCE 12h.

**Severity distribution:** CRITICAL 52 · HIGH 17 · MEDIUM 0 · LOW 0.

**Top 3 by volume/entity:**
1. **POST /analyze 499 errors** — 15 issues (HIGH); highest-volume single alert group, likely flapping.
2. **YOLO inference error spike** — 7 issues (HIGH; 4 on >20.0 threshold, 3 on >5.0).
3. **Deployment has unavailable pods** — bulk of the 52 CRITICAL; connector-20139-fs-344, connector-12005, connector-11998 each fired 3×, plus many one-off connectors.

Secondary: 5+ us-west-2 EC2 hosts firing "High CPU > 85%" (3 issues each). Caveat: `entityName` was null in this account, so attribution comes from alert-title strings; re-fires inflate counts vs. unique incidents.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- Patrol counts per site (message-scoped)
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%' OR message LIKE '%45061%' OR message LIKE '%37837%')
  AND (message LIKE '%patrol%' OR message LIKE '%Patrol%' OR message LIKE '%autopatrol%')
  FACET CASES(WHERE message LIKE '%41158%' AS 'site_41158', WHERE message LIKE '%41178%' AS 'site_41178',
    WHERE message LIKE '%40672%' AS 'site_40672', WHERE message LIKE '%45061%' AS 'site_45061',
    WHERE message LIKE '%37837%' AS 'site_37837')
  SINCE 12 hours ago LIMIT 10

-- Patrol counts per site (container-scoped, precise)
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND (container_name LIKE '%41158%' OR container_name LIKE '%41178%' OR container_name LIKE '%40672%' OR container_name LIKE '%45061%' OR container_name LIKE '%37837%')
  AND (message LIKE '%patrol%' OR message LIKE '%Patrol%')
  FACET CASES(WHERE container_name LIKE '%41158%' AS 'site_41158', ...)
  SINCE 12 hours ago LIMIT 10

-- Autopatrol-server errors
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server' AND level = 'ERROR' SINCE 12 hours ago

-- CNCTNFAIL per site
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND message LIKE '%CNCTNFAIL%'
  FACET CASES(WHERE message LIKE '%41158%' AS 'site_41158', ...) SINCE 12 hours ago LIMIT 10

-- Connector-side autopatrol errors
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
  FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet error counts
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
  FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery health
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
  FACET container_name SINCE 12 hours ago LIMIT 10

-- New Relic issues opened
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago
FROM NrAiIssue SELECT count(*) FACET title SINCE 12 hours ago LIMIT 50
```

</details>

## End
