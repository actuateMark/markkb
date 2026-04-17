---
title: "Orchid Integration Components"
type: entity
topic: integrations/orchid
tags: [integration, orchid, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Orchid Integration Components

## OrchidJpgFrameQueuePuller

`OrchidJpgFrameQueuePuller` extends `BasePuller` and streams JPEG frames from an Orchid VMS server via the Orchid Low-Bandwidth Streaming API. This puller supports both live and motion-triggered playback modes, making it one of the more specialized pullers in the system.

### Initialization

The puller takes an optional `motion_queue` (a `queue.Queue`). It constructs the base URL as `http://{server_ip}:{http_port}` and stores the camera's `stream_id` for API calls. Authentication uses `basic_username`/`basic_password` from the customer config via `get_authentication()`.

### API Methods

- `get_stream_guid(timestamp_milliseconds)`: POSTs to `/service/low-bandwidth/streams` to create a new stream session. The request body includes the `streamId`, target `resolution` (width/height from camera config), `startTime` (0 for live, or a millisecond timestamp for playback), `sync: True`, the configured FPS `rate`, a 30-second `waitThres` timeout, and `transport: "http"`. Returns a stream info object with an `id` (GUID) and state.
- `get_stream_state(guid)`: GETs the current state of a stream session (pending/active/failed).
- `get_frame(guid)`: GETs the next JPEG frame from `/service/low-bandwidth/streams/{guid}/frame`.
- `list_streams()`: GETs all active stream sessions.

### Stream Lifecycle

`request_stream()` creates a stream and polls `get_stream_state()` every 0.5 seconds until the stream transitions from "pending" to "active" (or raises `RuntimeError` on "failed"). The `stream()` method runs the main frame loop: it fetches frames via `get_frame()`, decodes the JPEG bytes, applies FPS gating (only submitting frames when the time gap exceeds `fps_gap`), and calls `submit_frame()` to push frames into the pipeline.

### Run Modes

The `run(duration)` method operates in two modes based on whether a `motion_ping_queue` was provided:

- **Live mode** (no motion queue): Calls `stream(0)` continuously for the specified duration. On error, waits 10 minutes before retrying to avoid hammering a down server.
- **Motion-triggered mode**: Blocks on `motion_ping_queue.get()` waiting for a motion event timestamp. When received, calls `stream(timestamp_ms)` to play back from that point. The `end_stream()` method checks whether the current frame timestamp has exceeded the motion start time plus the configured `motion_interval`, stopping the stream when the window expires.

### Connection Monitoring

`update_connection_status()` is called on the first frame to verify the stream is producing valid frames (width > 100 pixels). If connected, it updates the camera status DAO; if not, it triggers an unable-to-connect alarm.

## OrchidConnectorConfig

`OrchidConnectorConfig` extends `BaseConnectorConfig` with Orchid-specific configuration:

### OrchidCustomerConfig

Extends `CustomerConfig` with: `basic_username`, `basic_password`, `http_port`, `server_ip`, and optional `use_motion` with `motion_interval`.

### OrchidCameraConfig

Extends `CameraConfig` with: `stream_id` (an integer parsed from `orchid_stream_id` -- the Orchid-internal stream identifier), `width` (default 1920), `height` (default 1080), and `fps` (default 1). The width/height defaults ensure the low-bandwidth API always receives valid resolution parameters.

### OrchidCameraStreamConfig

Extends `CameraStreamConfig` with an explicit `self.camera` type assignment for `OrchidCameraConfig`, improving type hints for downstream consumers.

## Alarm Sending and Integration Calls

Orchid does not have a dedicated alarm sender or integration-calls module. Alert delivery for Orchid deployments uses the generic alarm-sending infrastructure. The integration is primarily a frame-ingestion integration, with the Orchid Low-Bandwidth API providing the video feed.
