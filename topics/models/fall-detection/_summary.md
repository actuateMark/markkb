---
title: "Model: Fall Detection"
type: summary
topic: models/fall-detection
tags: [model, fall, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Fall Detection

## Overview

Fall detection (slip-and-fall) identifies people who have fallen using a combination of YOLO inference and aspect ratio analysis. The inference model detects a `fall_person` class, and then a post-processing step confirms the detection by checking that the person's bounding box is wider than it is tall (i.e., the person is horizontal/lying down). This two-stage approach reduces false positives from objects that might visually resemble a fallen person.

## Detection Logic

Fall detection uses a two-step process implemented in `ConfirmFallStep` in [[actuate-libraries|actuate-pipeline]]:

1. **YOLO inference** -- The model detects `fall_person` labels in the frame. This is a dedicated class trained to recognize prone/supine human poses.

2. **Aspect ratio confirmation** -- For each `fall_person` detection, the step checks: `height / width < 1`. If the bounding box height is less than its width (the person is wider than tall, i.e., horizontal), the detection is confirmed and relabeled from `fall_person` to `fall`. If the aspect ratio check fails (person appears upright), the detection is filtered out.

This aspect ratio gate is intentionally simple and robust. A standing person has `h/w > 1`; a fallen person has `h/w < 1`. The check catches edge cases where the model detects a crouching or bending person as `fall_person` but their aspect ratio reveals they are not actually prone.

## Configuration

Fall detection is configured in settings.json with `fall` in the `metrics` block. The `raw_metrics` block contains settings for the `fall_person` YOLO label (confidence threshold, IOU threshold). At the label remapping stage in `StreamDeploymentConfig.remap_metrics()`, `fall` is passed through directly (not remapped like `intruder` -> `person`).

The `fall` metric is recognized as an "other detection metric" in `StreamDeploymentConfig._check_line_crossing_only()`, meaning its presence alongside line crossing prevents line-crossing-only mode.

## K8s Endpoint

Fall detection uses an inference model capable of detecting the `fall_person` class. The model runs in the `ds-model-prod` namespace following the standard inference URL pattern:

```
http://{model}-svc.ds-model-prod.svc.cluster.local:8080/infer
```

The specific model name is configured per feature deployment in settings.json via the `model_name` field.

## Pipeline Position

Fall detection flows through the [[data-science/_summary|Data Science Methodology]]: frame ingestion, FDMD motion detection, YOLO inference (detecting `fall_person`), then post-processing filters. The `ConfirmFallStep` runs after the standard filters (confidence, ignore zones, IOU, stationary) and before the label remapping step. Confirmed `fall` labels then enter the sliding window for alert generation.

## Products and Observers

Fall detection uses the standard sliding window pattern without a dedicated observer in [[actuate-libraries|actuate-connector-observers]]. Alerts are generated when the sliding window threshold is met and follow the standard path: frames to S3, alert messages to SQS.

## Current Status

Fall detection is **active in production** as one of the specialised detection products. It relies on the YOLO model having a `fall_person` class in its training data, which is configured per feature deployment.

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- detection pipeline
- [[models/crowd-detection]] -- another derived product using intruder model detections
- [[models/intruder-v5]] -- related person detection model
