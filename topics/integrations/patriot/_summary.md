---
title: "Patriot Integration"
type: summary
topic: integrations/patriot
tags: [integration, monitoring, patriot]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Patriot Integration

Patriot is a professional alarm monitoring and security management platform. Actuate integrates with Patriot as an alert destination, delivering AI detection events into the Patriot signal processing workflow.

## Components

### PatriotAlertSender

Defined in [[actuate-alarm-senders]] at `patriot/patriot_alert_sender.py`. Extends `EventListenerAlertSender` (which provides SQS event queue dispatch, S3 frame retrieval, and enriched frame annotation). Alerts are delivered **asynchronously via SQS** -- the sender formats a payload and pushes it to the `event_queue_patriot_alarm.fifo` queue, where a downstream event-listener worker delivers the alert to the Patriot API.

The alert payload for each recipient includes:

- `clientNo` -- Patriot client number identifying the monitored site
- `rawData` -- Human-readable alert text (e.g., "ACTUATE ALERT: CameraName at SiteName possible intruder at 04/13/26, 2:30 PM EST")
- `typeNo` -- Patriot signal type number (defaults to 100 if not configured)
- `zoneUser` -- Patriot zone number for the alert
- `media` -- A URL reference to the Actuate alert viewer (`url:{alert_url}`)

The sender also includes a `label_to_event()` mapping similar to [[integration-sentinel|Sentinel]], translating Actuate labels (intruder, gun, fire, loiterer, etc.) to Patriot event names, though the primary data is sent as `rawData` text.

Config fields: `recipients[].patriot_server`, `recipients[].patriot_client_no`, `recipients[].patriot_username`, `recipients[].patriot_password`, `recipients[].patriot_type_number`, `recipients[].patriot_zone_number`, `recipients[].send_video`, `recipients[].draw_ignore_zones`.

## Auth Method

**Username/password** authentication per recipient. Each Patriot recipient config includes `patriot_username` and `patriot_password`, which are passed through the SQS payload to the event-listener worker for API authentication when delivering the alert.

## Alert Delivery

Patriot uses the standard SQS event-listener pattern: the sender enqueues to `event_queue_patriot_alarm.fifo` with `message_group_id` set to the customer ID (ensuring FIFO ordering per customer). The event-listener worker dequeues, retrieves and annotates frames from S3/DynamoDB (respecting `draw_ignore_zones` and `send_video` flags), and delivers the alert to the Patriot server with media attachments.

The sender detects whether it is running in a container environment by checking for the `DEPLOYMENT_ID` environment variable (`is_container` flag), though this does not currently alter behavior.

## Architecture

The alarm sender factory in [[actuate-alarm-senders]] instantiates `PatriotAlertSender` when a Patriot alert config is present. There are no integration calls or puller components -- Patriot is a send-only monitoring integration.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- PatriotAlertSender lives here, extending AttachmentAlertSender > EventListenerAlertSender
- [[vms-connector]] -- builds the sender via the factory during camera initialization
- No corresponding module in [[actuate-integration-calls]] or [[actuate-pullers]]
