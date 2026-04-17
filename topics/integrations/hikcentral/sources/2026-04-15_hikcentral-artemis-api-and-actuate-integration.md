---
title: "Source: HikCentral Professional Artemis API and Actuate Integration"
type: source
topic: integrations/hikcentral
tags: [source, integration, hikcentral, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

HikCentral Professional (by Hikvision) exposes the **Artemis API**, a REST-style API accessed under the `/artemis/api/` path prefix. All requests use HMAC-SHA256 signed authentication. The API is used for event subscription and alarm triggering.

### Authentication

Authentication uses **HMAC-SHA256 signature** with Hikvision's proprietary signing scheme:

- **App Key** (`x-ca-key`): Identifies the application.
- **App Secret**: Used to compute the signature.
- **Nonce** (`x-ca-nonce`): Random UUID per request for replay protection.
- **Signature construction**: The canonical message includes the HTTP method, content-type headers, sorted custom headers (`accept-encoding`, `x-ca-key`, `x-ca-nonce`), and the URI path. This is HMAC-SHA256 signed with the app secret and base64-encoded.
- **Headers**: `X-Ca-Key`, `X-Ca-Nonce`, `X-Ca-Signature-Headers` (listing signed headers), `X-Ca-Signature`.

Protocol is HTTP or HTTPS depending on whether `server_port == 443`.

### Key Endpoints

- **Event Subscription** (`POST /artemis/api/eventService/v1/eventSubscriptionByEventTypes`): Subscribes to event types (e.g., `131331` for motion detection). The `eventDest` is a webhook URL (`https://signal.actuateui.net:443/eventRcv/{customer_id}`) that receives motion event callbacks.
- **General Event Rule List** (`POST /artemis/api/eventService/v1/generalEventRule/generalEventRuleList`): Lists configured general event rules (paginated with `pageNo`/`pageSize`).
- **Add General Event Rule** (`POST /artemis/api/eventService/v1/generalEventRule/single/add`): Creates a new general event rule with `generalEventRuleName`, `transportType`, `matchType`, `expression`, and `regularExpression`.
- **Trigger Alarm** (`POST /artemis/api/eventService/v1/generalEventRule/triggerAlarm`): Triggers an alarm from a general event rule using `generalEventRuleIndexCodes`.

### CHM-Relevant Diagnostics

- **Event subscription health**: The `subscribe_to_motion()` function logs success/failure of motion event subscription. Failed subscriptions trigger `internal_error_alert()`.
- **Trigger configuration**: `configure_triggers()` checks if triggers already exist (via `generalEventRuleList`) before creating them, preventing duplicate configuration. It creates detection-specific events (Slip and Fall, Fire, Gun, etc.) with regex matching patterns.
- **API reachability**: HTTP response codes from Artemis endpoints indicate server health. Non-200/201 responses are logged as errors.

### Actuate-Specific Notes

The integration module at `actuate-integration-calls/hikcentral/hikcentral_calls.py` provides three functions: `subscribe_to_motion()`, `send_request()` (generic signed request helper), and `configure_triggers()`. The integration is event-driven: HikCentral pushes motion events to Actuate's signal endpoint, which then triggers inference on the relevant camera. The `configure_triggers()` function pre-configures 12 detection event types (Postal Vehicle ID, Slip and Fall, Fire, Gun, Left Object, Hard Hat, Intruder, Vehicle Loitering, Loitering, Mask, No Mask, People Flow) with both exact and lowercase regex patterns.

The connector auth method is listed as "API Token" in the integration matrix. There is no dedicated HikCentral page in the Confluence KB space; references appear only in the EDOCS auto-generated documentation pages.

### Confluence References

- "actuate-integration-calls: API Integrations Reference" (EDOCS, page 496336908)
- "vms-connector: Supported Integrations" (EDOCS, page 496828419)
- "Integration Migration Status Table" (kb, page 160269555)
