---
title: "Queue Consumer"
type: entity
topic: vms-connector
tags: [queue-consumer, sqs, alerts, integrations, immix, ecs, docker]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Overview

The **Queue Consumer** is a multi-purpose alert dispatching service that reads messages from AWS SQS FIFO queues and forwards them to various third-party monitoring and integration platforms. Each supported integration has its own consumer implementation, and the service is deployed as multiple independent containers -- one per integration -- each reading from its own dedicated SQS queue. It is a critical part of the Actuate alert pipeline, responsible for delivering detection alerts from the inference system to customers' monitoring stations.

**Repository:** `aegissystems/queue_consumer`

## Tech Stack

- **Language:** Python 3.12 (managed with `uv`)
- **Queue:** AWS SQS FIFO queues (one per integration type)
- **AWS Services:** SQS, S3 (enriched frames/video), DynamoDB (`EnrichedFrameV2`), SES (email), Secrets Manager
- **Media Processing:** [[opencv-entity|OpenCV]] (`opencv-python-headless`), [[ffmpeg-entity|ffmpeg]] (static binary installed at build time)
- **[[actuate-libraries|Actuate Libraries]]:** `actuate-daos` (S3DAO, EnrichedFrameDAO), `actuate-viz` (visualization), `actuate-admin-api`, `actuate-secrets`, `actuate-integration-calls` (all from CodeArtifact)
- **Integration Protocols:** SMTP (Immix, [[softguard-components|Softguard]]), HTTP/REST (SureView, Milestone, [[sentinel-components|Sentinel]], Patriot, LISA, US Monitoring, SysAid, [[evalink-components|Evalink]], Eagle Eye, Webhook), TCP sockets (TCP sender), SQS-to-SQS (Echo, Analytics)

## Deployment Model

The service uses a single Dockerfile but is built into **per-consumer Docker images** via build args (`CONSUMER` and `STAGE`). Each consumer gets its own ECR repository (e.g., `queue_consumer_immix`, `queue_consumer_echo`) and ECS task definition. They run on the `prod-queue-consumers-sqs` ECS cluster.

CI/CD uses **per-consumer GitHub Actions workflows** (e.g., `main-immix.yml`, `main-echo.yml`, `main-health.yml`). Each workflow triggers only when files under its consumer subdirectory change on the `main` branch (`paths: - 'consumers/immix/**'`). This ensures that changing one consumer only redeploys that specific consumer.

The Docker image is based on `python:3.12-slim`, installs [[ffmpeg-entity|ffmpeg]], and runs `python3 -u app.py` as its entrypoint.

There is also a Kubernetes config (`kubernetes/config.yaml`) defining a `queue-consumer` namespace with a service account linked to the `ecs-task-admin` IAM role, suggesting some consumers may also run on EKS.

## Key Files and Entry Points

- **`app.py`** -- Main entry point. Reads `CONSUMER` from `.env` or environment, calls `consumer_factory.make_consumer()` to instantiate the appropriate consumer
- **`consumer_factory.py`** -- Factory function mapping consumer type strings to consumer classes. Supports 16 integrations: analytics, immix, echo, webhook, health, tcp, sureview, softguard, milestone, sentinel, patriot, eagle_eye, lisa, us_monitoring, sysaid, evalink
- **`consumers/base_queue_consumer.py`** -- `Consumer` base class: connects to SQS by queue name, implements `queue_listen()` (long-polling loop with exponential backoff), `single_process()` / `bulk_process()`, graceful SIGTERM handling, and a `/tmp/consumer_running` liveness marker for Kubernetes probes
- **`consumers/immix/immix_consumer.py`** -- Example integration: reads alerts from `event_queue_immix_alarm.fifo`, formats XML alarm payloads with image/video attachments, sends via SMTP to Immix monitoring stations with retry logic
- **`consumers/shared/utils.py`** -- Shared utilities for fetching enriched frame images from S3, building video from images, creating email attachments
- **`alert_utils/bounding_box.py`** -- Bounding box rendering utilities
- **`consumers/job_consumer.py`** -- A specialized consumer variant for job-type messages

## Consumer Types

| Consumer | Queue | Protocol | Purpose |
|---|---|---|---|
| immix | `event_queue_immix_alarm.fifo` | SMTP | Sends alerts to Immix monitoring stations |
| echo | Per-stage | SQS relay | Echoes/relays alert messages |
| webhook | -- | HTTP POST | Generic webhook alert delivery |
| health | -- | Internal | Camera/system health checking |
| tcp | -- | TCP socket | Raw TCP alert delivery |
| sureview | -- | HTTP | SureView Immix integration |
| softguard | -- | SMTP | [[softguard-components|Softguard]] alarm delivery |
| milestone | -- | HTTP | Milestone XProtect integration |
| sentinel | -- | HTTP | [[sentinel-components|Sentinel]] integration |
| patriot | -- | HTTP | Patriot PSIM integration |
| lisa | -- | HTTP | LISA integration |
| us_monitoring | -- | HTTP | US Monitoring integration |
| sysaid | -- | HTTP | SysAid ticketing integration |
| evalink | -- | HTTP | [[evalink-components|Evalink]] integration |
| eagle_eye | -- | HTTP | Eagle Eye Networks integration |
| analytics | -- | Internal | Analytics data processing |

## Configuration

Each consumer is configured via environment variables: `CONSUMER` (which consumer to run), `STAGE` (prod/dev/etc.), and `AWS_DEFAULT_REGION`. The base `Consumer` class reads from `.env` file or falls back to environment variables. Queue names are determined by stage -- prod uses named queues (e.g., `event_queue_immix_alarm.fifo`), non-prod uses `event_queue_{stage}.fifo`.

## Dependencies on Other Actuate Services

- **SQS Queues** -- populated upstream by the inference/alerting pipeline
- **S3** -- enriched frames and video clips are fetched for alert attachments
- **DynamoDB** (`EnrichedFrameV2`) -- frame metadata lookup for building alert media
- **SES** -- email delivery (SES CC for testing/debugging)
- **Admin API** -- used by some consumers for camera/site metadata

## Architecture Patterns

- **One-container-per-integration**: Each integration runs as its own container/ECS service, providing isolation and independent scaling/deployment
- **Factory pattern**: `consumer_factory.make_consumer()` maps string identifiers to consumer classes
- **Base class with template method**: `Consumer` handles SQS polling, message lifecycle (receive/delete), and error handling; subclasses implement `action(message)`
- **Graceful shutdown**: SIGTERM handler sets a flag to exit the polling loop cleanly, important for ECS/K8s pod termination
- **Exponential backoff**: On SQS errors, the timeout doubles (up to 600s), with queue reconnection
- **Path-based CI/CD**: Each consumer has its own GitHub Actions workflow triggered only by changes in its subdirectory, preventing unnecessary redeployments
