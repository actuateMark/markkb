---
title: "Genetec Integration Components"
type: entity
topic: integrations/genetec
tags: [integration, genetec, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
incoming_updated: 2026-05-01
---

# Genetec Integration Components

## GenetecAlertSender

`GenetecAlertSender` extends `AttachmentAlertSender` and delivers detection alarms to Genetec Security Center via the Web SDK REST API on port 4590. The `send(alert_data, retries=0)` method performs a three-step HTTP workflow:

1. **Alarm entity lookup**: A GET request to `http://{server_ip}:4590/WebSdk/report/EntityConfiguration?q=EntityTypes@Alarm,Name={label}` retrieves the alarm entity matching the detection label. The response XML is parsed with `xml.etree.ElementTree` to extract the alarm GUID from the first `QueryResult/Row/Cell` element.

2. **Camera entity lookup**: A second GET request to the same EntityConfiguration endpoint with `EntityTypes@Camera,Name={camera_name}` retrieves the camera entity GUID for the triggering camera.

3. **Alarm trigger**: A GET request to `http://{server_ip}:4590/WebSdk/alarm?q=TriggerAlarm({alarm_guid},{camera_guid})` fires the alarm, associating it with the specific camera.

All requests use HTTP Basic Auth with the customer's `server_username` (which includes the Genetec developer suffix) and `password`, with a 10-second timeout. The method retries up to 3 times on failure, incrementing the retry counter on each exception.

The key limitation of this sender is that it requires pre-configured alarm entities in Genetec Security Center whose names exactly match the Actuate detection labels. If no alarm entity matches the label name, the XML parsing will fail and the alarm will not be delivered.

## GenetecConnectorConfig

`GenetecConnectorConfig` extends `BaseConnectorConfig` with `GenetecCustomerConfig` containing connection and authentication fields:

- **Server connection**: `server_ip` for the Security Center server.
- **Authentication**: `username` and `password`. The `server_username` is automatically constructed by appending the Genetec developer suffix (`5RleU0nemH38g37bnTk8biF5C4leES8hxKJbvTqE2hxpxGdLzUQ/H+8QmRMv9940`) to the username with a semicolon separator. This suffix identifies the Actuate application to the Genetec SDK.
- **Motion settings**: Optional `use_motion` flag with `motion_interval`.

`GenetecCamera` extends `CameraConfig` with optional `stream_type` and `resolution` (parsed from the `width`/`height` keys respectively), `quality`, and runtime-assigned `camera_id` and `base_url` (both initialized to `None`). The config uses the standard `make_camera_streams` pattern with `GenetecFeatureDeployment` (no custom fields) and `GenetecCameraStream`.

## Integration Calls and Frame Pulling

Genetec does not have a dedicated integration-calls module or custom puller class. Camera streams are accessed via [[rtsp-deep-dive|RTSP]] URLs constructed at connector startup using the Security Center SDK credentials. The Genetec Web SDK on port 4590 is used exclusively for alarm delivery. Camera discovery and stream URL resolution are handled in the [[connector-factory|connector factory]] code within `vms-connector` rather than in a shared library module.
