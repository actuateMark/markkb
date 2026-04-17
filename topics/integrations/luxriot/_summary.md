---
title: "Luxriot Integration"
type: summary
topic: integrations/luxriot
tags: [integration, vms, luxriot]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Luxriot Integration

Luxriot (Luxriot Evo) is a video management system (VMS) that provides recording, live viewing, and management for IP cameras. Actuate integrates with Luxriot as a video source, pulling camera feeds for AI analytics.

## Components

### LuxriotConnectorConfig

Defined in [[actuate-config]] at `connector/luxriot/luxriot_config.py`. Extends `BaseConnectorConfig` with Luxriot-specific typed config classes:

- **`LuxriotCustomerConfig`** -- adds `server_ip`, `server_port`, `username`, `password`, and a computed `api_endpoint` field. The endpoint embeds credentials directly in the URL using HTTP basic-auth format: `http://[username]:[password]@[server_ip]:[server_port]/`. Also supports optional `use_motion` and `motion_interval` fields.
- **`LuxriotCamera`** -- extends `CameraConfig` with optional `width`/`height` overrides. The `camera_id` and `base_url` fields are initialized to `None` and set at runtime.

### Puller

No dedicated Luxriot puller class. The [[vms-connector]] constructs the video URL using the Luxriot customer's `api_endpoint` (which already contains embedded credentials) and feeds it to the standard HTTP/URL puller from [[actuate-pullers]]. The Luxriot server responds with a video stream or JPEG snapshots depending on the request path.

### Integration Calls

There is no `actuate-integration-calls` module for Luxriot. All communication with the VMS happens through HTTP requests using the credentials-embedded URL.

### Alarm Sender

No Luxriot-specific alarm sender. Alert delivery uses whichever monitoring sender is configured on the site.

## Auth Method

**HTTP Basic authentication via embedded URL credentials.** The `LuxriotCustomerConfig` builds the `api_endpoint` as `http://[username]:[password]@[server_ip]:[server_port]/`, which means credentials are included in every HTTP request as standard basic-auth in the URL. This approach requires no separate login or session management -- the Luxriot server validates credentials on each request.

## Key Config Fields

`server_ip`, `server_port`, `username`, `password` (used to construct the embedded-credentials URL). Optional: `use_motion` (boolean), `motion_interval` (seconds). Per-camera: optional `width`/`height` overrides.

## Alert Delivery

Luxriot is a video-source-only integration. There is no alert delivery back to the Luxriot platform. Alerts are routed through whatever monitoring integration (e.g., Immix, SureView, webhook) is configured alongside Luxriot.

## Relationship to Other Components

- [[actuate-config]] -- LuxriotConnectorConfig with customer and camera-level typed config
- [[actuate-pullers]] -- standard URL/HTTP puller consumes the credentials-embedded endpoint
- [[vms-connector]] -- builds the URL from config and starts the puller
- No corresponding module in [[actuate-integration-calls]] or [[actuate-alarm-senders]]
