---
title: "Source: Deployer Queue Consumer Architecture"
type: source
topic: infrastructure
tags: [worklog, deployer, queue-consumer, sqs, dead-letter-queue, auto-scaling]
ingested: 2026-04-14
author: kb-bot
---

# Deployer Queue Consumer Architecture

Source: internal architecture note on a queue-based deployer design.

## Design

All deployment jobs (reboot, start/stop, etc.) are pushed onto a queue rather than executed directly. Key features:

1. **Queue-driven execution** -- jobs are enqueued and consumed asynchronously.
2. **Auto-scaling** -- the deployer scales up based on queue depth (number of pending jobs).
3. **Automatic retry** -- failed jobs are automatically retried.
4. **Dead letter queue (DLQ)** -- persistently failing jobs are moved to a DLQ for investigation rather than being lost or retried indefinitely.
5. **Multiple deployer implementations** -- different deployer consumers can pull and execute jobs for different site types (regular sites, CHM, Bold, etc.), allowing specialized handling per integration.

## Significance

This pattern decouples job submission from execution, enables horizontal scaling during bulk operations, and provides resilience through retry and DLQ mechanisms. It is an application of the [[sns-sqs-fanout-pattern|SNS/SQS fan-out pattern]] to the deployment domain.
