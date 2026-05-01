---
title: "CHM Phase 6: SMTP and AILink Diagnostics"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-6]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase7-historical-trending.md
incoming_updated: 2026-05-01
---

# CHM Phase 6: SMTP and AILink Diagnostics

## Problem Statement

SMTP cameras deliver frames via email to an SQS-backed ingestion pipeline, not via [[rtsp-deep-dive|RTSP]]. AILink cameras deliver via a proprietary WebSocket protocol. Neither integration type has any diagnostics implementation -- both fall through to `DummyDiagnostics` in the `DiagnosticRunner.get_runner()` dispatch, which is a complete no-op across all five diagnostic methods.

These two integration types represent approximately 32,000 cameras -- the majority of the monitored fleet. When an SMTP camera stops delivering frames, the system eventually flags a connectivity failure (no frames received), but provides zero diagnostic context: Is the camera offline? Is the SMTP relay misconfigured? Is SQS backed up? Is the JPEG corrupt? Similarly, when an AILink camera drops its WebSocket connection, the failure surfaces only as a generic connectivity loss with no insight into whether the issue is protocol-level, network-level, or encoder-level.

The [[chm-phase4-generic-diagnostics|GenericDiagnostics]] fallback (Phase 4) provides baseline frame recency checks, but SMTP and AILink have unique delivery mechanisms that warrant dedicated diagnostic classes to extract maximum signal from the available telemetry.

## Proposed Solution

Two new diagnostic classes: `SMTPDiagnostics` and `AILinkDiagnostics`, each extending `BaseDiagnostics` and registered in `DiagnosticRunner.get_runner()` for their respective `integration_type` values.

### File Locations

- `healthcheck/alerts/diagnostics/integrations/smtp_diagnostics.py`
- `healthcheck/alerts/diagnostics/integrations/ailink_diagnostics.py`

### DiagnosticRunner Registration

```python
elif config.customer.integration_type == "smtp":
    return SMTPDiagnostics(config)
elif config.customer.integration_type == "ailink":
    return AILinkDiagnostics(config)
```

## SMTP Diagnostics Design

SMTP cameras are fundamentally different from [[rtsp-deep-dive|RTSP]] cameras: there is no persistent stream connection. Frames arrive as JPEG email attachments, processed by an SQS consumer and stored in S3. The diagnostic strategy centers on analyzing delivery patterns and frame integrity rather than stream metadata.

**`connectivity_diagnostics(puller, healthcheck_data)`** -- Frame recency analysis. Computes `time.time() - last_frame_timestamp` using the most recent frame timestamp available from the puller's frame cache or DynamoDB healthcheck record. Thresholds: no frames for 30 minutes = warning, no frames for 1 hour = alert. Additionally, queries SQS queue depth for the camera's ingestion queue (via `actuate_daos` SQS client) to distinguish between camera-not-sending (empty queue) and consumer-backlog (deep queue). An empty queue with no recent frames means the camera or SMTP relay is down. A deep queue with no recent frames means the consumer is stalled. Populates `healthcheck_data.diagnostics["network"]` with `frame_age_seconds`, `sqs_queue_depth`, and `delivery_state` (one of: `"delivering"`, `"camera_silent"`, `"consumer_backlog"`).

**`stream_quality_diagnostics(puller, healthcheck_data)`** -- JPEG integrity validation. SMTP frames arrive as JPEG attachments, and corruption during transmission is a known failure mode. Checks: (1) JPEG file size -- frames under 5KB are almost certainly corrupt or truncated, normal surveillance JPEGs range from 30KB to 500KB. (2) Frame dimension consistency -- compares current frame dimensions against the expected resolution from camera config; a sudden dimension change suggests the camera switched sub-streams or the NVR relay is substituting a thumbnail. (3) JPEG decode test -- attempts `cv2.imdecode()` and flags decode failure as corruption. Populates `healthcheck_data.diagnostics["stream"]` with `jpeg_size_bytes`, `dimensions_match`, and `decode_success`.

**`motion_status_diagnostics(puller, healthcheck_data)`** -- SMTP cameras often have a separate motion-signal SQS queue distinct from the frame delivery queue. Checks whether the motion signal queue is delivering events by examining the most recent motion event timestamp. A camera that delivers frames but produces zero motion events for an extended period (configurable, default 24 hours) may have a failed motion detector or misconfigured motion zones. Reports `motion_signal_age_seconds` and `motion_queue_active`.

**`recording_diagnostics(puller, healthcheck_data)`** -- Frame gap analysis specific to SMTP delivery patterns. SMTP cameras typically deliver frames in bursts (triggered by motion or on a schedule). Analyzes the inter-frame gap distribution from the last 24 hours of frame timestamps stored in the healthcheck table. If the maximum gap exceeds the camera's configured delivery interval by more than 3x, flags a recording interruption. Reports `max_gap_seconds`, `expected_interval_seconds`, and `gap_ratio`.

**`server_diagnostics(puller, healthcheck_data)`** -- If the camera config includes an NVR IP (some SMTP cameras relay through an on-premises NVR before emailing), performs a TCP probe to the NVR's SMTP relay port (25 or 587). Reports `nvr_smtp_reachable` and `nvr_smtp_latency_ms`. If no NVR IP is configured, this method returns `healthcheck_data` unmodified (no-op, consistent with the direct-to-cloud SMTP model).

## AILink Diagnostics Design

AILink cameras connect to the Actuate platform via a persistent WebSocket maintained by the `actuate_ailink` module. The camera pushes fMP4 (fragmented MP4) media segments over this channel. Diagnostic strategy focuses on connection state, frame delivery rate, and protocol-level health.

**`connectivity_diagnostics(puller, healthcheck_data)`** -- WebSocket connection state inspection. Reads the connection status from the `actuate_ailink` client associated with this camera: is the WebSocket currently open, in reconnecting state, or disconnected? Tracks reconnection frequency over the healthcheck window -- frequent reconnections (>3 in 15 minutes) indicate an unstable network path or camera firmware issue. Reports `ws_state` (one of: `"connected"`, `"reconnecting"`, `"disconnected"`), `reconnection_count`, and `last_connected_timestamp`.

**`stream_quality_diagnostics(puller, healthcheck_data)`** -- Frame arrival rate analysis. Compares the actual frame delivery rate against the expected rate from camera config. AILink cameras negotiate FPS during the WebSocket handshake; a sustained rate below 50% of negotiated indicates encoder strain or bandwidth throttling. Reports `fps_actual`, `fps_expected`, `delivery_ratio`.

**`motion_status_diagnostics(puller, healthcheck_data)`** -- Frame recency check. Identical pattern to SMTP: computes age of most recent frame and flags if it exceeds threshold. AILink cameras should deliver frames continuously while the WebSocket is open, so the recency threshold is tighter (5 minutes vs 1 hour for SMTP).

**`recording_diagnostics(puller, healthcheck_data)`** -- Frame gap detection. Analyzes timestamps of received fMP4 fragments for gaps exceeding 2x the expected fragment duration. Reports `max_fragment_gap_seconds` and `fragment_gap_count`.

**`server_diagnostics(puller, healthcheck_data)`** -- Protocol health analysis. Inspects fMP4 fragment parsing metrics from the AILink puller: timing of moof/mdat atoms, presence of parsing errors, and fragment duration consistency. A high parsing error rate suggests firmware bugs or stream corruption. Reports `fmp4_parse_error_rate`, `fragment_duration_mean_ms`, and `fragment_duration_std_ms`.

## Data Model

Both classes write to the standard `healthcheck_data.diagnostics` dict, using the same key structure (`"network"`, `"stream"`, `"recording"`) as other diagnostic classes. This ensures consistent [[new-relic|New Relic]] logging and alert generator compatibility.

## Effort Estimate

2-3 days. Breakdown: 1 day for `SMTPDiagnostics` (frame recency and SQS queue depth are the primary value; JPEG validation is straightforward). 1 day for `AILinkDiagnostics` (WebSocket state inspection and fMP4 parsing metrics require understanding the `actuate_ailink` internal APIs). 0.5-1 day for `DiagnosticRunner` registration, unit tests, and alert generator wiring.

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal with SMTP/AILink section
- [[chm-phase4-generic-diagnostics]] -- GenericDiagnostics baseline (SMTP/AILink override this)
- [[chm-diagnostics-gap-analysis]] -- gap matrix showing SMTP/AILink at Tier 3
- [[chm-diagnostics-architecture]] -- DiagnosticRunner dispatch and BaseDiagnostics contract
- [[chm-phase5-frame-probe]] -- FrameProbe analyses applicable to SMTP JPEG frames
