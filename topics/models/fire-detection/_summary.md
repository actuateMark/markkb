---
title: "Model: Fire Detection"
type: summary
topic: models/fire-detection
tags: [model, fire, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Fire Detection

## Overview

The fire detection model detects fire and smoke in camera frames. It is one of the specialised models in the Actuate platform alongside intruder, weapon, and hardhat models. Fire and smoke detection have unique pipeline behavior: they **bypass the stationary filter entirely**, which is critical because fire and smoke are inherently stationary in the frame (they do not move between frames like a person), yet they are real threats that must not be suppressed.

## Detection Classes

The model detects two classes: **fire** and **smoke**. These are direct pass-through labels -- the YOLO inference labels match the product metric names without remapping (unlike intruder, where `person` maps to `intruder`).

## K8s Endpoint

The fire model runs as a service in the `ds-model-prod` namespace following the standard inference URL pattern used by the [[actuate-libraries|actuate-inference-client]]:

```
http://fire-svc.ds-model-prod.svc.cluster.local:8080/infer
```

## Stationary Filter Bypass

The `StationaryFilterStep` in [[actuate-libraries|actuate-pipeline]] has a hardcoded `PASSTHROUGH_LABELS = frozenset(["fire", "smoke"])`. When the stationary filter encounters fire or smoke detections, it passes them through without checking motion polygon overlap. This is also implemented in the `LoitererObserver` stationary filter methods in [[actuate-libraries|actuate-connector-observers]], where fire and smoke labels bypass the motion overlap check.

This bypass is essential because the stationary filter's purpose is to suppress detections on static objects (parked cars, permanent fixtures) using FDMD motion polygons. Fire and smoke may not produce strong motion signals in FDMD, especially when burning steadily, but they are always genuine threats.

## Pipeline Position

Fire detection runs through the [[data-science/_summary|Data Science Methodology]] as a separate feature deployment with its own model, FPS, and thresholds. The processing chain is: frame ingestion, FDMD motion detection, YOLO inference on the fire model, then post-processing filters. The stationary filter step is bypassed for fire/smoke labels, but other filters (confidence, [[ignore-zones|ignore zones]], IOU) still apply. Alerts pass through the standard sliding window step.

## Configuration

Fire detection is configured as a feature deployment in settings.json with `fire` and `smoke` in the `metrics` block. The `raw_metrics` block contains per-label confidence thresholds. The `_check_line_crossing_only()` method in `StreamDeploymentConfig` recognizes `fire` as one of the "other detection metrics" that prevents line-crossing-only mode when present alongside line crossing products.

## Products and Observers

Fire detection uses the standard IntruderObserver sliding window pattern rather than a specialised observer. There is no dedicated fire observer in [[actuate-libraries|actuate-connector-observers]]. When the sliding window threshold is met, alerts follow the standard path: frames to S3, alert messages to SQS.

## Current Status

The fire model is **active in production** as one of the specialised models in the Actuate platform. It is listed among the "Other" models in the [[ai-models/_summary|AI Models & Evaluation]] model catalog alongside hardhat, thermal intruder, and package detection.

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- detection [[pipeline-architecture|pipeline architecture]]
- [[models/intruder-v5]] -- primary intruder model that fire detection coexists with
