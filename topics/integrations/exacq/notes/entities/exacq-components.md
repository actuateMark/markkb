---
title: "Exacq Integration Components"
type: entity
topic: integrations/exacq
tags: [integration, exacq, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Exacq Integration Components

## exacq_utils (Integration Calls)

The `exacq_utils` module in `actuate-integration-calls` provides two key functions for interacting with the exacqVision web interface:

### get_session_id(config)

Obtains an authenticated session ID from the exacqVision server using two fallback methods:

1. **Legacy login** (GET): Sends a GET request to `http://{server_ip}:{server_port}/login.web?s={server}&u={username}&p={password}&responseVersion=2`. Parses the JSON response to extract the `sessionId` field.

2. **New server version login** (POST): If the legacy method fails, sends a POST to `http://{server_ip}:{server_port}/login.web` with form-encoded fields (`mode=simple`, `l=2`, plus server/username/password). The session ID is extracted from the HTML response using a regex pattern matching `logout.web?s=(.+)"`.

If both methods fail, the function raises an exception. The `server` field in the config refers to the named exacqVision server instance, distinct from the server IP.

### get_stream_url(config, camera_config, session_id)

Constructs a video stream URL for a given camera based on the camera's `format` field:

- **Format 5**: Returns an RTSP URL (`rtsp://{username}:{password}@{server_ip}:{stream_port}/{camera_id}`). Sets `exacq_streaming = True` indicating the stream uses a persistent connection.
- **Format 7**: Returns an HTTP multipart video URL with `iframes=0` and `multipart_encode=0` parameters. Also sets `exacq_streaming = True`.
- **Other formats** (JPEG pull): Returns an HTTP URL to `video.web` with the session ID, camera ID, format type, quality, and optional width/height parameters. Sets `exacq_streaming = False`, meaning frames are polled individually.

The function returns a tuple of `(exacq_streaming: bool, stream_url: str)`, which the connector uses to decide whether to use a streaming puller or a JPEG-polling puller.

## ExacqConnectorConfig

`ExacqConnectorConfig` extends `BaseConnectorConfig` and builds camera streams using the standard `make_camera_streams` pattern. The key config classes are:

### ExacqCustomerConfig

Extends `CustomerConfig` with exacqVision-specific fields: `username`, `password`, `server_ip`, `server_port`, `server` (the named server instance), and `stream_port` (for RTSP streaming, optional). Motion detection support is optional via `use_motion` with a configurable `motion_interval` (default 30 seconds).

### ExacqCamera

Extends `CameraConfig` with per-camera stream parameters: `width`, `height`, `camera_id`, `format` (determines the streaming method -- see `get_stream_url` above), and `quality` (JPEG compression quality for non-streaming formats).

## Alarm Sending

Exacq does not have a dedicated alarm sender class. Alert delivery for exacq deployments typically uses the generic webhook, TCP, or monitoring-station alarm senders depending on the customer's downstream alerting configuration. The exacq integration focuses on video ingestion rather than alarm delivery.
