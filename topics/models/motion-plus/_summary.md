---
title: "Model: Motion+"
type: summary
topic: models/motion-plus
tags: [model, motion-plus, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Motion+

## Overview

Motion+ is a detection product tier that combines FDMD motion detection with the intruder YOLO model, specifically designed for clip-based camera connections where frames arrive in sporadic bursts. It addresses the fundamental challenge that approximately 32,000 cameras on the platform run on clip-based connections (SMTP, AILink, [[sentinel-components|Sentinel]]) where frames arrive minutes apart, breaking FDMD's temporal assumptions designed for continuous [[rtsp-deep-dive|RTSP]] streams.

## How It Works

Motion+ uses the same intruder model (currently [[models/intruder-v5|intruder-384h-512w-svc]]) but with modified pipeline behavior for single-frame clips. The key differences from standard Intruder detection are:

1. **Stationary filter bypass** -- When the model name contains "motion-plus", the pipeline sets `skip_stationary_filter = True` and `skip_iou_filter = True` on the frame data, bypassing motion-based filtering that would be unreliable without consecutive frames.
2. **FDMD skip for single-frame clips** -- MISS-630 addresses bypassing FDMD entirely for single-frame clips since there is no previous frame to diff against.
3. **Cumulative motion blob** -- MISS-652 enables cumulative motion evidence across frames within a clip for multi-frame clips.

## Product Classification

The [[vms-connector]] classifies products based on the model name in `check_for_plus()` (in `base_connector_factory.py` and `product_utils.py`). When the model name is `ECS to EKS motion-plus` or `EKS to EKS motion-plus`, the product is classified as **Motion+** (product ID 325, value `motion_plus`). This is distinct from **Intruder** (ID 43) and **Intruder+** (ID 206).

## K8s Endpoint

Motion+ uses the same intruder model endpoint as standard Intruder detection -- the difference is in pipeline configuration, not the model itself. The model runs in `ds-model-prod`:

```
http://intruder-384h-512w-svc.ds-model-prod.svc.cluster.local:8080/infer
```

## Pipeline Position

Frames enter through clip-based connectors (SMTP, AILink, [[sentinel-components|Sentinel]]) in the [[vms-connector]]. The [[data-science/_summary|Data Science Methodology]] processes them with modified behavior: FDMD may be skipped or use cumulative mode, YOLO inference runs normally, but the stationary filter and IOU filter are bypassed. The sliding window, [[ignore-zones|ignore zones]], and confidence filters still apply. Alerts follow the standard path to S3 and SQS.

## Observers and Products

Motion+ cameras can have the same observers as standard Intruder cameras: PersonLoitererObserver, VehicleLoitererObserver, LineCrossingObserver, and BlacklistObserver from [[actuate-libraries|actuate-connector-observers]]. The product classification difference is for billing and reporting (`site_product_ended` events), not detection behavior.

## Current Status

Motion+ is **active in production** serving the clip-based camera fleet. Ongoing improvements under MISS-652 (cumulative motion blob) and MISS-630 (skip FDMD for single-frame clips) aim to improve detection quality. The [[data-science/_summary|Data Science Methodology]] remains a significant area of research, with parameter tuning needed for clip-based scenarios.

## Related Jira

- **MISS-652** -- Cumulative motion blob for clip-based cameras
- **MISS-630** -- Skip FDMD for single-frame clips

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- [[motion-detection-challenge|motion detection challenge]] and [[pipeline-architecture|pipeline architecture]]
- [[models/intruder-v5]] -- the underlying intruder model
