---
title: "Softguard Integration Components"
type: entity
topic: integrations/softguard
tags: [integration, softguard, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/admin-api/notes/concepts/integration-architecture.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-7-alert-capture-replay.md
  - topics/integrations/softguard/_summary.md
  - topics/vms-connector/notes/entities/queue-consumer.md
incoming_updated: 2026-05-27
---

# Softguard Integration Components

The `SoftguardAlertSender` class in [[actuate-alarm-senders]] delivers detection alerts to Softguard monitoring platforms. Softguard is a Latin American alarm monitoring platform that uses a proprietary TCP-based protocol with sequential message numbering.

## Class Hierarchy

`SoftguardAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It uses the event listener queue pattern. The constructor initializes a `sequence_number` counter at 1, which auto-increments with each successful send and wraps back to 1 after reaching 99999.

## Alert Format

The alert payload includes `event_type` (from alert data), `approx_capture_timestamp` (as a float), `alert_url`, `customer_name`, `camera_name`, and Softguard-specific fields: `zone` (from `self.config.zone`), `account` (from `self.config.account`), `user` and `user_ext` (from config), plus the auto-incrementing `sequence_number`. Unlike other senders that serialize a list of recipients, Softguard uses a single `recipient` (via `self.config.recipient.to_json()`), along with top-level `server` and `port` fields extracted from that recipient.

## Delivery Mechanism

Alerts are dispatched via SQS FIFO queue `event_queue_softguard_alarm.fifo`. The `message_group_id` is set to the customer ID. The queue message also carries `attachment_frames`, `custcam_id`, `label`, `s3_folder` (window_id), and `start_time`. A downstream consumer reads the queue and sends the alert to the Softguard server. The sender checks the response status code -- only a 200 triggers the sequence number increment.

## Key Config Fields

Top-level config fields: `zone` (Softguard zone identifier), `account` (Softguard account number), `user` (Softguard user ID), `user_ext` (user extension). Single recipient with `server` (Softguard server address) and `port`. The `sequence_number` is managed in-memory on the sender instance and resets on service restart.

## Auth Method

Authentication details are embedded in the `account`, `user`, and `user_ext` config fields that identify the alarm source to the Softguard platform. The downstream consumer uses these fields when communicating with the Softguard server over its proprietary protocol.
