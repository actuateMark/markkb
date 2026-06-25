---
title: "Sentinel Integration Components"
type: entity
topic: integrations/sentinel
tags: [integration, sentinel, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-blur.md
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-platform/_summary.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/actuate-platform/notes/syntheses/watchman-vs-current-platform.md
  - topics/admin-api/notes/concepts/integration-architecture.md
  - topics/admin-api/notes/syntheses/2026-05-13_customer-model-dissection.md
  - topics/billing/notes/entities/snowflake-billing-tables.md
  - topics/camera-health-monitoring/notes/syntheses/chm-enhanced-diagnostics-proposal.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
incoming_updated: 2026-06-25
---

# Sentinel Integration Components

The `SentinelAlertSender` class in [[actuate-alarm-senders]] forwards detection alerts to Sentinel monitoring stations. Sentinel uses a pipe-delimited text format to describe events.

## Class Hierarchy

`SentinelAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It does not require an SES client or any direct HTTP client; all delivery is queue-based. The `EventListenerAlertSender` layer provides `self.event_listener` for SQS dispatch.

## Alert Format

The alert payload is a pipe-delimited string: `EventType=Actuate|Event={mapped_event}|CameraName={name}|Text={description}`. The `label_to_event()` method maps raw detection labels to Sentinel event types -- for example, `intruder` becomes `"Intruder"`, `fire`/`smoke` become `"Fire"`, `loiterer` becomes `"Loitering"`, and postal vehicle labels (`amazon`, `fedex`, `ups`, `usps`, `dhl`, `school_bus`) become `"Postal Vehicle ID"`. Other mappings include `"Slip and Fall"`, `"Gun"`, `"Left Object"`, `"Hard Hat"`, `"Mask"`, `"No Mask"`, and `"People Flow"`.

## Delivery Mechanism

Alerts go to SQS FIFO queue `event_queue_sentinel_alarm.fifo`. The queue message includes the serialized recipient list, `custcam_id`, `s3_folder` (set to `window_id`), `start_time`, `attachment_frames` count, polygonal [[ignore-zones|ignore zones]] (both label and motion), and the formatted `alert` string. A downstream consumer reads the queue and posts to the Sentinel server.

## Key Config Fields

Each recipient is defined with `sentinel_server` (the Sentinel station URL), `sentinel_site_id`, `sentinel_device_address`, `sentinel_link_to_guid`, and `draw_ignore_zones`. These are serialized into the SQS message as JSON. The `message_group_id` is set to the customer ID for FIFO ordering.

## Auth Method

No direct authentication occurs in the sender -- queue access uses IAM. The downstream consumer handles any Sentinel server authentication using the `sentinel_link_to_guid` and server connection details from the queue message.
