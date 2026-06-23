---
title: "Overnight Health Check 2026-06-11"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-11
updated: 2026-06-11
author: kb-bot
status: attention
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-11

## Summary

Pipeline core is healthy (no autopatrol-server errors, no CNCTNFAILs), but three items need eyes: site 45061's autopatrol CHM cronjob is missing, `queue-evalink-consumer` logged 672 errors, and 221 critical NR incidents fired overnight (largely pod/deployment churn from the rearchitecture rollout).

## Issues Found

- **Site 45061 — missing autopatrol cronjob.** Patrol-log count 123 (5-16x below peers); repeated VPA errors `CronJob rearchitecture/connector-45061-autopatrol-1025-chm-cronjob does not exist` (13:05–14:15 UTC). Scheduling gap — verify schedule 1025 config / cronjob deployment for 45061.
- **`queue-evalink-consumer` — 672 ERRORs in 12h** (threshold 20). Alert-delivery path; drill into message pattern. Other alert consumers clean.
- **Connector fleet — all top-15 containers >100 errors** (range 1,137–2,357). Top 3: connector-31563 (2,357), connector-30025 (2,272), connector-35025 (2,080). May be baseline noise vs. genuine unhealth — needs message-level triage to distinguish.
- **221 critical NR incidents** overnight, dominated by pod/deployment readiness conditions — consistent with rearchitecture rollout instability rather than independent root causes.
- **(Off-list) `connector-46767-autopatrol-1102-chm-cronjob` — 8 errors.** Not a tracked site; noted for awareness.

## AutoPatrol

**Scope:** cluster_name='Connector-EKS', SINCE 12h, sites 41158 / 41178 / 40672 / 45061 / 37837.

**Patrol log counts per site** (filter `message LIKE '%patrol%'`):

| Site | Patrol-log count (12h) |
|------|----------------------|
| 40672 | 2,042 |
| 37837 | 1,048 |
| 41158 | 869 |
| 41178 | 691 |
| 45061 | **123** ⚠ |

All five sites produced patrol traffic — no 0-patrol sites. 45061 is anomalously low (see flag).

**autopatrol-server errors:** 0 ✅
**CNCTNFAIL per site:** 0 across all five sites ✅
**Connector-side autopatrol errors:** only `connector-46767-autopatrol-1102-chm-cronjob` (8) — off tracked-list. No errors for any tracked site's autopatrol containers.

**Flags:**
- ⚠ **45061:** low patrol count + missing CHM cronjob (`connector-45061-autopatrol-1025-chm-cronjob does not exist`, repeated VPA errors today). Next step: `kubectl get cronjob -n rearchitecture | grep 45061` and verify the autopatrol schedule config for 45061.
- ⚠ **46767 (off-list):** 8 CHM cronjob errors.
- ✅ No autopatrol-server errors; no CNCTNFAILs; sites 40672 / 37837 / 41158 / 41178 healthy.

## Connector Fleet

ERROR counts SINCE 12h, FACET container_name, top 15. **Every container in the top 15 exceeds the 100-error flag threshold** (lowest is 1,137).

| Container | ERROR count |
|---|---|
| connector-31563 | 2,357 |
| connector-30025 | 2,272 |
| connector-35025 | 2,080 |
| connector-17328 | 1,511 |
| connector-12686 | 1,509 |
| connector-17331 | 1,507 |
| connector-17327 | 1,417 |
| connector-17379 | 1,415 |
| connector-23430 | 1,412 |
| connector-19527 | 1,409 |
| connector-10729 | 1,404 |
| connector-36679 | 1,290 |
| create-detection-window | 1,277 |
| connector-8075 | 1,145 |
| connector-38919 | 1,137 |

Top 3 (31563 / 30025 / 35025) sit notably above the pack. `create-detection-window` (1,277) is a platform service, not a site connector — worth a separate look. Caveat: FACET returns only top 15; additional sub-threshold containers likely exist. Recommend message-level triage on the top 3 to separate noisy-single-error from genuinely-unhealthy.

## Alert Delivery

ERROR counts SINCE 12h for canonical alert containers:

| Container | ERROR count | Status |
|---|---|---|
| queue-evalink-consumer | 672 | ⚠ FLAGGED (>20) |
| queue-eagle-eye-consumer | 2 | OK |
| smtp-frame-receiver | 0 | OK |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

Zero-count containers confirmed clean (FACET suppresses zero buckets). `queue-evalink-consumer` is the sole flag — 672 errors warrants a drill into the dominant message pattern.

## New Issues

**232 NR incident events** opened/transitioned SINCE 12h.

- **Severity:** Critical 221 (95%) · Warning 11 (5%) · High/Low 0.
- **Top conditions:** Pod is not ready (123, critical) · Deployment has unavailable pods (48, critical) · ReplicaSet missing desired pods (34, critical) · Container Memory % too high (9, warning) · High CPU (4) · SMTP files discarded (4).
- **Top 3 entities by unique incident count:** Log query aggregate (7) · djangoq-long-running (4) · connector-14299_rearchitecture (3).

Caveat: NrAiIncident counts events, not unique issues. The 205 pod/deployment events likely represent shared rollout churn (entities cluster on the `_rearchitecture` suffix) rather than 205 independent root causes.

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
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

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
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol Q4: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- AutoPatrol Q5: 45061 patrol message patterns (follow-up)
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%' AND message LIKE '%45061%'
SINCE 12 hours ago FACET message LIMIT 5

-- Connector fleet errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

-- NR Issues
FROM NrAiIncident SELECT count(*) FACET priority SINCE 12 hours ago LIMIT 10
FROM NrAiIncident SELECT count(*) FACET conditionName, priority SINCE 12 hours ago LIMIT 10
FROM NrAiIncident SELECT uniqueCount(incidentId) FACET targetName SINCE 12 hours ago LIMIT 5
```

</details>

## End
