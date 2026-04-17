---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [observability, monitoring, nrql, nerdgraph, alerting, apm]
---

# New Relic

New Relic is Actuate's **primary observability platform**, used for application performance monitoring (APM), log aggregation, custom dashboards, and alerting. It is the first stop for debugging production issues, validating releases, and conducting overnight soak checks.

## NRQL Queries

NRQL (New Relic Query Language) is the SQL-like query language used to interrogate telemetry data across all New Relic data types (events, metrics, logs, traces). Actuate engineers use NRQL for:

- **Connector monitoring** -- Querying frame processing rates, error counts, and latency distributions for [[vms-connector]] instances across customer sites.
- **Release validation** -- Comparing error rates and latency percentiles before and after a deployment to catch regressions early.
- **Overnight soak checks** -- Running pre-defined NRQL queries each morning to verify that overnight processing completed without anomalies. These checks cover frame throughput, alert delivery latency, and inference pipeline health.

## Custom Attributes

Actuate services emit custom attributes alongside standard APM telemetry. These attributes (e.g., `customer_id`, `camera_id`, `model_version`, `connector_instance`) enable fine-grained filtering in NRQL queries. The [[actuate-instrumentation]] library standardizes how custom attributes are attached to spans and logs, ensuring consistent observability across all services.

## NerdGraph API

NerdGraph is New Relic's GraphQL API, used programmatically for dashboard management, alert condition configuration, and data export. Actuate uses NerdGraph for automated alert policy management and for pulling telemetry data into the [[shadow-test-pipeline]] analysis modules (specifically the New Relic log analysis component in `analysis/`).

## Integration Points

New Relic is deployed as a cluster service via the [[kubernetes-deployments]] infrastructure (managed by ArgoCD). The New Relic Kubernetes integration provides container-level metrics, pod health, and node resource utilization alongside application-level APM data. Alerts from New Relic feed into [[sns-to-slack]] for team notification.

## See Also

- [[actuate-instrumentation]] -- the library that standardizes telemetry emission
- [[kubernetes-deployments]] -- where New Relic is deployed as a cluster service
- [[rollout-process]] -- release validation that relies on New Relic
- [[sns-to-slack]] -- alert notification pathway
