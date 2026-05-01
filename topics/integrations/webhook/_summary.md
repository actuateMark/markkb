---
title: "Webhook Integration"
type: summary
topic: integrations/webhook
tags: [integration, monitoring, webhook]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Webhook Integration

The webhook integration is a **generic, customer-configurable alert delivery mechanism** in Actuate. Unlike purpose-built monitoring integrations (Immix, [[sentinel-components|Sentinel]], SureView) that target specific platforms, the webhook sender delivers structured JSON alert payloads to any customer-specified HTTP endpoint, making it the most flexible outbound alert option.

## Components

### WebhookAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `webhook/webhook_alert_sender.py`. Extends `EventListenerAlertSender`. Alerts are delivered **asynchronously via SQS** -- the sender formats a payload and pushes it to the `event_queue_webhook.fifo` queue, where a downstream event-listener worker delivers the HTTP POST to the customer's endpoint.

The alert payload includes:
- `stream_id` -- identifier for the camera stream
- `label` -- the detection label (e.g., "intruder", "gun", "fire")
- `site_name` and `display_name` -- customer identifiers
- `camera_name` -- the source camera
- `confidence` -- detection confidence score
- `alert_url` -- link to the Actuate alert viewer
- `time` -- human-readable timestamp
- `event_type` -- categorized as `detection`, `no_motion`, or `unable_to_connect` based on the alert content
- `message` -- formatted alert text varying by event type (detection events include full details with camera, site, time, and viewer link)
- `camera_id`, `camera_guid`, `username`, `password` -- camera identification and optional credentials

The sender classifies alerts into three event types: `detection` (standard AI detections), `no_motion` (camera health), and `unable_to_connect` (connectivity failure), each with different message formatting. The `webhook_event_types` config field controls which event types the webhook should fire for.

The `is_custcam_id_sender` property returns `True`, indicating this sender operates at the camera-stream level rather than the site level.

### WebhookAlertConfig (config)

Defined in [[actuate-config]] at `alerts/webhook/webhook_config.py`. Extends `BaseAlertSenderConfig` with `stream_id` and `webhook_event_types` -- a filter that controls which event categories trigger webhook delivery.

## Auth Method

No authentication is configured on the sender side. The event-listener worker delivers HTTP POSTs to the customer's endpoint URL, and it is the customer's responsibility to secure their receiving endpoint. Customers can configure their webhook URL and any required headers through the Actuate admin interface.

## Alert Delivery

Webhooks follow the standard SQS event-listener pattern: the sender enqueues to `event_queue_webhook.fifo` with `message_group_id` for per-customer FIFO ordering. The event-listener worker dequeues and delivers the HTTP POST. This decoupled architecture means slow or failing customer endpoints do not block the [[detection-pipeline|detection pipeline]].

## Architecture

The alarm sender factory in [[actuate-alarm-senders]] instantiates `WebhookAlertSender` when a webhook alert config is present. There are no webhook-specific puller or integration calls components -- video ingestion uses whatever VMS integration is configured, and the webhook is purely an outbound alert mechanism. The [[vms-connector]] builds the sender via the factory during camera initialization. Webhooks are often configured alongside other monitoring senders (e.g., a site may send to both Immix and a customer webhook).
