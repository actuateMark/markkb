---
title: "Overnight Health Check 2026-04-20"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
status: degraded
---

# Overnight Health Check 2026-04-20

## Summary

Degraded — alert delivery path (`queue-evalink-consumer`) is 27× over threshold, connector fleet is broadly noisy (all top-15 containers >100 errors), cluster-level NR Issues are elevated (106 Critical in 12h), and target autopatrol site 41158 shows no `autopatrol` container activity.

## Issues Found

- **Alert delivery breach**: `queue-evalink-consumer` logged **540 ERRORs** in 12h (threshold >20). Other four alert-delivery containers are clean.
- **Connector fleet-wide noise**: All top-15 containers exceed the >100 ERROR threshold. Outliers: `connector-deploy` (**11,124**), `connector-11202` (**9,778**), `connector-34920` (4,631). Two named sites in the top 15: `sirix-volkswagen-boisbriand-1718` (1,412) and `bandit-systems-canyon-view-capital-5401` (1,239).
- **AutoPatrol target site 41158**: zero `autopatrol` container activity in 12h; only a `connector-41158-vch-761-chm-cronjob` (VCH/virtual-camera-host path) is active. Verify whether 41158 is intentionally VCH-only; if not, the autopatrol schedule is not firing.
- **AutoPatrol non-target hot spot**: site **35831** cams 259 and 310 each produced ~1,080 ERRORs — all `'NoneType' object has no attribute 'shape'` + `production yolo: Traceback`. Consistent with a model server returning null frames for this site.
- **Non-target CNCTNFAIL outliers**: `connector-35832-autopatrol-260` (96) and `autopatrol-server-dev` (66). Target sites are clean on CNCTNFAIL.
- **NR Issues**: 127 Issues / 225 Incidents opened in the window; **106 Critical**, 21 High. Dominant conditions are cluster-health (Pod not ready: 69, ReplicaSet drift: 46, Deployment unavailable pods: 39). Suggests sustained cluster-infra instability, not scattered transients.

## AutoPatrol

Scope: 5 target sites (41158, 41178, 40672, 45061, 37837) plus fleet-wide spot-checks. No kubectl available in this headless session — NR-only.

**Patrol activity per target site (autopatrol containers, 12h):**

| Site | Container | Log Lines |
|------|-----------|-----------|
| 41178 | `connector-41178-autopatrol-350-chm-cronjob` | 168 |
| 40672 | `connector-40672-autopatrol-1027-chm-cronjob` | 168 |
| 45061 | `connector-45061-autopatrol-1025-chm-cronjob` | 168 |
| 37837 | `connector-37837-autopatrol-1028-chm-cronjob` | 168 |
| **41158** | **No autopatrol container** — only `connector-41158-vch-761-chm-cronjob` active (last msg: `INFO: Patrols: <Response [200]>`) | **0** |

**`autopatrol-server`**: effectively idle (1 info log in 24h, 0 ERRORs). Healthy — server orchestrates, doesn't execute. `autopatrol-server-dev` is active (7,427 lines, 66 CNCTNFAILs) but is the dev instance.

**CNCTNFAIL**: zero on all 5 target sites. Fleet outliers: `connector-35832-autopatrol-260` (96), `connector-44346-vch-1049` (90), `autopatrol-server-dev` (66). All others <10.

**Connector-side autopatrol errors (non-target, sustained inference failure on site 35831):**

| Container | ERRORs (12h) |
|-----------|--------------|
| connector-35831-autopatrol-310-chm-cronjob | 1,086 |
| connector-35831-autopatrol-259-chm-cronjob | 1,080 |
| connector-35831-autopatrol-313-chm-cronjob | 174 |
| connector-35831-autopatrol-343-chm-cronjob | 84 |

Target sites 37837/40672/41178/45061 show only WARNINGs (36 each), no ERRORs.

## Connector Fleet

Every container in the top-15 exceeds the >100 ERROR threshold (flag ⚠):

| container_name | error_count |
|---|---|
| connector-deploy | 11,124 ⚠ |
| connector-11202 | 9,778 ⚠ |
| connector-34920 | 4,631 ⚠ |
| connector-29016 | 3,310 ⚠ |
| connector-32863 | 2,850 ⚠ |
| connector-28919 | 2,393 ⚠ |
| connector-36679 | 1,692 ⚠ |
| connector-12686 | 1,515 ⚠ |
| connector-42270 | 1,435 ⚠ |
| sirix-volkswagen-boisbriand-1718 | 1,412 ⚠ |
| connector-20628 | 1,405 ⚠ |
| connector-35025 | 1,350 ⚠ |
| connector-36681 | 1,280 ⚠ |
| bandit-systems-canyon-view-capital-5401 | 1,239 ⚠ |
| connector-32926 | 1,233 ⚠ |

`connector-deploy` and `connector-11202` are ~2× the next noisiest — likely systemic rather than site-local.

## Alert Delivery

| Container | ERRORs (12h) | Breach? |
|---|---|---|
| queue-evalink-consumer | **540** | **YES (>20)** |
| queue-eagle-eye-consumer | 4 | No |
| smtp-frame-receiver | 0 | No |
| cert-manager-webhook | 0 | No |
| clips-smtp-worker | 0 | No |

`queue-evalink-consumer` is ~27× over threshold. Suggested follow-up: `FACET message` on that container for the dominant failure pattern.

## New Issues

- **127 Issues opened** in 12h (225 underlying incidents).
- **Severity**: Critical 106, High 21, Medium 0, Low 0.
- **Top entities by incident count**:
  - `cluster-autoscaler` — 6 (Container Memory Usage %)
  - `connector-31794` — 6 (Container Memory Usage %)
  - `ip-10-10-39-154.us-west-2.compute.internal` — 5 (High CPU)
- **Top condition types**: Pod not ready (69), ReplicaSet missing desired pods (46), Deployment unavailable pods (39), Container Memory % (25), High CPU (19), Clip pipeline imbalance received vs analyzed (12).
- Open/closed resolution state is not cleanly available via NRQL; the volume + condition mix points to sustained cluster-infra instability rather than isolated app errors.

## Raw NRQL

<details>
<summary>Queries executed</summary>

```sql
-- AutoPatrol: patrol activity per target site (pattern discovered: per-site autopatrol cronjob containers)
SELECT
  filter(count(*), WHERE container_name LIKE '%connector-41158%') AS site_41158,
  filter(count(*), WHERE container_name LIKE '%connector-41178%') AS site_41178,
  filter(count(*), WHERE container_name LIKE '%connector-40672%') AS site_40672,
  filter(count(*), WHERE container_name LIKE '%connector-45061%') AS site_45061,
  filter(count(*), WHERE container_name LIKE '%connector-37837%') AS site_37837
FROM Log WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%'
SINCE 12 hours ago;

-- AutoPatrol: autopatrol-server ERRORs and level distribution
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago;

-- AutoPatrol: CNCTNFAIL per target site
SELECT
  filter(count(*), WHERE container_name LIKE '%connector-41158%') AS site_41158,
  filter(count(*), WHERE container_name LIKE '%connector-41178%') AS site_41178,
  filter(count(*), WHERE container_name LIKE '%connector-40672%') AS site_40672,
  filter(count(*), WHERE container_name LIKE '%connector-45061%') AS site_45061,
  filter(count(*), WHERE container_name LIKE '%connector-37837%') AS site_37837
FROM Log WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago;

-- AutoPatrol: CNCTNFAIL fleet-wide by container
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET container_name SINCE 12 hours ago LIMIT 10;

-- AutoPatrol: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%'
  AND level IN ('ERROR','error','WARN','warning','WARNING')
FACET container_name, level SINCE 12 hours ago LIMIT 20;

-- Connector fleet: top-15 ERROR containers
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15;

-- Alert delivery: canonical container names
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago;

-- NR Issues summary (NrAiIssue / NrAiIncident over 12h)
-- Severity + top-entity via list_recent_issues + NrAiIncident FACET entity.name
```

</details>

## End
