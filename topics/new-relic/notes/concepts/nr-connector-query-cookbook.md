---
title: "New Relic Connector Query Cookbook"
type: concept
topic: new-relic
author: kb-bot
created: 2026-04-16
updated: 2026-04-16
tags: [nrql, connector, cookbook, queries, new-relic, monitoring, autopatrol]
outgoing:
  - _index.md
  - topics/engineering-process/notes/concepts/2026-04-27_headless-mcp-bypass.md
  - topics/engineering-process/notes/entities/agent-nrql-investigator.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/fleet-architecture/notes/concepts/observability-and-tracing.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/new-relic/_summary.md
  - topics/new-relic/notes/concepts/actuate-nr-data-model.md
  - topics/new-relic/notes/concepts/nr-log-level-strategy.md
incoming:
  - _index.md
  - topics/autopatrol/notes/syntheses/2026-04-28_failed-patrol-investigation-handoff.md
  - topics/engineering-process/notes/concepts/2026-04-27_headless-mcp-bypass.md
  - topics/engineering-process/notes/entities/agent-nrql-investigator.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/fleet-architecture/notes/concepts/observability-and-tracing.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-observability.md
  - topics/new-relic/_summary.md
incoming_updated: 2026-05-30
---

# New Relic Connector Query Cookbook

Ready-to-use NRQL query templates for common operational tasks on the [[vms-connector]] fleet. All queries follow the [[nrql-efficient-query-patterns|efficiency patterns]] -- named attributes, tight scoping, small limits. Account ID: `3421145`.

Replace `{site_id}` with the numeric site ID (e.g., `34692`). Replace `{time_window}` with an appropriate `SINCE` clause.

---

## Is This Site Healthy?

**Goal:** Quick health check for a single connector site.

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
SINCE 30 minutes ago
FACET level LIMIT 5
```

**Healthy:** `INFO` count in the thousands/tens of thousands, `WARNING` low single digits or zero, `ERROR` zero or very low.

**Investigate if:** `ERROR` count is non-trivial (>10 in 30 min), or `INFO` count is zero (container may not be running).

---

## What Errors Is This Connector Throwing?

**Goal:** Identify the specific error messages for a site.

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
  AND level = 'ERROR'
SINCE 1 hour ago
FACET message LIMIT 10
```

**Healthy:** Zero results or only transient connection errors (see [[nr-log-level-strategy]]).

**Investigate if:** `NoneType` errors (inference failure), `pipeline run aborted` (puller crash), or any novel error message.

**Drill into a specific error:**

```sql
SELECT message, timestamp FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
  AND level = 'ERROR'
  AND message LIKE '%NoneType%'
SINCE 1 hour ago LIMIT 5
```

---

## Is Inference Working?

**Goal:** Verify the ML model server is responding to this connector.

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
  AND (message LIKE '%yolo call%'
    OR message LIKE '%inference%'
    OR message LIKE '%task results%')
SINCE 30 minutes ago
FACET message LIMIT 10
```

**Healthy:** `task results` messages appearing regularly. `yolo call failed` at zero or very low count.

**Investigate if:** `yolo call failed with status code 500` is high -- the model server may be overloaded. Check model server health:

```sql
SELECT count(*) FROM K8sContainerSample
WHERE containerName = 'model-server'
SINCE 30 minutes ago
FACET status LIMIT 5
```

---

## How Is the Deploy Going?

**Goal:** Compare staging vs production error rates during a release.

```sql
-- Staging error rate
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
FACET message LIMIT 10

-- Production error rate (excludes staging)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND container_name NOT LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
FACET message LIMIT 10
```

**Regression detection with COMPARE WITH:**

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
COMPARE WITH 30 minutes ago
FACET message LIMIT 10
```

**Healthy:** Current window error count is equal to or lower than previous window. No new error message types appearing.

**Investigate if:** Any message count significantly higher in the current window -- this is a regression candidate. See [[connector-fleet-monitoring]] for the full release monitoring cadence.

---

## AutoPatrol Health Check

**Goal:** Verify autopatrol runs completed successfully overnight.

```sql
SELECT count(*), latest(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND namespace LIKE 'autopatrol%'
  AND (message LIKE '%task results%'
    OR message LIKE '%All camera threads have ended%'
    OR message LIKE '%patrol%complet%')
SINCE 8 hours ago
FACET container_name LIMIT 20
```

**Healthy:** Each scheduled site shows both `task results` (inference ran) and `All camera threads have ended` (clean shutdown).

**Investigate if:** A site that should have run is missing entirely (cronjob may not have fired), or only `task results` appear without a clean shutdown (patrol may have been killed mid-run).

---

## CHM Healthcheck Status

**Goal:** Check if the connector health monitoring system is reporting.

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND (container_name LIKE '%healthcheck%'
    OR message LIKE '%healthcheck%'
    OR message LIKE '%health check%')
SINCE 1 hour ago
FACET container_name, level LIMIT 10
```

**Healthy:** Regular INFO-level healthcheck messages appearing.

**Investigate if:** No healthcheck messages at all, or ERROR-level healthcheck failures.

---

## Memory / Resource Issues

**Goal:** Check for OOMKilled pods or memory pressure.

```sql
-- K8s container restarts (potential OOMKill)
SELECT latest(restartCount), latest(status) FROM K8sContainerSample
WHERE clusterName = 'Connector-EKS'
  AND containerName LIKE 'connector-%'
SINCE 1 hour ago
FACET containerName LIMIT 10

-- Log-level memory errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND (message LIKE '%OOMKilled%'
    OR message LIKE '%memory%'
    OR message LIKE '%MemoryError%'
    OR message LIKE '%Cannot allocate memory%')
  AND level IN ('ERROR', 'WARNING')
SINCE 2 hours ago
FACET container_name, message LIMIT 10
```

**Healthy:** `restartCount` at 0 or stable (not incrementing). No memory error log lines.

**Investigate if:** `restartCount` is climbing for a container, or `OOMKilled` / `MemoryError` messages appear.

---

## Alert Delivery (SQS / Alarm Sender)

**Goal:** Verify alert pipeline is delivering notifications.

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND (container_name LIKE '%alarm%'
    OR container_name LIKE '%sqs%'
    OR container_name = 'queue_immix_consumer'
    OR message LIKE '%alarm sent%'
    OR message LIKE '%notification%delivered%')
SINCE 1 hour ago
FACET container_name, level LIMIT 10
```

**Healthy:** `queue_immix_consumer` showing INFO-level processing messages. No ERROR-level delivery failures.

**Investigate if:** ERROR count is elevated, or the consumer container shows no recent activity (may have crashed).

---

## Fleet-Wide Discovery

**Goal:** See all active containers and their log volume.

```sql
SELECT uniqueCount(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
SINCE 1 hour ago
FACET container_name LIMIT 30
```

**Goal:** See all active namespaces.

```sql
SELECT uniqueCount(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
SINCE 1 hour ago
FACET namespace LIMIT 30
```

---

## actuate_admin Containers in NR

**Confirmed via direct query 2026-04-29.** Admin-side logs in NR are scattered across multiple containers — there is **no single "admin pod" container_name**. Avoid these traps:

- **`prod_camera_admin` does not exist** — agents have hallucinated this name in past investigations. Direct `count(*)` returns zero.
- **The production camera-admin Django web pod is NOT forwarded to NR.** This is the pod that serves API requests like `PATCH /api/auto_patrol_product_metric/{id}/` and runs the synchronous + threaded portions of `AutoPatrolProductMetric.save()` → `deploy_schedule_settings()` → `_delayed_deploy_settings()` thread. **Its logs are NOT queryable here.** Use CloudWatch / kubectl / admin pod stderr for those.
- Only **staging** has a queryable admin web pod: `container_name = 'camera-admin-staging'` in `namespace = 'camera-admin-staging'` (~4.7k logs/24h).

**What IS in NR for admin-side debugging (verified live volumes 2026-04-29):**

| Container | 24h log volume | What it is | When to query |
|---|---|---|---|
| `djangoq` | ~210k | Django Q background workers (production). Runs scheduled jobs like `schedules_redeploy`, batch operations. | Scheduled / cron-driven admin work. Does NOT include the `_delayed_deploy_settings` thread (raw `Thread`, not django-q task) |
| `autopatrol-server` | ~9.5k | SQS consumer that processes patrol task results, writes patrol summaries to S3, calls Immix `update_patrol`. | Patrol completion lifecycle, [[immix-vendor-api|Immix API]] responses (incl. `update patrol response: ...`) |
| `camera-admin-staging` | ~4.7k | Stage admin web pod. Mirrors prod admin code paths but only for stage traffic. | Verifying admin-side fixes on stage before prod |
| `admin-auto-onboarding-schools` | ~8.6k | Onboarding cronjob for schools integration | Schools-specific onboarding issues |
| `admin-auto-onboarding-federated` | ~5.4k | Federated onboarding cronjob | Federated auth / multi-tenant issues |
| `admin-auto-onboarding-vpn-checker` | ~5.2k | VPN reachability checker | Network connectivity issues for onboarded sites |
| `admin-auto-onboarding-gun` | ~4.8k | Gun-detection product onboarding | Gun-product-specific onboarding |
| `admin-auto-onboarding-group-site` | ~70 | Group/site onboarding | Customer-group provisioning |
| `actuate-admin-rds` | ~220 | DB / migration layer | Schema migrations, DB connectivity |
| `djangoq-scaler` | ~10 | KEDA autoscaler for djangoq | Scaling events on the worker pool |

**Standard query template for admin-side investigations:**

```sql
SELECT message, timestamp FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'djangoq'  -- or other admin container per table above
  AND message LIKE '%<search_term>%'
SINCE 1 hour ago LIMIT 20
```

**Time-window guidance:** Scoped queries to a single admin container resolve fine for 24h windows. Unscoped fleet-wide LIKE queries against admin containers time out at >2 days (NRDB:1109). Always scope to `container_name`.

**Observability gap callout:** Customer save attempts on [[actuate-config]] (PATCH `/api/auto_patrol_product_metric/{id}/`) hit the production camera-admin web pod whose logs are NOT in NR. To debug "customer save didn't propagate" issues:
- Check `djangoq` for any post-save background task triggered by the save
- Check `autopatrol-server` for any patrol-side downstream effect
- For the actual web request and the `_delayed_deploy_settings` thread output, you need CloudWatch on the admin pod or admin pod stderr via kubectl

This gap should be tracked separately — forwarding the prod web pod logs to NR would close it. See AUTO-566 for context where this gap blocked investigation.

**Stage workaround for autopatrol deploy debugging:** `camera-admin-staging` DOES log autopatrol settings deploys. Useful for reproducing config-sync issues with full traceability. The key log lines are:

- `INFO settings_generator Uploading settings to: <key>, len: <bytes>` — fired by `_deploy_settings` → `SettingsGenerator.deploy_settings_autopatrol` (`settings_generator.py:1027`). One per S3 PUT.
- `RuntimeError: <container_name> error in settings generation: <messages>` — fired by `generate_autopatrol` (`settings_generator.py:1010-1013`) when `self.messages` accumulated errors. **This is the signature of the silent-failure mode in `_delayed_deploy_settings` thread.** If the `RuntimeError` propagates up through the thread and dies in stderr, no S3 PUT happens.

```sql
-- Catch deploy errors on stage:
SELECT message FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'camera-admin-staging'
  AND (message LIKE '%error in settings generation%'
    OR message LIKE '%Traceback%'
    OR (message LIKE '%settings_generator%' AND level = 'ERROR'))
SINCE 7 days ago LIMIT 20

-- All autopatrol uploads for a stage site:
SELECT message, timestamp FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'camera-admin-staging'
  AND message LIKE '%Uploading settings to: staging-connector-<site>-autopatrol-%'
SINCE 1 day ago LIMIT 50
```

---

## Related

- [[nrql-efficient-query-patterns]] -- the efficiency rules these queries follow
- [[actuate-nr-data-model]] -- attribute reference for building custom queries
- [[nr-log-level-strategy]] -- interpreting ERROR vs WARNING vs INFO
- [[connector-fleet-monitoring]] -- deployment monitoring cadence and patterns
