---
title: "Salient Integration Components"
type: entity
topic: integrations/salient
tags: [integration, salient, components, vms-connector]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
incoming_updated: 2026-06-25
---

# Salient Integration Components

Salient (formerly Salient Systems / CompleteView) is a VMS platform. The Actuate integration supports a multi-server architecture where a single customer has multiple Salient servers, each with its own set of cameras. This multi-server structure is the defining characteristic that distinguishes the Salient config from most other integrations.

## Config Classes

Defined in [[actuate-config]] at `actuate_config/connector/salient/salient_config.py`:

### SalientConnectorConfig

Extends `BaseConnectorConfig`. Unlike most connectors that call `make_camera_streams` (which iterates `json_config["cameras"]`), Salient has **custom camera stream construction** that iterates `json_config["servers"]` instead. Each server contains its own cameras array:

```python
for server in json_config["servers"]:
    for camera in server["cameras"]:
        # ... build feature deployments from camera["streams"]
        cam = SalientCamera(camera, server["server_address"])
        self.camera_streams.append(SalientCameraStream(cam, feature_deployments))
```

This means the settings JSON has a `servers` array at the top level rather than a flat `cameras` array. Each server entry has a `server_address` field that gets passed to camera construction.

### SalientCustomerConfig

Extends `CustomerConfig` with:

- `server_ip` -- primary server IP (used for customer-level identification).
- `server_port` -- primary server port.
- `username` and `password` -- server credentials.
- `use_motion` -- hard-coded to `False` (Salient does not use motion-gated pulling).

### SalientCamera

Extends `CameraConfig` with:

- `server_address` -- the address of the specific Salient server this camera belongs to (from the parent server entry). This is the key multi-server field.
- `camera_id` -- the Salient camera identifier.
- Optional `width`, `height`, and `quality` fields.

The `server_address` attribute on each camera is what enables multi-server support. When constructing [[rtsp-deep-dive|RTSP]] URLs at runtime, each camera uses its own server address rather than a single global server IP.

### SalientCameraStream, SalientModel, SalientFeatureDeployment

Standard pass-through subclasses with no additional fields.

## Puller

Salient does not have a dedicated puller in [[actuate-pullers]]. Camera streams are consumed via the standard URL-based pullers (`AvUrlFramePuller` or `UrlFramePuller`), with [[rtsp-deep-dive|RTSP]] URLs constructed from the per-camera `server_address` and `camera_id`.

## Integration Calls

There is **no** dedicated `actuate-integration-calls` module for Salient. The VMS interaction ([[rtsp-deep-dive|RTSP]] URL construction from server address + camera ID) is straightforward enough to be handled in the [[connector-factory|connector factory]].

## Factory Routing

In [[vms-connector]] `factory.py`, `integration_type == "salient"` routes to `SalientConnectorFactory`.

## Key Architectural Notes

- **Multi-server structure** -- the settings JSON uses a `servers[]` array instead of a flat `cameras[]` array. This is unique among connector configs.
- **Server-per-camera association** -- each `SalientCamera` carries its own `server_address`, allowing a single site deployment to span multiple physical Salient servers.
- **No motion support** -- `use_motion` is always `False`, so Salient always uses continuous-pull mode.
- **Customer-level credentials** -- unlike [[rtsp-deep-dive|RTSP]] (per-camera auth) the username/password are on the customer config, shared across all servers. Each server is accessed with the same credentials.
