---
title: "New Relic Connector Query Cookbook"
type: concept
topic: new-relic
author: kb-bot
created: 2026-04-16
updated: 2026-04-16
tags: [nrql, connector, cookbook, queries, new-relic, monitoring]
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

## Related

- [[nrql-efficient-query-patterns]] -- the efficiency rules these queries follow
- [[actuate-nr-data-model]] -- attribute reference for building custom queries
- [[nr-log-level-strategy]] -- interpreting ERROR vs WARNING vs INFO
- [[connector-fleet-monitoring]] -- deployment monitoring cadence and patterns
