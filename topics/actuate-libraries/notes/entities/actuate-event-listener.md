---
title: "actuate-event-listener"
type: entity
topic: actuate-libraries
tags: [library, integration-alerting, analytics, event-pipeline, sqs]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# actuate-event-listener

A wrapper library for sending analytics events to Actuate's internal event pipeline. Events are routed through an internal HTTP event handler service to SQS FIFO queues for downstream processing and storage in the analytics events table. Version **1.1.5**.

## Purpose

This library provides the mechanism for any Actuate service to emit structured analytics events -- detection counts, camera status changes, site metrics, and other telemetry. It abstracts the transport layer (HTTP POST to an internal load balancer, V3 pickle encoding, SQS FIFO routing) behind a clean registry-and-sender pattern. It is also used as a building block by [[actuate-alarm-senders]]'s `EventListenerAlertSender` hierarchy.

## Key Classes

**`EventListener`** -- Low-level HTTP client. Sends events to the internal event handler service (`internal-event-handler-lb` on AWS). V3 encoding pickles event data, base64-encodes it, and sends it as JSON alongside routing fields (`queue_id`, `event_type`, `message_group_id`). Methods:

- `send_to_queue(event_info)` -- POST event data (5-second timeout). V3 uses JSON with pickle payload; older versions use form data.
- `send_pickled(event_info)` -- Same as `send_to_queue` but flags data so consumers receive it still pickled.
- `send_webhook(stream_id, event_type, message)` -- Send to `event_queue_webhook.fifo`.
- `send_analytics(analytic_event)` -- Send an `AnalyticEvent` to `event_queue_analytics.fifo` with a random message group ID (1-20 for FIFO distribution).
- `encode_v3_data(event_info)` / `extract_pickled_data(event_info)` -- V3 serialization and deserialization.

**`AnalyticEvent`** -- Structured event data class mapping to the analytics database schema. Fields:

- `customer_id` (int, required), `event_type` (str), `event_timestamp` (datetime, formatted to Redshift `YYYY-MM-DD HH:MM:SS`)
- `act_a` through `act_j` -- 10 string fields (max 256 chars each, validated)
- `act_1` through `act_20` -- 20 integer fields (type-validated)
- `queue_id`, `message_group_id` -- set automatically by `EventListener`
- `toJSON()` -- serializes only non-None fields

**`EventSender`** -- Abstract base class for event type handlers. Subclass and override `make_event(data)` to transform raw data into an `AnalyticEvent`. The `push_event(value)` method calls `make_event()`, validates the result, and sends it via `EventListener.send_analytics()`.

**`EventLibrary`** -- Registry that maps event types to their `EventSender` implementations. Provides both async (3-worker thread pool) and sync dispatch via `send_event(event_type, data, run_async=True)`. Raises `ValueError` if no sender is registered for the given type.

## Public API

```python
from actuate_event_listener import EventLibrary, AnalyticEvent, EventSender, EventListener
```

## Architecture

```
Application Code -> EventLibrary.send_event()
                      -> EventSender.push_event()
                           -> EventSender.make_event() -> AnalyticEvent
                           -> EventListener.send_analytics()
                                -> HTTP POST to internal event handler
                                     -> SQS FIFO Queues -> Analytics DB
```

## Dependencies

- `boto3`, `botocore` -- AWS SDK (though the library primarily uses HTTP, not SQS directly)
- `requests` -- HTTP client for the internal event handler

## Consumers

- [[actuate-alarm-senders]] -- `EventListenerAlertSender` and its subclasses (Immix, Milestone, [[hikcentral-components|HikCentral]], EagleEye, [[evalink-components|Evalink]], LISA, AutoPatrol) use `EventListener` to dispatch alerts via SQS
- `vms-connector` and other connector services -- emit site-level and camera-level analytics events
- Any Actuate service that needs to write to the analytics events table

## Notable Patterns

- **V3 pickle encoding**: Routing fields (`queue_id`, `event_type`, `message_group_id`) travel in plain JSON; all other data is pickled and base64-encoded into a single `pickled` field. This allows the event handler to route without deserializing the full payload.
- **Random message group IDs (1-20)**: Analytics events use random group IDs to distribute across SQS FIFO partitions, trading strict ordering for throughput.
- **Stage-aware routing**: `stage="local"` redirects to `localhost:2345` for development.
- **Generic schema**: The `act_a`-`act_j` (string) and `act_1`-`act_20` (integer) fields provide a flexible columnar schema where each `EventSender` subclass defines the semantic meaning of each field for its event type.
