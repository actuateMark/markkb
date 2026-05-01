---
title: "streamId-null rejection in Immix patrol alert dispatch"
type: concept
topic: vms-connector
tags: [bug, autopatrol, vch, immix, alert-dispatch, streamid, patrol-api]
jira: ""
status: open
severity: medium
discovered: 2026-04-20
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-04-21_cleanup-lambda-stage-verify.md
  - topics/autopatrol/notes/syntheses/2026-04-17_stale-schedule-cleanup-design.md
  - topics/camera-health-monitoring/notes/syntheses/chm-enhanced-diagnostics-proposal.md
  - topics/engineering-process/notes/syntheses/2026-04-20_lambda-creation-and-tuning-playbook.md
  - topics/personal-notes/notes/daily/2026-04-20.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/releases/notes/entities/2026-04-20_vms-connector-pr-1654.md
  - topics/vms-connector/_summary.md
  - topics/vms-connector/notes/concepts/2026-04-20_dev-powerplus-ssl-cert-verify-failure.md
incoming_updated: 2026-05-01
---

# streamId-null rejection in Immix patrol alert dispatch

Immix patrol API rejects `raise_patrol_alert` calls with **HTTP 400 `$.streamId cannot convert to System.Guid`** whenever the client sends `"streamId": null`, `""`, or `0`. This fires exactly when we most need to alert: when a patrol camera's stream-initialization fails and we attempt to dispatch a CNCTNFAIL ("connection failed") alert.

PR #1654 (merged 2026-04-20) exposed this architectural gap to the `:latest` production image by promoting AutoPatrol from `:stage`-only to full deployment. **Investigation complete (2026-04-20).** Full API patterns, failure-mode taxonomy, and Immix coordination requests filed as GH#1656. The root cause is not missing a field — the field genuinely doesn't exist when a stream-init call fails.

## API Call Pattern

**Base URLs** (from `actuate-integration-calls/autopatrol/autopatrol_api.py:19–24`):
- `develop` → `https://api.autopatrol.immixconnect.com/v/develop`, subscription `actuate-develop`
- `prod` → `https://autopatrol.immixconnect.com/v`, subscription `actuate`

**Common headers** (set by `request()` at autopatrol_api.py:27–32):
- `Ocp-Apim-Subscription-Id: actuate` (or `actuate-develop`)
- `Ocp-Apim-Subscription-Key: <api_key>` (secret `prod/actuate/autopatrol`)
- `Cache-Control: no-cache`
- `Region-Override: EU` (only when `region=EU`)

**Step 1 — fetch stream:**
```
GET {base_url}/Patrols/{patrol_id}/Device/{device_id}/videostream?Duration=2&Tier=1&ShortCodes=1
tenantId: <tenant_id>
```
Happy path: `{"deviceStreamUrl": "wss://...", "deviceStreamId": "<GUID>"}`. Puller stores `self.stream_id = res.json().get("deviceStreamId")` (autopatrol_websocket_stream_puller.py:338).

**Step 2 — raise alert (failing call):**
```
PUT {base_url}/Patrols/{patrol_id}/raise
Content-Type: application/json
tenantId: <tenant_id>

{"deviceId": "<device_id>", "threatData": [...], "streamId": null}
```
Immix 400: `{"$.streamId": ["The JSON value could not be converted to System.Guid..."]}`

## The streamId Field

- **Owner:** Immix. Returned as `deviceStreamId` from `get_patrol_stream()` on success (200/201).
- **Backend expectation:** valid GUID string; `null`, `""`, `0`, and fabricated client-UUIDs all fail with 400 error.
- **Correct code path:** `actuate_pullers/socket/autopatrol_websocket_stream_puller.py:338` — `self.stream_id = res.json().get("deviceStreamId")` after successful response.
- **Init path:** puller `__init__` at line 26 sets `self.stream_id = None`; remains None until `init_stream()` succeeds.

## The Bug Flow

1. Puller spawns; `stream_id = None`.
2. `init_stream()` (line 314) calls `autopatrol_api.get_patrol_stream(...)`.
3. Call fails: `res is None` / non-200 / missing `deviceStreamUrl` / DELETED response. Early-return, connectivity marked broken, `stream_id` still None.
4. VCH or AP healthcheck observes `connectivity.broken_stream = True` → emits CNCTNFAIL.
5. `vch_alert_sender.raise_alert()` (line 41, 86, 99) passes `puller.stream_id` (None) to `raise_patrol_alert`.
6. Library serializes `{"streamId": null, "deviceId": "...", ...}` at `actuate_integration_calls/autopatrol/autopatrol_api.py:383`.
7. Immix backend rejects: **400 `$.streamId could not be converted to System.Guid`**.

## Failure-Mode Taxonomy from `get_patrol_stream`

Over 7 days of `:stage` logs, five distinct failure responses, none returning a streamId:

| Failure mode | Response | streamId? |
|---|---|---|
| Read timeout (30s) | No response body | No |
| `API returned None` | No response body | No |
| `400 Patrol {uuid} status=Pending; not Started` | plain-text error | No |
| `400 Patrol {uuid} status=SiteDisabledOrDisarmed` | plain-text error | No |
| `400 No Streams found for device: {device_id}` | plain-text — **Immix explicitly says no stream exists** | No |

## All Affected Call Sites in vms-connector

| Location | Role | Current state | Issue |
|---|---|---|---|
| `camera/autopatrol/autopatrol_camera.py:165` | Real source | `puller.stream_id = 0` (local only) | Never assigns production streamId |
| `camera/patrol/patrol_camera.py:33` | **Anti-fix** | `self.stream_id = uuid.uuid4().hex` | Fabricates garbage GUID; data integrity failure |
| `camera/patrol/patrol_camera.py:74,76` | Real source | Reads `self.stream_id` (fabricated UUID in prod) | Perpetuates bad value |
| `camera/patrol/patrol_camera_mixin.py:201,205` | Passthrough | `puller.stream_id` with `""` default | Fallback to empty string |
| `site_manager/connector/integrations/autopatrol_site_manager.py:58-63,70` | Passthrough | `camera.puller.stream_id` with `""` default | Fallback to empty string |
| `site_manager/connector/integrations/patrol_site_manager.py:51` | Passthrough | Hardcoded `"stream_id": ""` | Always sends empty string |
| `healthcheck/alerts/senders/vch_alert_sender.py:41,86,99` | Passthrough | `puller.stream_id` unguarded | Passes None or fabricated UUID |

## Field-Name Note

We send `"streamId"` (camelCase) on the wire. Immix's canonical property is `DeviceStreamID` (PascalCase). .NET `System.Text.Json` is case-insensitive by default — both bind to the same property. Evidence: 1,005 successful `raise_patrol_alert` dispatches on `:stage` over 7 days vs 66 failures using the same payload structure. The field name is not the cause of rejection; the **null value** is. The error message cites `$.streamId` because that's the path in our payload, not Immix's property name.

## Why Client-Generated UUIDs Are Wrong

Generating a UUID client-side makes the API call succeed (no 400), but sends Immix a `streamId` that **does not exist in their database**. Immix will record an orphan alert unlinked from real stream data, silently drop it, or fail on downstream foreign-key checks — all silent data-integrity failures. **The 400 rejection was the correct backend behavior.**

Removing the UUID fabrication at `patrol_camera.py:33` is mandatory regardless of architectural fixes.

## Traced Real Failure (Reference)

Prod `:latest` 2026-04-20, patrol `9803fe76-fd82-4b61-61d8-08de9ee65bbd`, camera "Axis office camera camera (1)":
```
Step 1: GET /Patrols/9803fe76.../Device/<dev>/videostream?...
        → 400 "Patrol id 9803fe76-... status=Pending; not Started"
        → self.stream_id stays None
Step 2: PUT /Patrols/9803fe76.../raise
        Body: {"streamId": null, ...}
        → 400 "$.streamId cannot convert to Guid"
```
Step 1 told us the patrol is Pending (stream not provisioned); Step 2 fails because we have no identifier to provide. **Client-server deadlock:** we can only report "couldn't connect" by providing an identifier that only the (failed) connect call returns.

## Observed Volume

- **`:stage` 7-day window:** 65 occurrences of `raise_patrol_alert failed ... streamId` (FACETed post-mortem). 48 fell in the weekend regression check for PR #1654.
- **`:latest` post-merge (2026-04-20, T+180min):** 2 occurrences from site 24, camera "Axis office camera camera (1)", test schedules only (not customer-facing).
- **Customer impact:** Low today (test sites only). Every production AP customer hitting a real camera disconnect will fail identically.

## The Real Fix

Requires **Immix-side coordination** (filed as GH#1656):

**Preferred option:** Make `streamId` optional on `PUT /Patrols/{patrol_id}/raise` for connectivity-class detection codes (CNCTNFAIL, CNCTNRECOVERED, etc.). Key such alerts by `deviceId` + `patrolId` instead. Unblocks first-ever connectivity failures and reconnection alerts.

**Fallback option:** Provide a lookup endpoint — `GET /Patrols/{patrol_id}/Device/{device_id}/streamId` — returning the expected `DeviceStreamID` without requiring an active stream. Lets the connector pre-fetch and cache before open-stream calls fail.

**Connector-side cleanup** (unconditional, no backend dependency):
- Remove `uuid.uuid4().hex` at `patrol_camera.py:33` — fabricated GUIDs are data corruption
- Remove hardcoded `"stream_id": ""` at `patrol_site_manager.py:51`
- Log and skip dispatch on exception instead of defaulting `""` in `autopatrol_site_manager.py:63`

## Related cleanup-Lambda initiative (internal remediation path)

The `SiteDisabledOrDisarmed` failure class covers **5 of 10 recent samples** in GH#1656. That overlaps meaningfully with the stale-schedule cleanup Lambda initiative tracked in [[mark-todos]] §3 / §10 (built in `autopatrol_onboarder`).

The existing Lambda:
- Listens on SQS, fed by the connector on terminal "no patrols" exits
- Counts occurrences per `schedule_id` in DynamoDB
- At threshold (`max(3, 48h / cadence_hours)`), confirms with Immix API (404 / DEACTIVATED) and soft-deletes the schedule in admin

**Proposed extension (mark-todos §10):** add `SiteDisabledOrDisarmed` as a second signal into the same pipeline. Connector emits a distinct SQS event type on this failure. Cleanup Lambda tracks it separately from "no patrols" on a **longer window (e.g. 30 days)** because `SiteDisabledOrDisarmed` can be legitimately transient (sites armed only during business hours). Soft-disable only if continuously in that state for the whole window.

Orthogonal to the GH#1656 Immix-side work — that addresses the alert-dispatch deadlock for all CNCTNFAIL; the cleanup-Lambda extension addresses only the subset caused by persistently disabled sites.

## Cross-references

- GH#1656 — GitHub issue with Immix discussion thread and full evidence
- [[2026-04-20_vms-connector-pr-1654|PR #1654 release note]] — bug exposed when AP promoted to `:latest`
- [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]] — related bug discovered in the same investigation: WebSocket connections to dev.powerplus.com fail SSL cert verification fleet-wide, separate failure mode from streamId-null
- [[mark-todos]] §3, §10 — stale-schedule cleanup Lambda initiative; §10 tracks the `SiteDisabledOrDisarmed` signal extension
- [[2026-04-17_stale-schedule-cleanup-design]] — cleanup Lambda design synthesis
- `actuate-integration-calls` library: `autopatrol/autopatrol_api.py:361–406` (raise_patrol_alert definition)
- `actuate_pullers` library: `socket/autopatrol_websocket_stream_puller.py:314–345` (init_stream, where streamId should be sourced)
