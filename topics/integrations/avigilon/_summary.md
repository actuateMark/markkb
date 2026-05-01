---
title: "Avigilon Integration"
type: summary
topic: integrations/avigilon
tags: [integration, vms, avigilon, acc]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Avigilon Integration

Avigilon (now part of Motorola Solutions) is a VMS platform with its Avigilon Control Center (ACC) software. Actuate integrates with Avigilon for both alert delivery and camera verification.

## Components

### AvigilonAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `avigilon/avigilon_alert_sender.py`. Extends `AttachmentAlertSender`. Alerts are sent **synchronously via HTTP REST** to the Avigilon ACC Web API -- no SQS queue is involved.

The alert flow:

1. **Retrieve alarm list** -- `GET {api_endpoint}alarms?session={session_key}` to fetch all configured alarms.
2. **Match by camera name** -- Iterates through the alarm list to find the alarm whose `name` matches the current camera's name, extracting the `alarm_id`.
3. **Trigger alarm** -- `PUT {api_endpoint}alarm` with the alarm ID, action `TRIGGER`, the detection label as `note`, and `permission=GRANT`.

This means alarms must be **pre-configured** in the Avigilon ACC with names matching the Actuate camera names. The sender retries on failure (with no retry limit -- potentially infinite recursion).

Config fields: `customer.api_endpoint` (ACC Web API base URL), `customer.session_key` (pre-existing session key).

### Avigilon Integration Calls

Defined in [[actuate-integration-calls]] at `avigilon/avigilon_utils.py`. Contains a single function:

- `camera_exists_avigilon(api_endpoint, session_key, camera_id)` -- Queries `GET {api_endpoint}cameras?session={session_key}` to list cameras on the NVR, then checks if the specified `camera_id` exists. Returns `True` on any error to avoid false negatives that could accidentally disable cameras.

## Auth Method

**Pre-existing session key.** The Avigilon ACC Web API uses session-based authentication. The `session_key` is obtained externally (likely through a manual login or separate auth flow) and stored in the customer config. No automatic token refresh or login is implemented -- if the session expires, alerts will fail.

## Architecture

The [[vms-connector]] uses the Avigilon integration calls to verify camera existence during initialization. Streams from Avigilon cameras are consumed via standard [[rtsp-deep-dive|RTSP]] URL-based pullers in [[actuate-pullers]] (no Avigilon-specific puller). When detections occur, the `AvigilonAlertSender` triggers alarms directly against the ACC Web API. The integration is relatively lightweight compared to [[integration-milestone|Milestone]] or [[integration-digital-watchdog|Digital Watchdog]] -- no complex auth flows, no cloud proxy support.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- AvigilonAlertSender lives here, extending AttachmentAlertSender
- [[actuate-integration-calls]] -- `avigilon_utils.py` provides camera existence checks
- [[vms-connector]] -- consumes integration calls for camera verification, builds the sender via factory
- [[actuate-pullers]] -- standard URL pullers used (no Avigilon-specific puller)
