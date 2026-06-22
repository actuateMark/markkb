---
title: "Generic Patrol Mode"
type: concept
topic: autopatrol
tags: [patrol, generic-patrol, architecture, mixin, connector-factory, immix]
jira: "ENG-106"
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/autopatrol/_summary.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/product-roadmap/notes/syntheses/b2b2b-vs-b2b-go-to-market.md
  - topics/releases/notes/entities/2026-04-20_vms-connector-pr-1654.md
  - topics/vms-connector/notes/concepts/connector-factory.md
  - topics/vms-connector/notes/concepts/s3-frame-fallback.md
incoming_updated: 2026-05-01
---

# Generic Patrol Mode

Generic patrol mode is the connector-side architecture that allows any VMS integration to participate in patrol-style healthcheck runs without a hard dependency on Immix. Before ENG-106, patrol logic lived exclusively in `AutoPatrolCamera`, which coupled patrol mechanics (timed frame pull, clip collection, motion reporting) to Immix-specific bootstrap code. The refactor extracted that logic into `PatrolCameraMixin` and gave both `AutoPatrolCamera` and the new `PatrolCamera` class this mixin as a base.

## PatrolCameraMixin

Holds all shared run-loop logic. It launches a puller thread, drives a frame-processing loop timed by `healthcheck_duration`, accumulates clips into `alerts_during_run`, and builds the task-result dict (camera ID, motion metrics, clip list, run-frame S3 key). Subclasses implement only `launch_process()` to select the appropriate puller, and optionally override `_start_motion_if_needed()` and `_on_puller_started()`. Cache sizing is handled by `compute_patrol_cache_size()`, called before `super().__init__()` so the pipeline receives the correctly-sized LRU cache at construction time.

## PatrolCamera

The generic subclass. Uses `AvUrlFramePuller` for [[rtsp-deep-dive|RTSP]] streams, designed so other pullers can be added without touching Immix code. Instantiated by `PatrolConnectorFactory`, which generates its own `patrol_id` locally (a UUID, no [[immix-vendor-api|Immix API]] call) and reads settings via `PatrolConnectorConfig`.

## Config Layer

`PatrolConfig` (in [[actuate-config]]) is the shared base between Immix AutoPatrol and generic Patrol. It reads `inner_integration_type`, `duration`, `batch_size`, `queue_stage`, and `endpoint_stage` from the settings `patrol` block. `endpoint_stage` drives which API environment downstream consumers target; `queue_stage` routes the SQS job to the dev or prod FIFO queue.

## Patrol as a Run Flag

Prior to this change, patrol mode required `integration_type: autopatrol`. Generic mode adds `integration_type: patrol` as a first-class routing option in the [[connector-factory]]. The distinction:
- **`autopatrol`**: Immix-driven scheduling, patrol ID from [[immix-vendor-api|Immix API]]
- **`patrol`**: Self-contained, generates its own patrol ID, no Immix dependency

## Related

- [[autopatrol/_summary|AutoPatrol (H1.2)]] — parent product
- [[connector-factory]] — routing by integration_type
- [[inference-pool]] — AIMD concurrency for multi-product patrols
- [[library-connector-dependency-map]] — [[actuate-config]] and [[actuate-daos]] changes
