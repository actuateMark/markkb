---
title: "actuate-monitoring"
type: entity
topic: actuate-libraries
tags: [library, health-monitoring, cloudwatch, newrelic, heartbeat, alarms, metrics, new-relic, dynamodb]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/dev-workflow.md
  - topics/actuate-libraries/notes/entities/actuate-admin-api.md
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-libraries/notes/entities/actuate-daos.md
  - topics/actuate-libraries/notes/entities/actuate-secrets.md
  - topics/actuate-platform/notes/entities/alertviewer.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
incoming_updated: 2026-05-01
---

## Purpose

actuate-monitoring (v1.1.4) provides process-level monitoring for connector deployments. It creates CloudWatch/[[new-relic|New Relic]] alarms, publishes heartbeat data to DynamoDB, and tracks bandwidth, motion percentage, and alert activity. The library supports multiple monitoring backends through an abstract base class.

## Key Classes

### `ActuateMonitor` (base)

Abstract base class defining `monitor_processes(is_container, is_eks)` -- the entry point that concrete monitors must implement.

### `CloudwatchMonitor`

The primary active monitor. On startup:

1. Writes an `awslogs.conf` file for the CloudWatch Logs agent.
2. Waits 5 minutes for data to accumulate.
3. Creates CloudWatch metric alarms based on `settings["monitoring"]`:
   - **Motion alarm** -- fires when `Motion Percentage` drops to zero (site likely crashed).
   - **Processing alarms** -- fires when processing speed exceeds real-time threshold for a given FPS.
   - **FPS alarms** -- fires when average FPS drops below 50% of desired.
   - **CPU/Memory underutilisation alarms** -- (ECS containers only) alerts when resource usage falls below 50% of reserved.
4. Starts a heartbeat thread (`put_heartbeat`) that periodically:
   - Reads bandwidth from nethogs (EC2) or ECS Container Insights.
   - Reads motion percentage and alert counts from CloudWatch custom metrics.
   - Updates the DynamoDB `Heartbeat` table with `bandwidth_usage`, `last_sample_time`, `motion_percentage`, `last_alert_time`, `last_motion_time`.
   - Publishes bandwidth as a custom CloudWatch metric.

### `NewRelicMonitor`

Alternative monitor using [[new-relic|New Relic]] NRQL queries for metrics. On startup, removes any existing mute rules (downtime) from [[new-relic|New Relic]] via GraphQL mutation, then enters a heartbeat loop writing to the DynamoDB `Heartbeat` table. Queries [[new-relic|New Relic]] for `stream_alert_total`, `motion_percentage`, `NetworkRxBytes` (ECS), and `net.rxBytesPerSecond` (EKS).

### `DummyMonitor`

Fully commented-out Datadog monitor. Preserved as historical reference for the Datadog-to-New Relic migration.

### `logger_creation`

Utility module providing `init_logger(filename, remove_previous_log, output_to_console)` for setting up file and console logging, and a `log_time_elapsed` decorator for timing functions.

## Dependencies

No Python package dependencies declared. At runtime uses: boto3, requests, [[actuate-config]] (BaseConnectorConfig), [[actuate-secrets]], [[actuate-daos]] (AdminDAO), [[actuate-admin-api]] (AdminApi).

## Consumers

vms-connector's monitoring thread. Each connector deployment runs one monitor instance that maintains the heartbeat and creates alarms for the site.

## Notable Patterns

- **Multi-backend**: The abstract base allows swapping CloudWatch for [[new-relic|New Relic]] without changing the connector code.
- **DynamoDB heartbeat table**: All monitors write to the same `Heartbeat` DynamoDB table, which the admin dashboard reads to show site health.
- **Alarm auto-provisioning**: Alarms are created dynamically based on the site's settings.json monitoring config, not pre-provisioned in infrastructure-as-code.
- **5-minute startup delay**: CloudwatchMonitor sleeps 300s on start to let metric data accumulate before creating threshold-based alarms.
