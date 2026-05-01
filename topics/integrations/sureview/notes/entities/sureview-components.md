---
title: "Sureview Integration Components"
type: entity
topic: integrations/sureview
tags: [integration, sureview, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
incoming_updated: 2026-05-01
---

# Sureview Integration Components

The `SureviewAlertSender` class in [[actuate-alarm-senders]] delivers detection alerts to Sureview Immix-style monitoring stations. The implementation closely mirrors the Immix sender, including the same URL formatting pattern and SES email support.

## Class Hierarchy

`SureviewAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It accepts an `ses_client` for optional email delivery via AWS SES. Like the Patriot sender, it checks for a `DEPLOYMENT_ID` environment variable to set `is_container`. A cached `video_loss_img` is maintained for `VideoLoss`/connection-issue events.

## Alert Format

The text body follows the standard Actuate pattern: "ACTUATE ALERT: Possible {labels} in {camera_name} at {local_time}". The alert URL is formatted identically to Immix -- `{base_url}?id={custcam_id}{label}@{s3_folder}` -- combining multiple parameters into a single URL parameter separated by `@`. The `event_type` is set to the detection label directly (unlike Immix which maps to SIA event types).

## Delivery Mechanism

Primary delivery is via SQS FIFO queue `event_queue_sureview_alarm.fifo`. The queue message includes `event_type`, serialized recipients (each with `send_to`, `port`, `server`, `subject`, `ses_cc`), `s3_folder` (window_id), `attachment_frames`, `custcam_id`, `immix_text`, `alert_url`, and `start_time`. A downstream consumer handles SMTP delivery to Sureview. There is also a `send_ses_alert()` method for direct SES email delivery using `sureview@actuate.ai` as the sender, typically used for the `ses_cc` debug copies.

## Key Config Fields

Per-recipient: `send_to` (Sureview email address), `server` (SMTP IP), `port` (typically 25), `subject` (email subject line), and `ses_cc` (optional CC for debugging). The `actuate_base_url` config provides the base for the formatted alert URL.

## Auth Method

Like Immix, no direct authentication to Sureview -- alerts are SMTP-based. The `ses_cc` path uses AWS SES with IAM credentials. The `get_connection_image()` method fetches a static `Actuate_ConnectionIssue.jpg` from the `actuate-misc-images` S3 bucket for video-loss events.
