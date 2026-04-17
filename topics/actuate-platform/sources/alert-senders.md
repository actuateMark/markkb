---
title: "Source: Alert Senders -- Unified Alert Topics"
type: source
topic: actuate-platform
tags: [worklog, alerts, sns, sqs, fan-out, architecture]
ingested: 2026-04-14
author: kb-bot
---

# Alert Senders -- Unified Alert Topics

Source: brief internal architecture note on the alert delivery pattern.

## Design

The alert delivery system follows the standard [[sns-sqs-fanout-pattern|SNS/SQS fan-out pattern]]:

1. **Unified alert topics** -- all alerts are published to a common set of SNS topics using a standardized alert object schema.
2. **Per-sender SQS queues** -- each alert delivery channel (email, SMS, push notification, webhook, etc.) has its own SQS queue subscribed to the relevant alert topics.
3. **Independent consumers** -- each sender pulls from its own queue and delivers via its channel. Senders are decoupled from each other and from the alert producers.

## Benefits

- Adding a new delivery channel requires only a new queue, a subscription, and a consumer -- no changes to alert producers.
- Each sender scales independently based on its own queue depth.
- Failures in one sender do not affect other channels.

This is a direct application of the fan-out/fan-in messaging model to the alert domain.
