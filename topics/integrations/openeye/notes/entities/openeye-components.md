---
title: "OpenEye Integration Components"
type: entity
topic: integrations/openeye
tags: [integration, openeye, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# OpenEye Integration Components

## OpeneyeConnectorConfig

`OpeneyeConnectorConfig` extends `BaseConnectorConfig` and is the primary library component for the OpenEye integration. It builds the customer configuration and camera streams using the standard `make_camera_streams` pattern. The config is structured around two deployment modes: on-premises (direct NVR access) and cloud-based via OpenEye Web Services (OWS).

### OpenEyeCustomerConfig

Extends `CustomerConfig` with fields that branch based on the deployment mode:

**OWS mode** (`use_ows = True`):
- `device_id`: The NVR device ID (from `nvr_id`).
- `tenant_id`: Initialized to empty string, set at runtime.
- `ows_username` / `ows_password`: Credentials for the OWS cloud API.
- `ows_base_url`: Hardcoded to `"actuate.api.gp4f.com"` -- the OpenEye cloud endpoint.
- `stream_type`: From `openeye_stream_type`, defaults to `"low"`.

**On-premises mode** (`use_ows = False`):
- `server_ip`, `server_port`: Direct NVR connection details.
- `username`, `password`: Local NVR credentials.

**Motion settings** (both modes):
- `use_motion`: Optional flag enabling motion-triggered analysis.
- `motion_port`, `http_motion_port`: Ports for receiving motion events (on-prem).
- `motion_interval`: Duration to analyze after motion is detected.
- SQS-based motion is also supported via `use_motion_sqs`, which sets `use_motion = True` and requires `motion_interval`.

### OpenEyeCamera

Extends `CameraConfig` with a default `openeye_fps` of 5 frames per second. No additional camera-specific fields are defined beyond the base class.

### OpenEyeCameraStream and OpenEyeFeatureDeployment

Both extend their respective base classes without adding custom fields.

## Alarm Sending and Frame Pulling

OpenEye does not have a dedicated alarm sender class in `actuate-alarm-senders`. Alert delivery for OpenEye deployments uses the generic URL-based puller infrastructure. The URL puller modules (`url_puller_motion_onoff.py`, `av_url_puller.py`, `url_puller_motion.py`) contain references to OpenEye in their implementations, indicating that OpenEye streams are consumed via HTTP URL polling or RTSP depending on the deployment mode. In OWS mode, stream URLs are obtained through the OWS cloud API; in on-premises mode, streams are accessed directly from the NVR.

## Integration Calls

There is no dedicated OpenEye integration-calls module. API interactions with the OWS cloud platform (authentication, stream URL retrieval, camera discovery) are handled in the connector factory code within `vms-connector` rather than in the shared library.
