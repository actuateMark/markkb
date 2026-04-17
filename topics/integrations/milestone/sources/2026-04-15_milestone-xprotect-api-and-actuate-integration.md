---
title: "Source: Milestone XProtect API and Actuate Integration"
type: source
topic: integrations/milestone
tags: [source, integration, milestone, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

Milestone XProtect exposes two primary API surfaces used by the Actuate integration: a **SOAP API** for management server operations and a **TCP socket protocol** for analytics events. The management server endpoint lives at `https://{server_ip}:{ssl_port}/ManagementServer/ServerCommandService.svc`.

### Authentication

Authentication uses **HTTP Basic Auth** with a special Milestone prefix format: `[BASIC]\{username}:{password}`, base64-encoded and sent in the `Authorization` header. The SOAP `Login` action returns a time-limited token with fields `Token`, `MicroSeconds` (TTL in microseconds), and `RegistrationTime`. Tokens are refreshed on a background thread -- the default TTL is ~62 minutes (3720 seconds) with a 120-second safety margin before expiry.

For certain on-prem sites (identified by management server IP), tokens are stored in S3 and shared across processes rather than obtained directly via SOAP, indicating a federated or multi-connector deployment pattern.

### Key Endpoints / Operations

- **Login** (`SOAPAction: .../IServerCommandService/Login`): Obtains a session token. SOAP envelope includes an `instanceId` (random UUID). Returns `Token`, `RegistrationTime`, and `MicroSeconds` (TTL).
- **GetConfiguration** (`SOAPAction: .../IServerCommandService/GetConfiguration`): Downloads the full system configuration as XML. The response contains `RecorderInfo` elements with `WebServerUri`, `Name`, and nested `CameraInfo` elements with `Name`, `DeviceId` (GUID), and `CameraSecurity/Live` status. This XML can be large and is cached locally as `config.xml` or compressed in S3 as `config.xml.gz`.
- **Analytics Events** (TCP socket): Alarm/event injection uses a raw TCP socket connection to the recording server on a configurable `alarm_port`. XML `AnalyticsEvent` payloads include `Timestamp`, `Message`, `Source` (with `ServerId` and `ObjectId` GUIDs), and optional `ObjectList` with `BoundingBox` coordinates (normalized 0-1 for Top/Left/Bottom/Right).

### CHM-Relevant Diagnostics

- **Server connectivity**: `try_server_connection()` tests HTTPS to the management server with `GetConfiguration`.
- **Recording server connectivity**: `try_recording_server_connection()` tests raw TCP socket connectivity to recording servers on their stream port.
- **Camera discovery**: `run_comparison()` compares cameras in the Actuate database against the Milestone configuration XML, identifying cameras not in the DB and cameras that have moved to different recording servers (failover detection).
- **Recording server mapping**: Maps between recording server hostnames (from `WebServerUri` in XML, typically `http://{hostname}:7563/`) and IP addresses via the Actuate admin API.

### Actuate-Specific Notes

The integration module lives at `actuate-integration-calls/milestone/milestone_service.py` as the `MilestoneService` class. Configuration uses `MilestoneCamera` objects with `recording_server_ip` fields. The connector auth method is listed as "DB credentials" in the integration matrix. Token management is complex: some sites use S3-based token sharing (genesis, convention center, federated deployments), while others use direct SOAP login. The connector also supports sending analytics events back to Milestone with bounding box overlays for detection visualization.

### Confluence References

- "actuate-integration-calls: API Integrations Reference" (EDOCS, page 496336908)
- "vms-connector: Supported Integrations" (EDOCS, page 496828419)
- "Integration Migration Status Table" (kb, page 160269555)
