---
title: "Salient Integration"
type: summary
topic: integrations/salient
tags: [integration, vms, salient]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Salient Integration

Salient (formerly Salient Systems) is an on-premise video management system. The Actuate integration connects to Salient's CompleteView VMS via RTSP streams, using the standard URL-based pullers for frame ingestion with Salient-specific configuration for server connectivity and camera discovery.

## Components

### SalientConnectorConfig (config)

Defined in [[actuate-config]] at `connector/salient/salient_config.py`. The configuration hierarchy includes:

- **SalientCustomerConfig**: Extends `CustomerConfig` with `server_ip`, `server_port`, `username`, `password`, and sets `use_motion=False` (motion-triggered streaming is not supported for Salient). These credentials are used for connecting to the Salient CompleteView server.

- **SalientCamera**: Extends `CameraConfig` with optional `width`, `height`, `quality` fields and a required `camera_id`. The camera also stores `server_address`, which is the specific recording server address for that camera (Salient supports multi-server deployments where different cameras may reside on different servers).

- **SalientCameraStream**: Standard `CameraStreamConfig` wrapper binding camera config to feature deployments.

- **SalientConnectorConfig**: Extends `BaseConnectorConfig`. Iterates over a `servers` array in the JSON config, where each server contains its own `server_address` and list of cameras. This multi-server structure reflects Salient's architecture where a single site can span multiple recording servers.

### Puller

Salient uses the standard RTSP URL-based pullers from [[actuate-pullers]] (`UrlFramePuller`, `AvUrlFramePuller`, or `GstUrlFramePuller`). No Salient-specific puller exists -- RTSP stream URLs are constructed by the [[vms-connector]] using the camera's `server_address`, `camera_id`, and customer credentials.

## Auth Method

**Username/password** for the Salient CompleteView server, stored in the customer config. These credentials are used to construct authenticated RTSP stream URLs. There is no API token or OAuth flow.

## Architecture

The [[vms-connector]] reads the `SalientConnectorConfig` at startup, constructs RTSP URLs per camera using the server address and camera ID, and passes them to standard URL pullers in [[actuate-pullers]]. There are no Salient-specific entries in [[actuate-alarm-senders]] or [[actuate-integration-calls]] -- alert delivery goes through whichever monitoring sender is configured, and camera discovery is handled through the config JSON rather than API calls. The multi-server config structure is the distinguishing feature compared to simpler RTSP-based integrations.
