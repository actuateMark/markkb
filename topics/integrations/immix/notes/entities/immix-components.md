---
title: "Immix Integration Components"
type: entity
topic: integrations/immix
tags: [integration, immix, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Immix Integration Components

Immix is Actuate's primary monitoring-station partner. The `ImmixAlertSender` class in [[actuate-alarm-senders]] delivers detection alerts to Immix CS/AI monitoring stations. Immix is the most feature-complete sender and was the first integration built, so several other senders (Sureview, Sentinel) borrow its patterns.

## Class Hierarchy

`ImmixAlertSender` inherits from `EventListenerAlertSender`, which itself extends `AttachmentAlertSender` (frame annotation logic, S3/DynamoDB frame retrieval) and ultimately `BaseAlertSender` (abstract `send()` contract). The `EventListenerAlertSender` layer wires up an `EventListener` for internal queue dispatch. `ImmixAlertSender` accepts an `ses_client` at construction for optional SES email CC copies.

## Alert Format

Alerts are packaged as a dictionary containing `event_type` (mapped from detection labels -- `IntruderDetected`, `PersonDetected`, or `ObjectDwell`), `immix_text` (human-readable description with camera name, labels, and local timestamp), `alert_url` (Actuate UI link with `custcam_id`, label, and `s3_folder` encoded as a single URL parameter separated by `@`), and per-recipient fields. The `is_custcam_id_sender` property returns `True`, meaning alerts are keyed by custcam_id.

## Delivery Mechanism

Alerts are dispatched via SQS FIFO queue `event_queue_immix_alarm.fifo`. The `send()` method serializes recipient configs (SMTP server, port, `send_to` email, `input1` camera identifier, optional `ses_cc`, `draw_ignore_zones`, `use_mp4` flags) into a JSON payload and calls `self.event_listener.send_to_queue(data)`. A downstream consumer reads the FIFO queue and performs the actual SMTP delivery to the Immix station.

## Key Config Fields

Each recipient requires `send_to` (Immix email address), `input1` (Immix camera/input number), `server` (SMTP IP), `port` (typically 25), `ses_cc` (optional debug CC), `draw_ignore_zones`, and `use_mp4`. When `use_mp4` is enabled, `attachment_frames` is multiplied by `product_fps`. The sender also supports `VideoLoss` events with a cached `Actuate_ConnectionIssue.jpg` image from S3.

## Auth Method

No direct authentication to Immix -- alerts are delivered via SMTP to the Immix station's email receiver. AWS SES credentials are used only for the optional `ses_cc` debug copy. Queue access relies on the IAM role of the running service.
