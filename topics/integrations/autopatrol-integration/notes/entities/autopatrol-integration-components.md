---
title: "AutoPatrol Integration Components"
type: entity
topic: integrations/autopatrol-integration
tags: [integration, autopatrol-integration, alarm-sender, components, autopatrol]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md
incoming_updated: 2026-06-25
---

# AutoPatrol Integration Components

The AutoPatrol integration is the most complex monitoring integration, spanning three libraries: `AutoPatrolAlertSender` in [[actuate-alarm-senders]], `AutoPatrolAPI` in [[actuate-integration-calls]], and `AutopatrolWebSocketStreamPuller` in [[actuate-pullers]]. AutoPatrol is Immix's cloud-based virtual guard tour product that provides scheduled patrol monitoring of camera feeds.

## Class Hierarchy -- AutoPatrolAlertSender

`AutoPatrolAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. Its constructor is the heaviest of all senders, requiring `connector_config` (AutoPatrolConnectorConfig), `dao_manager` (DaoManager), and `camera_config` (CameraConfig). It instantiates an `AutoPatrolAPI` client, an `AutoPatrolDAO` for persisting alert records, and holds a reference to the `AutopatrolWebSocketStreamPuller` via `set_puller()`.

## Alert Format and Detection Codes

The `get_autopatrol_alert_type()` function maps detection labels to `AutoPatrolDetectionCodeEnum` codes: `intruder` -> `PERSON`, `vehicle` -> `VEHICLE`, `bike` -> `BIKE`, `fire`/`fire_truck` -> `FIRE`, `smoke` -> `SMOKE`, `crowd` -> `CROWD`, plus postal vehicles (`AMAZON`, `DHL`, `UPS`, `USPS`, `FEDEX`, `SCHOOL_BUS`). Unknown labels raise `ValueError`. Tag zone hits (from zone-based detection) are appended to the alert message. The sender also builds an annotated image URL by fetching the first enriched frame, drawing bounding boxes via `_annotate_frame()`, uploading to S3, and generating a presigned URL (24-hour expiry).

## Delivery Mechanism

Unlike other senders, AutoPatrol does not use an SQS FIFO queue. The `send()` method calls `AutoPatrolAPI.raise_patrol_alert()` directly via HTTP PUT to `{base_url}/Patrols/{patrol_id}/raise`. The threat payload includes `deviceId`, `streamId`, `detectionCode`, `description`, `tier` (set to `TierEnum.THREAT` = 3), and optional media (reference and current images as JPEG URLs). After the API call, the alert is persisted via `autopatrol_dao.save_autopatrol_alert()` to DynamoDB.

## AutoPatrolAPI (actuate-integration-calls)

A full REST client for the AutoPatrol platform with methods for contracts, schedules, patrols, sites, devices, and streams. Auth uses `Ocp-Apim-Subscription-Key` and `Ocp-Apim-Subscription-Id` headers (Azure API Management). EU region adds a `Region-Override: EU` header. Base URLs: `autopatrol.immixconnect.com/v` (prod) and `api.autopatrol.immixconnect.com/v/develop` (dev).

## AutopatrolWebSocketStreamPuller (actuate-pullers)

Extends `AvUrlFramePuller` to consume video via WebSocket. Calls `autopatrol_api.get_patrol_stream()` to obtain a `deviceStreamUrl`, then connects via `websockets.connect()`. Parses fMP4 (fragmented MP4) by extracting `[ftyp][moov]` init segments and `[moof][mdat]` fragments, decodes frames with [[pyav-entity|PyAV]], applies downsampling based on the highest configured FPS, and pushes frames into the processing pipeline. Supports retry logic (3 attempts with configurable sleep), healthcheck mode (single frame), and connection duration control.

## Key Config Fields

`api_key` (Azure APIM subscription key), `tenant_id`, `patrol_id`, `stage` (`"prod"` or `"develop"`), `region` (`"US"` or `"EU"`), `duration` (stream seconds), `schedule_id`, `patrol_type` (`"AutoPatrol"` or VCH). Camera-level: `device_id`, `stream_id`.
