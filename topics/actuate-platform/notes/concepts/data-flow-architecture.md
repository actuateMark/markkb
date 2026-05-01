---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [architecture, data-flow, platform, pipeline]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497319963"
---

# Data Flow Architecture

The end-to-end data flow through the Actuate platform, from camera stream ingestion to customer alert delivery. This is the core pipeline that powers all of Actuate's products.

## Full Pipeline

```
[1] Camera Streams (RTSP / SMTP / AILink / 19+ VMS types)
         |
[2] actuate-pullers (frame ingestion)
         |
[3] actuate-movement (FDMD motion detection -- pre-filter)
         |
[4] actuate-inference-client --> model-svc (K8s, ds-model-prod namespace)
         |                        Rust YOLO servers (v5/v8)
         |
[5] actuate-filters (confidence, IOU, ignore zones, stationary, blacklist)
         |
[6] Observers (intruder, loiterer/BoTSORT, line crossing/TrajectoryManager, blacklist)
         |
[7] Sliding window confirmation
         |
[8] DynamoDB (WindowIds, DetectedV2, EnrichedFrame, ImageData, CameraStatus)
    S3 (frames, clips, settings)
         |
[9] SQS FIFO --> queue_consumer (K8s pod)
         |
[10] actuate-alarm-senders (25+ types: Immix, Evalink, Sentinel, Milestone, webhooks...)
         |
[11] Customer monitoring centers / end users
```

## Stage Details

### Stage 1-2: Ingestion

The [[vms-connector]] is the entry point. Deployed as K8s Deployments or CronJobs (one per site) in the `rearchitecture` namespace, each connector pod runs `actuate-pullers` to ingest frames from cameras. Actuate supports 19+ VMS types plus direct [[rtsp-deep-dive|RTSP]], SMTP clips, and AILink. For the [[integrations/morphean/_summary|Morphean]], ingestion happens from Morphean's cloud rather than directly from cameras (see [[cloud-to-cloud-architecture]]).

### Stage 3: Motion Pre-Filter

`actuate-movement` applies FDMD (Frame Difference Motion Detection) to identify frames with activity. This is a cheap pre-filter that avoids running expensive ML inference on static scenes, reducing model server load significantly.

### Stage 4: ML Inference

Frames that pass motion detection are sent to model servers via `actuate-inference-client`. The model servers run in the `ds-model-prod` K8s namespace and are implemented in Rust for performance. Current models include intruder v5 (`intruder-384h-512w-svc`), intruder v8 (`int07-actuate003-v8`, rolling out), weapon v8 (`weapon-v8-XL-736`, deploying), and dedicated fire models. [[michael-aleksa]]'s batching work (ENG-71) targets this stage.

### Stage 5: Post-Processing Filters

`actuate-filters` applies multiple layers of filtering to raw detections: confidence thresholding, IOU (Intersection over Union) deduplication, ignore zone masking, stationary object suppression, and blacklist matching. These filters are critical for reducing false positives -- a key value proposition.

### Stage 6: Observers

Specialized detection logic runs on filtered detections: intruder alerting, loitering detection (using BoTSORT multi-object tracking for dwell time), line crossing (using TrajectoryManager for directional movement), and blacklist re-identification.

### Stage 7: Sliding Window Confirmation

Detections must persist across a configurable sliding window before triggering an alert. This prevents transient false positives (e.g., a single frame with a spurious detection) from generating alerts.

### Stage 8-9: Persistence and Queuing

Confirmed detections are written to **DynamoDB** tables (WindowIds, DetectedV2, EnrichedFrame, ImageData, CameraStatus) and **S3** (frames, clips, settings). Alerts are enqueued to **SQS FIFO** queues for ordered, exactly-once delivery.

### Stage 10-11: Delivery

The `queue_consumer` (K8s pod) reads from SQS FIFO and dispatches to the appropriate alarm sender from `actuate-alarm-senders` (25+ types). See [[alarm-push-pattern]] for details on the [[evalink-components|Evalink]] example of this delivery mechanism.

## Configuration Layer

Orthogonal to the data flow, the [[admin-api/_summary|Actuate Admin API]] (Django 6.0 + DRF on ECS, maintained by [[tatiana-hanazaki]]) manages all configuration: customers, sites, cameras, analytics settings, schedules, integrations, and users. The `connector_deployer` service manages connector pod lifecycle based on Admin API configuration.

## User Interfaces

- **[[alert-ui]] / camera-ui** -- Web dashboards for monitoring and camera management
- **[[actuate_admin]]** -- Django admin portal + REST API
- **actuate-inference-api** -- External partner API (FastAPI on Lambda, see [[vinicius-flores]] and [[michael-aleksa]])

## See Also

- [[multi-region-deployment]] -- where this pipeline runs
- [[alarm-push-pattern]] -- detailed look at the delivery stage
- [[cloud-to-cloud-architecture]] -- variant ingestion path for Morphean
- [[actuate-platform/_summary|Actuate Platform Overview]] -- service inventory
