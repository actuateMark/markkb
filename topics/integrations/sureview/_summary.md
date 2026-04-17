---
title: "SureView Integration"
type: summary
topic: integrations/sureview
tags: [integration, monitoring, sureview]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# SureView Integration

SureView (SureView Immix Operations, formerly SureView Systems) is a professional alarm monitoring and response management platform. Actuate integrates with SureView as an alert destination, delivering AI detection events into the SureView operator workflow via SMTP email with image attachments.

## Components

### SureviewAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `sureview/sureview_alert_sender.py`. Extends `EventListenerAlertSender`. Alerts are delivered **asynchronously via SQS** -- the sender formats a payload and pushes it to the `event_queue_sureview_alarm.fifo` queue, where a downstream event-listener worker delivers the alert.

The alert payload includes:
- `recipients` -- JSON-serialized list of recipient configs, each with `send_to` (email), `server`, `port` (587), `subject`, and optional `ses_cc` (debug copy via AWS SES)
- `immix_text` -- Human-readable alert text (e.g., "ACTUATE ALERT: Possible intruder and vehicle in CameraName at 04/13/26, 2:30 PM EST")
- `alert_url` -- A specially formatted URL combining `custcam_id`, `label`, and `s3_folder` into a single parameter (SureView only accepts one URL parameter), using `@` as separator
- Standard fields: `event_type`, `custcam_id`, `attachment_frames`, `s3_folder`

The sender also has a `send_ses_alert()` method for direct email delivery via AWS SES as a fallback or debugging mechanism, and a `get_connection_image()` helper that retrieves a cached "Connection Issue" placeholder image from S3 for video loss alerts. Container-mode detection is available via the `DEPLOYMENT_ID` environment variable.

### SureviewAlertConfig (config)

Defined in [[actuate-config]] at `alerts/sureview/sureview_alert_config.py`. Extends `BaseAlertSenderConfig`. Supports multiple recipients, each as a `SureviewRecipientConfig` with `send_to` (email address), `server` (SMTP server), `port` (fixed at 587), `subject` (defaults to "Actuate Detected -"), and optional `ses_cc`.

## Auth Method

**SMTP-based delivery.** No API authentication is required from the sender side -- alerts are delivered as emails to the SureView receiver's SMTP server. The `ses_cc` mechanism uses AWS SES credentials (inherited from the event-listener's AWS role) for debug copies.

## Alert Delivery

SureView follows the standard SQS event-listener pattern. The event-listener worker dequeues from the FIFO queue, retrieves and annotates frames from S3/DynamoDB, and delivers the formatted email with image attachments to each configured SureView recipient SMTP endpoint.

## Architecture

The alarm sender factory in [[actuate-alarm-senders]] instantiates `SureviewAlertSender` when a SureView alert config is present. The sender requires an `ses_client` dependency (AWS SES client). There are no SureView-specific puller or integration calls components -- it is a send-only monitoring integration. The [[vms-connector]] builds the sender via the factory during camera initialization.
