---
title: "Orchid Integration"
type: summary
topic: integrations/orchid
tags: [integration, vms, orchid]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Orchid Integration

Orchid is an on-premise video management system (VMS). The Actuate integration uses Orchid's **low-bandwidth HTTP streaming API** to pull JPEG frames from cameras, making it one of the few integrations with a dedicated, VMS-specific puller rather than using generic RTSP streams.

## Components

### OrchidJpgFrameQueuePuller (puller)

Defined in [[actuate-pullers]] at `orchid/orchid_jpg_queue_puller.py`. Extends `BasePuller`. Connects to the Orchid server over HTTP and uses the `/service/low-bandwidth/streams` API to request JPEG frame streams for individual cameras identified by `orchid_stream_id`. The puller manages the full stream lifecycle: requesting a stream (with resolution, FPS, and start time parameters), polling until the stream state transitions from "pending" to "available", and then fetching individual frames via `/service/low-bandwidth/streams/{guid}/frame`.

Supports two operating modes:
- **Live mode** (`use_motion=False`): Continuously streams live frames, restarting with a 10-minute backoff on errors.
- **Motion-triggered mode** (`use_motion=True`): Waits for timestamps on a motion queue, then requests playback clips starting at the motion event time. Streams for the configured `motion_interval` duration before stopping and waiting for the next motion event.

Frame submission respects the configured FPS gap, skipping frames that arrive faster than the desired rate. Connection health is monitored via `update_connection_status()`, which checks frame dimensions and reports connectivity failures through the camera status sender.

### OrchidConnectorConfig (config)

Defined in [[actuate-config]] at `connector/orchid/orchid_config.py`. The `OrchidCustomerConfig` extends `CustomerConfig` with Orchid-specific fields: `basic_username`, `basic_password`, `http_port`, `server_ip`, and optional `use_motion` with `motion_interval`. The `OrchidCameraConfig` adds `stream_id` (the Orchid-assigned camera identifier), along with configurable `width` and `height` (defaulting to 1920x1080).

## Auth Method

**HTTP Basic Authentication** using `basic_username` and `basic_password` from the customer config. Every API call (stream creation, state polling, frame retrieval) includes these credentials via the `requests` library's `auth` parameter.

## Architecture

The [[vms-connector]] instantiates `OrchidJpgFrameQueuePuller` per camera during startup. Unlike most VMS integrations that use generic RTSP URL pullers, Orchid requires its own puller because it exposes a proprietary HTTP-based frame delivery API rather than standard RTSP streams. There is no Orchid-specific alarm sender or integration calls module -- alerts flow through whatever monitoring sender (Immix, webhook, etc.) is configured for the site. There are also no Orchid entries in [[actuate-integration-calls]].
