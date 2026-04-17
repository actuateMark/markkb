---
title: VMS Connector
type: summary
topic: vms-connector
tags: [connector, pipeline, vms, rtsp, kubernetes, frame-processing]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496238597"
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
---

# VMS Connector

The **core edge component** of the Actuate platform. A multi-threaded Python CLI application that connects to 19+ VMS integrations, pulls video frames, runs YOLO inference, applies detection filters, and generates alerts. Runs as Kubernetes Deployments/CronJobs in the `rearchitecture` namespace.

## Processing Pipeline

Chain-of-responsibility pattern via [[actuate-libraries]] (`actuate-pipeline`):

```
Pre-processors: Encode -> Crop -> Metadata
    |
Processors: YOLO Inference (async pool, AIMD congestion control) -> FPS Downsample
    |
Post-processors: Stationary Filter -> IOU -> Ignore Zones -> Sliding Window -> Confirmation -> Alerting
```

4 pipeline types: `default` (production), `gauntlet` (batch), `local` (dev), `healthcheck`

**AsyncInferencePool:** AIMD congestion control (initial 48 concurrent, floor 8, target 200ms latency)

## Supported Integrations (19+)

RTSP, Milestone, Avigilon, Exacq, Eagle Eye, Digital Watchdog, HikCentral, Genetec, Luxriot, OpenEye, Orchid, Star4Live, Salient, Video Insight, KVS, SQS Video, AutoPatrol, VCH, Patrol

Auth methods vary: Basic Auth, API Token, DB Credentials, HTTP API, AWS IAM, Backend API

## Deployment

- **K8s namespace:** `rearchitecture`
- **Docker images:** 4 variants (x86 CPU, x86 GPU, ARM CPU, ARM GPU)
- **Memory formula:** `cameras * 32MB + 500MB base`
- **Lifecycle:** connector_deployer manages create/update/delete of K8s resources per site
- **VPA:** Known issues with patching race conditions causing OOMKills

## Key Data Stores

| Store | Tables/Buckets | Purpose |
|-------|----------------|---------|
| DynamoDB | WindowIdsV2, EnrichedFrameV2, DetectedV2, ImageData, CameraStatus, PeopleFlow, Healthcheck, SceneChange, Motion, Blacklist, Analysis, ClipsMetadata, Token | Detection windows, frame metadata, status |
| S3 | Frame images, video clips, settings | Media storage, config |
| SQS | Alert queues (per-integration FIFO) | Alert delivery |

## Detection Products

| Product | Observer | Tracking | Key Filter |
|---------|----------|----------|------------|
| Intruder | IntruderObserver | None (frame_thresh consecutive) | Stationary filter |
| Loitering | PersonLoitererObserver / VehicleLoitererObserver | BoTSORT (actuate-botsort) | Dwell time threshold |
| Line Crossing | LineCrossingObserver | TrajectoryManager | Sign-change crossing |
| Weapon | IntruderObserver variant | None | Sliding window |
| Fire/Smoke | IntruderObserver variant | None | Bypasses stationary filter |
| Blacklist | BlacklistObserver | Re-ID | -- |

## Alert Delivery

`actuate-alarm-senders` library provides 25+ sender implementations:
- BaseAlertSender -> AttachmentAlertSender -> EventListenerAlertSender
- MultiAlertSender orchestrator for per-camera multi-destination delivery
- Targets: Immix (SMTP), Milestone, Sentinel, Bold, Patriot, Evalink, webhooks, etc.

## Cross-Platform Data Flow

```
actuate_admin --config--> vms-connector --frames--> ds-server-container (Rust YOLO)
                              |                          |
                         actuate-libraries          ds-slicing-microservice
                              |                          |
                         DynamoDB / S3 <---inference---+
                              |
                         SQS --> queue_consumer --> Customer Systems
```

## Development & Deployment Lifecycle

Feature development follows the [[connector-library-deployment-lifecycle]]:

1. **Library branch** → dev version published to CodeArtifact
2. **Connector pins dev version** → validate on stage fleet
3. **Library merges to main** → stable version published
4. **Connector pins stable version** → tests pass locally
5. **PR cleanup** → resolve conflicts, remove debug artifacts, no dev pins
6. **Merge feature → stage** (`--merge`, not `--squash`)
7. **ECR build** → ARM64 + x86 Docker images pushed
8. **NR monitoring** → staging connectors zero errors, patrol runs complete
9. **Overnight soak** → error rate flat or declining
10. **Merge stage → rearchitecture** (`--squash`) → production release

**Key skills:** `/pre-merge-workflow`, `/stage-release`

**Branch model:** `rearchitecture` (production) ← `stage` (release candidate) ← feature branches

## Known Issues (April 2026)

- **ENG-96 (Highest):** Schedule race condition -- midnight overrides miss arming (band-aid deployed: scaler replicas bumped 10->20)
- **ENG-78 (Highest):** VPA over-provisioning -- requests 3-5x CPU / 2x memory vs actual
- **ENG-66 (Highest):** Event-listener thundering herd -- silent event drops during traffic spikes
- **ENG-79 (Highest):** EKS upgrade needed (1.32 -> 1.35 for in-place pod resize)

## Fleet Architecture Redesign (planning 2026-04-16)

A strategic redesign to replace the site-per-pod monolith with a fleet-based architecture is in the planning + PoC phase. See [[fleet-architecture/_summary]] for the 5 candidate architectures (A-E), cross-cutting designs (graceful failover, frame transport), and the evaluation rubric. The initiative addresses ENG-78, ENG-96, ENG-66, and the single-point-of-failure property of today's architecture.
