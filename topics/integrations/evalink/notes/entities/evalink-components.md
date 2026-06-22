---
title: "Evalink Integration Components"
type: entity
topic: integrations/evalink
tags: [integration, evalink, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-libraries/notes/entities/actuate-event-listener.md
  - topics/actuate-platform/notes/concepts/data-flow-architecture.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/admin-api/notes/concepts/integration-architecture.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/data-access-control/notes/concepts/2026-05-11_admin-incident-catalog.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-reliability-fix-plan.md
  - topics/integrations/evalink/_summary.md
  - topics/integrations/evalink/evalink-integration/_summary.md
incoming_updated: 2026-05-27
---

# Evalink Integration Components

The `EvalinkAlertSender` class in [[actuate-alarm-senders]] delivers detection alerts to the Evalink cloud-based alarm management platform. Evalink is a Swiss SaaS platform for security operations centers, and this sender is one of the simpler integrations.

## Class Hierarchy

`EvalinkAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It requires no special constructor arguments beyond the base config -- no SES client, no extra DAOs. The `EventListenerAlertSender` layer provides the `self.event_listener` for SQS dispatch.

## Alert Format

The alert payload is a flat dictionary with: `alert_label` (detection label), `alert_url` (Actuate UI link), `custcam_id`, `camera_id` (from `alert_data.camera.admin_camera_id`), `alert_ts` (customer-local timestamp as a UNIX float via `customer_now.timestamp()`), `message` (the `verbose_subject` from alert data, containing camera name, site, labels, and time), and `event_type`. The sender uses a single `recipient` object from config rather than iterating over a list.

## Delivery Mechanism

Alerts are dispatched via SQS FIFO queue `event_queue_evalink_alarm.fifo`. The queue message includes the `recipient` config object directly (not JSON-serialized like most other senders). A downstream consumer reads the queue and posts to the Evalink API. Error handling logs at `error` level but does not raise exceptions.

## Key Config Fields

The config uses `self.config.recipient` (singular, not plural) -- a single recipient object containing Evalink-specific connection details. The `camera_id` field maps to the `admin_camera_id` from the camera config, which Evalink uses to identify the source device. The `verbose_subject` provides the human-readable alert description.

## Auth Method

Authentication details are encapsulated in the `recipient` config object and handled by the downstream [[queue-consumer|queue consumer]] when making API calls to Evalink. The sender itself does not directly authenticate -- it only queues the alert data along with the recipient configuration.
