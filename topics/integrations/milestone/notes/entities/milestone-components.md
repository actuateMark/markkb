---
title: "Milestone Integration Components"
type: entity
topic: integrations/milestone
tags: [integration, milestone, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
incoming_updated: 2026-05-01
---

# Milestone Integration Components

## MilestoneAlertSender

`MilestoneAlertSender` extends `EventListenerAlertSender` and delivers detection alarms directly to a Milestone XProtect event server over a raw TCP socket connection. The `send(alert_data, retries=0)` method opens a TCP socket to the customer's `event_server_ip` on the configured `alarm_port` with a 3-second timeout and transmits an XML `AnalyticsEvent` document following the `urn:milestone-systems` schema.

The XML payload includes a server-timezone-aware timestamp (derived from `approx_capture_timestamp` with millisecond precision via `pytz`), the detection label as the event `Type`, the customer's configured `event_name` as the `Message`, and camera/server GUIDs (`server_guid` and `alarm_guid`) to associate the event with the correct device. A configurable `alarm_guid` override on the config object takes precedence over the camera's own GUID.

Three code paths handle different payload variants. For Genesis-lead gun/pistol detections, it sends a simplified payload with `event_name` overridden to "Actuate Gun Detection" and no bounding boxes. For most other detections when `model_response` is present, it constructs an `ObjectList` containing normalized bounding boxes (coordinates divided by frame dimensions, clamped to 0-1, with a 1.5x size expansion). The fallback path sends the event without bounding boxes. The payload is sent with a `\r\n\r\n` terminator, the response is read (up to 1024 bytes), and the socket is closed. On failure, the method retries once after a 1-second sleep.

## MilestoneService

`MilestoneService` in `actuate-integration-calls` is the Milestone management-plane client. It handles SOAP-based authentication against the XProtect Management Server (`ServerCommandService.svc`) using Basic auth with a `[BASIC]\\user:pass` credential format. Key responsibilities include:

- **Token lifecycle**: `retrieve_file_token_milestone()` either downloads token files from S3 (for specific hardcoded Genesis/federated server IPs) or performs a SOAP `Login` call to obtain a time-limited token. Token TTL is parsed from the `<MicroSeconds>` element. The `token_refresh()` and `process_token_refresh()` methods run as background threads, re-fetching tokens on a cycle tied to the TTL minus a 120-second safety margin.
- **Configuration retrieval**: `get_configuration()` fetches the full system XML configuration (recording servers + cameras) via SOAP `GetConfiguration`, or downloads a gzipped config from S3 for Genesis deployments. `extract_settings()` parses the XML using `lxml` to extract recording server IPs and live camera GUIDs, applying recording-server-name-to-IP mappings from the Admin API.
- **Camera comparison**: `run_comparison()` compares database-stored camera-to-recording-server mappings against the live Milestone configuration. Cameras not in the DB are written to `new_cameras.json`; cameras that moved recording servers are tracked in `moved_recording_server` for failover.
- **Connection testing**: `try_server_connection()` and `try_recording_server_connection()` verify reachability of the management server and individual recording servers.
- **Alarm triggering**: `trigger_alarm_milestone()` sends AnalyticsEvent XML over a TCP socket, similar to the alarm sender but used from the service layer.

## MilestoneJpgFramePuller

`MilestoneJpgFramePuller` extends `BasePuller` and streams JPEG frames from a Milestone recording server over a persistent TCP socket (with optional TLS via `connect_with_optional_tls`). The protocol is Milestone's proprietary Image Server protocol: the puller sends XML `methodcall` commands (`connect` then `live`) with the camera GUID, connection token, transcoding parameters (width, height, compression rate, FPS), and whether motion-only frames are requested.

The incoming byte stream is accumulated in a buffer; JPEG frames are identified by scanning for `\xff\xd8` (SOI) and `\xff\xd9` (EOI) markers. Frame timestamps are extracted from `Current:` headers embedded in the stream. A 20 MB backlog limit prevents memory exhaustion. Frames are submitted to the pipeline at the configured FPS rate, gated by `fps_gap`.

Failover handling is central to this puller. When a recording server becomes unreachable, the puller checks if the management server is still reachable (to distinguish recording-server failure from VPN outage). If the management server is up, it triggers `milestone_service.run_comparison()` to detect camera-to-recording-server moves and switches to the new recording server. Token refreshes are detected by comparing the local token copy against `milestone_service.token`, triggering a full reconnect cycle. Per-camera bandwidth tracking reports throughput every 5 minutes. The `run_healthcheck()` variant performs the same streaming but pushes only the first frame for connectivity verification.

## MilestoneConnectorConfig

`MilestoneConnectorConfig` extends `BaseConnectorConfig` with `MilestoneCustomerConfig` containing connection details: `basic_username`/`basic_password` for SOAP auth, `management_server_ip`, `ssl_port`, `http_port`, `stream_port`, `event_server_ip`, `alarm_port`, `event_name`, and `server_guid`. The `is_raw` flag (default `True`) switches between raw and JPEG software type. `MilestoneCamera` adds `frame_rate_relative`, `milestone_motion`, `compression_rate`, `width`, `height`, `recording_server_ip`, and `guid`. The config iterates `recording_servers` in the JSON, building `MilestoneCameraStream` objects per camera per recording server -- a structure unique to Milestone among the VMS integrations.
