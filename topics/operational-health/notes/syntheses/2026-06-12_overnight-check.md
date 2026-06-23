---
title: "Overnight Health Check 2026-06-12"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-12
updated: 2026-06-12
author: kb-bot
status: warn
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-12

## Summary

Mostly healthy core pipelines, but several items need attention: site 45061 ran zero patrols (missing CronJob), a connector-pod-unavailability wave drove 35 CRITICAL NR issues, two connector containers are error outliers (11202, 30022), and queue-evalink-consumer logged 430 errors.

## Issues Found

- **AutoPatrol — site 45061 has ZERO patrols in 12h.** VPA recommender repeatedly logs that CronJob `connector-45061-autopatrol-1025-chm-cronjob` does not exist (firing ~every 10 min). Patrol CronJob appears deleted or never created. Verify the autopatrol schedule/CronJob in the `rearchitecture` namespace for site 45061.
- **Connector fleet — error outliers.** `connector-11202` at 14,009 errors (≈2× next) and `connector-30022` at 7,915 errors stand out well above the ~1,400–2,240 baseline cluster. Worth targeted investigation.
- **Alert delivery — queue-evalink-consumer at 430 errors** (threshold >20). All other alert-delivery containers clean.
- **NR Issues — pod-unavailability wave.** 38 issues opened (35 CRITICAL / 3 HIGH); ~32 are the same "Deployment has unavailable pods" condition across many connectors, suggesting a cluster-wide rollout/availability event. Also one "FPS 3 Low" (connector-9214) and one "High CPU" node alert.

## AutoPatrol

autopatrol-server is clean: **0 ERRORs** in the last 12h. **CNCTNFAIL counts are zero across all five target sites.** Patrol log volumes for sites 40672 (2,059), 37837 (1,053), 41158 (758), and 41178 (694) are healthy.

**Flag — site 45061: zero confirmed patrols.** Its 94 "patrol" log hits are entirely VPA recommender errors about a missing CronJob (`connector-45061-autopatrol-1025-chm-cronjob`), not patrol-run events. The 5 autopatrol-server lines mentioning "45061" actually belong to site 47738 (key-string collision). No autopatrol pod activity for 45061 in the window — recommend verifying the CronJob/schedule deployment in the `rearchitecture` namespace.

Connector-side autopatrol errors: a single isolated error in `connector-46767-autopatrol-1102-chm-cronjob` (unrelated site); no autopatrol errors for any of the five target sites.

| Site ID | Patrol log count | CNCTNFAIL | Status |
|---------|------------------|-----------|--------|
| 40672 | 2,059 | 0 | Healthy |
| 37837 | 1,053 | 0 | Healthy |
| 41158 | 758 | 0 | Healthy |
| 41178 | 694 | 0 | Healthy |
| 45061 | 0 (94 hits = VPA errors) | 0 | **FLAG — no patrols** |

## Connector Fleet

All 15 containers in the top-15 ERROR facet exceed the >100 threshold. Two clear outliers; positions 4–15 cluster tightly (~1,391–1,651), likely a shared error type / common polling/reconnect pattern rather than individual site failures.

| Rank | Container | ERROR Count |
|------|-----------|-------------|
| 1 | connector-11202 | 14,009 |
| 2 | connector-30022 | 7,915 |
| 3 | connector-31563 | 2,240 |
| 4 | connector-35025 | 1,651 |
| 5 | connector-12686 | 1,510 |
| 6 | connector-17331 | 1,508 |
| 7 | connector-17328 | 1,504 |
| 8 | connector-36679 | 1,501 |
| 9 | sirix-volkswagen-boisbriand-1718 | 1,418 |
| 10 | connector-17327 | 1,414 |
| 11 | connector-19527 | 1,412 |
| 12 | connector-23430 | 1,410 |
| 13 | connector-17379 | 1,407 |
| 14 | connector-10729 | 1,401 |
| 15 | connector-47778 | 1,391 |

Priority follow-up: `connector-11202` and `connector-30022`.

## Alert Delivery

Only one alert-delivery container logged errors in the window.

| Container | ERROR Count | Flag |
|-----------|-------------|------|
| queue-evalink-consumer | 430 | **FLAG (>20)** |
| queue-eagle-eye-consumer | 0 (no rows) | — |
| smtp-frame-receiver | 0 (no rows) | — |
| cert-manager-webhook | 0 (no rows) | — |
| clips-smtp-worker | 0 (no rows) | — |

Caveat: zero-row containers may genuinely have no errors or may not be emitting logs under those exact names in the window. A bare `FACET container_name` existence check (no level filter) would confirm if any are silently down.

## New Issues

38 NR issues opened SINCE 12 hours ago.

- **Severity distribution:** CRITICAL 35, HIGH 3, MEDIUM 0, LOW 0.
- **Dominant condition:** ~32 of the 35 CRITICAL are "Deployment has unavailable pods" (query result > 0.0 for 10 min) across many connector deployments (connector-44300-fs-1591, connector-37781, connector-20274, +~30 more) — likely a cluster-wide or rollout event.

**Top 3 by entity:**
1. **connector-9214** — "FPS 3 Low" (< 1.5 for 15 min) — CRITICAL. Low FPS; possible camera/stream delivery problem.
2. **ip-10-10-22-94.us-west-2.compute.internal** — "High CPU" (> 85.0 for 5 min) — CRITICAL. EC2 node in Connector-EKS CPU-saturated.
3. **Multiple connectors** — "Deployment has unavailable pods" — CRITICAL. The bulk of the wave.

The single notable HIGH: "POST /analyze 499 errors" — log-based alert on 499 (client disconnect / upstream timeout) to the analyze endpoint.

Caveats: NrAiIssue events reflect lifecycle events (opened/closed/acked), so 38 may include re-opened events; `entityNames` was null on all rows (entity names parsed from titles). To assess the pod-unavailability wave: `FROM K8sDeploymentSample SELECT latest(unavailableReplicas) FACET deploymentName WHERE clusterName='Connector-EKS' SINCE 12 hours ago`.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol Q1: patrol counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10

-- AutoPatrol Q2: autopatrol-server errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- AutoPatrol Q3: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10

-- AutoPatrol Q4: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name LIMIT 15 SINCE 12 hours ago

-- Alert delivery errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- NR Issues opened (via list_recent_issues + NrAiIssue aggregation), SINCE 12 hours ago
```

</details>

## End
