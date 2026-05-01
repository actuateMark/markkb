---
title: "Library-Connector Dependency Map"
type: synthesis
topic: vms-connector
tags: [synthesis, cross-topic, dependencies, actuate-libraries, pipeline, critical-path, vms-connector]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Library-Connector Dependency Map

The [[vms-connector]] is the single largest consumer of the [[actuate-libraries]] monorepo. Of the 41 published packages, at least 30 are direct or transitive dependencies of the connector. This synthesis maps which libraries are used at which pipeline stage, identifies the critical path for a detection to become an alert, and highlights the blast radius of changes to core libraries.

## Pipeline Stage to Library Mapping

### Stage 1: Initialization and Configuration

Before any frame is processed, the [[connector-factory]] assembles the entire runtime graph:

- [[actuate-config]] -- Parses `settings.json` into typed config objects (`ConnectorConfig`, `CameraStreamConfig`, 20+ VMS-specific configs, 25+ alert sender configs). This is the single most depended-upon library in the connector.
- [[actuate-admin-api]] -- Fetches camera, customer, and model metadata from the Admin API during startup. Also used for runtime config refresh.
- [[actuate-secrets]] -- Retrieves credentials from AWS Secrets Manager with caching. Feeds into [[actuate-admin-api]] and VMS auth.
- [[actuate-daos]] -- Initializes 17 DAOs (DynamoDB, S3, SQS, SNS, PostgreSQL, CloudWatch, [[new-relic|New Relic]], Datadog). The `DaoManager` is passed to virtually every subsystem.
- [[actuate-log]] -- Configures structured logging via `ActuateLogAdapter`. Loaded first; used everywhere.
- [[actuate-network]] -- VPC subnet overlap checks and VPN route integration for WireGuard sites.
- [[actuate-wireguard]] -- Manages WireGuard tunnel setup for sites connecting through Teltonika RMS.

### Stage 2: Frame Acquisition

Each camera thread runs a puller from [[actuate-pullers]], which is itself the most dependency-heavy acquisition library:

- [[actuate-pullers]] -- 15+ puller subclasses for [[rtsp-deep-dive|RTSP]], S3, SQS, [[kvs-components|KVS]], Milestone, Orchid, and more. Depends on:
  - [[actuate-image-cache]] -- Thread-safe LRU/TTL cache storing decoded frames. Shared between puller and observers.
  - [[actuate-movement]] -- `MotionDetector` (FDMD) gates frame submission. Depends on [[actuate-math]] for NMS on motion contours.
  - [[actuate-pipeline-objects]] -- `ImageDataPacket` wraps every frame entering the pipeline.
  - [[actuate-healthmonitoring]] -- SES/SNS alerts for puller connectivity failures.
  - [[actuate-imutils]] -- [[opencv-entity|OpenCV]] image processing utilities for frame manipulation.
  - [[actuate-image-manipulation]] -- Fisheye dewarping via native C library (for specialized cameras).
  - [[actuate-blur]] -- FFT-based blur detection to skip unusable frames.

### Stage 3: Inference

The processing phase of the [[pipeline-architecture]]:

- [[actuate-inference-client]] -- Modern HTTP client (httpx, sync+async) for the Rust [[ds-server-container]] model servers. Used by the `AsyncInferencePool`.
- [[actuate-classic-inference-client]] -- Legacy inference client wrapping `requests.post()`. Still in use for most production sites; the `YoloClient` class routes through the [[inference-pool|inference pool]] when available.
- [[actuate-inference-objects]] -- Canonical `Detection`, `BoundingBox`, `DetectionTag` types. Every downstream library that touches detections depends on this.
- [[actuate-inference-slicing]] -- SAHI-style sliced inference for high-resolution streams. Splits images, dispatches tiles, merges results.
- [[actuate-threadpool]] -- `ActuateThreadPoolExecutor` wraps the standard ThreadPoolExecutor with error handling. Used by the [[inference-pool|inference pool]]'s slot mechanism and by observer dispatch.

### Stage 4: Post-Processing Filters

Applied in sequence between inference and observer dispatch:

- [[actuate-filters]] -- 6+ filter implementations (Label, Confidence, LabelwiseConfidence, PolyZone, IoU, Stationary, Blacklist). Each extends `BaseFilter`. See [[filter-architecture]].
- [[actuate-math]] -- IoU computation, NMS, bounding box operations. Consumed by both [[actuate-filters]] and [[actuate-movement]].

### Stage 5: Observer and Alert Generation

The [[observer-pattern]] layer that decides whether to fire alerts:

- [[actuate-connector-observers]] -- The widest dependency fan-out of any library. `ObservableManager` plus 6+ observer types (Intruder, PersonLoiterer, VehicleLoiterer, LineCrossing, Blacklist, PeopleFlow, LeftObject). Depends on:
  - [[actuate-botsort]] -- BoT-SORT multi-object tracker for loitering and line crossing.
  - [[actuate-sort]] -- Simpler SORT tracker (Kalman + IoU association).
  - [[actuate-filterpy]] -- Vendored Kalman filter (numpy, scipy). Underpins both trackers.
  - [[actuate-frames]] -- `save_frame` persists detection window frames to S3/DynamoDB.
  - [[actuate-alarm-senders]] -- 27 sender implementations. Depends on:
    - [[actuate-integration-calls]] -- VMS API clients for alert delivery.
    - [[actuate-viz]] -- Bounding box drawing, ignore zone overlays, trajectory rendering on alert images.
    - [[actuate-event-listener]] -- SQS FIFO dispatch for queue-based alert delivery.
    - [[actuate-pipeline-objects]] -- `AlertData`, `WindowDataPacket` types.

### Stage 6: Monitoring and Health

Running throughout the pipeline lifecycle:

- [[actuate-monitoring]] -- Deployment health reporting to [[new-relic|New Relic]], CloudWatch, and Datadog.
- [[actuate-healthcheck-objects]] -- Health data objects for the CHM (Camera Health Monitoring) product.
- [[actuate-healthmonitoring]] -- SES/SNS job queue alert mechanisms for operational alerts.
- [[actuate-suddenscenechange]] -- SIFT-based [[scene-change-detection|scene change detection]] for camera tampering.
- [[actuate-notification]] -- Slack (SNS) and email (SES) for internal notifications.
- [[actuate-instrumentation]] -- Data capture for debugging and diagnostics.

### VLM Layer (Emerging)

- [[actuate-vlm]] -- Vision Language Model client (SQS + DynamoDB polling) for the [[vlm-fp-reduction|VLM FP reduction]] filter (Qwen3-VL-8B). Used in [[autopatrol/_summary|AutoPatrol (H1.2)]] and planned for broader deployment.

## The Critical Path

The minimum set of libraries a detection must traverse to become an alert:

```
actuate-config -> actuate-pullers -> actuate-movement -> actuate-pipeline (+ actuate-pipeline-objects)
    -> actuate-classic-inference-client (+ actuate-inference-objects)
    -> actuate-filters (+ actuate-math)
    -> actuate-connector-observers -> actuate-alarm-senders (+ actuate-event-listener)
    -> actuate-daos (DynamoDB/S3/SQS writes)
```

This critical path spans **12 libraries minimum**. A bug or breaking change in any of them can halt alert generation. The three highest-risk libraries on this path are:

1. **[[actuate-config]]** -- consumed by virtually everything; a parsing error here blocks the entire connector from starting.
2. **[[actuate-inference-objects]]** -- the `Detection` type is the lingua franca between inference, filters, observers, and senders. A field rename or type change cascades through 7+ direct dependents.
3. **[[actuate-connector-observers]]** -- the widest fan-out library. Changes here can affect tracking, windowing, alert generation, and frame persistence simultaneously.

## Dependency Graph Properties

From the [[dependency-graph]] concept note:

- **11 leaf libraries** with no internal dependencies -- safe to change in isolation.
- **5 core libraries** with many dependents -- changes require full regression testing via the [[dev-workflow]].
- **Bidirectional coupling** between [[actuate-config]] and [[actuate-daos]] is a known architectural smell. Config depends on daos for certain runtime lookups; daos depends on config for connection strings and table names.
- The UV workspace enables local cross-library testing, but CI must validate the full dependency closure before merge to main.

## Practical Implications for Development

When working on the [[vms-connector]], understanding this map helps predict the impact of library upgrades. A patch to [[actuate-math]] (leaf library, only affects [[actuate-filters]] and [[actuate-movement]]) is low-risk. A change to [[actuate-pipeline-objects]] (used by pullers, pipeline, observers, senders) requires testing the entire detection-to-alert flow. The [[dev-workflow]] -- feature branch with dev versions, pin in consumer, test, merge to main, pin stable -- exists precisely because this [[dependency-graph|dependency graph]] is deep and wide.
