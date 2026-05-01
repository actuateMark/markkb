---
title: "OpenEye Integration"
type: summary
topic: integrations/openeye
tags: [integration, vms, openeye, vms-connector]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# OpenEye Integration

OpenEye is a cloud-managed video surveillance platform providing NVR/DVR hardware and the OWS (OpenEye Web Services) cloud portal for remote camera access. Actuate integrates with OpenEye as a video source, pulling camera feeds for AI analytics. OpenEye supports two connectivity modes: direct on-premise access and cloud-based OWS streaming.

## Components

### OpeneyeConnectorConfig

Defined in [[actuate-config]] at `connector/openeye/openeye_config.py`. Extends `BaseConnectorConfig` with:

- **`OpenEyeCustomerConfig`** -- supports two connectivity modes:
  - **Direct mode** (default): uses `server_ip`, `server_port`, `username`, `password` to connect to the on-premise OpenEye NVR directly.
  - **OWS mode** (`use_ows: true`): connects via the OpenEye cloud service at `actuate.api.gp4f.com`. Uses `ows_username`, `ows_password`, `nvr_id` (device ID), and `openeye_stream_type` (defaults to "low" for substream). No direct server IP is needed in this mode.
  - Optional motion detection settings: `use_motion`, `motion_port`, `http_motion_port`, `motion_interval`, and `use_motion_sqs`.
- **`OpenEyeCamera`** -- extends `CameraConfig` with a default `openeye_fps` of 5 frames per second.

### Puller

No dedicated OpenEye puller class. Depending on the connectivity mode:
- **Direct mode**: The [[vms-connector]] constructs an [[rtsp-deep-dive|RTSP]] or HTTP URL from the customer config and uses the standard puller from [[actuate-pullers]].
- **OWS mode**: The connector uses the OWS cloud API to obtain a streaming URL, which is then consumed by the standard URL/[[rtsp-deep-dive|RTSP]] puller.

### Integration Calls

There is no `actuate-integration-calls` module for OpenEye. Cloud API interactions for OWS mode are handled within the [[connector-factory|connector factory]] logic in [[vms-connector]].

### Alarm Sender

No OpenEye-specific alarm sender. Alert delivery uses whichever monitoring sender is configured on the site.

## Auth Method

Two authentication paths depending on connectivity mode:

- **Direct mode**: HTTP basic auth or [[rtsp-deep-dive|RTSP]] credentials using `username`/`password` against the on-premise NVR.
- **OWS mode**: Cloud authentication using `ows_username`/`ows_password` against the OpenEye cloud API (`actuate.api.gp4f.com`). The `nvr_id` identifies which NVR/device to stream from.

## Key Config Fields

Direct mode: `server_ip`, `server_port`, `username`, `password`. OWS mode: `use_ows` (boolean), `nvr_id`, `ows_username`, `ows_password`, `openeye_stream_type` ("low"/"high"). Motion: `use_motion`, `use_motion_sqs`, `motion_port`, `http_motion_port`, `motion_interval`. Per-camera: `openeye_fps` (default 5).

## Alert Delivery

OpenEye is a video-source-only integration. There is no alert delivery back to the OpenEye platform. Alerts are routed through whatever monitoring integration is configured alongside OpenEye.

## Relationship to Other Components

- [[actuate-config]] -- OpeneyeConnectorConfig with dual-mode customer config
- [[actuate-pullers]] -- standard [[rtsp-deep-dive|RTSP]] or URL puller consumes the stream
- [[vms-connector]] -- [[connector-factory|connector factory]] handles mode selection and URL construction
- No corresponding module in [[actuate-integration-calls]] or [[actuate-alarm-senders]]
