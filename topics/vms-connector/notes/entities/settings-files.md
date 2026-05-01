---
title: "settings-files"
type: entity
topic: vms-connector
tags: [vms-connector, configuration, json, camera-settings, monitoring]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
  - topics/engineering-process/notes/concepts/code-review-checklist.md
  - topics/product-roadmap/notes/syntheses/b2b2b-vs-b2b-go-to-market.md
incoming_updated: 2026-05-01
---

# settings-files

A working directory (not a formal package) containing JSON configuration files used to configure individual **[[vms-connector|VMS connector]]** instances. Each file represents the full settings payload for a specific connector deployment at a customer site. The repo contains 150+ `connector-{id}_preview_settings.json` files, along with older-format VCH JSON files and miscellaneous debugging artifacts.

## File Naming Convention

- `connector-{id}_preview_settings.json` -- the standard format; `{id}` is the numeric connector ID matching the admin system.
- `{name}_vch.json` and `{name}-vch.json` -- older "VCH" (Video Channel) format files for specific sites.
- Other files include screenshots, spreadsheets, and test scripts used during debugging sessions -- this directory doubles as an ad-hoc scratch space.

## JSON Structure

Each settings file is a deeply nested JSON document with three top-level sections:

### `customer`
Site-level metadata and behavior configuration:
- **Identity**: `name`, `display_name`, `parent_group_id`, `timezone`, `lead`, `demo` flag.
- **VMS integration**: `integration_type` (e.g. `"milestone"`, `"genetec"`, `"axis"`), `management_server_ip`, `event_server_ip`, `software_type`, ports (`ssl_port`, `http_port`, `stream_port`, `alert_port`), credentials (`basic_username`, `basic_password`).
- **Storage**: `store_local`, `store_local_directory`, `store_samples_local`, `store_samples_local_directory`.
- **Processing**: `fps_and_processing_sample_period`, `composite_model`, confidence thresholds (`low_confidence_max`, `low_confidence_interval`, `low_confidence_max_frames`).
- **Motion detection**: `use_motion`, `use_motion_envera`.
- **Telemetry**: `use_new_relic`, `use_datadog`.
- **Healthcheck**: deployment count, alert/report emails, cell numbers, sensitivity level.
- **Camera status**: toggles for `no_motion` and `unable_to_connect` alerting.

### `monitoring`
CloudWatch-style alarm definitions:
- `fps_alarms` -- frame-rate drop detection with threshold, period, and missing-data handling.
- `processing_alarms` -- processing latency alerts.
- `heartbeat` -- period and bandwidth tracking.
- `motion` -- motion metric alarms.
- `cpu` / `memory` -- optional resource monitoring toggles.

### `recording_servers`
An array of VMS recording server entries, each containing:
- `server_ip` -- the recording server address.
- `cameras[]` -- per-camera configuration including `guid`, `camera_name`, `admin_camera_id`, resolution (`width`, `height`), codec settings, and a `streams` object defining production inference pipelines.

Each camera's `streams.production.threat` block configures the AI model pipeline: model name, desired input size, FPS, confidence thresholds, polygonal exclusion/inclusion zones, crop regions, black-box regions, S3 bucket for frame storage, alert window length, area filters, stationary object filtering, and per-class detection metrics (intruder, vehicle, bike) with IoU thresholds.

## How These Files Are Used

Settings files are loaded by the vms-connector at startup to configure camera ingestion, inference routing, alarm thresholds, and VMS event dispatch. They can be previewed and edited through the admin UI or pulled directly from S3/DynamoDB for debugging.
