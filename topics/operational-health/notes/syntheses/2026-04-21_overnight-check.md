---
title: "Overnight Health Check 2026-04-21"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Overnight Health Check 2026-04-21

## Summary

Degraded — autopatrol fleet-wide patrol queue is empty (all 4 active sites executing cronjobs but finding zero patrols to run), site 41158 has no autopatrol container at all, 81 new NR issues opened in 12h (73 CRITICAL — widespread "unavailable pods"), and connector-11202 / connector-deploy / create-detection-window are each over 8k errors.

## Issues Found

- **CRITICAL — Autopatrol scheduling broken fleet-wide.** All 4 sites with active cronjobs (41178, 40672, 45061, 37837) exit every run with "No patrols to run after all attempts." Zero patrols executed in 12h across the fleet. Upstream scheduler likely down — prod `autopatrol-server` container is absent from logs (only `autopatrol-server-dev` present).
- **CRITICAL — Site 41158 has no autopatrol container.** No logs match `*41158*autopatrol*` in 12h. K8s CronJob may have been deleted or never created.
- **CRITICAL — 73 CRITICAL NR issues opened in 12h.** "Deployment has unavailable pods" firing across connector-14170, 11998, 12005, 20139, 27056, 37256, 41190 — looks like a widespread pod availability incident.
- **HIGH — connector-11202: 11,104 ERRORs in 12h** (5x the next-highest site connector). Needs triage.
- **HIGH — connector-deploy: 10,881 ERRORs in 12h.** Platform deployer service hammering errors.
- **HIGH — create-detection-window: 8,791 ERRORs in 12h.** Platform service; may cascade into [[detection-pipeline|detection pipeline]] failures.
- **HIGH — queue-evalink-consumer: 724 ERRORs in 12h** (~60/hr). Alert delivery degradation for [[evalink-components|Evalink]] integration.
- **INFO — smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker logged zero ERRORs.** Confirm these containers are actually running, not just silently absent.

## AutoPatrol

| Site ID | Autopatrol Container | Patrol Log Events | "No patrols" warnings | Status |
|---------|---------------------|-------------------|----------------------|--------|
| 41158 | **None found** | 0 | — | **CRITICAL: no container** |
| 41178 | `connector-41178-autopatrol-350-chm-cronjob` | 168 | 36 | WARN: all runs empty |
| 40672 | `connector-40672-autopatrol-1027-chm-cronjob` | 168 | 36 | WARN: all runs empty |
| 45061 | `connector-45061-autopatrol-1025-chm-cronjob` | 168 | 36 | WARN: all runs empty |
| 37837 | `connector-37837-autopatrol-1028-chm-cronjob` | 168 | 36 | WARN: all runs empty |

- **Autopatrol-server errors:** 0 (prod variant absent from logs; only `autopatrol-server-dev` active — 4,359 unstructured log entries, 0 ERROR).
- **CNCTNFAIL per site:** 0 across all five sites — camera connectivity is not the cause of the empty patrol queue.
- **Connector-side autopatrol ERROR-level logs:** 0 — failures are silent at WARNING level.

**Root-cause hypothesis:** Prod `autopatrol-server` is not running. Cronjobs hit the API, get 200, find no scheduled patrols, retry 3x, exit. Sites 41178/40672/45061/37837 are firing on schedule but producing no work. Site 41158 is missing its cronjob entirely. Needs human verification of K8s state (kubectl not available in this headless session).

## Connector Fleet

All 15 containers in the top-15 by error count breached the >100 threshold — the entire top of the distribution is flagged.

| container_name | ERROR count |
|---|---|
| connector-11202 | 11,104 |
| connector-deploy | 10,881 |
| create-detection-window | 8,791 |
| connector-34920 | 4,362 |
| connector-43622 | 2,136 |
| connector-36679 | 1,753 |
| connector-17328 | 1,510 |
| connector-12686 | 1,506 |
| connector-32863 | 1,422 |
| sirix-volkswagen-boisbriand-1718 | 1,413 |
| connector-20628 | 1,410 |
| connector-32926 | 1,262 |
| connector-35025 | 1,176 |
| connector-31563 | 1,164 |
| connector-46060 | 1,152 |

Outliers: `connector-11202` and `connector-deploy` are ~5x the next-highest site connector. `create-detection-window` (platform service) at 8,791 is likely contributing to downstream [[detection-pipeline|detection pipeline]] failures across the fleet. Drill-down into message patterns recommended.

## Alert Delivery

| Container | ERROR Count | Flagged (>20) |
|---|---|---|
| queue-evalink-consumer | 724 | YES |
| queue-eagle-eye-consumer | 8 | — |
| smtp-frame-receiver | 0 | — |
| cert-manager-webhook | 0 | — |
| clips-smtp-worker | 0 | — |

`queue-evalink-consumer` at ~60 errors/hr is a sustained degradation, not a burst. Other alert-path containers are clean or silent — verify `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker` are actually running (zero rows could mean either healthy or not logging).

## New Issues

- **Total opened in 12h:** 81
- **Severity:** CRITICAL 73 / HIGH 8 / MEDIUM 0 / LOW 0
- **Top 3 by occurrence:**
  1. `connector-14170` — "Deployment has unavailable pods" — CRITICAL (8)
  2. "Envera Camera Unavailable High" — "Log query result is > 100.0" — CRITICAL (6)
  3. "Clip pipeline imbalance (received vs analyzed)" — HIGH (6)

"Unavailable pods" is firing across connector-14170, 11998, 12005, 20139, 27056, 37256, 41190, and more — a widespread pod-availability event, not isolated failures. Likely correlated with the elevated `connector-deploy` error count above.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol: per-site patrol events (scan)
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%patrol%41158%' OR message LIKE '%41158%patrol%') AS site_41158,
  filter(count(*), WHERE message LIKE '%patrol%41178%' OR message LIKE '%41178%patrol%') AS site_41178,
  filter(count(*), WHERE message LIKE '%patrol%40672%' OR message LIKE '%40672%patrol%') AS site_40672,
  filter(count(*), WHERE message LIKE '%patrol%45061%' OR message LIKE '%45061%patrol%') AS site_45061,
  filter(count(*), WHERE message LIKE '%patrol%37837%' OR message LIKE '%37837%patrol%') AS site_37837
WHERE cluster_name = 'Connector-EKS'
AND (container_name LIKE '%autopatrol%' OR namespace LIKE '%autopatrol%')
SINCE 12 hours ago

-- AutoPatrol: server ERROR count
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
AND container_name = 'autopatrol-server' AND level = 'ERROR' SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%41158%' OR message LIKE '%41158%CNCTNFAIL%') AS site_41158,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%41178%' OR message LIKE '%41178%CNCTNFAIL%') AS site_41178,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%40672%' OR message LIKE '%40672%CNCTNFAIL%') AS site_40672,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%45061%' OR message LIKE '%45061%CNCTNFAIL%') AS site_45061,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%37837%' OR message LIKE '%37837%CNCTNFAIL%') AS site_37837
WHERE cluster_name = 'Connector-EKS' SINCE 12 hours ago

-- AutoPatrol: connector-side errors
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- AutoPatrol: confirmed per-site patrol counts
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
AND container_name IN (
  'connector-37837-autopatrol-1028-chm-cronjob',
  'connector-41178-autopatrol-350-chm-cronjob',
  'connector-40672-autopatrol-1027-chm-cronjob',
  'connector-45061-autopatrol-1025-chm-cronjob'
) AND message LIKE '%patrol%'
SINCE 12 hours ago FACET container_name LIMIT 10

-- Connector fleet errors
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery errors
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- NR Issues: list_recent_issues, 12h window, account 3421145
```

</details>

## End
