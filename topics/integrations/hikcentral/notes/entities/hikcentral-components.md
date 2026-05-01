---
title: "Hikcentral Integration Components"
type: entity
topic: integrations/hikcentral
tags: [integration, hikcentral, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-event-listener.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/integrations/hikcentral/_summary.md
  - topics/integrations/video-insight/notes/entities/video-insight-components.md
  - topics/video-processing/notes/concepts/connector-decoder-routing-map.md
incoming_updated: 2026-05-01
---

# Hikcentral Integration Components

## HikcentralAlertSender

`HikcentralAlertSender` extends `EventListenerAlertSender` and delivers detection alarms to HikCentral Professional via an SQS event queue. On initialization, it calls `configure_triggers(self.config)` from the hikcentral integration calls module to ensure the required generic event rules exist on the HikCentral server.

The `send(alert_data)` method constructs an SQS message containing:

- `queue_id`: Fixed to `"event_queue_hikcentral_alarm.fifo"` (a FIFO SQS queue).
- `recipient`: A JSON-serialized dictionary with `server_ip`, `server_port`, `secret` (HMAC signing key), `app_key`, and `alert_port` from the connector config.
- `alert`: The detection label mapped to a HikCentral event name via `__label_to_event()`.

The `__label_to_event()` private method maps Actuate detection labels to HikCentral-specific event names: postal vehicle labels (amazon, dhl, fedex, ups, usps, school_bus) map to "Postal Vehicle ID"; fire/smoke to "Fire"; gun/pistol to "Gun"; fall to "Slip and Fall"; intruder/bike/vehicle to "Intruder"; and specific labels to "Left Object", "Hard Hat", "Vehicle Loitering", "Loitering", "Mask", "No Mask", and "People Flow". The message is delivered via `self.event_listener.send_to_queue()`.

## Hikcentral Integration Calls (hikcentral_calls)

The `hikcentral_calls` module handles the HikCentral Open Platform (Artemis) API, which uses HMAC-SHA256 signed requests.

### send_request(config, method, uri, body)

The core HTTP client function. It constructs the `X-Ca-Signature` by HMAC-SHA256-signing a canonical message string that includes the HTTP method, content type headers, `X-Ca-Key`, a random `X-Ca-Nonce`, and the URI path. The signature is Base64-encoded and included in the request headers alongside `X-Ca-Key`, `X-Ca-Nonce`, and `X-Ca-Signature-Headers`. The protocol (HTTP vs HTTPS) is selected based on whether `server_port` is 443.

### configure_triggers(config)

Called once during alarm sender initialization. It first checks if generic event rules already exist by querying `/artemis/api/eventService/v1/generalEventRule/generalEventRuleList`. If no rules are found, it creates 12 predefined generic event rules (Postal Vehicle ID, Slip and Fall, Fire, Gun, Left Object, Hard Hat, Intruder, Vehicle Loitering, Loitering, Mask, No Mask, People Flow) via `/artemis/api/eventService/v1/generalEventRule/single/add`. Each rule includes a `regularExpression` that matches both the title-case and lowercase versions. After creation, it retrieves the full list and configures alarm triggers for each via `/artemis/api/eventService/v1/generalEventRule/triggerAlarm`.

### subscribe_to_motion(config, customer_id, dao_manager)

Subscribes to HikCentral motion detection events (event type 131331) by posting to `/artemis/api/eventService/v1/eventSubscriptionByEventTypes`. The callback destination is `https://signal.actuateui.net:443/eventRcv/{customer_id}`.

## HikcentralConnectorConfig

`HikcentralConnectorConfig` extends `BaseConnectorConfig` with `HikcentralCustomerConfig` containing: `server_ip`, `server_port`, `secret` (the HMAC signing secret), and `app_key`. `HikcentralCamera` adds `camera_id` (from `camera_uid`) and `stream_quality` (clamped to 0 or 1). The `HikcentralFeatureDeployment` is unique in that it injects the hikcentral connection details (`server_ip`, `server_port`, `secret`, `app_key`, `hikcentral_alert_port`) directly into each feature deployment's configuration, making them available per-camera-stream for alarm routing.
