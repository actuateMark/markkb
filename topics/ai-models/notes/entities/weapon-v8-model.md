---
title: "Weapon v8 Model (weapon-v8-XL-736)"
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [model, yolov8, weapon, deployment]
incoming:
  - topics/ai-models/notes/concepts/confidence-threshold-calibration.md
  - topics/ai-models/notes/concepts/model-evaluation-framework.md
  - topics/ai-models/notes/entities/intruder-v8-model.md
  - topics/data-science/notes/concepts/detection-pipeline.md
  - topics/data-science/notes/concepts/evaluation-tiers.md
  - topics/data-science/notes/concepts/training-pipeline-architecture.md
  - topics/models/weapon-v8/_summary.md
  - topics/team-structure/notes/entities/carlos-torres.md
  - topics/team-structure/notes/entities/zack-schmidt.md
incoming_updated: 2026-05-27
---

# Weapon v8 Model (weapon-v8-XL-736)

## Overview

`weapon-v8-XL-736` is a YOLOv8 **XL** weapon detection model trained by **[[carlos-torres|Carlos Torres]]**. It represents a major upgrade over the previous v5 weapon model, described internally as an "improvement by many orders of magnitude." The decision to deploy has been made, tracked under **PROD-98**.

## Architecture

The model uses the YOLOv8 XL variant -- the largest standard YOLOv8 backbone -- which provides the highest accuracy at the cost of increased inference time and memory. The "736" in the name likely refers to the input resolution. It detects a single class: **weapon**.

The choice of the XL backbone reflects the high-stakes nature of weapon detection: false negatives (missed weapons) carry severe safety consequences, justifying the heavier model. The XL architecture's additional capacity also helps distinguish genuine weapons from visually similar objects (tools, umbrellas, phone cases), which plagued the v5 model.

## Confidence Thresholds

New confidence thresholds have been established for the v8 weapon model, replacing the v5 settings:

| Sensitivity Level | Confidence Threshold |
|-------------------|---------------------|
| **HIGH** | 0.65 |
| **MEDIUM** | 0.60 |
| **LOW** | 0.55 |

These thresholds are notably tight (only a 0.10 spread from low to high), reflecting the model's improved calibration. The v8 model produces more confident and better-separated predictions, allowing the thresholds to sit in a narrow, high-confidence band.

## False Positive Mitigation

A key finding during evaluation was that most false positives from the old v5 weapon model were **single-frame spikes** -- brief, spurious high-confidence detections that did not persist across consecutive frames. These are effectively eliminated by the existing **sliding window filter** in the [[detection-pipeline]], which requires detections to persist across multiple frames before triggering an alert.

The combination of the v8 model's inherently lower FP rate and the sliding window's temporal filtering means the deployed system should see a dramatic reduction in false weapon alerts compared to the v5 era.

## Deployment Status (PROD-98)

The deployment decision has been made. The model will be hosted in the `ds-model-prod` Kubernetes namespace following the standard inference URL pattern used by the [[actuate-inference-client]]. [[carlos-torres|Carlos Torres]], who trained the model, is involved in the deployment process alongside [[zack-schmidt|Zack Schmidt]], who owns weapon model decisions.

## Evaluation Methodology

The weapon model was evaluated using the same [[model-evaluation-framework]] applied to intruder models:

- **Frame-level mAP** via [[actuate-eval]]
- **FP stress testing** against Genesis image sets
- **Confidence threshold sweep** (0.10--0.80) to determine optimal operating points
- Comparison against cumulative misses validation set to prevent regression

## Related Notes

- [[intruder-v8-model]] -- sibling v8 model for intruder detection
- [[model-evaluation-framework]] -- multi-level evaluation process
- [[detection-pipeline]] -- the pipeline this model plugs into
- [[shadow-testing-methodology]] -- statistical testing methodology
