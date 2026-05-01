---
title: "Luxriot Integration Components"
type: entity
topic: integrations/luxriot
tags: [integration, luxriot, components, vms-connector]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
incoming_updated: 2026-05-01
---

# Luxriot Integration Components

Luxriot (now Luxriot Evo) is a VMS platform. The Actuate integration connects to Luxriot servers via HTTP with embedded credentials to retrieve camera streams. Luxriot sites use the standard [[rtsp-deep-dive|RTSP]] puller path after constructing URLs from the server configuration.

## Config Classes

Defined in [[actuate-config]] at `actuate_config/connector/luxriot/luxriot_config.py`:

### LuxriotConnectorConfig

Extends `BaseConnectorConfig`. Instantiates `LuxriotCustomerConfig` from the customer section and delegates camera stream construction to `make_camera_streams` with Luxriot-specific types.

### LuxriotCustomerConfig

Extends `CustomerConfig` with server connection details:

- `server_ip` -- Luxriot server IP address.
- `server_port` -- Luxriot server port.
- `username` and `password` -- credentials for the Luxriot API.
- `api_endpoint` -- auto-constructed as `http://{username}:{password}@{server_ip}:{server_port}/`. This embeds HTTP Basic Auth credentials directly in the URL, which is used for both API access and video stream retrieval.
- Optional `use_motion` and `motion_interval` fields for motion-gated operation.

The embedded-credential URL pattern is the defining characteristic of the Luxriot integration. Unlike [[rtsp-deep-dive|RTSP]] integrations where credentials are per-camera, Luxriot uses a single server-level credential pair embedded in the base HTTP URL.

### LuxriotCamera

Extends `CameraConfig` with optional `width`/`height` fields and placeholder `camera_id` and `base_url` attributes (set at None by default, populated at runtime).

### LuxriotCameraStream, LuxriotModel, LuxriotFeatureDeployment

Standard pass-through subclasses of `CameraStreamConfig`, `ModelConfig`, and `StreamDeploymentConfig` with no additional fields.

## Puller

Luxriot does not have a dedicated puller in [[actuate-pullers]]. The video streams exposed by the Luxriot server are consumed via the standard URL-based pullers (`AvUrlFramePuller` or `UrlFramePuller`), with the stream URL constructed from the `api_endpoint` base and camera-specific paths. If `use_motion` is enabled, the motion-based puller variants are used.

## Integration Calls

There is **no** dedicated `actuate-integration-calls` module for Luxriot. API interaction (camera discovery, stream URL retrieval) is handled at setup time in the [[connector-factory|connector factory]] rather than through a reusable calls library.

## Factory Routing

In [[vms-connector]] `factory.py`, `integration_type == "luxriot"` routes to `LuxriotConnectorFactory`.

## Key Architectural Notes

- **HTTP embedded credentials** -- the `api_endpoint` format `http://user:pass@host:port/` means credentials are visible in the URL string. The `_redact_url_credentials` utility in [[actuate-pullers]] ensures these are masked in log output.
- **Server-level auth** -- unlike [[rtsp-deep-dive|RTSP]] (per-camera credentials) or Salient (per-server credentials), Luxriot uses a single credential pair for the entire customer.
- **Optional motion support** -- when `use_motion` is True, the puller connects only during motion windows (saving bandwidth and CPU on low-activity sites).
