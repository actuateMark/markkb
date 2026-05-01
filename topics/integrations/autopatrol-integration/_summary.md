---
title: "AutoPatrol Integration"
type: summary
topic: integrations/autopatrol-integration
tags: [integration, autopatrol, immix, patrol]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# AutoPatrol Integration

AutoPatrol (part of the Immix platform) is a remote video-patrol and monitoring service. Security operators schedule patrols of camera devices; Actuate runs AI analytics on the resulting video streams and raises threat alerts back into AutoPatrol. The integration spans all three component layers: puller, alarm sender, and integration calls.

## Components

### AutoPatrolAlertSender

Defined in [[actuate-alarm-senders]] at `immix/autopatrol_sender.py`. Extends `EventListenerAlertSender`. On each detection the sender maps the Actuate label (intruder, vehicle, fire, etc.) to an `AutoPatrolDetectionCodeEnum` code, optionally builds an annotated image URL via S3, and calls `AutoPatrolAPI.raise_patrol_alert()` to push the threat into AutoPatrol. It also persists alerts to DynamoDB via `AutoPatrolDAO`.

### AutopatrolWebSocketStreamPuller

Defined in [[actuate-pullers]] at `socket/autopatrol_websocket_stream_puller.py`. Extends `AvUrlFramePuller`. Requests a WebSocket stream URL from the AutoPatrol API (`get_patrol_stream`), then connects over WebSocket to consume an fMP4 stream. The puller parses `ftyp`/`moov` init segments and `moof`/`mdat` fragments using [[pyav-entity|PyAV]], decodes frames, applies downsampling based on highest configured FPS, and submits them to the pipeline. Supports automatic reconnection with configurable retry count and sleep intervals.

### AutoPatrolAPI -- Integration Calls Module

Defined in [[actuate-integration-calls]] at `autopatrol/autopatrol_api.py`. A REST client for the AutoPatrol HTTP API. Key operations: manage contracts (get, activate), manage schedules (get, activate, deactivate), manage patrols (start, end, update status), get sites and devices, request device stream URLs, request device preview/reference images, and raise patrol alerts with threat data. All requests include `Ocp-Apim-Subscription-Key` and `Ocp-Apim-Subscription-Id` headers. An optional `Region-Override: EU` header supports European deployments.

### AutoPatrol Enums

`autopatrol_enums.py` defines status enums (`ContractStatusEnum`, `PatrolStatusEnum`, `ScheduleStatusEnum`, `TierEnum`) and detection codes (`AutoPatrolDetectionCodeEnum`) covering person, vehicle, bike, crowd, fire, smoke, postal vehicles, and VCH health-check codes.

## Auth Method

API-key authentication. The `api_key` is passed to `AutoPatrolAPI` at init time and sent as `Ocp-Apim-Subscription-Key` on every request. A `subscription_id` header identifies the Actuate tenant (`actuate` for prod, `actuate-develop` for dev).

## Key Config Fields

Configuration lives in `AutoPatrolConfig` (extends `PatrolConfig`) within [[actuate-config]]'s `immix/immix_config.py`: `api_key`, `tenant_id`, `site_id`, `schedule_id`, `patrol_id`, `region` (US/EU), `stage` (prod/develop), `duration`, `batch_size`, `queue_stage`, `endpoint_stage`, `retry_sleep_time`.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- AutoPatrolAlertSender
- [[actuate-pullers]] -- AutopatrolWebSocketStreamPuller
- [[actuate-integration-calls]] -- AutoPatrolAPI and enums
- [[actuate-config]] -- AutoPatrolConfig / AutoPatrolConnectorConfig in the immix config module
- [[vms-connector]] -- orchestrates patrol runs, batch-processes cameras per schedule
