---
title: "Model: Weapon v8"
type: summary
topic: models/weapon-v8
tags: [model, yolov8, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Weapon v8

## Overview

The weapon v8 model (`weapon-v8-XL-736`) is a YOLOv8 **XL** weapon detection model trained by **Carlos Torres**. It represents a major upgrade over the previous v5 weapon model, described internally as an "improvement by many orders of magnitude." The deployment decision has been made, tracked under **PROD-98**.

## Detection Classes

The model detects a single class: **weapon**. In the [[vms-connector]] pipeline, weapon detection is configured with separate `gun` and `pistol` metrics in settings.json, each with independent sliding windows. The weapon model typically runs at higher FPS (2-3 fps) with image slicing enabled (`max_slices: 4`) for small-object detection.

## Architecture

The model uses the YOLOv8 XL variant -- the largest standard YOLOv8 backbone -- chosen because false negatives in weapon detection carry severe safety consequences. The "736" in the name refers to the input resolution. The XL architecture's additional capacity helps distinguish genuine weapons from visually similar objects (tools, umbrellas, phone cases) that plagued the v5 model.

## K8s Endpoint

The model will be hosted in the `ds-model-prod` namespace following the standard inference URL pattern:

```
http://weapon-v8-XL-736-svc.ds-model-prod.svc.cluster.local:8080/infer
```

## Confidence Thresholds and Sensitivity

New confidence thresholds have been established for the v8 weapon model:

| Sensitivity Level | Confidence Threshold |
|-------------------|---------------------|
| **HIGH** | 0.65 |
| **MEDIUM** | 0.60 |
| **LOW** | 0.55 |

These thresholds are notably tight (only a 0.10 spread), reflecting the model's improved calibration. The v8 model produces more confident and better-separated predictions, allowing thresholds to sit in a narrow, high-confidence band. Previous v5 weapon settings used higher confidence (80%) due to the model's false-positive issues.

## False Positive Mitigation

A key finding during evaluation: most v5 weapon false positives were **single-frame spikes** -- brief, spurious high-confidence detections. These are eliminated by the existing sliding window filter in the [[data-science|detection pipeline]], which requires detections to persist across multiple frames (typically thresh=2 of denominator=5). The v8 model's inherently lower FP rate combined with temporal filtering should dramatically reduce false weapon alerts.

## Pipeline Position

Weapon detection runs through the same [[data-science|detection pipeline]] as intruder detection but as a separate feature deployment with its own model, FPS, and thresholds. The pipeline applies `RawModelFilterStep`, ignore zones, IOU, `StationaryFilterStep`, then the sliding window. Weapon alerts are flagged as `threat` type in [[actuate-libraries|actuate-config]]'s `StreamDeploymentConfig`, which forces `live_alert = True`.

## Current Status

The deployment decision has been made. The model is in the process of being deployed to production. Carlos Torres trained the model and is involved in deployment alongside Zack Schmidt, who owns weapon model decisions.

## Related Jira

- **PROD-98** -- Weapon v8 deployment

## Related Topics

- [[ai-models]] -- model catalog and evaluation methodology
- [[data-science]] -- detection pipeline
- [[models/intruder-v8]] -- sibling v8 model for intruder detection
