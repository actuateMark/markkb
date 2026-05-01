---
title: "actuate-healthmonitoring"
type: entity
topic: actuate-libraries
tags: [library, health-monitoring, alerting, email, sms, ses, sns]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/entities/actuate-daos.md
  - topics/actuate-libraries/notes/entities/actuate-healthcheck-objects.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

## Purpose

actuate-healthmonitoring (v1.0.5) provides utilities for sending healthcheck alert notifications. It contains two modules: `message_sender` for email/SMS delivery via AWS SES and SNS, and `oneoff_alert_sender` for pushing connection failure alerts into the connector's job queue.

## Key Functions

### `message_sender`

- **`send_text(sns_client, msg, phones)`** -- Sends an SMS message to a list of phone numbers via SNS `publish`. Logs each send and catches `ClientError`.
- **`send_email(ses_client, email_source, subject, body_text, emails, attachments=None)`** -- Sends a MIME multipart email via SES `send_raw_email`. Supports file attachments via `make_attachement(file, filename)`. Sends individually to each recipient address.
- **`make_attachement(file, filename)`** -- Creates a `MIMEApplication` attachment with a Content-Disposition header.

### `oneoff_alert_sender`

- **`push_connection_alert(job_queue, customer_config, camera_config, alert_topic, err_msg, fail_init, site_level)`** -- Creates `HealthcheckDataPacket` instances for each camera with broken connectivity, wraps them in a `ConnectorJob` of type `"send_alert"`, and pushes to the connector's job queue. Detects site-level alerts by checking for "site" in the alert topic.

## Dependencies

None declared in pyproject.toml. At runtime, uses `botocore.exceptions`, `actuate_config.connector.base_config` (CameraConfig, CustomerConfig), `actuate_healthcheck_objects` (HealthcheckDataPacket), and `actuate_pipeline_objects` (ConnectorJob).

## Consumers

Used by the vms-connector healthcheck workers and the connector alert pipeline. When a healthcheck run detects connectivity or other failures, these utilities deliver the notification via email/SMS or push the alert into the connector's internal processing queue.

## Notable Patterns

- **SES raw email**: Uses `send_raw_email` rather than `send_email` to support MIME attachments (e.g., detection frame images attached to alert emails).
- **Job queue integration**: `push_connection_alert` bridges the healthcheck system with the connector's job queue, allowing healthcheck-triggered alerts to flow through the same pipeline as detection alerts.
- **Stateless functions**: Both modules are pure functions with no class state, keeping the library simple and easy to test.
