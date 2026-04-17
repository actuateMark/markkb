---
title: "Source: SNS/SQS Fan-out/Fan-in Pattern"
type: source
topic: actuate-platform
tags: [worklog, sns, sqs, messaging, fan-out, fan-in, architecture]
ingested: 2026-04-14
author: kb-bot
---

# SNS/SQS Fan-out/Fan-in Pattern

Source: internal architecture document explaining the messaging pattern used across the Actuate platform.

## Mental Model

A message queue is like a tube you roll a ball into. The sender writes a message, drops it in, and does not care who receives it, when they receive it, or how fast they process it. This model yields strong decoupling benefits:

- **Sender and receiver are independent** -- neither cares about the other's identity, capacity, implementation, or location.
- **Rate independence** -- the sender publishes at its own pace; the receiver consumes at its own pace.
- **No impact propagation** -- load on one side does not affect the other.

## AWS Implementation: SNS + SQS

- **SNS (Simple Notification Service)** provides **topic-based** messaging. Producers publish messages to a topic; the publish API closely mirrors SQS, so most producers are agnostic.
- **SQS (Simple Queue Service)** queues subscribe to SNS topics and buffer messages for their respective consumers.
- Subscribing a queue to a topic is free (no additional charge).

## The Pattern

1. **Publish** every message to one appropriate SNS topic.
2. **Create one SQS queue per receiver** (consumer service).
3. **Subscribe** each receiver's queue to the topics it cares about.

A single queue can subscribe to multiple topics (fan-in), and a single topic can push to multiple queues (fan-out). This keeps the architecture open to expansion: adding a new consumer means creating a new queue and subscribing it -- zero changes to producers or existing consumers.

## Significance to Actuate

This is the foundational messaging pattern for the platform's event-driven services, including [[alert-senders|alert delivery]], [[deployer-queue-consumer|deployer jobs]], and the broader push toward [[microservice-split-discussion|distributed microservices]].
