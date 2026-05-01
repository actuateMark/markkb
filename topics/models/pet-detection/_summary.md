---
title: "Model: Pet Detection"
type: summary
topic: models/pet-detection
tags: [model, pet, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Pet Detection

## Overview

The pet detection model identifies animals (primarily dogs and cats) in camera frames. It is one of the specialised models in the Actuate platform, used for scenarios where customers need to detect or distinguish animals from human intruders. Pet detection helps reduce false positives in intruder detection by identifying animal activity that might otherwise trigger person alerts, and also serves dedicated pet monitoring use cases.

## Detection Classes

The model detects pet-related classes (e.g., dog, cat). These labels are direct pass-through -- they do not require the remapping that intruder detection uses (`person` -> `intruder`). The specific class set depends on the model variant deployed.

## K8s Endpoint

The pet detection model runs as a Kubernetes service in the `ds-model-prod` namespace following the standard inference URL pattern:

```
http://{pet-model}-svc.ds-model-prod.svc.cluster.local:8080/infer
```

Requests are routed through the [[actuate-libraries|actuate-inference-client]] library using the `KubernetesModelUri` abstraction.

## Confidence and Sensitivity

Per-label confidence thresholds are configured in `raw_metrics` within each camera's feature deployment in settings.json. The default `minimum_confidence` pattern (50%) applies unless overridden. Sensitivity levels in the `metrics` block control sliding window behavior through `thresh` and `denominator` settings.

## Pipeline Position

Pet detection runs through the [[data-science/_summary|Data Science Methodology]] as a separate feature deployment with its own model, FPS, and thresholds. The processing chain is: frame ingestion, FDMD motion detection, YOLO inference on the pet model, then post-processing filters (confidence, ignore zones, IOU, stationary). The standard sliding window handles alert generation.

## Products and Observers

Pet detection uses the standard IntruderObserver sliding window pattern. There is no dedicated pet observer in [[actuate-libraries|actuate-connector-observers]]. When the sliding window threshold is met, alerts follow the standard path: frames to S3, alert messages to SQS.

## Configuration

Pet detection is configured as a feature deployment in settings.json with pet-related labels in the `metrics` and `raw_metrics` blocks. Each camera's feature deployment specifies the pet model via `model_name`, FPS rate, and confidence thresholds.

## Current Status

Pet detection is listed among the specialised models in the [[ai-models/_summary|AI Models & Evaluation]] model catalog. It operates as a standalone feature deployment on cameras where pet monitoring or animal differentiation is required.

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- detection pipeline architecture
- [[models/intruder-v5]] -- the primary intruder model that pet detection complements
