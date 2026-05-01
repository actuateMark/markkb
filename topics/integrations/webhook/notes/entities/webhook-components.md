---
title: "Webhook Integration Components"
type: entity
topic: integrations/webhook
tags: [integration, webhook, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
incoming_updated: 2026-05-01
---

# Webhook Integration Components

The `WebhookAlertSender` class in [[actuate-alarm-senders]] is the generic outbound webhook integration, allowing customers to receive detection alerts at their own HTTP endpoints. It serves as the catch-all for customers who do not use a specific monitoring-station platform.

## Class Hierarchy

`WebhookAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It initializes `stream_id` and `webhook_event_types` from the config at construction. The `is_custcam_id_sender` property returns `True`, meaning webhook alerts are dispatched per custcam_id.

## Alert Format

The sender classifies alerts into three event types: `"no_motion"` (if the text contains "motion"), `"unable_to_connect"` (if "Unable to connect" is in the text), or `"detection"` (all other alerts). For detection events, the message body is a multi-line text block with detection labels, camera name, site name, local time, and the alert viewer URL. The payload includes rich metadata: `stream_id`, `label`, `site_name`, `display_name`, `camera_name`, `confidence`, `alert_url`, `time` (string-formatted local time), `event_type`, `message`, `camera_id` (admin camera ID), `camera_guid`, and camera `username`/`password` (for [[rtsp-deep-dive|RTSP]] access if needed).

## Delivery Mechanism

Alerts are dispatched via SQS FIFO queue `event_queue_webhook.fifo`. The `message_group_id` is the customer ID. Unlike the monitoring-station senders that use `recipients` config, the webhook sender sends a single payload per alert. The downstream consumer reads the queue and POSTs the JSON payload to the customer's configured webhook URL.

## Key Config Fields

`stream_id` (identifies the camera stream), `webhook_event_types` (list of event types the customer wants to receive), and `WebhookAlertConfig` from `actuate_config.alerts`. Camera credentials (`username`, `password`) are included in the payload with safe fallbacks to empty strings if not configured. The `camera_guid` is read via `getattr` with an empty-string default.

## Auth Method

No sender-side authentication. The webhook consumer handles any required auth (API keys, OAuth tokens, etc.) based on the customer's webhook configuration. Camera credentials passed in the payload allow the receiving system to access camera streams directly if needed.
