---
title: "Video Insight Integration Components"
type: entity
topic: integrations/video-insight
tags: [integration, video-insight, components, vms-connector]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/integrations/video-insight/_summary.md
  - topics/video-processing/notes/concepts/gst-rtsp-h264-only-audit.md
  - topics/vms-connector/_summary.md
incoming_updated: 2026-05-01
---

# Video Insight Integration Components

Video Insight (now part of Panasonic i-PRO) is a VMS platform. The Actuate integration connects to Video Insight servers via a REST API for camera discovery and token management, then pulls video streams over [[rtsp-deep-dive|RTSP]]/HTTP. Video Insight has its own site manager subclass for analytics, distinguishing it from generic [[rtsp-deep-dive|RTSP]] integrations.

## Config Classes

Defined in [[actuate-config]] at `actuate_config/connector/video_insight/video_insight_config.py`:

### VideoInsightConnectorConfig

Extends `BaseConnectorConfig`. Instantiates `VideoInsightCustomerConfig` and delegates camera stream construction to `make_camera_streams` with Video Insight-specific types.

### VideoInsightCustomerConfig

Extends `CustomerConfig` with server connection details:

- `server_ip` -- Video Insight server IP address.
- `server_port` -- Video Insight server port.
- `username` and `password` -- credentials for the Video Insight API.
- `token` -- initialized as empty string `""`, populated at runtime after authentication.
- `api_endpoint` -- auto-constructed as `http://{server_ip}:{server_port}/api/v1/`. Unlike Luxriot, credentials are **not** embedded in the URL; instead authentication uses the separate `token` field obtained via the API.

The API endpoint format (`/api/v1/`) indicates a versioned REST API, distinguishing Video Insight from integrations that use embedded-credential HTTP URLs.

### VideoInsightCamera

Extends `CameraConfig` with:

- Optional `width` and `height` fields.
- Optional `fps` field (clamped to minimum 1).
- `camera_id` and `base_url` -- initialized as `None`, populated at runtime during camera discovery.

The per-camera `fps` field is notable -- most integrations rely on the stream's native FPS, but Video Insight allows explicit FPS configuration per camera in the settings.

### VideoInsightCameraStream, VideoInsightModel, VideoInsightFeatureDeployment

Standard pass-through subclasses of `CameraStreamConfig`, `ModelConfig`, and `StreamDeploymentConfig` with no additional fields.

## Puller

Video Insight does not have a dedicated puller in [[actuate-pullers]]. Once stream URLs are constructed from the API, video is consumed via the standard URL-based pullers (`AvUrlFramePuller` or `UrlFramePuller`).

## Integration Calls

There is **no** dedicated `actuate-integration-calls` module for Video Insight. API interaction for camera discovery and token management is handled in the [[connector-factory|connector factory]].

## Site Manager

Video Insight has a dedicated `VideoInsightAnalyticsSiteManager` in [[vms-connector]] (`site_manager/connector/integrations/video_insight_site_manager.py`), selected by `get_site_type` in `factory.py`. This suggests Video Insight requires custom analytics lifecycle behavior beyond what the default `AnalyticsSiteManager` provides.

## Factory Routing

In [[vms-connector]] `factory.py`, `integration_type == "video_insight"` routes to `VideoInsightConnectorFactory`.

## Key Architectural Notes

- **Token-based auth** -- unlike Luxriot (embedded credentials) or [[rtsp-deep-dive|RTSP]] (per-camera credentials), Video Insight authenticates via a runtime token obtained from the API.
- **Per-camera FPS** -- the explicit `fps` field per camera is unique among connector configs and allows overriding the native stream rate.
- **Custom site manager** -- one of the few integrations with its own `AnalyticsSiteManager` subclass, alongside Milestone, Exacq, Eagle Eye, Avigilon, and [[hikcentral-components|HikCentral]].
