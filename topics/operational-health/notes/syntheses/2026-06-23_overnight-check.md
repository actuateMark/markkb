---
title: "Overnight Health Check 2026-06-23"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-23
updated: 2026-06-23
author: kb-bot
status: warn
---

# Overnight Health Check 2026-06-23

## Summary

AutoPatrol pipeline is healthy (all 5 sites patrolling, zero CNCTNFAILs, zero autopatrol-server errors), but the connector fleet and alert layer show elevated noise — `queue-evalink-consumer` at 332 errors, a hot outlier connector (`connector-11202` at ~8k errors), and 42 NR issues (40 CRITICAL) dominated by "Deployment has unavailable pods."

## Issues Found

- **Alert delivery — `queue-evalink-consumer`: 332 ERRORs in 12h** (threshold 20). Other four alert containers clean.
- **Connector fleet — all top-15 containers exceed 100 errors.** `connector-11202` is a ~3x outlier at 7,965 errors; the rest cluster tightly in 1,400–1,600 (suggests a shared/baseline error pattern rather than per-connector faults — verify against historical baseline before treating as regression).
- **42 NR Issues opened (40 CRITICAL).** Overwhelming majority are "Deployment has unavailable pods" (38/40), spanning connector-template deployments and `smtp-frame-receiver-depl`. Three EC2 worker nodes also firing High CPU concurrently — possible cluster-level CPU pressure.
- **`smtp-frame-receiver-depl` had unavailable pods ≥10 min** — platform service (SMTP frame ingestion), wider blast radius than a single connector. Note: its container logged 0 ERRORs in the alert-health check, so verify whether pods have since recovered.
- Minor: 31 connector-side autopatrol cronjob errors across 4 containers (sites 46767, 47738×2, 37255) — outside the 5 monitored sites.

## AutoPatrol

NR-only check (kubectl/kubefwd unavailable in headless session). Account 3421145, `cluster_name='Connector-EKS'`, SINCE 12h.

**Patrol counts per site:**

| Site ID | Patrol message count |
|---------|---------------------|
| 40672   | 2,044               |
| 37837   | 1,026               |
| 41158   | 887                 |
| 41178   | 684                 |
| 45061   | 179                 |

All five sites active — none at zero.

**Autopatrol-server ERRORs:** 0 ✅
**CNCTNFAIL per site:** 0 across all five sites ✅
**Connector-side autopatrol cronjob errors:**

| Container | ERRORs |
|-----------|--------|
| connector-46767-autopatrol-1102-chm-cronjob | 11 |
| connector-47738-autopatrol-1136-chm-cronjob | 8 |
| connector-47738-autopatrol-1135-chm-cronjob | 8 |
| connector-37255-autopatrol-1127-chm-cronjob | 4 |

**Flags:** 0-patrol sites — none. CNCTNFAIL >5 — none. autopatrol-server errors — none. The cronjob errors above are on sites outside the monitored set; informational only.

## Connector Fleet

ERROR counts, `cluster_name='Connector-EKS'`, SINCE 12h, top 15 by container. **All 15 exceed the 100-error flag threshold.**

| Rank | container_name | ERRORs |
|------|----------------|--------|
| 1 | connector-11202 | 7,965 |
| 2 | connector-43276 | 2,755 |
| 3 | connector-31563 | 2,272 |
| 4 | connector-35025 | 1,593 |
| 5 | connector-12686 | 1,517 |
| 6 | connector-41087 | 1,517 |
| 7 | connector-17331 | 1,514 |
| 8 | connector-17328 | 1,505 |
| 9 | connector-19527 | 1,413 |
| 10 | connector-17379 | 1,413 |
| 11 | sirix-volkswagen-boisbriand-1718 | 1,412 |
| 12 | connector-39780 | 1,411 |
| 13 | connector-17327 | 1,409 |
| 14 | connector-17295 | 1,409 |
| 15 | connector-23430 | 1,405 |

`connector-11202` is the clear outlier (~3x next highest) and the priority drill-down target. The tight 1,400–1,600 cluster among the rest may reflect a shared baseline pattern — compare to prior days before declaring regression.

## Alert Delivery

ERROR counts for canonical alert-path containers, SINCE 12h:

| Container | ERRORs | Status |
|---|---|---|
| queue-evalink-consumer | 332 | ⚠️ FLAGGED (>20) |
| queue-eagle-eye-consumer | 0 | quiet |
| smtp-frame-receiver | 0 | quiet |
| cert-manager-webhook | 0 | quiet |
| clips-smtp-worker | 0 | quiet |

Only `queue-evalink-consumer` is noisy. Recommended drill-down: `FACET message` to identify the dominant error pattern.

## New Issues

NR Issues opened SINCE 12h (account 3421145; `list_recent_issues` MCP exceeded token limits, fell back to NRQL over `NrAiIssue`).

- **Total: 42** — CRITICAL: 40, HIGH: 2 (likely repeated firings of 1 distinct HIGH), MEDIUM/LOW: 0.
- **Dominant pattern:** "Deployment has unavailable pods" = 38 of 40 CRITICAL.
- **Top 3 by entity:**
  1. `smtp-frame-receiver-depl` (CRITICAL) — unavailable pods ≥10 min; platform service, wide blast radius.
  2. `connector-template-14921` / `connector-template-14920` (CRITICAL) — two template deployments firing together; possible template rollout / node-scheduling issue.
  3. `ip-10-10-35-58` / `ip-10-10-249-173` / `ip-10-10-23-158` (CRITICAL) — three EKS worker nodes breached 85% CPU ≥5 min; cluster-level CPU spike, possibly causally linked to the pod-unavailability alerts.

**Caveat:** `NrAiIssue` counts each firing; the 40 CRITICAL likely includes repeated firings of the same condition across many site-ID deployments.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol: patrol counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol: autopatrol-server errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet: ERROR counts, top 15
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name LIMIT 15 SINCE 12 hours ago

-- Alert delivery: canonical container ERROR counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

-- New Issues (fallback NRQL over NrAiIssue)
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago
FROM NrAiIssue SELECT count(*) FACET title SINCE 12 hours ago LIMIT 20
```

</details>

## End
