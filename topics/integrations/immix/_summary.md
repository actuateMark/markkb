---
title: "Immix Integration"
type: summary
topic: integrations/immix
tags: [integration, monitoring, immix, autopatrol]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Immix Integration

Immix is the **primary monitoring center partner** for Actuate, representing approximately **$800K in 12-month VCH revenue**. The integration delivers AI-generated alerts from the Actuate pipeline into the Immix alarm monitoring platform, and also powers the [[integration-autopatrol-integration|AutoPatrol]] virtual patrol product built on Immix Connect.

## Components

### ImmixAlertSender

Defined in [[actuate-alarm-senders]] at `immix/immix_alert_sender.py`. Extends `EventListenerAlertSender` (which itself extends `AttachmentAlertSender`). Alerts are delivered **asynchronously via SQS** -- the sender builds a message payload and pushes it to the `event_queue_immix_alarm.fifo` queue, where a downstream event-listener worker picks it up and delivers the actual **SMTP email** to the Immix receiver. Key fields in the payload include `recipients` (each with `send_to`, `input1`, `port`, `server`, `ses_cc`), `immix_text`, `event_type`, and `attachment_frames`. The sender maps detection labels to Immix event types (`IntruderDetected`, `PersonDetected`, `ObjectDwell`). An `ses_cc` field allows a debug copy via AWS SES. The sender also supports `use_mp4` for video clip attachments and participates in the clips alert factory (`build_clips_alert_senders`).

Config fields: `actuate_base_url`, `recipients[].send_to`, `recipients[].input1`, `recipients[].port`, `recipients[].server`, `recipients[].ses_cc`, `recipients[].draw_ignore_zones`, `recipients[].use_mp4`.

### AutoPatrolAlertSender

Defined at `immix/autopatrol_sender.py`. Also extends `EventListenerAlertSender`. This sender powers the **AutoPatrol** product -- virtual patrols sold through Immix Connect. It uses the [[actuate-integration-calls]] `AutoPatrolAPI` client to call `raise_patrol_alert()` on the Immix Connect REST API, authenticated via `Ocp-Apim-Subscription-Key`. Detection labels are mapped to `AutoPatrolDetectionCodeEnum` values (PERSON, VEHICLE, BIKE, FIRE, SMOKE, CROWD, delivery-specific codes). The sender builds annotated frame images (bounding boxes drawn on S3 frames), uploads them, and sends a presigned URL. Alerts are also persisted to DynamoDB via `AutoPatrolDAO`.

Config fields: `autopatrol.api_key`, `autopatrol.stage` (prod/develop), `autopatrol.region` (US/EU), `autopatrol.tenant_id`, `autopatrol.patrol_id`.

### AutoPatrolAPI (integration-calls)

Full REST client in [[actuate-integration-calls]] at `autopatrol/autopatrol_api.py`. Manages the complete AutoPatrol lifecycle: contracts, schedules, patrols, sites, devices, and stream previews. The base URL switches between `autopatrol.immixconnect.com/v` (prod) and `api.autopatrol.immixconnect.com/v/develop` (develop). Supports EU region override via header.

## Auth Method

- **ImmixAlertSender:** SMTP-based delivery (server, port, email address). No API auth -- relies on network-level SMTP access.
- **AutoPatrol:** Subscription key auth (`Ocp-Apim-Subscription-Key` header) against the Immix Connect API.

## Architecture

Immix alerts flow through the [[actuate-alarm-senders]] `MultiAlertSender` fan-out, are queued to SQS FIFO, and processed by the event-listener service. AutoPatrol alerts are sent directly via HTTP from the [[vms-connector]] process. Both senders are instantiated by the alarm sender factory in [[actuate-alarm-senders]] based on config type.
