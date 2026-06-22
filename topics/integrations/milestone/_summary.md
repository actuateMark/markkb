---
title: "Milestone Integration"
type: summary
topic: integrations/milestone
tags: [integration, vms, milestone, xprotect]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Milestone Integration

Milestone XProtect is a major on-premise VMS platform. The Actuate integration spans all three core libraries -- [[actuate-pullers]], [[actuate-alarm-senders]], and [[actuate-integration-calls]] -- making it the most deeply integrated VMS in the platform.

## Components

### MilestoneJpgFramePuller (puller)

Defined in [[actuate-pullers]] at `milestone/milestone_jpg_frame_puller.py`. Extends `BasePuller`. Connects to Milestone recording servers over **raw TCP sockets** (with optional TLS) on the configured `stream_port`. Requests JPEG frames from individual cameras by GUID and recording server IP. Uses `MilestoneXmlParser` to interpret XML-formatted responses from the Milestone Image Server protocol. Each camera thread maintains its own socket connection and tracks per-camera bandwidth via `BandwidthTracker`. Supports failover to alternate recording servers when the primary is unreachable, and integrates with `push_connection_alert` for health monitoring. The puller requires a `MilestoneService` instance for token management.

Config fields: `camera.guid`, `camera.recording_server_ip`, `customer.stream_port`, `customer.management_server_ip`, `customer.server_guid`.

### MilestoneAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `milestone/milestone_alert_sender.py`. Extends `EventListenerAlertSender`. Sends analytics events to the Milestone Event Server over **raw TCP sockets** using the Milestone Analytics Event XML schema (`urn:milestone-systems`). The XML payload includes timestamp, detection type, event name, server GUID, and camera GUID (alarm_guid). When model response data is available, bounding boxes are included as normalized `<ObjectList>` coordinates. Special handling exists for Genesis customer gun detections (separate "Actuate Gun Detection" event name, no bounding boxes). Connects to the customer's `event_server_ip` on `alarm_port`.

Config fields: `customer.event_server_ip`, `customer.alarm_port`, `customer.server_guid`, `customer.event_name`, `config.alarm_guid`.

### MilestoneService (integration calls)

The most complex integration client in [[actuate-integration-calls]], defined at `milestone/milestone_service.py`. Handles:

- **SOAP-based token authentication** -- Logs in to the Milestone ManagementServer via SOAP (`[BASIC]\\user:pass` encoded), retrieves a time-limited token, and refreshes it on a configurable sleep cycle. File-based token sharing (`milestone_token/token.txt`) allows multiple processes on the same host to share a single token.
- **S3 token fallback** -- For specific Genesis customer IPs, tokens and configuration XML are retrieved from S3 rather than directly from the Milestone server. The four hardcoded management-server IPs in `milestone_service.py:142 retrieve_file_token_milestone()` and their S3 paths in `s3://actuate-settings/`: `172.16.254.103 → genesis/` (Genesis Schools), `172.16.250.114 → genesis_convention_center/` (Genesis Convention Center), `172.16.254.91 → genesis_federated/` (Genesis Federated), `172.16.250.235 → connector-8959/`. All four are Genesis-owned customers. **Reader is in our code (vms-connector pods); writer is elsewhere — a scheduled task on our infra (most likely `prod-job-scheduler` ECS service, logs only in NR). Writer identity not yet definitively in KB.** Read cycle pulls `token.txt`, `token_registration_time.txt`, `token_ttl.txt` and sets `self.expiry = ttl - 120`. Without the writer running, the reader keeps presenting an expired token to Milestone, which returns `<connected>no</connected><errorreason>Security token invalid</errorreason>` — see [[2026-05-24_genesis-no-alerts-milestone-token-rejection]] for the customer-impacting incident driven by this gap.
- **Configuration retrieval** -- Downloads the full XProtect XML configuration via SOAP, parses it with `lxml` to extract recording servers and camera lists.
- **Camera comparison** -- Compares cameras from the Milestone configuration against a PostgreSQL database to detect new/moved cameras.
- **Alarm triggering** -- `trigger_alarm_milestone()` sends analytics events over TCP sockets, identical to the sender but callable from the service layer.
- **Recording server connectivity checks** -- TCP socket probes to verify recording server reachability.

Auth: SOAP Basic Auth with `[BASIC]\\username:password` base64-encoded header.

## Architecture

The [[vms-connector]] instantiates `MilestoneService` during startup, which manages tokens and configuration. Camera threads each get a `MilestoneJpgFramePuller` instance that pulls JPEG frames via the Image Server protocol. When detections occur, the `MilestoneAlertSender` pushes analytics events back to the Milestone Event Server. This creates a bidirectional integration: frames flow from Milestone to Actuate, and alerts flow back.
