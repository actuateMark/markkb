---
title: "Source: Genetec Security Center Web SDK and Actuate Integration"
type: source
topic: integrations/genetec
tags: [source, integration, genetec, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

Genetec Security Center exposes a **REST-style Web SDK** on port 4590. The API returns XML responses and is used for entity configuration queries, alarm triggering, and event subscription (motion). Video streaming uses RTSP on port 654.

### Authentication

Authentication uses **HTTP Basic Auth** with a Genetec developer suffix appended to the username: `{username};{developer_key}` where the developer key is a fixed string (`5RleU0nemH38g37bnTk8biF5C4leES8hxKJbvTqE2hxpxGdLzUQ/H+8QmRMv9940`). This combined credential is passed as `auth=(server_username, password)` on all API requests.

### Key Endpoints

- **Entity Configuration** (`GET /WebSdk/report/EntityConfiguration?q=EntityTypes@{type},Name={name}`): Queries entities by type and name. Returns XML with `QueryResult > Row > Cell` containing the entity GUID. Used for both camera and alarm lookups. Entity types include `Camera` and `Alarm`.
- **Trigger Alarm** (`GET /WebSdk/alarm?q=TriggerAlarm({alarm_guid},{camera_guid})`): Triggers a named alarm associated with a specific camera. Used by the alert sender to push detection events back to Security Center.
- **Event Subscription** (`GET /WebSdk/events/subscribe?q=event({guid},CameraMotionOn),event({guid},CameraMotionOff),...`): Subscribes to camera motion events. Accepts comma-separated event specifications.
- **Event Stream** (`GET /WebSdk/events`): Long-lived HTTP streaming connection that delivers subscribed events as XML chunks. Events contain `SourceEntity` (camera GUID) and `Type` (`CameraMotionOn` or `CameraMotionOff`).

### Video Streaming

Camera RTSP URLs follow the pattern: `rtsp://{username}:{password}@{server_ip}:654/{camera_guid}/live`. The camera GUID is resolved by querying the EntityConfiguration endpoint with the camera name, then the RTSP URL is constructed for the AvUrlFramePuller.

### CHM-Relevant Diagnostics

- **Camera discovery**: Entity configuration queries return XML with camera GUIDs. Missing `QueryResult`, `Row`, or `Cell` elements in the response indicate the camera does not exist or has been removed from Security Center.
- **Alarm delivery**: The alert sender (`GenetecAlertSender`) queries both the alarm entity and camera entity GUIDs before triggering, with up to 3 retries on failure.
- **Motion event health**: The motion listener (`genetec_motion.py`) maintains a motion dictionary per camera and uses a 2-second keepalive loop to propagate motion-on states. Event stream disconnection would stop motion signals.
- **Server reachability**: All API calls target `http://{server_ip}:4590/WebSdk/` with 10-second timeouts.

### Actuate-Specific Notes

The Genetec integration spans three codebases: `actuate-alarm-senders/genetec/genetec_alert_sender.py` (alarm triggering), `vms-connector/camera/genetec/genetec_camera.py` (RTSP stream setup), and `vms-connector/motion/genetec/genetec_motion.py` (motion event listener). There is no `actuate-integration-calls` module for Genetec. The camera class extends `BaseStreamCamera` and supports both continuous and motion-based pulling via `AvUrlFramePuller` / `MotionBasedAvUrlFramePuller`. The connector auth method is listed as "API Token" in the integration matrix. The motion listener uses XML streaming over HTTP with line-by-line parsing. The Confluence KB "Integration Migration Status Table" lists Genetec as "Not Started" for rearchitecture migration.

### Confluence References

- "actuate-alarm-senders: Alert Sender Reference" (EDOCS, page 496828438)
- "actuate-config: Alert Configuration Classes" (EDOCS, page 497909761) -- includes GenetecAlertConfig
- "vms-connector: Supported Integrations" (EDOCS, page 496828419)
- "Integration Migration Status Table" (kb, page 160269555)
