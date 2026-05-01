---
title: "actuate-queue-consumer"
type: entity
topic: actuate-libraries
tags: [library, utility, sqs, queue, consumer, worker]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-queue-consumer (v1.0.0) provides a base class for SQS [[queue-consumer|queue consumer]] workers. It handles the polling loop, message processing, graceful shutdown, and error recovery so that concrete consumers only need to implement the `action(message)` method.

## Key Class: Consumer

Located in `core.base_queue_consumer`, `Consumer` is initialised with a `queue_name`, optional `num_messages`, and `wait_time_seconds`. It reads configuration from `.env` or environment variables and resolves the SQS queue by name.

### Core Methods

- **`queue_listen(bulk=False)`** -- Main polling loop. Writes a `/tmp/consumer_running` sentinel file for Kubernetes liveness probes, then continuously calls `receive_messages`. Supports both single-message and bulk processing modes. Handles `SIGTERM` for graceful shutdown via a module-level `shutdown_flag`. On error, reconnects to SQS with exponential backoff (capped at 600s).
- **`queue_bulk_listen()`** -- Convenience wrapper that calls `queue_listen(bulk=True)`.
- **`single_process(messages)`** -- Processes each message individually, calling `process_message` then deleting on success.
- **`bulk_process(messages)`** -- Collects all message bodies into a list, processes them together, then deletes all on success.
- **`action(message)`** -- Abstract method (raises `NotImplementedError`). Subclasses implement this with their business logic.
- **`get_config()`** -- Loads config from `.env` file via `dotenv_values`, falling back to `os.environ`.

### Lifecycle

1. Consumer starts, reads config, connects to SQS queue by name.
2. Writes `/tmp/consumer_running` for K8s probes.
3. Polls in a while loop, respecting `shutdown_flag` set by SIGTERM.
4. On SQS connection error, sleeps with backoff and reconnects.

## Dependencies

None declared in pyproject.toml (zero external dependencies). Uses boto3 and python-dotenv at runtime, expecting them in the deployment environment.

## Consumers

Used by event-listener services and any SQS-driven worker that needs a standard polling loop. The concrete consumer subclasses `Consumer` and implements `action()`.

## Notable Patterns

- **SIGTERM-aware shutdown**: Registers a `signal.SIGTERM` handler that sets `shutdown_flag = True`, allowing the loop to exit cleanly for Kubernetes pod termination.
- **K8s probe file**: Writes `/tmp/consumer_running` as a liveness probe indicator.
- **Stage-aware queue naming**: In non-prod stages, rewrites the queue name to `event_queue_{stage}.fifo`.
- **Zero declared dependencies**: Keeps the package minimal; runtime dependencies (boto3, dotenv) come from the consuming service's environment.
