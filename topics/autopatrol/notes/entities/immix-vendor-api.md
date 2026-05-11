---
title: "Immix Vendor API for AutoPatrol"
type: entity
topic: autopatrol
tags: [immix, api-reference, autopatrol, partner-integration, vch, openapi, autopatrol, immix, autopatrol, immix]
jira: ""
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
aliases: ["AutoPatrol Vendor API", "Immix Partner API", "Immix API"]
outgoing:
  - topics/autopatrol/notes/data/2026-05-06_immix-streamfinished-inquiry.md
  - topics/autopatrol/notes/syntheses/2026-05-07_consumer-side-websocket-close-feasibility.md
  - topics/personal-notes/notes/daily/2026-05-06.md
incoming:
  - topics/actuate-platform/notes/entities/actuate-admin-api.md
  - topics/admin-api/notes/concepts/2026-04-30_data-model-cascade-semantics.md
  - topics/autopatrol/_summary.md
  - topics/autopatrol/notes/concepts/2026-04-17_autopatrol-sync-endpoint-behavior.md
  - topics/autopatrol/notes/concepts/2026-04-17_no-patrols-emit-points.md
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/concepts/2026-04-24_stale-schedule-cleanup-investigation.md
  - topics/autopatrol/notes/concepts/2026-04-29_immix-zombie-tenants.md
  - topics/autopatrol/notes/concepts/autopatrol-alert-lifecycle.md
  - topics/autopatrol/notes/concepts/generic-patrol-mode.md
incoming_updated: 2026-05-09
---

# Immix Vendor API for AutoPatrol

HTTP REST API exposed by Immix for AI vendors to access AutoPatrol and VCH resources, manage contracts and schedules, and consume video streams for analysis. **This is the only integration surface between [[autopatrol-server]] and Immix.**

## Authoritative Sources

- **OpenAPI 3.0.1 spec** (canonical): `topics/autopatrol/notes/data/2026-05-06_immix-vendor-api-openapi-spec.json`
- **Live developer portal**: https://autopatrol-api.developer.azure-api.net/ (PROD)
- **Human guide**: Immix AI Partner/Vendor Developers Guide to AutoPatrol PDF (internal docs)

## Environments & Regions

| Environment | Developer Portal | Base URL | Notes |
|---|---|---|---|
| **PROD** | `https://autopatrol-api.developer.azure-api.net/` | `autopatrol.immixconnect.com` | Live customer traffic; **two geographic regions**: EU (UK, Germany, South Africa), US (USA); vendors must hit their tenant's region |
| **DEV** | `https://autopatrol-dev-apimanagment.developer.azure-api.net/` | (varies) | Development/testing; all regions allowed |

Auth: Include `ocp-apim-subscription-key` HTTP header with your API key. Tenant-scoped calls also require `tenantId` header.

## API Operations (OpenAPI 3.0.1)

**16 operations across 13 paths, no hidden endpoints.** OperationIds are stable references for tooling.

### Contracts
Represent the AI vendor–tenant relationship. Vendor activates contracts after provisioning user accounts.

| Method | Path | OperationId | Purpose |
|---|---|---|---|
| GET | `/Contracts` | `get-contracts` | List all contracts (paginated; filter by `contractStatus`) |
| GET | `/Contracts/{contractId}` | `get-contracts-contractid` | Single contract + contact details; may timeout (on-premise lookups) |
| PUT | `/Contracts/{contractId}` | `put-contracts-contractid` | Activate contract (set `contractStatus` to "Active") |

**Contract statuses:** Created, UnderReview, Rejected, Cancelled, Active, Suspended, Terminated

### Sites
Groups of cameras (devices) on the tenant's on-premise system. Only sites with a configured schedule appear.

| Method | Path | OperationId | Purpose |
|---|---|---|---|
| GET | `/Sites` | `get-sites` | List sites (paginated) |
| GET | `/Sites/{siteId}` | `get-sites-siteid` | Single site + device tree (returns `GroupModel` with `groupId`, `groupName`, devices) |
| GET | `/Sites/{siteId}/device/{deviceId}/preview` | `get-sites-siteid-device-deviceid-preview` | WebSocket preview stream URL; optional `duration` query param |
| GET | `/Sites/{siteId}/device/{deviceId}/RefShot` | `get-sites-siteid-device-deviceid-refshot` | Reference image (base64 JPEG/PNG); includes `placeholder` flag |

### Schedules
Define patrol recurrence (Cron) and sweep parameters. **States:** Awaiting (vendor must activate) → Active → Suspended / Paused / Removed / Deleted.

| Method | Path | OperationId | Purpose |
|---|---|---|---|
| GET | `/Schedules` | `get-schedules` | List schedules (filter by `scheduleStatus`, `siteId`; paginated) |
| GET | `/Schedules/{scheduleId}` | `get-schedules-scheduleid` | Single schedule + device list |
| PUT | `/Schedules/{scheduleId}` | `put-schedules-scheduleid` | Update schedule status (body: `AutoPatrolScheduleStatus` enum) |

**Schedule statuses:** Awaiting, Active, Suspended, Paused, Removed, Deleted  
**Patrol types (on both Schedules and Patrols):** AutoPatrol, VisualCameraHealth

### Patrols (Hot Path)
Individual patrol execution records. **1-minute server-side timeout:** vendor must call an endpoint (PUT start/raise/finish, GET stream, or WebSocket start) at least once per minute, or Immix terminates the DeviceWorker.

| Method | Path | OperationId | Purpose | Conformance |
|---|---|---|---|---|
| GET | `/Patrols` | `get-patrols` | List patrols (filter by `siteId`, `scheduleId`; paginated) | Timeout risk if idle >1 min |
| GET | `/Patrols/{patrolId}` | `get-patrols-patrolid` | Single patrol record | Tickles 1-min timeout |
| PUT | `/Patrols/{patrolId}` | `put-patrols-patrolid` | Update patrol status (body: `PatrolStatus` enum) | Resets timeout clock |
| GET | `/Patrols/{patrolId}/Device/{deviceId}/videostream` | `get-patrols-patrolid-device-deviceid-videostream` | Request video stream; query params: `Duration`, `Tier`, `ShortCodes[]` | **Each call = NEW session ID** — see [[2026-05-06_bugfix-stream-id-history-iteration]] |
| PUT | `/Patrols/{patrolId}/raise` | `put-patrols-patrolid-raise` | Raise threat detection (see RaisePatrolModel schema) | Send ASAP after detect; validate [[2026-04-20_streamid-null-patrol-alert-bug]] |

**Patrol statuses:** Pending, Started, Finished (patrol-level only — **no per-stream status**)

### Health Check

| Method | Path | OperationId | Purpose |
|---|---|---|---|
| GET | `/HeathCheck` | `get-heathcheck` | Vendor probe (typo in API: "Heath" not "Health") |

## Request/Response Models

All tenant-scoped operations include a **required `tenantId` header parameter**.

### Stream Response: VideoStreamModel

Returned by `/videostream` and `/preview` endpoints. **Note: `fileStoreId` is nullable, not currently parsed by our pullers.**

```json
{
  "deviceStreamUrl": "string (WebSocket URL, nullable)",
  "deviceStreamId": "string (UUID)",
  "lifeSpan": "string (duration/date-span ISO format)",
  "fileStoreId": "int32 (nullable, undocumented use)"
}
```

### Alert Dispatch: RaisePatrolModel

Body for `PUT /patrols/{patrolId}/raise`. **Required fields:** `deviceId`, `streamId`, `threatData[]`.

```json
{
  "deviceId": 13,
  "streamId": "UUID-from-videostream-call",
  "threatData": [
    {
      "detectionCode": "string",
      "tier": 1,
      "description": "string (nullable)",
      "media": [
        {
          "mimeType": "string (nullable)",
          "url": "string (nullable)",
          "imageType": "string (nullable)"
        }
      ]
    }
  ]
}
```

## API Coverage in actuate-integration-calls

Our library (`actuate_integration_calls.autopatrol.autopatrol_api`) implements full coverage. Every spec operation has a corresponding method:

| Spec Operation | Library Method |
|---|---|
| GET /Contracts | `get_contracts`, `get_awaiting_contracts` (filtered) |
| GET /Contracts/{id} | `get_contract` |
| PUT /Contracts/{id} | `activate_contract`, `put_contract` |
| GET /HeathCheck | `get_healthcheck` |
| GET /Patrols | `get_patrols` |
| GET /Patrols/{id} | `get_patrol` |
| PUT /Patrols/{id} | `start_patrol`, `end_patrol`, `update_patrol` |
| GET /Patrols/.../videostream | `get_patrol_stream` |
| PUT /Patrols/{id}/raise | `raise_patrol_alert` |
| GET /Schedules | `get_schedules`, `get_awaiting_schedules` (filtered) |
| GET /Schedules/{id} | `get_schedule` |
| PUT /Schedules/{id} | `activate_schedule`, `put_schedule` |
| GET /Sites | `get_sites` |
| GET /Sites/{id} | `get_site`, `get_devices` |
| GET /Sites/.../preview | `get_device_preview` |
| GET /Sites/.../RefShot | `get_device_reference_image` |

**No new endpoints to add.** Possible enhancements: parse `fileStoreId` in stream responses, generate Pydantic models from spec for type-safe responses.

## The `AutoPatrolActionType` Gap: Confirmed Internal-Only

A screenshot from Immix's internal audit surface shows an `AutoPatrolActionType` enum with values: Started, Finished, Raised, TimeoutCheck, Timeout, StreamUrlRequested, StreamPending, StreamStarted, **StreamFinished, StreamFailed, AudioClipRequested, AudioClipFinished, AudioClipFailed**.

**Confirmed by OpenAPI 3.0.1 spec:** `AutoPatrolActionType` does **NOT** appear in the partner-facing API at all. The spec defines no:
- Schema component for `AutoPatrolActionType`
- Endpoint to POST/PUT a `StreamFinished`, `StreamFailed`, or `AudioClip*` action
- `streamStatus` field on any stream resource
- Audio clip lifecycle endpoints

**Conclusion:** `AutoPatrolActionType` is an **Immix-internal enum only** — audit logging, observability, or internal API. Partners cannot write to it.

**Misdiagnosis context:** [[2026-05-06_immix-streamfailed-worker-lifespan]] documents that every no-detection patrol is labeled `StreamFailed` in Immix's UI despite successful completion (HTTP 200, correct patrol status). The label is driven by the DeviceWorker's lifespan timer expiring as designed — the requested duration limit hitting its boundary is normal termination, not a failure. Immix's labeling layer conflates timer expiry with "stream failure," which is why [[autopatrol-server]] sees no failure signal in the partner API but sees "failed" in the internal UI.

## One-Minute Timeout Operational Impact

Every active patrol has a hard server-side timeout: **if the vendor makes no API call (PUT start/raise/finish or GET stream/WebSocket start) for 60 seconds, Immix terminates the DeviceWorker and marks the patrol timed out.**

**Connector behavior:** The patrol cronjob in [[autopatrol-server]] implicitly tickles this timeout with each `get_patrol_stream` and `raise_patrol_alert` call. A quiet patrol that runs 10 seconds and yields no detections is safe if the cronjob's poll cycle is ≤60 seconds. If a patrol "hangs" (consumer stuck in `consume_stream`) and blocks the cronjob loop, other patrols may timeout.

See [[2026-05-06_immix-streamfailed-worker-lifespan]] for the Worker's perspective on lifespan limits and graceful closure.

## Cross-References

- [[autopatrol-server]] — our orchestrator; main consumer of this API
- [[2026-05-06_bugfix-stream-id-history-iteration]] — fix for stream_id mismatch on WebSocket reconnect
- [[2026-04-20_streamid-null-patrol-alert-bug]] — null-guard validation on raise side (GH#1656)
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — Worker lifecycle and the misdiagnosed "streamfailed" label
- [[2026-04-23_immix-api-error-patterns]] — error response catalogue
- [[2026-04-29_immix-zombie-tenants]] — operational issue with stale tenant onboarding state
