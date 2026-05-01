---
title: "Evalink Integration"
type: summary
topic: integrations/evalink
tags: [integration, monitoring, evalink]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Evalink Integration

[[evalink-components|Evalink]] is a cloud-based alarm management platform used by monitoring centers to receive, process, and dispatch security events. Actuate integrates with [[evalink-components|Evalink]] as an alert destination, forwarding AI-generated detections via an **SQS FIFO queue** for downstream delivery to the [[evalink-components|Evalink]] API.

## Components

### EvalinkAlertSender

Defined in [[actuate-alarm-senders]] at `evalink/alert_sender.py`. Extends `EventListenerAlertSender`, meaning it sends alerts through the SQS-backed event-listener pattern rather than calling the [[evalink-components|Evalink]] API directly. When `send()` is called with an `AlertData` object, the sender packages the alert into a message containing:

- `queue_id` -- always `"event_queue_evalink_alarm.fifo"`, targeting the [[evalink-components|Evalink]] SQS FIFO queue
- `recipient` -- the configured recipient (server/token/device info)
- `alert_label`, `alert_url`, `custcam_id`, `camera_id` -- identifiers for the detection event
- `alert_ts` -- timestamp in the customer's local timezone
- `message` -- the verbose alert subject text
- `event_type` -- the detection event type

The message is sent to the event listener via `self.event_listener.send_to_queue(data)`. A separate consumer process reads from the FIFO queue and delivers to [[evalink-components|Evalink]]'s API.

### Integration Calls

There is no dedicated `actuate-integration-calls` module for [[evalink-components|Evalink]]. The SQS consumer that reads from the FIFO queue and posts to the [[evalink-components|Evalink]] REST API is handled outside of the actuate-libraries monorepo.

### Puller

No Evalink-specific puller exists. Evalink is a send-only monitoring integration; video comes from whichever [[vms-connector|VMS connector]] the site uses.

## Auth Method

Authentication to the [[evalink-components|Evalink]] platform is handled at the queue-consumer level (outside actuate-libraries). At the sender level, per-site config provides the token and server details that are forwarded in the SQS message for the consumer to use.

## Key Config Fields

Alert configuration is defined in [[actuate-config]] at `alerts/evalink/alert_config.py` via `EvalinkAlertConfig`. The config reads from `evalink_alerts` in the feature deployment, collecting a list of recipient dicts. Each recipient typically includes server endpoint, authentication token, and device ID fields that the downstream consumer uses when posting to the [[evalink-components|Evalink]] API.

## Alert Delivery

[[evalink-components|Evalink]] uses the **SQS FIFO queue** pattern. The sender writes to `event_queue_evalink_alarm.fifo`, which guarantees ordered, exactly-once delivery. A separate Lambda or worker process consumes messages from this queue and forwards them to the [[evalink-components|Evalink]] REST endpoint. This decouples the real-time connector process from external API latency.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- EvalinkAlertSender lives here, extending EventListenerAlertSender
- [[actuate-config]] -- EvalinkAlertConfig provides per-site alert configuration
- [[vms-connector]] -- builds the sender via the alarm-sender factory when [[evalink-components|Evalink]] alerts are configured
- No corresponding module in [[actuate-integration-calls]] or [[actuate-pullers]]
