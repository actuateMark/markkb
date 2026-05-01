---
title: "KVS Integration Components"
type: entity
topic: integrations/kvs
tags: [integration, kvs, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-pullers.md
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/infrastructure/notes/entities/remote-access-proxy.md
  - topics/integrations/kvs/_summary.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
incoming_updated: 2026-05-01
---

# KVS Integration Components

KVS (Amazon [[aws-kvs-entity|Kinesis Video Streams]]) is an AWS-native integration where video is ingested from a KVS stream rather than directly from camera [[rtsp-deep-dive|RTSP]] URLs. Cameras push video to KVS, and the Actuate connector pulls from the cloud-side KVS endpoint. This is used when direct network access to cameras is unavailable or when the customer's architecture already uses KVS as a video aggregation layer.

## Puller -- KVSFramePuller

Defined in [[actuate-pullers]] at `actuate_pullers/kvs/kvs_puller.py`. The puller is a thin wrapper around `KVSGstreamerPipeline`. It accepts a `kvs_stream_name` parameter (the KVS stream name, which equals the camera name in config), registers a frame callback, and delegates all streaming to the pipeline. The callback calls `submit_frame` and updates `last_frame_timestamp`.

### KVSGstreamerPipeline

The heavy lifting lives in `kvs_ingestor.py`. This class builds a [[gstreamer-entity|GStreamer]] pipeline:

```
appsrc -> matroskademux -> decodebin -> videoconvert -> jpegenc -> queue -> appsink
```

**AWS connection flow**: Uses `boto3` to call `kinesisvideo.get_data_endpoint` for the `GET_MEDIA` API, then creates a `kinesis-video-media` client pointed at that endpoint. Calls `get_media` with `StartSelector: NOW` to get a streaming payload of MKV-wrapped video data.

**Data feed**: A background thread (`feed_kvs_data`) reads the KVS payload in 64KB chunks (`CHUNK_SIZE`) and pushes each chunk into the [[gstreamer-entity|GStreamer]] `appsrc` as `Gst.Buffer` objects. The pipeline demuxes the MKV container, decodes the video, encodes frames as JPEG, and emits them through the `appsink`.

**Auto-reconnection**: If the stream ends or a socket error occurs, the pipeline resets to NULL state, recreates itself, and retries the KVS connection. A 5-second `WAIT_TIME` backoff is used between retries. If the media client itself fails, a fresh client is obtained before retrying.

**Frame processing**: The `on_new_sample` callback extracts the PTS timestamp (converted from nanoseconds to seconds via `Gst.SECOND`), maps the buffer data, decodes it with `cv2.imdecode`, and passes the numpy frame to the registered callback.

## Config Classes

Defined in [[actuate-config]] at `actuate_config/connector/kvs/kvs_config.py`:

- **KvsConnectorConfig** -- extends `BaseConnectorConfig` with standard `CustomerConfig` (no KVS-specific customer fields). Uses `make_camera_streams` with `KvsCamera`, `KvsFeatureDeployment`, `KvsStream`.
- **KvsCamera** -- extends `CameraConfig` and sets `kvs_stream_name` from the camera's `camera_name` field. This is the key link: the camera name in the settings file must match the KVS stream name in AWS.

## Factory Routing

In [[vms-connector]] `factory.py`, `integration_type == "kvs"` routes to `KvsConnectorFactory`.

## Key Differences from RTSP

- No URL construction -- the stream is identified by name, not by an [[rtsp-deep-dive|RTSP]] URL with credentials.
- AWS authentication via IAM/boto3 rather than per-camera username/password.
- [[gstreamer-entity|GStreamer]] pipeline uses `appsrc` (byte-fed from HTTP) rather than `rtspsrc` (network protocol).
- No motion-based variants -- KVS streams are always continuous.
