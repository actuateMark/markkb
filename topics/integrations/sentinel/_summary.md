---
title: "Sentinel Integration"
type: summary
topic: integrations/sentinel
tags: [integration, monitoring, sentinel]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Sentinel Integration

[[sentinel-components|Sentinel]] is a professional alarm monitoring platform. Actuate integrates with [[sentinel-components|Sentinel]] as an alert destination, delivering AI detection events from the video analytics pipeline into the [[sentinel-components|Sentinel]] monitoring workflow.

## Components

### SentinelAlertSender

Defined in [[actuate-alarm-senders]] at `sentinel/sentinel_alert_sender.py`. Extends `EventListenerAlertSender` (which provides SQS event queue dispatch and S3 frame retrieval). Alerts are delivered **asynchronously via SQS** -- the sender formats a payload and pushes it to the `event_queue_sentinel_alarm.fifo` queue, where a downstream event-listener worker delivers the alert to the [[sentinel-components|Sentinel]] receiver.

The alert payload uses a **pipe-delimited format**: `EventType=Actuate|Event={event}|CameraName={name}|Text={text}`. The `Event` field is mapped from Actuate detection labels via `label_to_event()`, which translates labels into Sentinel-specific event types:

| Actuate Label | [[sentinel-components|Sentinel]] Event |
|---|---|
| intruder, bike, vehicle | Intruder |
| gun, pistol | Gun |
| fire, smoke | Fire |
| loiterer | Loitering |
| vehicle_loiterer | Vehicle Loitering |
| fall | Slip and Fall |
| left_object | Left Object |
| mask | Mask |
| no_mask | No Mask |
| no_hard_hat | Hard Hat |
| delivery vehicles | Postal Vehicle ID |
| people_flow | People Flow |

Each recipient in the config specifies a `sentinel_server`, `sentinel_site_id`, `sentinel_device_address`, and `sentinel_link_to_guid`. The sender also passes `draw_ignore_zones`, `polygonal_zones`, and `motion_polygonal_zones` to the event-listener for frame annotation before delivery.

Config fields: `recipients[].sentinel_server`, `recipients[].sentinel_site_id`, `recipients[].sentinel_device_address`, `recipients[].sentinel_link_to_guid`, `recipients[].draw_ignore_zones`.

## Auth Method

No explicit API authentication. Alert delivery relies on network-level access to the [[sentinel-components|Sentinel]] server endpoint. The event-listener worker handles the actual transmission after dequeuing from SQS.

## Architecture

[[sentinel-components|Sentinel]] alerts flow through the standard [[actuate-alarm-senders]] pipeline: the `MultiAlertSender` calls `SentinelAlertSender.send()`, which enqueues to an SQS FIFO queue. The event-listener service dequeues, retrieves and annotates frames from S3/DynamoDB, and delivers the formatted alert with image attachments to the [[sentinel-components|Sentinel]] monitoring platform. The sender is instantiated by the alarm sender factory in [[actuate-alarm-senders]] when a [[sentinel-components|Sentinel]] alert config is present. There are no integration calls or puller components for [[sentinel-components|Sentinel]] -- it is a send-only monitoring integration.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- SentinelAlertSender lives here, extending AttachmentAlertSender > EventListenerAlertSender
- [[vms-connector]] -- builds the sender via the factory during camera initialization
- No corresponding module in [[actuate-integration-calls]] or [[actuate-pullers]]
