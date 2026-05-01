---
title: "Actuate New Relic Data Model"
type: concept
topic: new-relic
author: kb-bot
created: 2026-04-16
updated: 2026-04-16
tags: [nrql, data-model, attributes, logs, new-relic]
incoming:
  - topics/new-relic/_summary.md
  - topics/new-relic/notes/concepts/nr-connector-query-cookbook.md
  - topics/new-relic/notes/concepts/nr-log-level-strategy.md
  - topics/new-relic/notes/concepts/nr-programmatic-deep-links.md
  - topics/new-relic/notes/concepts/nrql-efficient-query-patterns.md
incoming_updated: 2026-05-01
---

# Actuate New Relic Data Model

This note documents the attributes available on `Log` events in NR account `3421145`, discovered via `SELECT keyset() FROM Log`. Knowing what attributes exist lets you craft targeted queries without running `keyset()` each session -- saving tokens and round-trips. See [[nrql-efficient-query-patterns]] for how to use these attributes efficiently.

## Core Log Attributes

These are the attributes you will use in nearly every query:

| Attribute | Type | Description |
|---|---|---|
| `message` | string | The log line content. The primary text to search/filter. |
| `level` | string | Log level: `INFO`, `WARNING`, `ERROR`, `DEBUG` (uppercase for connector logs; some services use lowercase). See [[nr-log-level-strategy]]. |
| `timestamp` | numeric | Unix epoch milliseconds. Used for ordering and time-range filtering. |
| `cluster_name` | string | Kubernetes cluster. Always `Connector-EKS` for the connector fleet. |
| `container_name` | string | Identifies the workload. Patterns: `connector-{site_id}`, `staging-connector-{site_id}`, or service names like `queue_immix_consumer`. |
| `namespace` | string | K8s namespace: `rearchitecture`, `connector`, `autopatrol*`, `ds-model-prod`, `smtp`, `clips`, `monitoring`, etc. |
| `namespace_name` | string | Alias for namespace (some log forwarders use this field instead). |
| `pod_name` | string | Specific pod instance within a deployment. |
| `pod` | string | Alias for pod_name in some log sources. |

## Kubernetes Infrastructure Attributes

| Attribute | Type | Description |
|---|---|---|
| `container_id` | string | Docker/containerd container ID |
| `container_hash` | string | Image digest hash |
| `container_image` | string | Full ECR image URI |
| `deployment` | string | K8s Deployment name |
| `image` | string | Short image reference |

## Connector Application Attributes

These appear on logs from [[vms-connector]] and related services:

| Attribute | Type | Description |
|---|---|---|
| `cameraName` | string | Camera identifier within a site (e.g., `Camera 01`, `6_pl`) |
| `caller` | string | The function or module that emitted the log |
| `err` | string | Error detail string (separate from `message`) |
| `error` | string | Alternative error field used by some services |
| `feature` | string | Feature flag or feature identifier |
| `lead` | string | Lead/operator identifier |
| `logger` | string | Python logger name |
| `thread` | string | Thread identifier |
| `response` | string | HTTP or API response content |
| `messageId` | string | Correlation message ID |
| `correlation_id` | string | Cross-service correlation ID for tracing |
| `trace.id` | string | Distributed trace ID (links to `Span` events) |

## Platform Service Attributes

These appear on logs from non-connector services:

| Attribute | Type | Description |
|---|---|---|
| `service` | string | Service name identifier |
| `taskName` | string | Task or job name (used by cronjobs, Lambda) |
| `operation` | string | Operation being performed |
| `targets` | string | Target entities for the operation |
| `resourceID` | string | AWS resource identifier |
| `streamName` | string | Kinesis/SQS stream name |

## FastAPI / HTTP Attributes

Present on logs from FastAPI services (camera-admin, monitoring-api):

| Attribute | Type | Description |
|---|---|---|
| `fastapi.method` | string | HTTP method |
| `fastapi.path` | string | Request path |
| `fastapi.route` | string | Matched route pattern |
| `fastapi.x-api-key` | string | API key used |
| `httpRequest.clientIp` | string | Client IP address |
| `httpRequest.httpMethod` | string | HTTP method (WAF logs) |
| `httpRequest.uri` | string | Request URI (WAF logs) |
| `httpRequest.host` | string | Request host header |

## AWS / Infrastructure Attributes

| Attribute | Type | Description |
|---|---|---|
| `aws.accountId` | string | AWS account ID |
| `aws.region` | string | AWS region |
| `aws.logGroup` | string | CloudWatch log group |
| `aws.logStream` | string | CloudWatch log stream |
| `function_name` | string | Lambda function name |
| `function_arn` | string | Lambda function ARN |
| `cold_start` | boolean | Lambda cold start indicator |

## New Relic Internal Attributes

| Attribute | Type | Description |
|---|---|---|
| `entity.guids` | string | NR entity GUIDs associated with the log |
| `newrelic.logs.batchIndex` | numeric | Position in the ingestion batch |
| `newrelic.logs.metadata` | string | Metadata added by NR log forwarder |
| `logtype` | string | Log type classification |
| `plugin` | string | NR ingestion plugin identifier |

## Discovering New Attributes

If you suspect a service has added new custom attributes not listed here, run:

```sql
SELECT keyset() FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
SINCE 1 hour ago
```

Scope the `keyset()` query to the specific container or namespace you are investigating -- an unscoped keyset returns hundreds of attributes from all log sources, most of which are irrelevant to your query.

## Event Types Beyond Log

The account also contains these event types (query with `SHOW EVENT TYPES`):

- **`K8sContainerSample`** -- container CPU, memory, restarts. Key attributes: `containerName`, `cpuUsedCores`, `memoryUsedBytes`, `restartCount`.
- **`K8sPodSample`** -- pod health. Key attributes: `podName`, `status`, `isReady`.
- **`K8sNodeSample`** -- node resources. Key attributes: `nodeName`, `cpuUsedCoreMilliseconds`, `memoryUsedBytes`.
- **`K8sDeploymentSample`** -- deployment status. Key attributes: `deploymentName`, `podsAvailable`, `podsDesired`.
- **`Span`** -- distributed traces. Key attributes: `name`, `duration`, `error`, `service.name`.
- **`Metric`** -- custom metrics. Queried via `FROM Metric SELECT ...` with `WHERE metricName = '...'`.

## Related

- [[nrql-efficient-query-patterns]] -- how to query these attributes without wasting tokens
- [[nr-connector-query-cookbook]] -- pre-built queries using these attributes
- [[new-relic]] -- platform overview
- [[actuate-instrumentation]] -- library that emits custom attributes
