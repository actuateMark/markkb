---
title: "RTSP Integration"
type: summary
topic: integrations/rtsp
tags: [integration, vms, rtsp]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# RTSP Integration

[[rtsp-deep-dive|RTSP]] (Real Time Streaming Protocol) is the **default and fallback integration type** in Actuate. Any camera or VMS that exposes an RTSP or HTTP video stream URL can be onboarded using this integration, making it the most widely deployed type. It is also the underlying frame ingestion method for many named VMS integrations (Eagle Eye, Digital Watchdog, Avigilon, Genetec, Salient, etc.) that use RTSP URLs obtained via their respective integration calls.

## Components

### Puller Variants

All defined in [[actuate-pullers]] under the `url/` directory. The [[rtsp-deep-dive|RTSP]] integration has the most puller variants of any integration:

- **UrlFramePuller** (`url_puller.py`): The primary puller. Uses [[opencv-entity|OpenCV]] (`cv2.VideoCapture`) to decode RTSP/HTTP streams. Handles connection retries, FPS calibration (grabs sample frames to measure native FPS), broken stream detection and reconnection, and frame submission at the configured rate. Supports Digital Watchdog Nx proxy sleep delays.

- **AvUrlFramePuller** (`av_url_puller.py`): Alternative puller using the [[pyav-entity|PyAV]] library (`av.open`) instead of OpenCV. Reads PTS timestamps from video packets for more accurate frame timing. Supports configurable retry intervals with exponential backoff, TLS certificate verification bypass, and RTSP transport options (TCP/UDP). Includes a `read_time_from_packet` mode for VMS-synchronized timestamps.

- **GstUrlFramePuller** (`gst_url_puller.py`): GStreamer-based puller using `GStreamerInputPipeline`. Receives frames via callback rather than polling. Supports FPS downsampling at the [[gstreamer-entity|GStreamer]] level for reduced CPU usage.

- **MotionBasedUrlFramePuller** (`url_puller_motion.py`): Extends `UrlFramePuller` with motion-triggered streaming. Waits on a motion queue, connects to the stream on motion events, and disconnects after the `motion_interval` plus a 5-second buffer. Used with VMS-side or SMTP motion triggers.

- **MotionBasedAvUrlFramePuller** (`av_url_puller_motion.py`): Combines `AvUrlFramePuller` with motion-triggered connect/disconnect behavior. The preferred motion puller for newer deployments.

- **OnOffMotionBasedUrlFramePuller** (`url_puller_motion_onoff.py`): A variant that uses a boolean on/off motion signal via a thread rather than interval-based motion windows.

- **GenesisUrlFramePuller** (`genesis_url_puller.py`): Extends `AvUrlFramePuller` with random bridge failover for the Genesis customer's multi-bridge infrastructure.

### RTSPConnectorConfig (config)

Defined in [[actuate-config]] at `connector/rtsp/rtsp_config.py`. The `RTSPCustomerConfig` extends `CustomerConfig` with `protocol` (defaults to "rtsp"), optional `use_motion` with associated `motion_port`, `http_motion_port`, `smtp_port`, or `smtp_auth_port` for motion trigger sources, and `motion_interval`. Also supports `use_motion_sqs` for SQS-based motion signals. `RTSPCamera` adds `username`, `password`, and `base_url` fields.

## Auth Method

Camera-level credentials embedded in the [[rtsp-deep-dive|RTSP]] URL or passed as `username`/`password` in the camera config. No VMS-level authentication is needed since streams are accessed directly.

## Architecture

The [[vms-connector]] selects the appropriate URL puller variant based on the customer's configuration (motion mode, preferred decoder library, special customer overrides). [[rtsp-deep-dive|RTSP]] streams are consumed directly from cameras or NVRs. Alert delivery is handled by whatever monitoring sender is configured for the site. The RTSP integration has no alarm sender or integration calls component of its own.
