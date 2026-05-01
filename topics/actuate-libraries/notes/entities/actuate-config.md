---
title: "actuate-config"
type: entity
topic: actuate-libraries
tags: [library, config-data, settings-parsing, connector, alert-config, vms-integration]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/dev-workflow.md
  - topics/actuate-libraries/notes/concepts/filter-architecture.md
  - topics/actuate-libraries/notes/concepts/inference-client-evolution.md
  - topics/actuate-libraries/notes/entities/actuate-admin-api.md
  - topics/actuate-libraries/notes/entities/actuate-daos.md
  - topics/actuate-libraries/notes/entities/actuate-healthcheck-objects.md
  - topics/actuate-libraries/notes/entities/actuate-monitoring.md
  - topics/actuate-libraries/notes/entities/actuate-tests.md
incoming_updated: 2026-05-01
---

## Purpose

actuate-config (v1.9.12) is the foundational configuration library for the Actuate platform. It parses the per-site `settings.json` file into strongly-typed Python configuration objects that the rest of the stack -- connectors, DAOs, monitoring, healthchecks -- consumes at runtime. Every [[vms-connector|VMS connector]] deployment starts by loading settings.json through this library.

## Architecture

The library is split into two major subpackages:

### `connector` -- VMS Connector Configs

The `connector` package defines the base configuration hierarchy and one subpackage per supported Video Management System (VMS). The base layer lives in `connector.base_config` and exports:

- **`BaseConnectorConfig`** -- Top-level config parsed from settings.json. Holds model configs, camera streams, region-specific S3/SQS/SNS resource identifiers, and monitoring settings. Properties include `settings_bucket`, `spray_bucket`, `detection_bucket`, `queue_url`, `newrelic_api_url`, and dozens of other AWS/telemetry endpoints set at runtime.
- **`CustomerConfig`** -- Site-level metadata: customer name, timezone, integration type, motion settings, TTL, demo flags. On non-mock initialisation it reaches out to `AdminDAO`/`AdminApi` to load the AI models list from Camera Admin.
- **`CameraConfig`** -- Per-camera settings: name, admin camera ID, motion sleep, delta noise cutoff, dewarp/panorama parameters, spray sensitivity, [[gstreamer-entity|GStreamer]] toggle, downsample flag.
- **`CameraStreamConfig`** -- Per-stream settings (FPS, resolution, stream URL).
- **`ModelConfig`** -- Inference model connection info (name, IP, port).
- **`MonitoringConfig`** -- Heartbeat period, alarm thresholds.
- **`HealthcheckConfig`** -- Healthcheck run parameters.
- **`MetricConfig`** -- Metric label/type mappings.
- **`StreamDeploymentConfig`** -- Stream deployment metadata.
- **`GenericConnectorConfig`** -- Variant of BaseConnectorConfig for non-standard integrations.

VMS-specific subpackages (avigilon, eagle_eye, exacq, genetec, hikcentral, immix, kvs, luxriot, milestone, openeye, orchid, patrol, [[rtsp-deep-dive|rtsp]], salient, smartpss, smtp, sqs_video, star4live, video, video_insight, yoursix, dw) each extend or compose these base classes to handle VMS-specific fields in settings.json.

### `alerts` -- Alert Sender Configs

The `alerts` package defines per-integration alert configuration objects. Each maps the alert-sender section of settings.json to a typed config. Supported alert integrations include: Avigilon, [[bold-components|Bold]], CommandCentral, CrisisGo, Digital Watchdog, Eagle Eye, Envera, [[evalink-components|Evalink]], Genetec, Immix, LISA, Milestone, Patriot, [[sentinel-components|Sentinel]], SES email, SMS/SNS, [[softguard-components|Softguard]], Stages, Sureview, SysAid, TCP Alert, US Monitoring, Verifier Alert, and Webhook. All derive from or are composed with `BaseAlertSenderConfig` in `shared_alert`.

## Key Classes

| Class | Module | Role |
|---|---|---|
| `BaseConnectorConfig` | `connector.base_config` | Root settings.json parser |
| `CustomerConfig` | `connector.base_config` | Site identity and behaviour flags |
| `CameraConfig` | `connector.base_config` | Per-camera parameters |
| `ModelConfig` | `connector.base_config` | Inference model endpoint |
| `ImmixAlertConfig` | `alerts.immix` | Immix integration alert settings |
| `WebhookAlertConfig` | `alerts.webhook` | Generic webhook alert settings |

## Dependencies

- **[[actuate-admin-api]] ~=1.2** -- used by CustomerConfig at init to pull AI model list from Camera Admin.
- **[[actuate-daos]] ~=3.2** -- AdminDAO used during non-mock customer config initialisation.

## Consumers

Nearly every Actuate service depends on actuate-config: vms-connector, [[actuate-healthcheck-objects]] (uses CameraConfig, CustomerConfig), [[actuate-monitoring]] (uses BaseConnectorConfig), [[actuate-tests]] (loads sample settings.json through RTSPConnectorConfig), and all connector variants.

## Notable Patterns

- **Lazy AWS resource binding**: BaseConnectorConfig declares S3/SQS/SNS endpoints as private properties with setters; the connector runtime populates them after region detection, keeping the config object serialisable at parse time.
- **settings.json is the single source of truth**: All runtime behaviour -- camera lists, model endpoints, alert routing, monitoring thresholds -- flows from this JSON file, making per-site configuration fully declarative.
- **One subpackage per VMS/alert integration**: Adding a new VMS or alert sender means adding a new subdirectory with its own config class, then registering it in the parent `__init__.py` `__all__` list.
