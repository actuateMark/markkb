---
title: Detection Pipeline
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [pipeline, detection, yolo, fdmd, observers, architecture]
---

# Detection Pipeline

## Overview

The detection pipeline is the end-to-end processing chain that transforms raw camera frames into customer-facing alerts. Every detection product at Actuate -- intruder, loitering, line crossing, weapon, hardhat, fire -- flows through variants of this pipeline. Understanding the pipeline is essential for debugging false positives, missed detections, and alert timing issues.

## Pipeline Stages

### 1. Frame Ingestion

Camera streams enter the system through the **[[vms-connector|VMS Connector]]** layer. Supported protocols include [[rtsp-deep-dive|RTSP]] (continuous streaming), SMTP (email-based clips), AILink, and [[sentinel-components|Sentinel]]. The ingestion method determines frame cadence: [[rtsp-deep-dive|RTSP]] cameras deliver continuous frames, while SMTP and clip-based cameras deliver frames in bursts separated by minutes of silence. This distinction has major implications for downstream stages, especially [[motion-detection-challenge|motion detection]].

### 2. FDMD Motion Detection

The **Frame Difference Motion Detector (FDMD)** identifies regions of the frame where motion has occurred, producing **motion polygons**. Only regions with detected motion are forwarded for inference, reducing unnecessary GPU load.

FDMD was originally designed for continuous [[rtsp-deep-dive|RTSP]] streams. Approximately 32,000 cameras on the platform use clip-based connections where frames arrive minutes apart, breaking FDMD's temporal assumptions. See [[motion-detection-challenge]] for the ongoing fixes (cumulative blob, single-frame skip).

### 3. YOLO Model Inference

Frames (or motion-cropped chips) are sent to the appropriate YOLO model running as a Kubernetes service in the `ds-model-prod` namespace. The [[actuate-inference-client]] routes requests to the correct model endpoint based on the camera's configured product and model assignment.

Current production models include:
- [[intruder-v5-model]] (`intruder-384h-512w-svc`) -- being replaced by [[intruder-v8-model]]
- [[weapon-v8-model]] (`weapon-v8-XL-736`) -- deploying
- Various specialised models: `fpfinder`, `hardhat`, `fire`, `thermal intruder`, `package`

### 4. Post-Processing Filters

Raw YOLO detections pass through a chain of filters that suppress false positives before reaching observer logic:

- **Stationary Filter** -- compares bounding boxes against FDMD motion polygons; if a detection overlaps significantly with a non-motion area, it is suppressed (catches parked cars, static objects)
- **Confidence Filter** -- applies the configured sensitivity threshold (HIGH/MEDIUM/LOW maps to a confidence cutoff)
- **[[ignore-zones|Ignore Zones]]** -- customer-configured regions of the frame to exclude from detections
- **IOU Filter** -- deduplicates overlapping detections
- **Blacklist Filter** -- suppresses detections matching known nuisance patterns

### 5. Observers (Product Logic)

Filtered detections reach product-specific **observers** that implement alert logic:

- **IntruderObserver** -- requires `frame_thresh` consecutive frames with a detection before triggering. The sliding window prevents single-frame spikes from generating alerts.
- **PersonLoitererObserver** -- uses [[botsort-tracking|BoTSORT tracking]] with `max_age=5` to maintain track identity, triggers when dwell time exceeds the configured threshold.
- **VehicleLoitererObserver** -- similar to person loitering but with `max_age=3` (vehicles are larger, easier to re-acquire).
- **LineCrossingObserver** -- uses [[line-crossing-detection|TrajectoryManager]] with sign-change crossing logic and optional directional filtering.

### 6. Alert Generation

When an observer triggers, the system generates an alert package: annotated frames are uploaded to **S3**, and an alert message is published to **SQS** for downstream consumption (customer notifications, AutoPatrol review, analytics).

### 7. Optional VLM FP Reduction

A post-alert filter using **Qwen3-VL-8B-Instruct** (vision-language model) can review generated alerts and suppress false positives before they reach customers. This runs on K8s via SQS queues with a vLLM backend on EC2 g5.2xlarge instances.

## Related Notes

- [[motion-detection-challenge]] -- FDMD issues with clip-based cameras
- [[botsort-tracking]] -- tracking for loitering products
- [[line-crossing-detection]] -- trajectory-based crossing logic
- [[model-evaluation-framework]] -- how models in this pipeline are validated
