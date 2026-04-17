---
title: "actuate-sqs"
type: entity
topic: actuate-libraries
tags: [library, utility, aws, sqs, messaging, queue]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-sqs (v1.1.1) provides a standalone SQS message-sending library, separate from the `SQSDAO` in actuate-daos. It contains `QueueSender` (a general-purpose queue sender) and `MotionQueue` (a specialised sender for short-lived motion event queues).

## Key Classes

### `QueueSender`

Initialised with an optional `queue_id`. Builds queue URLs against a hardcoded base (`https://sqs.us-west-2.amazonaws.com/388576304176/`).

- **`send_to_queue(data, message_group_id, is_retry, message_attributes, queue_id)`** -- Serialises data to JSON and sends to the specified queue. Handles FIFO queues (sends `MessageGroupId`) vs standard queues. On `QueueDoesNotExist`, auto-creates the queue and retries once.
- **`create_queue(queue_id)`** -- Creates a standard or FIFO queue depending on whether "fifo" appears in the queue name.
- **`queue_url` property** -- Returns the full URL for the configured queue.

### `MotionQueue`

Extends `QueueSender` with motion-specific queue attributes: `ContentBasedDeduplication: true`, `MessageRetentionPeriod: 60` seconds (for both FIFO and standard). Used for ephemeral motion event signalling where messages are consumed immediately.

## Dependencies

- **boto3** >=1.35.23 -- AWS SDK for SQS operations.

## Consumers

Used by connector services that need to send motion events or arbitrary messages to SQS queues. The motion queue pattern is used for camera motion signalling in the connector pipeline.

## Notable Patterns

- **Auto-create on send**: If a queue does not exist when `send_to_queue` is called, it is created automatically and the send is retried, making the sender resilient to queue lifecycle issues.
- **Hardcoded AWS account**: The base queue URL embeds the AWS account ID (388576304176) and region (us-west-2).
- **Distinct from SQSDAO**: actuate-daos has its own `SQSDAO` for queue operations within the DAO layer; actuate-sqs is the standalone alternative used outside the DaoManager context.
