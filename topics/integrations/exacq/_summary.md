---
title: "Exacq Integration"
type: summary
topic: integrations/exacq
tags: [integration, vms, exacq]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Exacq Integration

Exacq (exacqVision) is an enterprise video management system (VMS) from Johnson Controls used for recording and managing IP camera feeds. Actuate integrates with Exacq to pull live and recorded video for AI analytics.

## Components

### Integration Calls -- exacq_utils

Defined in [[actuate-integration-calls]] at `exacq/exacq_utils.py`. Provides two key functions:

- **`get_session_id(config)`** -- authenticates with the exacqVision server to obtain a session ID. Tries two login methods in sequence: (1) a legacy GET-based login with `responseVersion=2` that returns JSON, and (2) a newer POST-based login that parses the session ID from the HTML response via regex. Falls back to the second method if the first raises an exception.
- **`get_stream_url(config, camera_config, session_id)`** -- constructs the video stream URL for a camera. Supports three formats based on the camera's `format` field:
  - **Format 5** -- direct RTSP streaming: `rtsp://[user]:[pass]@[ip]:[stream_port]/[camera_id]`
  - **Format 7** -- HTTP live video: `http://[ip]:[port]/video.web?s=[session]&camera=[id]&format=7`
  - **Other formats** -- HTTP JPEG pull with optional width/height/quality parameters

Returns a tuple `(exacq_streaming, stream_url)` where `exacq_streaming` indicates whether the camera uses a persistent stream (formats 5/7) versus JPEG pull.

### ExacqConnectorConfig

Defined in [[actuate-config]] at `connector/exacq/exacq_config.py`. Extends `BaseConnectorConfig` with Exacq-specific typed config classes:

- `ExacqCustomerConfig` -- adds `username`, `password`, `server_ip`, `server_port`, `server` (server name), `stream_port` (for RTSP), and optional `use_motion`/`motion_interval` fields.
- `ExacqCamera` -- adds `width`, `height`, `camera_id`, `format`, and `quality` fields per camera.

### Puller

No dedicated Exacq puller class. The [[vms-connector]] uses `exacq_utils.get_session_id` and `get_stream_url` to obtain a URL, then feeds it to either the RTSP puller or HTTP/URL puller from [[actuate-pullers]] depending on the stream format.

### Alarm Sender

No Exacq-specific alarm sender. Alert delivery uses whichever monitoring sender is configured on the site.

## Auth Method

**HTTP session-based authentication.** The connector calls `get_session_id` at startup, passing username and password to the exacqVision web interface. The returned session ID is included as a query parameter (`s=`) in all subsequent video requests. Sessions expire, so reconnection logic must re-authenticate.

## Key Config Fields

`server_ip`, `server_port`, `server` (server name), `username`, `password`, `stream_port` (for RTSP format 5). Per-camera: `camera_id`, `format` (5=RTSP, 7=HTTP stream, others=JPEG), `width`, `height`, `quality`.

## Relationship to Other Components

- [[actuate-integration-calls]] -- exacq_utils provides session auth and URL construction
- [[actuate-config]] -- ExacqConnectorConfig with customer and camera-level typed config
- [[actuate-pullers]] -- standard RTSP or URL puller consumes the constructed stream URL
- [[vms-connector]] -- orchestrates session login, URL construction, and puller startup
