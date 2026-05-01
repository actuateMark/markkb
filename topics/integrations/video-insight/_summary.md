---
title: "Video Insight Integration"
type: summary
topic: integrations/video-insight
tags: [integration, vms, video-insight]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Video Insight Integration

[[video-insight-components|Video Insight]] (now part of Panasonic i-PRO) is an on-premise video management system. The Actuate integration connects to Video Insight's REST API for authentication and camera management, then uses [[rtsp-deep-dive|RTSP]] streams for frame ingestion via standard URL-based pullers.

## Components

### VideoInsightConnectorConfig (config)

Defined in [[actuate-config]] at `connector/video_insight/video_insight_config.py`. The configuration hierarchy includes:

- **VideoInsightCustomerConfig**: Extends `CustomerConfig` with `server_ip`, `server_port`, `username`, `password`, and a computed `api_endpoint` URL (`http://{server_ip}:{server_port}/api/v1/`). Also stores a `token` field that is populated after authentication.

- **VideoInsightCamera**: Extends `CameraConfig` with optional `width`, `height`, and `fps` fields (FPS has a floor of 1). Also includes `camera_id` and `base_url` fields that are populated during camera discovery.

- **VideoInsightConnectorConfig**: Extends `BaseConnectorConfig`. Uses the standard `make_camera_streams()` factory method to build camera streams from the JSON config, making it structurally similar to other simple VMS integrations.

### Puller

[[video-insight-components|Video Insight]] uses the standard [[rtsp-deep-dive|RTSP]] URL-based pullers from [[actuate-pullers]] (`UrlFramePuller`, `AvUrlFramePuller`, or `GstUrlFramePuller`). No Video Insight-specific puller exists -- stream URLs are obtained via the Video Insight API and passed to the generic URL puller infrastructure.

## Auth Method

**Username/password** authentication against the [[video-insight-components|Video Insight]] REST API (`/api/v1/`). The customer config stores `server_ip`, `server_port`, `username`, and `password`. A session `token` is obtained post-authentication and used for subsequent API calls. The authentication flow is handled by the [[vms-connector]] during startup.

## Architecture

The [[vms-connector]] reads the `VideoInsightConnectorConfig` at startup, authenticates against the [[video-insight-components|Video Insight]] API to obtain a session token, discovers cameras and their [[rtsp-deep-dive|RTSP]] stream URLs, and passes them to standard URL pullers in [[actuate-pullers]]. There are no Video Insight-specific entries in [[actuate-alarm-senders]] or [[actuate-integration-calls]] -- alert delivery goes through whichever monitoring sender is configured for the site. The integration is relatively lightweight, relying on the standard config and puller infrastructure with Video Insight-specific customer and camera config classes.
