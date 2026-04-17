---
title: "LISA Integration"
type: summary
topic: integrations/lisa
tags: [integration, monitoring, lisa]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# LISA Integration

LISA (Leitstellen-Software) is a German alarm monitoring and control-room platform used by security operations centers to receive and dispatch security events. Actuate integrates with LISA as an alert destination, forwarding verified AI detections and Frontel protocol events to the LISA webhook API.

## Components

### LisaAlertSender

Defined in [[actuate-alarm-senders]] at `lisa/lisa_alert_sender.py`. Extends `EventListenerAlertSender`. Unlike most alert senders that implement `send()`, Lisa primarily uses `send_clips()` for clip-based analysis results. The sender:

- Only forwards clips tagged as `"Verified"` -- unverified clips are silently skipped.
- Builds event text from detected labels (uppercased, underscores replaced with spaces) or from direct Frontel protocol event fields.
- Constructs a URL pointing to the Actuate clips viewer for the customer's site and date.
- Iterates over all configured `recipients` and sends each alert to `event_queue_lisa_alarm.fifo` via the event listener, including server endpoint, account number, area, zone, event, text, token, timezone, and connection/sourcetype metadata.

### LisaClient -- Integration Calls Module

Defined in [[actuate-integration-calls]] at `lisa/lisa.py`. A lightweight REST client for the LISA webhook API. Supports:

- **`post_events(payload)`** -- sends event or state payloads to `/events/actuate`.
- **`make_event_payload(...)`** -- builds a structured event dict with TYPE, MID (UUID), CREATED timestamp, ID (account number), AREA, ZONE, EVENT, TEXT, URL, REF, CONNECTION, SOURCETYPE, and additionalData fields.
- **Path-based event endpoints** -- `post_event_for_object()` (`/ev/event/{ObjectNumber}/{event}`), `post_event_for_oid()` (`/ev/oevent/{oid}/{event}`), `post_event_for_device()` (`/ev/device/{id}/{event}`).

Authentication uses an optional **Bearer token** in the `Authorization` header. The base URL defaults to `http://lisaapi.leitstellensoftware.de:16123` or can be overridden with a full server URL.

### LisaAlertConfig

Defined in [[actuate-config]] at `alerts/lisa/lisa_alert_config.py`. Each recipient specifies `lisa_server` (endpoint URL) and `lisa_token` (Bearer token). Multiple recipients can be configured per feature deployment.

### Puller

No LISA-specific puller. LISA is a send-only monitoring integration.

## Auth Method

**Bearer token authentication.** Each LISA recipient has its own `lisa_token` sent as `Authorization: Bearer <token>` on API calls. The token is configured per-site in the `lisa_alerts` section of the feature deployment.

## Alert Delivery

Alerts follow the **SQS FIFO queue** pattern (`event_queue_lisa_alarm.fifo`). The sender writes structured messages to the queue; a downstream consumer reads them and posts to the LISA webhook API using the `LisaClient`.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- LisaAlertSender
- [[actuate-integration-calls]] -- LisaClient for the LISA webhook API
- [[actuate-config]] -- LisaAlertConfig with per-recipient server and token
- [[vms-connector]] -- builds the sender via the alarm-sender factory
- No corresponding module in [[actuate-pullers]]
