---
title: "Overnight Health Check 2026-06-04"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-04
updated: 2026-06-04
author: kb-bot
status: warn
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-04

## Summary

Degraded — autopatrol end-patrol calls to Immix are failing fleet-wide (HTTP 400, 222 ERROR logs), alert-delivery consumer `queue-evalink-consumer` is over threshold (246 errors), and 61 critical NR incidents are open (led by an "Envera Camera Unavailable" log alert and two connector deployments with unavailable pods).

## Issues Found

- **AutoPatrol end_patrol failing fleet-wide** — 7 autopatrol cronjob containers, 222 total ERROR logs, all the identical message `end_patrol exhausted 3 attempts (last status=400); patrol may remain in STARTED on Immix`. Systemic upstream [[immix-vendor-api|Immix API]] rejection; patrols likely accumulating in STARTED state.
- **Site 41158 — 0 autopatrol-container hits** — 886 general patrol-term log matches but zero when scoped to `container_name LIKE '%autopatrol%'`. Needs follow-up to confirm which container executes patrols for this site.
- **Connector fleet error volume high** — all top-15 connector containers exceed 100 ERROR logs in 12h; `connector-11202` is a 7,893-error outlier (~2.8× the next highest). LIMIT 15 means more sub-threshold containers likely exist below the cap.
- **Alert delivery — `queue-evalink-consumer` over threshold** — 246 errors (threshold >20). The other four monitored consumers/workers are clean (0 errors).
- **61 critical NR incidents open** — led by "Envera Camera Unavailable High" (20 occurrences, log alert) and connector-11998 / connector-12005 deployments with unavailable pods.

## AutoPatrol

**Account:** 3421145 | **Cluster:** Connector-EKS | **Window:** SINCE 12 hours ago. *(NR-only; kubectl/kubefwd unavailable in headless session.)*

### Patrol-related log counts per site

| Site | Patrol log count (all containers) | Autopatrol-container only |
|------|----------------------------------|---------------------------|
| 37837 | 1,117 | 312 |
| 40672 | 1,101 | 349 |
| 41158 | 886 | **0** |
| 41178 | 703 | 181 |
| 45061 | 123 | 6 |

No site is fully dark on the broad patrol-term measure, but 41158 has **0** dedicated autopatrol-container hits and 45061 is very low (6).

### Autopatrol-server error count

`container_name='autopatrol-server'` (exact) → **0 errors**. Note: no container matched this exact name — it may be renamed or not deployed in this cluster.

### CNCTNFAIL counts per site

The `CNCTNFAIL` token does not appear in any log in this cluster. Functional equivalent `Connection failed` substituted:

| Site | "Connection failed" count |
|------|---------------------------|
| 45061 | 14 |
| 41158 | 0 |
| 41178 | 0 |
| 40672 | 0 |
| 37837 | 0 |

No site exceeds the >5 CNCTNFAIL flag on a site-attributed basis except 45061 (14). Cluster-wide `Connection failed` total is ~935k but is overwhelmingly not attributed to these five site IDs by message content.

### Connector-side autopatrol errors (FACET container_name)

| Container | Errors | Message |
|-----------|--------|---------|
| connector-35830-autopatrol-309-chm-cronjob | 48 | `end_patrol exhausted 3 attempts (last status=400)` |
| connector-35831-autopatrol-259-chm-cronjob | 48 | same |
| connector-35831-autopatrol-310-chm-cronjob | 48 | same |
| connector-35832-autopatrol-260-chm-cronjob | 48 | same |
| connector-35831-autopatrol-313-chm-cronjob | 12 | same |
| connector-46767-autopatrol-1102-chm-cronjob | 12 | same |
| connector-35831-autopatrol-343-chm-cronjob | 6 | same |

**Total: 222 ERROR logs, all identical** — Immix end-patrol call returns HTTP 400 and exhausts 3 retries.

### Flags

- 🚩 **Site 41158** — 0 autopatrol-container hits; identify which container runs its patrols.
- 🚩 **All autopatrol cronjobs** — systemic `end_patrol` HTTP 400 against Immix; patrols may remain STARTED upstream.
- ⚠️ Site 45061 — low activity (6 autopatrol hits, 14 connection failures); monitor for drift to zero.
- ℹ️ No `autopatrol-server` container and no `CNCTNFAIL` token present in this sink.

## Connector Fleet

ERROR counts SINCE 12h, FACET container_name, LIMIT 15. **All 15 exceed the >100 flag.**

| Container | Errors |
|-----------|--------|
| connector-11202 | **7,893** ← outlier |
| connector-32249 | 2,857 |
| connector-31563 | 2,272 |
| connector-32220 | 2,151 |
| connector-35025 | 1,870 |
| connector-41088 | 1,697 |
| connector-17331 | 1,529 |
| connector-12686 | 1,510 |
| connector-17328 | 1,509 |
| connector-17327 | 1,414 |
| connector-23430 | 1,411 |
| connector-17379 | 1,408 |
| connector-34883 | 1,405 |
| connector-19527 | 1,405 |
| connector-10729 | 1,405 |

`connector-11202` is ~2.8× the next highest and warrants a message-pattern drill-down. LIMIT 15 caps the list — additional >100-error containers likely exist below.

## Alert Delivery

ERROR counts SINCE 12h for canonical alert-path containers:

| Container | Errors | Flag (>20) |
|-----------|--------|------------|
| queue-evalink-consumer | 246 | 🚩 YES |
| queue-eagle-eye-consumer | 0 | — |
| smtp-frame-receiver | 0 | — |
| cert-manager-webhook | 0 | — |
| clips-smtp-worker | 0 | — |

Only `queue-evalink-consumer` is over threshold (246). Zero-row containers may be clean or logging at a non-ERROR level — worth a level-agnostic spot-check if surprising.

## New Issues

**68 open incidents** SINCE 12h — **61 critical, 7 warning, 0 medium, 0 low.**

Top 3 by entity:

1. **[log alert / no entity] — "Envera Camera Unavailable High"** — CRITICAL — 20 occurrences breaching the `>100` log threshold.
2. **connector-11998 — "Deployment has unavailable pods"** — CRITICAL — 1 deployment-level + 4 pod-level `Is Ready = 0` incidents (pods 52jsr, gmkzx, hfqm8, hrh9p). Highest-impact single site.
3. **connector-12005 — "Deployment has unavailable pods"** — CRITICAL — 1 deployment-level + 1 pod-level `Is Ready = 0` (pod ztvw6).

Remaining criticals are individual pod `Is Ready = 0` alarms (connector-12183, -19505, -38597, others, 1 each). The 7 warnings: 4× "POST /analyze 499 errors" (log threshold), 2× `djangoq-long-running` memory >90%, 1× `clips-prod` CPU >90%.

*Caveat:* `NrAiIncident` counts individual incidents, not grouped issues; one NR issue can contain N incidents.

## Raw NRQL

<details>
<summary>Queries used (account 3421145, SINCE 12 hours ago)</summary>

```sql
-- Patrol counts per site
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND (message LIKE '%patrol%' OR message LIKE '%autopatrol%' OR message LIKE '%Patrol%')
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET CASES(WHERE message LIKE '%41158%' AS 'site_41158', ...) SINCE 12 hours ago LIMIT 10

-- Autopatrol-server errors
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server' AND level = 'ERROR' SINCE 12 hours ago

-- CNCTNFAIL / Connection failed per site
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND message LIKE '%Connection failed%'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET CASES(...) SINCE 12 hours ago LIMIT 10

-- Connector-side autopatrol errors
FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet errors
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- New issues
FROM NrAiIncident SELECT count(*) FACET priority WHERE event = 'open' SINCE 12 hours ago
FROM NrAiIncident SELECT count(*), latest(title) FACET entity.name, priority
  WHERE event = 'open' AND priority = 'critical' SINCE 12 hours ago LIMIT 10
```
</details>

## End
