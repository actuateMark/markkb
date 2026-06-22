---
title: "Connector Fleet Monitoring via New Relic"
type: synthesis
topic: infrastructure
tags: [monitoring, new-relic, nrql, connector, deployment, observability, autopatrol]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/operational-health/notes/syntheses/2026-04-23_dashboard-sketch.md
  - topics/operational-health/notes/syntheses/2026-05-05_operational-dashboard-context.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-27
---

# Connector Fleet Monitoring via New Relic

Operational patterns for monitoring the [[vms-connector]] fleet during and after deployments, derived from the April 13 2026 stage release. All queries target NR account `3421145`, cluster `Connector-EKS`.

---

## Discovering Active Connectors

The fleet mixes three container name patterns in the same cluster. Know which you're looking at before drawing conclusions.

```sql
-- Enumerate all active connector namespaces/containers in the last hour
SELECT uniqueCount(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND (container_name LIKE 'connector-%'
    OR container_name LIKE 'staging-connector-%'
    OR namespace LIKE 'autopatrol%')
SINCE 1 hour ago
FACET namespace, container_name LIMIT 50
```

| Pattern | Fleet | Image |
|---|---|---|
| `connector-{site_id}` | Production | rearchitecture ECR |
| `staging-connector-{site_id}` | Staging | stage ECR |
| `autopatrol-*` cronjobs | AutoPatrol | rearchitecture ECR |

Staging containers only exist while a staging release is active. If `staging-connector-*` returns no results, the staging fleet may have already been torn down or not yet deployed.

---

## Error Monitoring

### Current error rate with regression detection

Compare the last 30 minutes against the preceding 30 to detect a regression introduced by the deploy:

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 1 hour ago
COMPARE WITH 30 minutes ago
FACET message LIMIT 20
```

For production connectors during a post-release soak:

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
COMPARE WITH 30 minutes ago
FACET container_name, message LIMIT 20
```

A clean release shows the right column (previous window) higher than or equal to the current window. Any message whose count grows significantly is a regression candidate.

---

## AutoPatrol Health

AutoPatrol patrols complete in discrete runs. Three log messages mark a healthy run:

```sql
-- Patrol completion markers — all three should appear for healthy sites
SELECT message, container_name FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND namespace LIKE 'autopatrol%'
  AND (message LIKE '%task results%'
    OR message LIKE '%All camera threads have ended%'
    OR message LIKE '%patrol%complet%')
SINCE 2 hours ago LIMIT 50
```

- **`task results`** — inference data returned for a camera segment; confirms the ML pipeline fired.
- **`All camera threads have ended`** — the patrol run wrapped up cleanly (not killed mid-flight).
- Absence of both for a site that should have patrolled overnight is a signal to investigate the cronjob.

---

## Staging vs Production

Both fleets coexist in `Connector-EKS` during a stage release window. Always scope queries explicitly — combined results will mislead error rate calculations.

```sql
-- Staging-only error count
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago

-- Production-only error count (excludes staging)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND container_name NOT LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
```

Staging connectors are the primary validation target immediately after a deploy. Production should remain stable; any error rate increase in `connector-%` (non-staging) during a stage-only release is infrastructure noise, not a code regression.

---

## Release Monitoring Cadence

| Time post-deploy | What to check | Healthy signal |
|---|---|---|
| 0–5 min | ECR workflow triggered | GitHub Actions run queued |
| 5–15 min | ECR build complete | ARM64 + x86 images pushed |
| 15–30 min | Staging connectors live | `staging-connector-*` appears in NR, 0 ERRORs |
| 30–60 min | Error regression check | COMPARE WITH query shows flat or declining counts |
| 1 hour | AutoPatrol task results | At least one `task results` message per scheduled site |
| Overnight | Soak confirmation | Error rate flat, no new ERROR message types introduced |

---

## Common Error Patterns

| Message fragment | Root cause | Action |
|---|---|---|
| `NoneType` / `shape` | Inference timeout — frame sent to ML service, response was None | Check inference service health; usually transient but spikes indicate overload |
| `pipeline run aborted` | Puller disconnected mid-run | Usually recovers on next cycle; persistent means camera stream instability |
| `unable to connect` | Camera is offline or network unreachable | Check camera status at the site; not a connector code issue |

Query to surface these patterns together:

```sql
SELECT count(*), latest(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND level = 'ERROR'
  AND (message LIKE '%NoneType%'
    OR message LIKE '%pipeline run aborted%'
    OR message LIKE '%unable to connect%')
SINCE 2 hours ago
FACET message LIMIT 10
```

---

## Related

- [[connector-library-deployment-lifecycle]] — full stage release process including the deploy steps that precede this monitoring
- [[vms-connector]] — connector architecture, site configuration, ECR image lifecycle
