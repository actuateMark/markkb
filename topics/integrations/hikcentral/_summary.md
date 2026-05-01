---
title: "HikCentral Integration"
type: summary
topic: integrations/hikcentral
tags: [integration, vms, hikcentral]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# HikCentral Integration

[[hikcentral-components|HikCentral]] is Hikvision's centralized video management platform for managing IP cameras, NVRs, and security events at scale. Actuate integrates with HikCentral both as a video source (via its [[rtsp-deep-dive|RTSP]] streams) and as an alert destination, pushing AI-generated events back into HikCentral's event system through the Artemis OpenAPI.

## Components

### HikcentralAlertSender

Defined in [[actuate-alarm-senders]] at `hikcentral/hikcentral_alert_sender.py`. Extends `EventListenerAlertSender`. On initialization it calls `configure_triggers()` to ensure generic event rules exist in [[hikcentral-components|HikCentral]]. When `send()` fires, it maps Actuate detection labels to HikCentral event names (e.g., "intruder" becomes "Intruder", "fire"/"smoke" becomes "Fire", "gun"/"pistol" becomes "Gun") and sends the alert to the `event_queue_hikcentral_alarm.fifo` SQS FIFO queue with the recipient's server IP, port, secret, app key, and alert port.

### Integration Calls -- hikcentral_calls

Defined in [[actuate-integration-calls]] at `hikcentral/hikcentral_calls.py`. Provides:

- **`send_request(config, method, uri, body)`** -- builds HMAC-SHA256 signed requests for the Artemis OpenAPI. Signs a canonical message containing the HTTP method, content type, and `x-ca-key`/`x-ca-nonce` headers. The signature goes in the `X-Ca-Signature` header.
- **`subscribe_to_motion(config, customer_id, dao_manager)`** -- subscribes to HikCentral motion events (event type 131331) with a callback URL at `signal.actuateui.net`.
- **`configure_triggers(config)`** -- checks whether generic event rules already exist; if not, creates rules for each Actuate detection type (Intruder, Fire, Gun, Slip and Fall, etc.) and configures alarm triggers for them.

### HikcentralConnectorConfig

Defined in [[actuate-config]] at `connector/hikcentral/hikcentral_config.py`. Extends `BaseConnectorConfig` with:

- `HikcentralCustomerConfig` -- adds `server_ip`, `server_port`, `secret` (hikcentral_secret), and `app_key` (hikcentral_key).
- `HikcentralCamera` -- adds `camera_id` (from `camera_uid`) and `stream_quality` (0 or 1).
- `HikcentralFeatureDeployment` -- propagates HikCentral credentials and alert port into each feature deployment.

### Puller

No dedicated HikCentral puller. HikCentral exposes [[rtsp-deep-dive|RTSP]] streams, which are consumed by the standard RTSP puller in [[actuate-pullers]].

## Auth Method

**HMAC-SHA256 API signing** via the Artemis OpenAPI. Each request is signed using `app_key` and `secret` credentials. The signature covers the HTTP method, content types, and custom headers (`x-ca-key`, `x-ca-nonce`). A unique nonce (UUID) is generated per request to prevent replay attacks.

## Alert Delivery

Alerts go through the **SQS FIFO queue** pattern (`event_queue_hikcentral_alarm.fifo`). The sender writes alert metadata to the queue; a downstream consumer reads messages and posts the events to [[hikcentral-components|HikCentral]] via the signed Artemis API.

## Key Config Fields

`server_ip`, `server_port`, `hikcentral_secret`, `hikcentral_key`, `hikcentral_alert_port`. Per-camera: `camera_uid`, `stream_quality`.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- HikcentralAlertSender
- [[actuate-integration-calls]] -- hikcentral_calls (HMAC signing, motion subscription, trigger configuration)
- [[actuate-config]] -- HikcentralConnectorConfig with customer/camera/deployment config
- [[actuate-pullers]] -- standard [[rtsp-deep-dive|RTSP]] puller for video ingestion
- [[vms-connector]] -- initializes the sender and configures triggers on startup
