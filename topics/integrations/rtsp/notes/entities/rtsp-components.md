---
title: "RTSP Integration Components"
type: entity
topic: integrations/rtsp
tags: [integration, rtsp, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# RTSP Integration Components

The RTSP integration is the default and most common integration type in the Actuate platform. It serves as the fallback path for any VMS that exposes video over RTSP or HTTP streams. The `integration_type` value `rtsp` (and the alias `milestone_rtsp`) routes through this path. Adpro also uses this path since its Rust puller re-serves streams as local RTSP.

## Puller Variants

All URL-based pullers live in [[actuate-pullers]] under `actuate_pullers/url/`. They share the abstract `BasePuller` base class and are distinguished by their decoding backend and motion-handling strategy.

### UrlFramePuller (OpenCV/cv2)

The original puller (`url_puller.py`). Uses `cv2.VideoCapture` to connect and `cap.read()` to decode frames. Handles FPS measurement by grabbing initial frames and calculating native FPS. Contains retry logic with 60-second sleep on connection failure and URL fallback for H.264 codec parameters. Supports a `_submit_frame` batching mode when `highest_fps == 3` that collects frames within a second, then sub-samples them at the configured gap.

### AvUrlFramePuller (PyAV/FFmpeg)

The modern replacement (`av_url_puller.py`). Uses PyAV (`av.open`) for stream decoding, giving direct access to PTS timestamps, codec metadata, and hardware acceleration. Supports GPU decoding via CUDA (NVDEC), VAAPI (Intel), VideoToolbox (macOS), and AMF (AMD) through configurable `hw_accel` settings. Contains `TimestampTracker` for robust PTS-to-UNIX conversion with discontinuity detection and buffer-burst drift correction. Includes a `connect_stream` method with `quick_probe` for fast failover detection after 3+ consecutive failures. Per-camera `BandwidthTracker` reports inbound bandwidth. Supports custom headers and connection options.

### GstUrlFramePuller (GStreamer)

A GStreamer-native puller (`gst_url_puller.py`) that delegates to `GStreamerInputPipeline`. Builds a GStreamer pipeline string: `rtspsrc ! rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! jpegenc ! appsink` for RTSP, or `souphttpsrc ! decodebin` for HTTP. Supports `videorate` element insertion for FPS downsampling via `camera.downsample`. Frames arrive through an `appsink` new-sample callback. This variant is used when GStreamer is preferred over PyAV for pipeline stability.

### MotionBasedUrlFramePuller

Extends `UrlFramePuller` to support motion-gated capture (`url_puller_motion.py`). Holds a `motion_ping_queue` and blocks on it -- only connecting to the camera and decoding frames when motion is detected. After a motion event, it streams for `motion_interval + 5` seconds, then releases the capture and blocks again. Used with integrations that provide external motion signals (SMTP, SQS, or ONVIF motion events).

### MotionBasedAvUrlFramePuller

The PyAV equivalent of the motion-based puller (`av_url_puller_motion.py`). Same queue-blocking pattern but uses `av.open` and PyAV frame decoding with PTS timestamp extraction.

### OnOffMotionBasedUrlFramePuller

A variant (`url_puller_motion_onoff.py`) that uses a threaded on/off model. Motion start triggers continuous capture in the main loop; a background `motion_off` thread monitors the queue for a `False` signal, sleeps 10 seconds, then sets `self.motion = False` to stop the capture loop.

### GenesisUrlFramePuller

A site-specific subclass of `AvUrlFramePuller` (`genesis_url_puller.py`) for the Genesis bridge infrastructure. Overrides `try_failover` with random bridge IP selection across a pool of 36 bridges (172.16.254.11-.46). Bypasses `quick_probe` to avoid excessive failover churn. Uses a 60-second retry interval.

## Config Classes

Defined in [[actuate-config]] at `actuate_config/connector/rtsp/rtsp_config.py`:

- **RTSPConnectorConfig** -- extends `BaseConnectorConfig`. Delegates to `make_camera_streams` with RTSP-specific types.
- **RTSPCustomerConfig** -- adds `protocol` (default `"rtsp"`), motion configuration (`use_motion`, `motion_port`, `http_motion_port`, `smtp_port`, `smtp_auth_port`, `motion_interval`), and SQS motion support.
- **RTSPCamera** -- adds `username`, `password`, and `base_url` fields (credentials embedded per-camera, not per-customer).

## Factory Routing

In [[vms-connector]] `factory.py`, `integration_type` values `rtsp`, `milestone_rtsp`, and `adpro` all route to `RTSPConnectorFactory`.
