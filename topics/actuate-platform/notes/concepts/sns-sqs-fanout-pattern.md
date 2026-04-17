---
title: "SNS/SQS Fan-out/Fan-in Pattern"
type: concept
topic: actuate-platform
tags: [sns, sqs, messaging, fan-out, fan-in, architecture, decoupling]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# SNS/SQS Fan-out/Fan-in Pattern

The SNS/SQS fan-out/fan-in pattern is the foundational messaging architecture used across the Actuate platform for decoupling producers from consumers.

## How It Works

1. **Producers publish to SNS topics** -- each message goes to one logically appropriate topic. The SNS publish API is nearly identical to SQS, so most producers are agnostic about which they are using.
2. **Consumers own SQS queues** -- each consumer service has its own dedicated queue.
3. **Queues subscribe to topics** -- a queue can subscribe to multiple topics (fan-in), and a topic can deliver to multiple queues (fan-out). Subscription is free.

This means adding a new consumer requires zero changes to producers or existing consumers -- just create a queue and subscribe it.

## Decoupling Properties

- **Identity**: sender and receiver do not know about each other.
- **Rate**: each side operates at its own pace without impacting the other.
- **Location**: services can be anywhere -- same host, different region, different account.
- **Capacity**: queue depth absorbs load spikes, preventing backpressure propagation.
- **Implementation**: either side can be rewritten without affecting the other.

## Applications at Actuate

| Domain | How the pattern is applied |
|--------|---------------------------|
| **Alert delivery** | Unified alert SNS topics with per-sender SQS queues (email, SMS, webhook). Each sender scales independently. |
| **Deployer** | Deployment jobs (reboot, start/stop) queued with auto-scaling consumers, retry, and DLQ. Different deployer implementations consume for different site types. |
| **Future pipeline** | The rearch video processing pipeline is designed to be split at fan-out points (multi-model inference) and bottleneck points (slow inference steps), with message brokers replacing internal function calls. |

## Relationship to Microservice Decomposition

This pattern is the key enabler for the platform's distributed microservice vision. Once services communicate via topics and queues rather than direct calls or shared databases, they can be independently deployed, scaled, and replaced. The team identified specific split points in the rearch pipeline: fan-out (one frame to multiple models), unpredictable latency (inference), and bidirectional coupling.

## Sources

- [[sns-sqs-fanout-pattern|SNS/SQS Fan-out Pattern explanation]]
- [[alert-senders|Alert Senders]]
- [[deployer-queue-consumer|Deployer Queue Consumer]]
- [[microservice-split-discussion|Microservice Split Discussion]]
