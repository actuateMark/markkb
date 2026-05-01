---
title: "KVS Integration"
type: summary
topic: integrations/kvs
tags: [integration, puller, kvs, aws]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# KVS Integration

Amazon [[aws-kvs-entity|Kinesis Video Streams]] ([[kvs-components|KVS]]) is an AWS managed service for ingesting, storing, and processing real-time video streams. Actuate integrates with KVS as a video source, pulling frames from KVS streams for AI analytics. This is used when cameras or edge devices publish video directly to AWS rather than exposing [[rtsp-deep-dive|RTSP]] endpoints.

## Components

### KVSFramePuller

Defined in [[actuate-pullers]] at `kvs/kvs_puller.py`. Extends `BasePuller`. Wraps a `KVSGstreamerPipeline` instance, registering a frame callback that receives decoded frames and timestamps and submits them to the pipeline via `submit_frame()`. The `run()` method starts the pipeline and blocks for up to 7 days (the default duration). Supports healthcheck via the base puller interface.

### KVSGstreamerPipeline

Defined in [[actuate-pullers]] at `kvs/kvs_ingestor.py`. The core streaming engine that:

1. **Connects to [[kvs-components|KVS]]** via `boto3` -- creates a `kinesisvideo` client, obtains a `GET_MEDIA` data endpoint, then calls `get_media()` with `StartSelector: NOW` to begin reading the live stream.
2. **Builds a [[gstreamer-entity|GStreamer]] pipeline** -- `appsrc ! matroskademux ! decodebin ! videoconvert ! jpegenc ! queue ! appsink`. Raw MKV bytes from KVS are pushed into `appsrc`; decoded JPEG frames come out of `appsink`.
3. **Feeds data in a background thread** -- `feed_kvs_data()` runs in a daemon thread, reading chunks (default 64KB) from the KVS payload and pushing them as GStreamer buffers.
4. **Delivers frames via callback** -- `on_new_sample()` pulls frames from the sink, decodes the JPEG buffer into an [[opencv-entity|OpenCV]] numpy array, and invokes the registered `frame_callback`.
5. **Auto-reconnects** -- on stream interruption or errors, resets the pipeline, re-obtains the media client endpoint, and recreates the pipeline.

### KvsConnectorConfig

Defined in [[actuate-config]] at `connector/kvs/kvs_config.py`. Extends `BaseConnectorConfig`. The `KvsCamera` class maps `camera_name` from the settings to `kvs_stream_name`, which is the KVS stream identifier passed to the puller. Uses the standard `CustomerConfig` with no additional customer-level fields.

### Alarm Sender

No KVS-specific alarm sender. Alert delivery uses whichever monitoring sender is configured on the site.

## Auth Method

**AWS IAM authentication.** The `boto3` clients (`kinesisvideo`, `kinesis-video-media`) use standard AWS credential resolution (environment variables, instance profile, or shared credentials file). No application-level username/password is needed. The IAM principal must have permissions for `kinesisvideo:GetDataEndpoint` and `kinesisvideo:GetMedia` on the target stream.

## Key Config Fields

Per-camera: `camera_name` (maps to the [[kvs-components|KVS]] stream name). No special customer-level auth fields -- AWS credentials come from the execution environment.

## Relationship to Other Components

- [[actuate-pullers]] -- KVSFramePuller and KVSGstreamerPipeline live here
- [[actuate-config]] -- KvsConnectorConfig provides typed config with stream-name mapping
- [[vms-connector]] -- instantiates KVSFramePuller for each configured camera
- [[actuate-alarm-senders]] -- no KVS-specific sender
