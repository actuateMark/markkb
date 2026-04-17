---
title: "Avigilon Integration Components"
type: entity
topic: integrations/avigilon
tags: [integration, avigilon, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Avigilon Integration Components

## AvigilonAlertSender

`AvigilonAlertSender` extends `AttachmentAlertSender` and delivers detection alarms to Avigilon ACC (Access Control Central) via the ACC REST API. The `send(alert_data)` method performs a two-step HTTP workflow:

1. **Alarm lookup**: A GET request to `{api_endpoint}alarms?session={session_key}` retrieves the list of configured alarms on the ACC server. The method iterates through the returned alarm objects to find one whose `name` matches `alert_data.camera_name`, extracting its `id`.

2. **Alarm trigger**: A PUT request to `{api_endpoint}alarm` with a form-data payload containing `session` (the session key), `id` (the matched alarm ID), `action` set to `"TRIGGER"`, `note` set to the detection label, and `permission` set to `"GRANT"`.

Both requests use `verify=False` to skip SSL certificate validation and a 10-second timeout. On any exception, the method recursively retries with no retry limit or backoff -- a potential infinite-recursion risk if the server is persistently down. The `api_endpoint` is constructed in the config as `https://{server_ip}:{server_port}/mt/api/rest/v1/`.

## Avigilon Integration Calls (avigilon_utils)

The `avigilon_utils` module provides a single utility function: `camera_exists_avigilon(api_endpoint, session_key, camera_id)`. This function queries the ACC cameras endpoint (`{api_endpoint}cameras?session={session_key}`) to verify that a specific camera still exists on the NVR. It iterates through the response's `result.cameras` array, matching by camera `id`. The function is designed to be conservative -- it returns `True` on any error (HTTP failure or exception) to avoid false negatives that could incorrectly mark a camera as removed. Only a confirmed absence (camera not found in the list with a 200 response) returns `False`.

## AvigilonConnectorConfig

`AvigilonConnectorConfig` extends `BaseConnectorConfig` and builds an `AvigilonCustomerConfig` from the JSON settings. The customer config captures connection details specific to the Avigilon ACC REST API:

- **Server connection**: `server_ip`, `server_port`, `username`, `password`
- **Auth tokens**: `user_nonce` and `key` for API authentication
- **API endpoint**: Automatically constructed as `https://{server_ip}:{server_port}/mt/api/rest/v1/`
- **Motion settings**: Optional `use_motion` flag with `motion_port` and `motion_interval`. Also supports SQS-based motion via `use_motion_sqs`.

`AvigilonCamera` extends `CameraConfig` with optional `stream_type`, `resolution`, and `quality` fields parsed from `width`/`height`/`quality` keys. The `camera_id` and `base_url` are initialized to `None` and set at runtime. The config uses the standard `make_camera_streams` pattern with `AvigilonFeatureDeployment` (no custom fields) and `AvigilonCameraStream`.

## Frame Pulling

Avigilon does not have a custom puller class. Video frames are pulled via the generic RTSP/URL puller infrastructure, using stream URLs constructed from the ACC API endpoint and session credentials at connector startup time.
