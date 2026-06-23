---
title: "Overnight Health Check 2026-06-03"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-03
updated: 2026-06-03
author: kb-bot
status: warn
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-03

## Summary

Autopatrol pipeline healthy (all 5 monitored sites patrolling, 0 CNCTNFAILs, 0 server errors), but the connector fleet and alert path show elevated noise: a multi-connector pod-availability event fired 9 CRITICAL issues overnight, connector-11202 logged ~15.7K errors, and queue-evalink-consumer exceeded its alert-delivery error threshold.

## Issues Found

- **Connector fleet error spike** — `connector-11202` logged **15,707** errors in 12h (~10× fleet median); `connector-30022` logged **8,064**. All 15 returned containers exceeded the 100-error threshold; the remaining 13 cluster ~1,440–3,563 (baseline noise floor). Top two warrant message-level drill-down.
- **Alert delivery** — `queue-evalink-consumer` logged **270** errors (>20 threshold). Other four canonical alert containers clean (eagle-eye 1; smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker = 0).
- **NR Issues** — multi-connector "Deployment has unavailable pods" burst (~05:11–05:38 UTC) fired **9 CRITICAL** issues across rearchitecture/clips/queue-consumer/smtp namespaces, all still ACTIVATED. "Envera Camera Unavailable High" (CRITICAL) flapping; clips `/analyze` 499 errors (HIGH) recurring through the night; Genesis unmapped failover server (CRITICAL) still open.
- **Connector-side autopatrol cronjob errors** — 222 ERROR lines across 7 `*-autopatrol-*-chm-cronjob` containers (sites 35830/35831/35832/46767, outside the 5 monitored IDs). Counts of 48/12/6 look job-cycle-aligned; confirm content if operationally relevant.
- **Note (not flagged):** site 45061 patrol volume (141) is 6–8× lower than peers — verify expected activity.

## AutoPatrol

NR-only check (kubectl/kubefwd unavailable in headless session). Cluster `Connector-EKS`, SINCE 12h.

**Patrol log counts per site** — all five active, no zero-patrol sites:

| Site ID | Patrol log lines |
|---------|-----------------|
| 37837   | 1,112 |
| 40672   | 1,043 |
| 41158   | 894 |
| 41178   | 786 |
| 45061   | 141 *(low — note)* |

**autopatrol-server ERROR count:** 0 — clean.

**CNCTNFAIL per site:** no rows — 0 across all five sites. Clean.

**Connector-side autopatrol cronjob ERRORs (FACET container_name):** 222 total across 7 containers — `connector-35832-autopatrol-260` (48), `35831-autopatrol-310` (48), `35831-autopatrol-259` (48), `35830-autopatrol-309` (48), `35831-autopatrol-313` (12), `46767-autopatrol-1102` (12), `35831-autopatrol-343` (6). These are connector-side cronjobs (not autopatrol-server) and fall outside the 5 monitored site IDs.

**Flags:** no zero-patrol site; no CNCTNFAILs; autopatrol-server clean. Connector-side cronjob errors flagged for follow-up; site 45061 low-volume noted.

## Connector Fleet

ERROR counts, cluster `Connector-EKS`, SINCE 12h, FACET container_name, LIMIT 15. **All 15 returned containers exceed the 100-error threshold.**

| Container | Error Count |
|---|---|
| connector-11202 | 15,707 |
| connector-30022 | 8,064 |
| connector-32249 | 3,563 |
| connector-32220 | 3,287 |
| connector-31563 | 2,267 |
| connector-30396 | 1,779 |
| connector-42616 | 1,636 |
| connector-36679 | 1,614 |
| connector-41088 | 1,586 |
| connector-17331 | 1,510 |
| connector-12686 | 1,510 |
| connector-17328 | 1,508 |
| connector-35025 | 1,466 |
| connector-36681 | 1,454 |
| connector-38431 | 1,440 |

`connector-11202` (15,707) and `connector-30022` (8,064) are severe outliers vs. the ~1,440–3,563 baseline of the other 13. **Caveat:** LIMIT 15 truncates the list — additional erroring containers below the top 15 are not shown, so the true fleet footprint may be wider. Recommend message/TIMESERIES drill on the top two to distinguish burst vs. sustained.

## Alert Delivery

ERROR counts, cluster `Connector-EKS`, SINCE 12h, canonical container names only.

| Container | Error Count | Status |
|---|---|---|
| queue-evalink-consumer | 270 | FLAGGED (>20) |
| queue-eagle-eye-consumer | 1 | OK |
| smtp-frame-receiver | 0 (no row) | OK |
| cert-manager-webhook | 0 (no row) | OK |
| clips-smtp-worker | 0 (no row) | OK |

`queue-evalink-consumer` (270) well above the 20-error threshold — recommend a FACET on `message` to identify the dominant error type. **Caveat:** the three zero-row containers are treated as 0 errors; a separate log-volume check would confirm clean vs. no ingestion.

## New Issues

NR Issues opened in the last ~12h (account 3421145, client-side filtered on `createdAt`; cutoff ~2026-06-03 00:03 UTC).

- **Total opened:** 17
- **Severity:** CRITICAL 13, HIGH 4, MEDIUM 0, LOW 0
- **State:** ACTIVATED (open) 11, CLOSED 6

**Top 3 by entity / notability:**

1. **Multi-connector "Deployment has unavailable pods" (CRITICAL)** — 9 connector deployments (`connector-20274`, `connector-44300-fs-1505`, `connector-11998` + 6 more) fired within a ~5-min burst (~05:11–05:38 UTC), all still ACTIVATED, across rearchitecture/clips/queue-consumer/smtp namespaces. Dominant signal of the night. Policy: K8s Deployment Pod Startup Issues.
2. **Envera Camera Unavailable High (CRITICAL)** — log-query condition (envera container), opened ~13:03 UTC (most recent overall), still ACTIVATED; a prior instance closed earlier → flapping.
3. **Clips `/analyze` POST 499 errors (HIGH)** — Clips Production policy, opened ~06:16 UTC, still ACTIVATED; three earlier instances closed (~01:52/02:53/03:02 UTC) → repeated client-timeout pattern through the night.

Also notable (just outside top 3): **Genesis unmapped failover server (CRITICAL)**, ACTIVATED since ~06:06 UTC — failover host with no mapping.

## Raw NRQL

<details>
<summary>Queries used (cluster_name='Connector-EKS', SINCE 12 hours ago, account 3421145)</summary>

```sql
-- AutoPatrol: patrol counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
SINCE 12 hours ago
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837');

-- AutoPatrol: autopatrol-server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago;

-- AutoPatrol: CNCTNFAIL counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837');

-- AutoPatrol: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago
FACET container_name LIMIT 10;

-- Connector fleet: overnight error counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago
FACET container_name LIMIT 15;

-- Alert delivery: canonical container error counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago
FACET container_name;

-- New Issues: via mcp__newrelic__list_recent_issues (account_id=3421145), 12h filter applied client-side on createdAt
```

</details>

## End
