---
title: "actuate-healthcheck-objects"
type: entity
topic: actuate-libraries
tags: [library, health-monitoring, healthcheck, data-objects, packets]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-healthcheck-objects (v1.1.2) defines the data model for healthcheck runs. It provides typed packet classes representing the result of each healthcheck type (connectivity, stream quality, motion status, recording, scene change, server status) along with enums and JSON encoders. These objects are created during healthcheck runs, stored in DynamoDB, and used to trigger alerts.

## Key Classes

### `HealthcheckPacket`

Base class for all healthcheck type packets. Holds:
- Camera identity (`camera_name`, `camera_id`)
- Check metadata: `hc_type`, `hc_title`, severity/tier enums, `error_msg`, `alert_topic`, `subject`, `next_steps`
- Lifecycle timestamps: `created_timestamp`, `end_timestamp`
- Status tracking: `status` (ongoing/resolved/pending/healthy), `current_run_status` (unchanged/opened/resolved)
- Email tracking: `open_email_sent`, `closed_email_sent` timestamps
- Frame keys: `background_frame_key`, `detected_frame_key`
- `valid` property -- defaults to True, set to False via `override_valid()` when a check fails

Supports rehydration from `previous_run_data` dict for continuity across healthcheck cycles.

### `HealthcheckDataPacket`

Composite object representing a full healthcheck run for a single camera. Contains one instance of each sub-packet: `ConnectivityPacket`, `StreamQualityPacket`, `MotionStatusPacket`, `SceneChangePacket`, `RecordingPacket`, `ServerStatusPacket`, and a `DummyPacket` for active-cam checks. Also tracks `in_alert`, `in_progress`, `error_text`, and `run_timestamp`.

Key method: `get_invalid_checks()` returns a list of HealthcheckPackets that failed validation, with conditional logic (stream/motion/recording/scene checks only run if connectivity is valid).

### Sub-Packets

Each extends `HealthcheckPacket` with type-specific logic:
- `ConnectivityPacket` -- camera reachability
- `StreamQualityPacket` -- stream bitrate/resolution validation
- `MotionStatusPacket` -- motion detection health
- `SceneChangePacket` -- sudden [[scene-change-detection|scene change detection]]
- `RecordingPacket` -- recording status verification
- `ServerStatusPacket` -- VMS server reachability
- `AlertDataPacket` -- alert payload carrier

### Enums

- `StatusEnum` -- general status values
- `HealthCheckTypeEnum` -- healthcheck type identifiers (connectivity, stream_quality, etc.)
- `HealthcheckTitleEnum` -- display titles for healthcheck types
- `HealthcheckPacketStatusEnum` -- UNCHANGED / OPENED / RESOLVED
- `HealthcheckSeverityEnum` -- High / Medium / Low / Healthy
- `HealthcheckTierEnum` -- Error / Warning / Info / Resolved

### JSON Encoding

`HealthcheckEncoder` and `HealthcheckDataEncoder` handle serialisation of the packet hierarchy, stripping Python name-mangled prefixes from private attributes and converting `Decimal` to float.

## Dependencies

None. This is a pure data-object library with zero external dependencies.

## Consumers

[[actuate-daos]] (`HealthcheckDAO` stores these), [[actuate-healthmonitoring]] (creates and evaluates them), vms-connector healthcheck workers, [[actuate-config]] (`HealthcheckDataPacket` imports `CameraConfig` and `CustomerConfig`).

## Notable Patterns

- **Previous-run rehydration**: Packets accept a `previous_run_data` dict in their constructor, allowing healthcheck state to persist across runs without an ORM.
- **Conditional check cascading**: `get_invalid_checks()` skips stream/motion/recording checks when connectivity itself has failed, preventing false positives.
- **Name-mangled serialisation**: The custom JSON encoders strip `__ClassName` prefixes from private attributes, producing clean JSON keys.
