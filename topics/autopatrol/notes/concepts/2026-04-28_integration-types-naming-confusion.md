---
title: "Operational Pitfall: Three Patrol-Style Integration Types, Misleading Container Names"
type: concept
topic: autopatrol
tags: [integration-types, naming-conventions, dashboard-signals, operational-debugging, vms-connector, nrql-filters, autopatrol]
jira: "AUTO-566, AUTO-567"
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
incoming:
  - topics/autopatrol/notes/syntheses/2026-04-28_failed-patrol-investigation-handoff.md
  - topics/camera-health-monitoring/notes/concepts/2026-04-28_vch-chm-vs-autopatrol-naming.md
  - topics/personal-notes/notes/daily/2026-04-28.md
incoming_updated: 2026-05-08
---

# Three Patrol-Style Integration Types, One K8s Naming Convention

vms-connector supports three "patrol-style" integration types that run as K8s CronJobs. They share the same container naming suffix (`-chm-cronjob`), which creates a dangerous ambiguity when querying logs, dashboards, or alerts. **Only ONE type runs ML models.**

## The Three Types

| Integration | Runs ML? | What It Does | Container Discriminator |
|---|---|---|---|
| **AutoPatrol** | **Yes** | Scheduled inference patrols on customer cameras; detections sent as alerts to Immix | Contains `-autopatrol-N-` segment: `connector-<site>-autopatrol-<N>-chm-cronjob` |
| **VCH** (Visual Camera Health) | No | Connectivity, FPS, blur, scene-change checks; raises camera health alerts to Immix | Plain name: `connector-<site>-chm-cronjob` (no `-autopatrol-` segment) |
| **CHM** (Camera Health Monitor) | No | Similar to VCH; subset of health monitoring features | Plain name: `connector-<site>-chm-cronjob` |

## The Operational Hazard

When building NR queries, dashboards, or alerting rules that filter for ML-related signals (e.g., "sites with no models configured"), you must explicitly filter to **only AutoPatrol containers**. Otherwise you get 10–15x false positives.

**Example:** During AUTO-566 (2026-04-28), a fleet-wide sweep for the warning "No models configured for site, appending dummy model" returned **30 sites**. After correcting the filter to `container_name LIKE '%-autopatrol-%'`, the real count was **2 production sites** + 1 staging.

**Why:** VCH and CHM intentionally have empty `models` arrays in their settings — that's not misconfiguration, it's by design. They don't run inference. An unfiltered log query treats them as silent failures.

## Where the Confusion Comes From

The naming convention dates to when CHM was the primary patrol-style workload. When AutoPatrol was added, it reused the cronjob suffix but added a middle segment (`-autopatrol-N-`) to disambiguate within the same customer. The suffix itself provides no hint that one type runs ML and two don't.

See [[2026-04-28_dashboard-signal-dummy-model-fallback-24h]] for the defensive dashboard signal added to catch this in the future.

## How to Filter Correctly

In NRQL queries targeting ML-related signals:

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%-autopatrol-%'    -- THIS IS KEY
  AND message LIKE '%No models configured%'
SINCE 24 hours ago
```

For health-only queries (VCH/CHM analysis), do the opposite:

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%-chm-cronjob'     -- Plain names only
  AND NOT container_name LIKE '%-autopatrol-%'  -- Exclude AutoPatrol
SINCE 24 hours ago
```

## Related Incidents

- [[2026-04-28_dashboard-signal-dummy-model-fallback-24h]] — defensive monitoring signal added to catch recurring ML misconfiguration (auto-created after AUTO-566)
- AUTO-567 — follow-up task to document this distinction in vms-connector CLAUDE.md

## Cross-Reference

See the entry point log in `connector_factories/shared/factory.py:45` where the "appending dummy model" warning is emitted.
