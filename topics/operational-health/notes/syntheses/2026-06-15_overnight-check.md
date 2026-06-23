---
title: "Overnight Health Check 2026-06-15"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-15
updated: 2026-06-15
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-15

## Summary

Degraded — 2 monitored autopatrol sites silent for 12h+ (41158, 45061), a fleet-wide error baseline with connector-30022 as a 9k-error outlier, queue-evalink-consumer alert path failing (318 errors), and a ~11:45 UTC mass pod-unavailability event that opened 14+ CRITICAL issues still mostly active.

## Issues Found

- **Autopatrol — site 41158:** 0 patrol logs over 12h *and* 7 days; no autopatrol container has ever registered in NR. Possible un-provisioned cronjob or offboarded site. Investigate.
- **Autopatrol — site 45061:** Same as 41158 — zero patrol logs across a 7-day lookback, no container ever visible in NR.
- **Connector fleet — connector-30022:** 9,005 ERRORs/12h, ~3x the next-highest container. Severe outlier; needs message-level drill-down.
- **Alert delivery — queue-evalink-consumer:** 318 ERRORs/12h, far over the 20 threshold. [[evalink-components|Evalink]] alert delivery likely impaired.
- **NR Issues — mass pod-unavailability event (~11:45 UTC):** 14+ simultaneous CRITICAL issues across connectors, clips-prod/clips-frontel, and queue-eagle-eye-consumer; most still ACTIVATED.
- **Fleet noise:** all top-15 connector containers exceed 100 errors/12h — broadly noisy baseline.

## AutoPatrol

NR-only check (kubectl/kubefwd unavailable in headless session). Account 3421145, cluster_name='Connector-EKS', SINCE 12h.

**Patrol activity per site** (log-volume proxy from `connector-{site}-autopatrol-*-chm-cronjob` containers):

| Site | Patrol log lines (12h) | Status |
|---|---|---|
| 41158 | 0 | SILENT — no container in NR over 7d |
| 41178 | 516 | OK |
| 40672 | 3,082 | OK |
| 45061 | 0 | SILENT — no container in NR over 7d |
| 37837 | 768 | OK |

**CNCTNFAIL per site:**

| Site | CNCTNFAIL (12h) |
|---|---|
| 41158 | 0 |
| 41178 | 1 |
| 40672 | 0 |
| 45061 | 0 |
| 37837 | 0 |

All sites under the >5 threshold; the single 41178 CNCTNFAIL appeared in a cluster-wide log, not its own autopatrol container.

**Autopatrol-server errors:** 0 ERRORs in 12h — clean.

**Connector-side autopatrol errors** (`container_name LIKE '%autopatrol%' AND level='ERROR'`):

| Container | ERRORs |
|---|---|
| connector-47738-autopatrol-1136-chm-cronjob | 4 |
| connector-46767-autopatrol-1102-chm-cronjob | 1 |

Both are sites outside the monitored 5; none of the 5 target sites logged autopatrol errors.

**Flags triggered:** sites 41158 and 45061 with 0 patrols in 12h. No CNCTNFAIL or autopatrol-server flags.

> Caveat: "patrol count" here is total log volume from each site's autopatrol container — the namespace-LIKE filter returned empty because these pods use the standard cluster namespace, not an `autopatrol` namespace label. Confirmed live container pattern: `connector-{site_id}-autopatrol-{job_id}-chm-cronjob`.

## Connector Fleet

ERROR counts SINCE 12h, FACET container_name, top 15. **Every container in the top 15 exceeds the >100 flag** — broadly noisy fleet.

| Rank | container_name | ERRORs |
|---|---|---|
| 1 | connector-30022 | 9,005 |
| 2 | connector-47116 | 2,804 |
| 3 | connector-31563 | 2,317 |
| 4 | connector-47778 | 1,912 |
| 5 | connector-12686 | 1,515 |
| 6 | connector-17328 | 1,510 |
| 7 | connector-17331 | 1,509 |
| 8 | sirix-volkswagen-boisbriand-1718 | 1,414 |
| 9 | connector-19527 | 1,412 |
| 10 | connector-17379 | 1,411 |
| 11 | connector-23430 | 1,408 |
| 12 | connector-10729 | 1,404 |
| 13 | connector-17327 | 1,404 |
| 14 | connector-35025 | 1,326 |
| 15 | create-detection-window | 1,291 |

Notables: **connector-30022** is the critical outlier (~3x #2); **sirix-volkswagen-boisbriand-1718** is the only named-site connector in the top 15 (possible site-specific driver issue); **create-detection-window** is a platform service, not a connector — errors there carry cross-fleet blast radius. LIMIT 15 may hide additional >100 containers; counts don't distinguish a single repeated error from diverse failures.

## Alert Delivery

ERROR counts SINCE 12h for canonical alert-path containers:

| Container | ERRORs | Status |
|---|---|---|
| queue-evalink-consumer | 318 | OVER THRESHOLD (>20) |
| queue-eagle-eye-consumer | 1 | OK |
| smtp-frame-receiver | 0 | OK |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

**queue-evalink-consumer** is well over the 20-error threshold — [[evalink-components|Evalink]] alert delivery likely impaired; drill into its message distribution for root cause. The three zero-count containers are active on other log levels (no data gap).

## New Issues

**25 NR Issues opened in the last 12h**, all high-severity.

| Priority | ACTIVATED | CLOSED | Total |
|---|---|---|---|
| CRITICAL | 17 | 6 | 23 |
| HIGH | 0 | 2 | 2 |
| MEDIUM / LOW | 0 | 0 | 0 |
| **Total** | **17** | **8** | **25** |

**Top 3 by recency/impact:**
1. **High CPU — ip-10-10-58-96** (CRITICAL/ACTIVATED, ~12:22 UTC) — node CPU >85% for 5 min.
2. **Envera Camera Unavailable High** (CRITICAL/ACTIVATED, ~12:10 UTC) — log-query alert, result >100.
3. **Connector Unavailable Pods — connector-44300-fs-1632** (CRITICAL/ACTIVATED, ~12:03 UTC) — deployment unavailable pods for 10 min.

**Pattern:** a mass pod-unavailability event ~11:45 UTC triggered 14+ simultaneous CRITICAL issues across connectors (19501, 19503, 19504, 20274, 37781, 11998, 12183, 14299, 12005), platform services (clips-prod, clips-frontel), and queue-eagle-eye-consumer — most still ACTIVATED. Likely the same underlying cause behind the elevated fleet error counts.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol: per-site patrol log volume (run per site_id; 7d confirm for 41158/45061)
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-{site_id}-autopatrol%'
SINCE 12 hours ago

-- AutoPatrol: autopatrol-server ERROR count
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server' AND level = 'ERROR'
SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site (cluster-wide CASE FACET)
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND message LIKE '%CNCTNFAIL%'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET CASES(WHERE message LIKE '%41158%' AS 'site_41158',
             WHERE message LIKE '%41178%' AS 'site_41178',
             WHERE message LIKE '%40672%' AS 'site_40672',
             WHERE message LIKE '%45061%' AS 'site_45061',
             WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol: connector-side autopatrol ERRORs by container
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet: overnight ERROR counts
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15

-- Alert delivery: canonical container ERROR counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver',
    'cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name LIMIT 10

-- New Issues: mcp__newrelic__list_recent_issues (account 3421145, 24h),
-- filtered client-side to createdAt >= now - 12h
```
</details>

## End
