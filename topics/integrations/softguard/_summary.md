---
title: "Softguard Integration"
type: summary
topic: integrations/softguard
tags: [integration, monitoring, softguard]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Softguard Integration

[[softguard-components|Softguard]] is a professional alarm monitoring and security management platform used by monitoring centers (ARCs), primarily in Latin America. Actuate integrates with Softguard as an alert destination, delivering AI detection events into the Softguard alarm processing workflow via an SQS-based event queue.

## Components

### SoftguardAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `softguard/softguard_alert_sender.py`. Extends `EventListenerAlertSender` (which provides SQS event queue dispatch). Alerts are delivered **asynchronously via SQS** -- the sender formats a payload and pushes it to the `event_queue_softguard_alarm.fifo` queue, where a downstream event-listener worker delivers the alert to the [[softguard-components|Softguard]] receiver.

The alert payload includes:
- `zone` -- Softguard zone identifier
- `account` -- Softguard account number for the monitored site
- `user` and `user_ext` -- Softguard user identifier and extension
- `server` and `port` -- the Softguard receiver endpoint (from `recipient` config)
- `attachment_frames` -- number of frames to include with the alert
- Standard fields: `event_type`, `customer_name`, `camera_name`, `alert_url`, `custcam_id`, `label`, `s3_folder`

The sender maintains a `sequence_number` that increments with each successful send and wraps at 99999, providing a monotonic ordering reference for the Softguard receiver.

### SoftguardAlertConfig (config)

Defined in [[actuate-config]] at `alerts/softguard/softguard_alert_config.py`. Extends `BaseAlertSenderConfig` with Softguard-specific fields: `zone`, `account`, `user`, `user_ext`, `alarm_type` (defaults to "E999"), and a `SoftguardRecipientConfig` containing the receiver `server` and `port`. Includes a `to_json()` method for serialization.

## Auth Method

No explicit API authentication. The [[softguard-components|Softguard]] receiver is identified by `server` IP and `port`, and the `account`, `zone`, and `user` fields serve as the site/device identifier within the Softguard system. Access relies on network-level connectivity to the Softguard receiver.

## Alert Delivery

[[softguard-components|Softguard]] follows the standard SQS event-listener pattern: the sender enqueues to `event_queue_softguard_alarm.fifo` with `message_group_id` set to the customer ID (ensuring FIFO ordering per customer). The event-listener worker dequeues, retrieves frames from S3, and delivers the formatted alert to the Softguard monitoring platform.

## Architecture

The alarm sender factory in [[actuate-alarm-senders]] instantiates `SoftguardAlertSender` when a [[softguard-components|Softguard]] alert config is present. There are no Softguard-specific puller or integration calls components -- video ingestion uses whatever VMS integration ([[rtsp-deep-dive|RTSP]], Milestone, etc.) is configured, and Softguard is purely a send-only monitoring integration. The [[vms-connector]] builds the sender via the factory during camera initialization.
