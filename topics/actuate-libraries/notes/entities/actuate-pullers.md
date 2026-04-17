---
title: "actuate-pullers"
type: entity
topic: actuate-libraries
tags: [library, camera-stream, video-ingestion, frame-pulling, gstreamer]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-pullers

## Purpose

actuate-pullers is the video ingestion layer of the Actuate platform. It implements the patterns that connect to video data sources (RTSP streams, webcams, S3 buckets, SQS queues, KVS, MJPEG URLs, sockets, and more) and feed decoded frames into the downstream processing pipeline. Every connector deployment uses a puller to acquire frames before they enter the inference pipeline.

**Version:** 1.17.10

## Key Classes

- **`BasePuller`** (ABC) -- Abstract base class all pullers inherit from. Manages the frame queue, motion detector integration, bandwidth tracking, connectivity/health packets, and frame submission logic. Requires `image_cache`, `frame_queue`, and `dao_manager` at construction.
- **`BandwidthTracker`** -- Thread-safe utility that measures per-camera inbound bandwidth in configurable windows (default 5 min). Reports kbps/mbps.
- **`UrlFramePuller`** -- Primary puller for RTSP/HTTP streams via OpenCV `VideoCapture`.
- **`GstUrlFramePuller`** -- GStreamer-based URL puller; optional import (requires PyGObject).
- **`AvUrlFramePuller`** -- PyAV-based URL puller; optional import.
- **`MotionBasedUrlFramePuller` / `OnOffMotionBasedUrlFramePuller`** -- URL pullers that integrate motion-gated frame submission.
- **`S3FramePuller`** -- Pulls frames from S3 objects.
- **`SQSFramePuller`** -- Consumes frame references from SQS.
- **`KVSFramePuller`** -- Pulls from Amazon Kinesis Video Streams (optional).
- **`WebcamFramePuller`** -- Local webcam capture.
- **`QueueFramePuller` / `FrameQueueWriter`** -- In-process queue-based puller and writer pair.
- **`BufferFramePuller`** -- Buffer-based frame source.
- **`JpgFrameQueuePuller`** -- JPEG frame queue consumer.
- **`MilestoneJpgFramePuller` / `OrchidJpgFrameQueuePuller`** -- VMS-specific JPEG pullers for Milestone and Orchid integrations.
- **`VideoQueueFramePuller`** -- Pulls from a video file queue.
- **`DummyPuller`** -- No-op puller for testing.
- **`PullerState`** -- Enum tracking puller health states.

## Public API

All pullers follow the `BasePuller` contract: instantiate with config objects (`CameraStreamConfig`, `CustomerConfig`, `DaoManager`, `ImageCache`), then the puller runs a pull loop that decodes frames and pushes `ImagePacket` objects onto the shared `frame_queue`.

## Dependencies

`actuate-image-cache`, `actuate-config`, `actuate-movement`, `actuate-pipeline-objects`, `actuate-healthmonitoring`, `actuate-connector-observers`, `opencv-python-headless`, `PyGObject`, `PyTurboJPEG`.

## Consumers

Used by `vms-connector` and all other connector services. The connector's camera thread instantiates the appropriate puller subclass based on the camera source type in the configuration.

## Notable Patterns

- Optional imports with `try/except` for GStreamer, KVS, and PyAV pullers -- allows the package to install on systems without those native dependencies.
- Motion detection is integrated directly into `BasePuller` via `actuate_movement.MotionDetector`, gating whether frames are submitted to the pipeline.
- `BandwidthTracker` uses a lock-guarded sliding window, not atomic counters, for thread safety.
- Timestamp-zone masking is offloaded to a single-thread executor to avoid blocking the pull loop.
