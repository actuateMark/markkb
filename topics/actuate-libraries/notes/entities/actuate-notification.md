---
title: "actuate-notification"
type: entity
topic: actuate-libraries
tags: [library, integration-alerting, notification, slack, email, sns, ses]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# actuate-notification

Notification utilities for sending Slack messages (via AWS SNS) and emails (via AWS SES). Version **1.0.2**.

## Purpose

This library provides a simple, stage-aware notification layer for Actuate services. It handles two primary channels: Slack messaging (routed through an AWS SNS topic that triggers a Slack integration) and email delivery via AWS SES. Services use it for operational notifications -- deployment status, error alerts, audit trail messages -- rather than for customer-facing detection alerts (which go through [[actuate-alarm-senders]]).

## Key Classes

**`ActuateNotification`** -- Slack notification sender via AWS SNS.

Constructor parameters:
- `app_name` (str) -- identifies the sending application in messages
- `stage` (str, default from `STAGE` env var or `"prod"`) -- only sends to Slack when `"prod"`; otherwise logs locally
- `notify_to_warnings` (bool) -- if `True`, errors go to `#eng_connector_warnings`
- `channel` (str, default `"#eng_connector_audit_trail"`) -- Slack channel for non-critical messages
- `admin_api` (optional `AdminApi`) -- enriches messages with site metadata (customer name, inframap link)

Methods:
- `send_message(message, subject, critical=False)` -- Publishes to SNS topic `arn:aws:sns:us-west-2:388576304176:customer-warnings`. Critical messages go to the topic directly (routed to `#eng_connector_warnings`); non-critical messages include a `channel` message attribute to route to the configured Slack channel.
- `get_request_metadata(kwargs)` -- Extracts `stage`, `customer_pk`, and `username` from kwargs and builds a formatted metadata string with an inframap link.
- `notify_failure(func)` -- Decorator that wraps a function; if it raises an exception, sends the error details to Slack and logs the exception. Does not re-raise -- the exception is swallowed after notification.

**`EmailSender`** -- Email sender via AWS SES with attachment support.

Constructor parameters:
- `recipient` (str), `body` (str, HTML allowed), `subject` (str), `logger` (optional)

Methods:
- `prepare_message()` -- Builds a MIME multipart message with HTML body
- `add_attachment(attachment_name, attachment_file)` -- Adds a binary attachment
- `add_attachments_from_list(attachment_locations)` -- Reads files from disk and attaches them
- `send()` -- Sends via `ses.send_raw_email()` from `noreply@actuate.ai`

## Convenience Functions

- `send_email(recipient, body, subject, attachment_locations=None)` -- One-liner to send an email with optional file attachments
- `send_email_with_attachment(recipient, body, subject, attachment_location)` -- Single-attachment variant for backward compatibility

## Public API

```python
from actuate_notification import ActuateNotification, EmailSender, send_email, send_email_with_attachment
```

## Dependencies

- `boto3` -- AWS SDK for SNS (`publish`) and SES (`send_raw_email`, `verify_email_identity`)

## Consumers

- `vms-connector` -- sends operational Slack notifications during startup, configuration changes, and error conditions
- Other Actuate backend services that need Slack or email notifications
- Typically instantiated once per service with the service's `app_name`

## Notable Patterns

- **Stage-gating**: In non-prod environments, `send_message()` only logs the message locally and returns a fake `MessageId`. This prevents accidental Slack noise during development and testing.
- **SNS-to-Slack routing**: All messages go to a single SNS topic (`customer-warnings`). Non-critical messages include a `channel` message attribute that a downstream Lambda or SNS subscription filter uses to route to the correct Slack channel.
- **Decorator pattern**: `notify_failure()` provides a clean way to add error notification to any function without modifying its implementation. Note that it swallows the exception after notifying -- the wrapped function returns `None` on error rather than propagating.
- **Email sender always calls `verify_email_identity`** before sending, which is a no-op for already-verified identities but ensures the sender address is registered with SES.
- The library has `moto`-based dev test dependencies for mocking AWS services in unit tests.
