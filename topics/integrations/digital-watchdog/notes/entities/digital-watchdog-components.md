---
title: "Digital Watchdog Integration Components"
type: entity
topic: integrations/digital-watchdog
tags: [integration, digital-watchdog, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
incoming_updated: 2026-05-01
---

# Digital Watchdog Integration Components

## DWAlertSender

`DWAlertSender` extends `AttachmentAlertSender` and delivers detection alarms to DW Spectrum / Nx Witness servers. The `send(alert_data)` method supports both cloud-connected and on-premises deployments with a multi-fallback strategy.

### Authentication

For cloud-connected systems (`use_nx_proxy = True`), the sender obtains an OAuth2 bearer token via `_get_bearer_token()`. This first discovers the cloud host (e.g., `dwspectrum.digital-watchdog.com`) by querying `{cloud_system_id}.relay.vmsproxy.com/rest/v3/system/info` (falling back to v2). It then posts to `https://{cloud_host}/cdb/oauth2/token` with password grant type and a `cloudSystemId` scope. The token is cached and reused; on a 401 response, the cache is cleared and the token is refreshed once.

For on-premises systems, HTTP Digest Auth is used with the customer's local `username`/`password`.

### Event Delivery

The event payload is a JSON object with: `caption` ("Actuate - {LABEL} Detected"), `description` (the label), `source` (camera name), `timestamp` (milliseconds since epoch), and `metadata` (JSON-encoded camera reference). Two API endpoints are tried in priority order:

1. `POST /rest/v4/events/generic` -- the DW/NX v6.1+ secure endpoint
2. `POST /api/createEvent` -- the legacy endpoint

For on-premises, both HTTP and HTTPS base URLs are attempted. For cloud, only the relay proxy URL is used. The `_try_post()` method manually follows 307 redirects (up to 5 hops) to preserve the Authorization header, which the `requests` library would strip on cross-host redirects.

## DW Integration Calls (dw_utils)

The `dw_utils` module provides connection management, camera discovery, and system configuration:

### Authentication and Login

`login()` handles three auth modes: cloud OAuth2 (for cloud users), HTTP Digest, and HTTP Basic (as fallback). `check_cloud_user()` queries the relay to determine if the configured username is a cloud account. `get_cloud_domain_name()` discovers the cloud host and relay domain for constructing API URLs. The login function returns a tuple of `(logged_in, response, system_auth_header)`.

### Camera Discovery

Camera lists are fetched via either `rest/v1/devices` (v5+ systems) or `ec2/getCamerasEx?format=json` (legacy). `camera_exists_dw()` checks camera existence by UID, trying Digest then Basic auth, and returns `True` on errors to avoid false negatives.

### System Configuration

`increase_connection_count()` raises the DW system's `maxWebMTranscoders` and `maxHttpTranscodingSessions` limits to accommodate Actuate's connections. It tries five different auth/API combinations: Basic auth GET, Digest auth GET, Bearer token PATCH (REST v3), and a session-creation POST fallback. `check_mismatch()` detects aspect-ratio mismatches between primary and substreams by inspecting `mediaStreams` in camera parameters.

### Helper Functions

`get_url()`, `get_username()`, `get_password()` abstract over the on-prem vs. cloud-proxy URL/credential differences. `get_cloud_system_id()` fetches the system ID from `nxvms.com/cdb/system/get` if not already configured.

## DWConnectorConfig

`DWConnectorConfig` extends `BaseConnectorConfig` with `DWCustomerConfig` containing: `server_ip`, `server_port`, `username`, `password`, and cloud fields (`use_nx_proxy`, `nx_username`, `nx_password`, `cloud_system_id`). `use_v5` enables the v5+ REST API path. `DWCamera` adds `stream_type`, `resolution`, `stream_quality`, `codec`, and `camera_uid`. Motion support includes both direct (`motion_port`, `http_motion_port`) and SQS-based (`use_motion_sqs`) modes.
