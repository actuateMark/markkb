---
title: "Autopatrol Server"
type: entity
topic: autopatrol
tags: [autopatrol, server, analysis, flask, sqs, neptune, computer-vision]
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/autopatrol-alert-lifecycle.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/autopatrol/notes/syntheses/2026-04-16_deferred-alert-race-condition.md
  - topics/team-structure/notes/entities/clarissa-herman.md
incoming_updated: 2026-05-01
---

## Overview

The **Autopatrol Server** is the core analysis backend for the Actuate AutoPatrol product. It receives patrol job requests -- either via a Flask HTTP API or by consuming messages from an SQS FIFO queue (`autopatrol_jobs.fifo`) -- and runs computer vision analysis pipelines on security camera video clips. The results include object counts, activity heuristics, motion statistics, and patrol-level summaries which are relayed back to the AutoPatrol third-party platform (immix Connect) and persisted to S3.

**Repository:** `aegissystems/autopatrol-server`

## Tech Stack

- **Language:** Python 3.12+ (managed with `uv`)
- **Web Framework:** Flask (HTTP API) alongside a long-running SQS consumer
- **Analysis Libraries:** scikit-learn, scikit-image, scipy, numpy, pandas, filterpy (Kalman filtering for SORT tracker), shapely (geometry/tag-zone overlaps), imageio-ffmpeg (video decoding)
- **Graph Database:** Amazon Neptune via `gremlinpython` -- used for storing per-clip analysis results and querying historical camera data for forensic analysis
- **AWS Services:** SQS (FIFO [[queue-consumer|queue consumer]]), S3 (clip storage, result persistence), DynamoDB (timestamp/window-ID lookups), Secrets Manager
- **[[actuate-libraries|Actuate Libraries]]:** `actuate-admin-api`, `actuate-daos`, `actuate-queue-consumer`, `actuate-integration-calls` (all from CodeArtifact, some pinned with `+autopatrol` dev tags)

## Deployment Model

The service is containerized via Docker (Python 3.12-slim base, built with uv, ARM64 target). CI/CD is a GitHub Actions workflow on push to `main` that builds and pushes to ECR repository `autopatrol_service`, tagged with the pyproject version. The container runs `python3 -m server.app` as its entrypoint, which starts the SQS [[queue-consumer|queue consumer]] (not the Flask dev server).

The Docker image is deployed to ECS or EKS (ARM64 nodes). It pulls private packages from AWS CodeArtifact at build time via a `UV_INDEX` build arg.

## Key Files and Entry Points

- **`server/app.py`** -- Flask app with `/health` and `/process_patrol` endpoints; `main()` instantiates the `AutoPatrolQueueConsumer` (SQS listener)
- **`server/autopatrol_queue.py`** -- `AutoPatrolQueueConsumer` extends `actuate_queue_consumer.Consumer`; listens on `autopatrol_jobs.fifo`, parses patrol messages, runs analysis via `AutoPatrolHandler`, saves results to S3, raises patrol alerts via the AutoPatrol API, and ends the patrol
- **`handler/ap_handler.py`** -- `AutoPatrolHandler` orchestrates clip-level analysis: resolves custcam IDs from DynamoDB, runs object tracking and activity analysis in parallel threads via `ThreadManager`, aggregates results via `PatrolSummarizer`
- **`handler/analysis_engine.py`** -- `ClipAnalysisEngine` runs the actual analysis modules (ObjectCounter, ActivityAnalyzer) and stores results in Neptune with thread-safe per-clip node caching
- **`object_tracking/object_counter.py`** -- Object counting using the SORT tracker (`object_tracking/sort.py`)
- **`activity_analysis/heuristic_activity_analysis.py`** -- Heuristic activity analysis: occupancy grids, max objects per frame, median bounding box sizes, motion detection
- **`activity_analysis/neptune_storage_manager.py` / `neptune_query_manager.py`** -- Neptune graph DB read/write for analysis results
- **`patrol_aggregation/patrol_summarizer.py`** -- Aggregates clip-level results into a patrol-level summary
- **`utils/config.py`** -- Feature flags: `DEV_MODE`, `CLIP_TRUNCATION`, `ANALYZE_OBJECT_TRACKING`, `ANALYZE_HEURISTIC_ANALYSIS`, `ANALYZE_CLIP_DESCRIPTION` (future), `ANALYZE_FORENSIC_ANALYSIS` (future)

## Configuration

Runtime behavior is controlled by environment variables and `utils/config.py` flags. Key environment variables include `LOCAL` (use local dev mode), `DUMMY_JSON` (use test fixture), `AUTOPATROL_API_KEY`, `DEV_AUTOPATROL_API_KEY`, and `AUTOPATROL_REGION`. Secrets are fetched from AWS Secrets Manager (`prod/actuate/autopatrol`).

## Dependencies on Other Actuate Services

- **Admin API** -- resolves customer IDs from site IDs, fetches site classification data
- **AutoPatrol API (immix Connect)** -- raises patrol alerts, ends patrols, streams patrol data (keepalive)
- **S3** -- reads video clips, writes patrol result JSONs
- **DynamoDB** -- resolves approx_capture_timestamps and window IDs to custcam IDs
- **Neptune** -- persists and queries per-clip analysis results for historical/forensic analysis

## Dev vs Prod Server Environments

Two deployments of autopatrol-server run in parallel: **prod** and **dev** (`autopatrol-server-dev`). Each listens on a dedicated SQS FIFO queue:

| Queue | Server |
|---|---|
| `autopatrol_jobs.fifo` | prod |
| `autopatrol_jobs_dev.fifo` | dev |

The **vms-connector** (which enqueues patrol task results) has two `PatrolConfig` fields that control routing:

- **`queue_stage`** -- selects which SQS queue receives the task result message (`"prod"` → `autopatrol_jobs.fifo`, `"dev"` → `autopatrol_jobs_dev.fifo`)
- **`endpoint_stage`** -- selects which autopatrol-server HTTP endpoint is called for synchronous/fallback flows

During the 2026-04-13 hotfix (commit `e234e8a3` "force prod queue"), `queue_stage` was hard-coded to prod on the stage connector environment to route completed patrols away from the dev server. The dev server processed 96 completed patrols during that validation window before the fix was applied.

### Task Result Payload Structure

The JSON message enqueued by vms-connector contains:

```
patrol_id, tenant_id, site_id,
cameras: [{ camera_id, motion_data, clips: [{ s3_key, ... }], s3_frame_keys }],
analysis_types: [...],
frames: [...]
```

`analysis_types` governs which analysis modules autopatrol-server runs for the patrol.

## Architecture Patterns

- **SQS FIFO consumer pattern**: the primary runtime is a long-polling SQS consumer, not the Flask HTTP server (Flask exists for direct API testing)
- **Thread-per-clip parallelism**: each clip in a patrol is processed in its own thread, with a `ThreadManager` coordinating results
- **Analysis engine with versioned types**: analysis types (object_tracking v1.0.0, activity_analysis v1.0.0) are versioned and extensible
- **Per-clip Neptune node caching**: thread-safe in-memory cache prevents duplicate Neptune queries during parallel clip processing
- **Graceful error isolation**: individual clip failures are captured as error results rather than failing the entire patrol
