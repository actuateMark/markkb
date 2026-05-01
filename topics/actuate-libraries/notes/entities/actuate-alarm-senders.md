---
title: "actuate-alarm-senders"
type: entity
topic: actuate-libraries
tags: [library, integration-alerting, alarm-sender, alert-dispatch, factory-pattern]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/dev-workflow.md
  - topics/actuate-libraries/notes/concepts/observer-pattern.md
  - topics/actuate-libraries/notes/entities/actuate-connector-observers.md
  - topics/actuate-libraries/notes/entities/actuate-daos.md
  - topics/actuate-libraries/notes/entities/actuate-event-listener.md
  - topics/actuate-libraries/notes/entities/actuate-integration-calls.md
  - topics/actuate-libraries/notes/entities/actuate-notification.md
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
incoming_updated: 2026-05-01
---

# actuate-alarm-senders

Runtime alert sender implementations for the Actuate AI video analytics platform. Each sender class consumes a config object from `actuate-config` and dispatches alerts to external systems -- alarm monitoring platforms, email, SMS, webhooks, and VMS event servers. Version **1.9.15**.

## Purpose

This library is the outbound alerting layer of the Actuate pipeline. When a detection observer decides an alert should fire, it calls into a `MultiAlertSender` which fans out to every configured sender for that camera stream. The library provides a base abstraction, a factory for instantiation, and 27 concrete sender implementations.

## Sender Class Hierarchy

```
BaseAlertSender (abstract)
  |-- send(alert_data: AlertData)           # Must implement
  |-- send_chm(chm_alert_data)              # Optional: CHM alerts
  |-- send_clips(clips_alert_data)          # Optional: clip alerts
  |
  +-- AttachmentAlertSender (abstract)       # Adds S3 frame retrieval + annotation
  |     +-- EventListenerAlertSender         # Adds SQS event queue dispatch
  |           +-- ImmixAlertSender
  |           +-- MilestoneAlertSender
  |           +-- HikcentralAlertSender
  |           +-- EagleEyeAlertSender
  |           +-- EvalinkAlertSender
  |           +-- LisaAlertSender
  |           +-- AutoPatrolAlertSender
  |     +-- AvigilonAlertSender, BoldAlertSender, CommandCentralAlertSender,
  |         CrisisGoAlertSender, DWAlertSender, EnveraAlertSender,
  |         GenetecAlertSender, PatriotAlertSender, SentinelAlertSender,
  |         SesAlertSender, SoftguardAlertSender, StagesAlertSender,
  |         SureviewAlertSender, TCPAlertSender, UsMonitoringAlertSender,
  |         WebhookAlertSender
  |
  +-- SmsAlertSender (direct)
  +-- SnsTopicAlertSender (direct)
  +-- VerifierAlertSender (direct)
  +-- SysAidAlertSender (direct)
```

## All Alarm Sender Types (27 total)

| Sender | Integration Target | Dependencies |
|---|---|---|
| `ImmixAlertSender` | Immix alarm monitoring | `ses_client`, `s3_dao`, `enriched_frames_dao` |
| `BoldAlertSender` | [[bold-components|Bold]] alarm monitoring | `ses_client`, `s3_dao`, `enriched_frames_dao` |
| `SesAlertSender` | Email via AWS SES | `ses_client`, `s3_dao`, `enriched_frames_dao` |
| `SmsAlertSender` | SMS via AWS SNS | `sns_client` |
| `SnsTopicAlertSender` | Generic SNS topic | `sns_client` |
| `VerifierAlertSender` | Human verifier queue | `sns_client` |
| `AvigilonAlertSender` | Avigilon NVR | -- |
| `GenetecAlertSender` | Genetec Security Center | -- |
| `DWAlertSender` | Digital Watchdog NVR | -- |
| `EnveraAlertSender` | Envera monitoring | -- |
| `CrisisGoAlertSender` | CrisisGo platform | -- |
| `StagesAlertSender` | Stages platform | -- |
| `MilestoneAlertSender` | Milestone XProtect | -- |
| `WebhookAlertSender` | Generic HTTP webhook | -- |
| `CommandCentralAlertSender` | Motorola CommandCentral | -- |
| `TCPAlertSender` | Raw TCP socket alert | -- |
| `SureviewAlertSender` | SureView Immix | `ses_client`, `s3_dao`, `enriched_frames_dao` |
| `SentinelAlertSender` | [[sentinel-components|Sentinel]] monitoring | `s3_dao`, `enriched_frames_dao` |
| `PatriotAlertSender` | Patriot monitoring | `s3_dao`, `enriched_frames_dao` |
| `UsMonitoringAlertSender` | US Monitoring | `s3_dao`, `enriched_frames_dao` |
| `SoftguardAlertSender` | [[softguard-components|Softguard]] monitoring | `s3_dao`, `enriched_frames_dao` |
| `EagleEyeAlertSender` | Eagle Eye Networks | -- |
| `AutoPatrolAlertSender` | AutoPatrol/Immix Connect | `connector_config`, `dao_manager`, `camera_config` |
| `EvalinkAlertSender` | [[evalink-components|Evalink]] alarm platform | -- |
| `LisaAlertSender` | LISA alarm receiver | -- |
| `HikcentralAlertSender` | [[hikcentral-components|HikCentral]] VMS | -- |
| `SysAidAlertSender` | SysAid (CHM only) | -- |

## Key Classes

**`MultiAlertSender`** -- The main orchestrator. One instance per camera stream holds all configured senders. On `trigger_alert()` it builds an `AlertData` object, writes a detection window to DynamoDB, and submits `send()` to a single-worker thread pool for each sender. The serialized thread pool prevents overwhelming external systems.

**`AlertData`** / **`ChmAlertData`** / **`ClipsAlertData`** -- Data transfer objects carrying alert context: window ID, labels, confidence, frame dimensions, alert URL, customer/camera metadata, model response, timestamps, and zone information.

**`CameraStatusSender`** -- Handles non-detection alerts: video loss, no-motion, unable-to-connect, spray/scene-change, and health status updates.

## Factory Functions

- `build_alert_senders(connector_config, camera_config, configs, sns_client, ses_client, dao_manager)` -- Main factory mapping config type to sender instance.
- `build_chm_alert_senders(configs, sns_client, ses_client)` -- Factory for Camera Health Monitoring alerts (currently `SysAidAlertSender`).
- `build_clips_alert_senders(configs, ses_client, dao_manager)` -- Factory for video clip analysis alerts (`ImmixAlertSender`, `LisaAlertSender`).

## Dependencies

- `actuate-integration-calls` -- VMS-specific API calls
- `actuate-inference-objects`, `actuate-viz` -- Detection rendering
- `actuate-daos` -- S3, DynamoDB, enriched frames
- `actuate-event-listener` -- SQS event queue dispatch
- `actuate-pipeline-objects` -- `ImageDataPacket`, `WindowDataPacket`
- `actuate-secrets`, `actuate-threadpool`, `pytz`

## Consumers

- [[actuate-connector-observers]] -- observers hold `MultiAlertSender` references and call `trigger_alert()`
- `vms-connector` -- builds alert senders via the factory during initialization

## Notable Patterns

- **Factory pattern** with `isinstance` dispatch on config type -- each `BaseAlertSenderConfig` subclass maps to exactly one sender class.
- **Thread-pool serialization** -- `MultiAlertSender` uses a 1-worker `ActuateThreadPoolExecutor` to serialize sends per camera, avoiding race conditions and rate-limiting issues.
- **Three alert categories**: detection alerts (`AlertData`), camera health alerts (`ChmAlertData`), and clip analysis alerts (`ClipsAlertData`) -- each with its own factory and data class.
- Senders that need frame images extend `AttachmentAlertSender` which retrieves and annotates frames from S3/DynamoDB.
