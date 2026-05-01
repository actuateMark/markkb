---
title: "Digital Watchdog Integration"
type: summary
topic: integrations/digital-watchdog
tags: [integration, vms, digital-watchdog, nx-witness]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Digital Watchdog Integration

Digital Watchdog (DW) is a VMS platform built on the Nx Witness/Nx Meta engine. Actuate integrates with DW for both alert delivery and camera management, supporting on-premise and **cloud-connected** (Nx Cloud relay proxy) deployments.

## Components

### DWAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `digital_watchdog/dw_alert_sender.py`. Extends `AttachmentAlertSender`. Alerts are sent **synchronously via HTTP REST** -- no SQS queue is involved. The sender tries multiple endpoints in priority order:

1. `POST /rest/v4/events/generic` (DW/NX v6.1+ secure endpoint)
2. `POST /api/createEvent` (legacy endpoint)

For **cloud-connected** systems (`use_nx_proxy=True`), the sender discovers the cloud host via the relay proxy (`{cloud_system_id}.relay.vmsproxy.com`), obtains a system-scoped **OAuth2 bearer token** from the DW cloud, and uses `Authorization: Bearer` headers. Token refresh on 401 is handled automatically. For **on-premise** systems, HTTP Digest Auth is used with local username/password. The sender tries both HTTP and HTTPS for on-prem, and follows 307 redirects manually to preserve auth headers.

The event payload includes `caption` ("Actuate - {LABEL} Detected"), `description`, `source` (camera name), `timestamp` (milliseconds), and `metadata` with camera reference UIDs.

Config fields: `customer.server_ip`, `customer.server_port`, `customer.username`, `customer.password`, `customer.use_nx_proxy`, `customer.cloud_system_id`, `customer.nx_username`, `customer.nx_password`, `camera.camera_uid`.

### Digital Watchdog Integration Calls

Defined in [[actuate-integration-calls]] at `digital_watchdog/dw_utils.py`. Provides camera discovery, authentication, and system management:

- `login()` -- Multi-method auth cascade: OAuth2 cloud token (for cloud users), Digest auth, Basic auth. Supports both v1 REST (`/rest/v1/devices`) and legacy (`/ec2/getCamerasEx`) endpoints. Returns camera list response.
- `get_url()` / `get_username()` / `get_password()` -- Build stream URL and credentials, switching between on-prem and cloud relay.
- `check_cloud_user()` -- Queries the relay to determine if the user is a cloud-type account.
- `get_cloud_domain_name()` -- Discovers cloud host and relay domain from system info.
- `increase_connection_count()` -- Attempts to raise `maxWebMTranscoders` and `maxHttpTranscodingSessions` limits on the NVR using a cascade of Basic auth, Digest auth, Bearer token PATCH, and session token fallback. This is necessary because DW NVRs have default transcoding session limits that are too low for Actuate's multi-camera connections.
- `camera_exists_dw()` -- Camera existence check with false-negative safety.
- `check_mismatch()` -- Detects aspect ratio mismatches between primary and substream resolutions.

## Auth Methods

- **On-premise:** Digest or Basic HTTP auth (cascading attempt)
- **Cloud (Nx proxy):** OAuth2 password grant via `{cloudHost}/cdb/oauth2/token` with `client_id=3rdParty` and `scope=cloudSystemId={id}`
- **Mixed:** Session token creation via `POST /rest/v1/login/sessions` as fallback

## Architecture

The [[vms-connector]] uses DW integration calls to authenticate, discover cameras, and build [[rtsp-deep-dive|RTSP]] stream URLs. Streams are consumed by standard URL-based pullers in [[actuate-pullers]]. When detections occur, the `DWAlertSender` sends events directly to the DW NVR REST API. Cloud-connected sites use the Nx relay proxy (`relay.vmsproxy.com`) as an intermediary for all communication.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- DWAlertSender lives here, extending AttachmentAlertSender
- [[actuate-integration-calls]] -- `dw_utils.py` provides auth, camera discovery, and connection management
- [[vms-connector]] -- consumes integration calls for login/setup, builds the sender via factory
- [[actuate-pullers]] -- standard URL pullers used (no DW-specific puller)
