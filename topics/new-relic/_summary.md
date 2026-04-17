---
title: "New Relic"
type: summary
topic: new-relic
author: kb-bot
created: 2026-04-16
updated: 2026-04-16
tags: [observability, monitoring, nrql, logs, apm, new-relic]
---

# New Relic

New Relic is Actuate's primary observability platform. All production telemetry -- logs, Kubernetes metrics, traces, and infrastructure samples -- flows into a single account and is queried using [[nrql-efficient-query-patterns|NRQL]].

## Account

| Field | Value |
|---|---|
| Account ID | `3421145` |
| Primary cluster | `Connector-EKS` |
| Query language | NRQL (New Relic Query Language) |

## What Data Flows into New Relic

Actuate's New Relic account ingests telemetry from several sources:

- **Connector fleet logs** -- Every [[vms-connector]] instance (production `connector-{site_id}`, staging `staging-connector-{site_id}`) ships structured logs via the New Relic Kubernetes integration. This is the highest-volume data source.
- **AutoPatrol logs** -- Cronjob-based patrol runs in `autopatrol*` namespaces.
- **Platform services** -- `queue_immix_consumer`, `smtp-frame-receiver`, `create-detection-window`, `webhook_listener`, `clips-prod`, `updater`, `recommender`, and others.
- **Global Guardian / Eyeforce connectors** -- Named containers like `globalguardian-*` and `eyeforce-*` running custom pipeline configurations.
- **Kubernetes infrastructure** -- `K8sContainerSample`, `K8sPodSample`, `K8sNodeSample`, `K8sDeploymentSample` and related event types provide resource utilisation data.
- **AWS Lambda** -- `AwsLambdaInvocation` and `AwsLambdaInvocationError` events from serverless functions.
- **Synthetic monitors** -- `SyntheticCheck` and `SyntheticRequest` for uptime monitoring.
- **Distributed tracing** -- `Span` and `DistributedTraceSummary` events for cross-service traces.

## Key Event Types

Discovered via `SHOW EVENT TYPES SINCE 1 day ago`:

| Event Type | Use Case |
|---|---|
| `Log` | Primary -- connector logs, platform service logs, infrastructure logs |
| `K8sContainerSample` | Container CPU/memory/restart metrics |
| `K8sPodSample` | Pod-level health and status |
| `K8sNodeSample` | Node resource utilisation |
| `K8sDeploymentSample` | Deployment replica counts and status |
| `K8sCronjobSample` | AutoPatrol and scheduled job health |
| `Span` | Distributed tracing spans |
| `Metric` | Custom and infrastructure metrics |
| `InfrastructureEvent` | Infrastructure change events |
| `NrAiIncident` / `NrAiIssue` | Alert incidents and issues |
| `SyntheticCheck` | Synthetic monitor results |
| `AwsLambdaInvocation` | Lambda function telemetry |

## Data Model (Log Attributes)

See [[actuate-nr-data-model]] for the full attribute reference. Key attributes for connector queries:

- `cluster_name` -- always `Connector-EKS` for connector fleet
- `container_name` -- identifies the site (`connector-{site_id}`) or service
- `namespace` -- Kubernetes namespace (`rearchitecture`, `connector`, `autopatrol*`, `ds-model-prod`, etc.)
- `level` -- `INFO`, `WARNING`, `ERROR`, `DEBUG`
- `message` -- the log line content
- `pod_name` -- specific pod instance

## Log Levels (24h Distribution)

| Level | Count | Notes |
|---|---|---|
| INFO | ~1.85B | Normal operations -- bulk of volume |
| WARNING | ~26.5M | Transient issues (connection retries, frame skips, yolo 500s) |
| ERROR | ~187K | Investigate -- connection failures, NoneType inference errors |
| DEBUG | 72 | Rarely enabled in production |

## Namespaces in Connector-EKS

`rearchitecture`, `connector`, `connector-tools`, `ds-model-prod`, `ds-model-dev`, `smtp`, `clips`, `monitoring`, `camera-admin-staging`, `admin-auto-onboarding`, `actuate-admin-rds`, `actuate-remote-link`, `timestamp-ocr`, `kube-system`, `istio-system`, `newrelic`, `kyverno`, `keda`, `argo-cd`, `arc-systems`, `arc-runner-set`, `spegel`, `sonarqube`, `eks-node-cordoner`

## Concept Notes

- [[nrql-efficient-query-patterns]] -- **Start here.** How to write NRQL queries that minimise token usage in Claude Code sessions.
- [[actuate-nr-data-model]] -- Complete attribute reference for Log events.
- [[nr-connector-query-cookbook]] -- Ready-to-use query templates for common operational tasks.
- [[nr-log-level-strategy]] -- What each log level means at Actuate and how to triage.

## Related

- [[new-relic]] (entity note) -- platform overview and integration points
- [[connector-fleet-monitoring]] -- deployment monitoring patterns derived from real releases
- [[vms-connector]] -- connector architecture
- [[actuate-instrumentation]] -- custom telemetry emission library
