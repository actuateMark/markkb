---
title: "actuate-integration-calls"
type: entity
topic: actuate-libraries
tags: [library, integration-alerting, vms, api-client, camera-integration]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/integrations/ajax/_summary.md
  - topics/integrations/autopatrol-integration/_summary.md
  - topics/integrations/autopatrol-integration/notes/entities/autopatrol-integration-components.md
  - topics/integrations/avigilon/_summary.md
  - topics/integrations/bold/_summary.md
  - topics/integrations/digital-watchdog/_summary.md
  - topics/integrations/eagle-eye/_summary.md
incoming_updated: 2026-05-01
---

# actuate-integration-calls

Client libraries for communicating with external Video Management System (VMS) platforms and third-party security services. Each sub-module encapsulates authentication, API calls, and data formatting for a specific external system. Version **1.11.6**.

## Purpose

This library provides the low-level HTTP/SOAP/socket integration layer that Actuate connectors use to authenticate against customer VMS platforms, retrieve camera lists, construct stream URLs, trigger alarms, and verify camera existence. It sits below [[actuate-alarm-senders]] in the stack -- alarm senders call into these utilities when they need to interact with the VMS directly.

## Integration Modules

| Module | External System | Auth Method | Key Class/Functions |
|---|---|---|---|
| `ajax/` | [[ajax-components|Ajax]] security systems | API key + session token (username/password hash login) | `AjaxCalls` |
| `autopatrol/` | AutoPatrol (Immix Connect) virtual patrol API | Subscription key (`Ocp-Apim-Subscription-Key`) | `AutoPatrolAPI` |
| `avigilon/` | Avigilon NVR | Pre-existing session key | `camera_exists_avigilon()` |
| `digital_watchdog/` | Digital Watchdog / Nx Witness NVR | Digest/Basic/OAuth2 cascade | `login()`, `get_url()`, `camera_exists_dw()`, `increase_connection_count()` |
| `eagle_eye/` | Eagle Eye Networks cloud VMS | OAuth2 (v3), API key (v2), Camera Manager OAuth2 | `get_token()`, `get_camera_list()`, `get_url_v3()`, `camera_exists_v3()` |
| `exacq/` | Exacq (Illustra) NVR | Session ID via GET/POST login | `get_session_id()`, `get_stream_url()` |
| `hikcentral/` | [[hikcentral-components|HikCentral]] VMS | HMAC-SHA256 signature | `subscribe_to_motion()`, `send_request()` |
| `lisa/` | LISA alarm receiver (Leitstellensoftware) | Optional bearer token | `LisaClient` |
| `milestone/` | Milestone XProtect VMS | SOAP Basic Auth with token refresh | `MilestoneService` |

## Key Classes and Functions

**`AutoPatrolAPI`** -- Full REST client for the AutoPatrol/Immix Connect API. Manages contracts, schedules, patrols, sites, and devices. Supports `raise_patrol_alert()` for sending threat detections with media attachments back to the patrol platform.

**`MilestoneService`** -- The most complex integration. Handles SOAP-based token authentication with file-based token sharing between processes, XML configuration parsing via `lxml`, camera comparison against a PostgreSQL database, and `trigger_alarm_milestone()` which sends analytics events over raw TCP sockets with bounding box overlays.

**`LisaClient`** -- Lightweight HTTP client for the LISA webhook API. Supports posting events to `/events`, `/ev/event/{ObjectNumber}/{event}`, `/ev/oevent/{oid}/{event}`, and `/ev/device/{id}/{event}` endpoints. Includes `make_event_payload()` for constructing standardized event payloads.

**Camera existence checks** (`camera_exists_avigilon`, `camera_exists_dw`, `camera_exists_v3`) -- False-negative-safe verification functions that return `True` on any error to avoid accidentally disabling cameras.

**Stream URL construction** -- Multiple modules build [[rtsp-deep-dive|RTSP]] or HTTP stream URLs: Digital Watchdog (direct or proxied via Nx Cloud relay), Eagle Eye (feeds API v3, media streams v2), Exacq (HTTP [[mjpeg-and-still-image-formats|MJPEG]] or [[rtsp-deep-dive|RTSP]] depending on format type).

## Public API

Most modules expose module-level functions rather than classes. Notable exceptions are `AjaxCalls`, `AutoPatrolAPI`, `LisaClient`, and `MilestoneService` which are stateful clients.

## Dependencies

- `requests` -- HTTP client for all REST API calls
- `lxml` -- XML parsing (Milestone configuration)
- `actuate-admin-api` -- `AdminApi` for named configuration retrieval ([[ajax-components|Ajax]])
- Runtime dependencies on `actuate-config`, `actuate-daos`, `actuate-secrets`, `actuate-healthmonitoring`, `actuate-threadpool` (Milestone)

## Consumers

- [[actuate-alarm-senders]] -- alarm sender implementations call into these utilities for VMS-specific operations
- `vms-connector` and other connector services -- use these directly for camera discovery, stream URL construction, and login

## Notable Patterns

- All API calls are wrapped in try/except with logging; methods return `None` or empty collections on failure rather than raising.
- HTTP requests use explicit timeouts (10-30 seconds).
- The Milestone integration uses file-based token sharing (`milestone_token/token.txt`) for multi-process environments and has hardcoded S3 paths for specific customer server IPs (Genesis sites).
- Eagle Eye supports three separate API generations: Camera Manager, v2, and v3.
- Digital Watchdog has an `increase_connection_count()` function that tries multiple auth methods (Basic, Digest, Bearer, session token PATCH) in cascade to increase the NVR's max transcoding sessions.
