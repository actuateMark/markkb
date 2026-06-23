---
title: "Overnight Health Check 2026-06-02"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-02
updated: 2026-06-02
author: kb-bot
status: warn
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-02

## Summary

Pipelines functioning but degraded: autopatrol patrols flowing on all 5 sites with clean CNCTNFAILs and zero server errors, but the connector fleet shows broad elevated ERROR volume (15+ containers over threshold), 17 NR issues opened overnight (15 CRITICAL — mostly connector pod-unavailability), and `queue-evalink-consumer` flagged for alert-delivery errors.

## Issues Found

- **NR Issues:** 17 issues opened in 12h, 15 CRITICAL / 2 HIGH. Dominated by 11 connectors with "Deployment has unavailable pods", plus "Envera Camera Unavailable High" and an "Invalid Token Spike" auth anomaly.
- **Connector fleet:** All 15 returned containers exceed the 100-error threshold. Top offender `connector-11202` at 8,228 errors (~1.6x the next). `create-detection-window` (platform service, not a connector) at 2,144 — worth separate triage.
- **Alert delivery:** `queue-evalink-consumer` at 328 errors (>20 threshold, ~27/hr sustained). Other four alert containers reported zero ERROR rows.
- **AutoPatrol connector-side cronjobs:** 222 ERROR events across 7 cronjob containers; 4 containers (connectors 35830–35832) sit at exactly 48 each — uniformity suggests a per-execution recurring failure.
- **AutoPatrol site 45061:** patrol count 155, ~6–8x below peer sites (834–1,250). Non-zero but anomalous — confirm expected cadence.

## AutoPatrol

**Patrol counts per site (12h):**

| Site ID | Patrol Log Events |
|---------|-------------------|
| 37837   | 1,250             |
| 40672   | 1,036             |
| 41178   | 857               |
| 41158   | 834               |
| 45061   | 155 ⚠️            |

No site at 0 patrols. Site 45061 flagged as a soft warning — well below peers; verify it isn't partially stalled or simply running fewer cameras / a slower schedule.

**Autopatrol-server errors:** 0 (clean).

**CNCTNFAIL per site (12h):**

| Site ID | CNCTNFAIL |
|---------|-----------|
| 41158   | 1         |
| 41178   | 0         |
| 40672   | 0         |
| 45061   | 0         |
| 37837   | 0         |

No site over the >5 threshold (max = 1 on 41158).

**Connector-side autopatrol cronjob errors:**

| Container | ERROR Count |
|-----------|-------------|
| connector-35832-autopatrol-260-chm-cronjob | 48 |
| connector-35831-autopatrol-310-chm-cronjob | 48 |
| connector-35831-autopatrol-259-chm-cronjob | 48 |
| connector-35830-autopatrol-309-chm-cronjob | 48 |
| connector-35831-autopatrol-313-chm-cronjob | 12 |
| connector-46767-autopatrol-1102-chm-cronjob | 12 |
| connector-35831-autopatrol-343-chm-cronjob | 6 |

222 total. The four uniform 48-count containers point to a structured per-run failure (connectors 35830–35832). Suggested follow-up: sample ERROR messages from `connector-35832-autopatrol-260-chm-cronjob` to classify (timeout / auth / app exception).

**Note:** Pod-level / k8s checks from the full `/autopatrol-overnight-check` skill were skipped — kubectl + kubefwd MCP unavailable in this headless session. NR-only.

## Connector Fleet

ERROR counts, `cluster_name='Connector-EKS'`, FACET container_name, LIMIT 15, SINCE 12h. **All 15 returned containers exceed the 100-error flag threshold:**

| Container | Error Count |
|---|---|
| connector-11202 | 8,228 |
| connector-32249 | 5,011 |
| connector-32220 | 3,423 |
| connector-31563 | 2,272 |
| connector-42616 | 2,257 |
| create-detection-window | 2,144 |
| connector-42270 | 1,981 |
| connector-12686 | 1,509 |
| connector-17331 | 1,500 |
| connector-17328 | 1,498 |
| connector-19527 | 1,416 |
| connector-34883 | 1,412 |
| connector-23430 | 1,412 |
| connector-17379 | 1,412 |
| connector-36381 | 1,411 |

`connector-11202` is a clear outlier (60% above #2). Ranks 8–15 cluster tightly in the 1,411–1,509 band — suggests a shared systemic error rather than site-specific faults. `create-detection-window` (platform service) at 2,144 warrants its own drill-down. Caveat: LIMIT 15 may hide additional >100 containers below the cutoff.

## Alert Delivery

ERROR counts for canonical alert-pipeline containers, SINCE 12h:

| Container | ERROR Count | Status |
|---|---|---|
| queue-evalink-consumer | 328 | ⚠️ FLAGGED (>20) |
| queue-eagle-eye-consumer | 0 | zero rows — idle or not logging |
| smtp-frame-receiver | 0 | zero rows — idle or not logging |
| cert-manager-webhook | 0 | zero rows — idle or not logging |
| clips-smtp-worker | 0 | zero rows — idle or not logging |

`queue-evalink-consumer` at ~27 errors/hr sustained — check for upstream feed issues / repeated connection failures. The four zero-row containers are not necessarily unhealthy (may be idle or logging below ERROR).

## New Issues

17 unique NR issues opened in the last 12h. **Severity:** CRITICAL 15, HIGH 2, MEDIUM 0, LOW 0.

**Top 3 by entity/impact:**

1. **Connector "Deployment has unavailable pods" (CRITICAL) — 11 connector entities:** 705-fs-630, 44300-fs-1492, 20274, 20139-fs-344, 19504, 19503, 19501, 14299, 12183, 12005, 11998. Accounts for 11 of the 15 CRITICALs (threshold: unavailable pods >0 for 10 min). Possible shared node group / rolling-restart correlation worth checking.
2. **"Envera Camera Unavailable High" (CRITICAL):** log-query alert exceeded 100 — high volume of Envera cameras offline. No specific entity (log-based condition).
3. **"Invalid Token Spike (auth anomaly)" (CRITICAL):** log-query result exceeded 30 sustained 15 min — elevated invalid auth tokens; possible credential rotation, replay, or misconfigured client.

**HIGH issues:** `djangoq-long-running` (memory working set >90% for 5+ min); POST /analyze 499 errors (client-side cancellations).

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- Patrol counts per site
SELECT filter(count(*), WHERE message LIKE '%41158%') AS site_41158,
       filter(count(*), WHERE message LIKE '%41178%') AS site_41178,
       filter(count(*), WHERE message LIKE '%40672%') AS site_40672,
       filter(count(*), WHERE message LIKE '%45061%') AS site_45061,
       filter(count(*), WHERE message LIKE '%37837%') AS site_37837
FROM Log WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
SINCE 12 hours ago;

-- Autopatrol-server errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago;

-- CNCTNFAIL per site
SELECT filter(count(*), WHERE message LIKE '%41158%') AS site_41158,
       filter(count(*), WHERE message LIKE '%41178%') AS site_41178,
       filter(count(*), WHERE message LIKE '%40672%') AS site_40672,
       filter(count(*), WHERE message LIKE '%45061%') AS site_45061,
       filter(count(*), WHERE message LIKE '%37837%') AS site_37837
FROM Log WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago;

-- Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10;

-- Connector fleet overnight errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15;

-- Alert delivery health
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago;

-- NR Issues opened (12h)
FROM NrAiIssue SELECT count(*) WHERE event IN ('open','activate') FACET priority SINCE 12 hours ago;
```

</details>

## End
