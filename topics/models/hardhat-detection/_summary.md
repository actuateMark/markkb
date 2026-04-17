---
title: "Model: Hard Hat Detection"
type: summary
topic: models/hardhat-detection
tags: [model, ppe, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Hard Hat Detection

## Overview

The hard hat detection model identifies whether individuals on camera are wearing hard hats or other required personal protective equipment (PPE). It serves construction sites, industrial facilities, and other workplaces where PPE compliance monitoring is required. The model is listed as `hardhat` in the [[ai-models]] model catalog among the specialised models alongside fire, thermal intruder, and package detection.

## Detection Classes

The model detects PPE-related classes such as `hardhat` (person wearing a hard hat) and potentially `no_hardhat` (person without required PPE). The `ppe` metric name is recognized in [[actuate-libraries|actuate-config]]'s `StreamDeploymentConfig._check_line_crossing_only()` as one of the "other detection metrics," meaning its presence alongside line crossing prevents line-crossing-only mode.

## K8s Endpoint

The hard hat model runs as a Kubernetes service in the `ds-model-prod` namespace following the standard inference URL pattern:

```
http://{hardhat-model}-svc.ds-model-prod.svc.cluster.local:8080/infer
```

Requests are routed through the [[actuate-libraries|actuate-inference-client]] library using the `KubernetesModelUri` abstraction. The `actuate-inference` CLI tool can target the model endpoint via kubefwd for evaluation and debugging.

## Confidence and Sensitivity

Per-label confidence thresholds are configured in `raw_metrics` within each camera's feature deployment in settings.json. The standard `minimum_confidence` default (50%) applies unless overridden for PPE-specific tuning. Sensitivity levels in the `metrics` block control sliding window behavior through `thresh` and `denominator` settings.

## Pipeline Position

Hard hat detection runs through the [[data-science|detection pipeline]] as a separate feature deployment with its own model, FPS, and thresholds. The processing chain follows the standard path: frame ingestion, FDMD motion detection, YOLO inference on the hardhat model, then post-processing filters (confidence, ignore zones, IOU, stationary), and sliding window alert generation.

## Products and Observers

Hard hat detection uses the standard sliding window pattern without a dedicated observer in [[actuate-libraries|actuate-connector-observers]]. Alerts are generated when the sliding window threshold is met and follow the standard path: frames to S3, alert messages to SQS. The product can run concurrently with other feature deployments (intruder, weapon) on the same camera at different FPS rates.

## Use Cases

- **Construction site monitoring** -- Detecting workers without hard hats in active construction zones
- **Industrial safety** -- Compliance monitoring in factories, warehouses, and manufacturing facilities
- **Workplace safety auditing** -- Automated PPE compliance tracking and reporting

## Configuration

Hard hat detection is configured as a feature deployment in settings.json with PPE-related labels in the `metrics` and `raw_metrics` blocks. Each camera's feature deployment specifies the hardhat model via `model_name`, FPS rate, and confidence thresholds. A single camera can run both intruder detection and hard hat detection simultaneously as separate feature deployments.

## Current Status

Hard hat detection is listed as an active specialised model in the [[ai-models]] model catalog. It serves customers with PPE compliance requirements across construction and industrial sites.

## Related Topics

- [[ai-models]] -- model catalog
- [[data-science]] -- detection pipeline architecture
- [[models/intruder-v5]] -- the primary intruder model that runs alongside hardhat
- [[models/fire-detection]] -- another specialised safety model
