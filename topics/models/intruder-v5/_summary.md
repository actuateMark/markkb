---
title: "Model: Intruder v5"
type: summary
topic: models/intruder-v5
tags: [model, yolov5, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Intruder v5

## Overview

The [[intruder-v5-model|intruder v5 model]] (`intruder-384h-512w-svc`) is the current **production** intruder detection model deployed across the Actuate platform. Built on the YOLOv5 architecture, it serves as the primary model behind intruder, vehicle, and bike detection for the vast majority of customer cameras. The model name encodes its input resolution: 384 pixels high by 512 pixels wide.

## Detection Classes

The model detects **seven object classes**: person, car, bicycle, motorcycle, bus, truck, and machinery. These cover the core intruder detection use case -- identifying people and vehicles entering monitored zones. The class set balances detection breadth against false-positive risk.

## K8s Endpoint

The model runs as a Kubernetes service in the `ds-model-prod` namespace:

```
http://intruder-384h-512w-svc.ds-model-prod.svc.cluster.local:8080/infer
```

Requests are routed through the [[actuate-libraries|actuate-inference-client]] library using the `KubernetesModelUri` abstraction. For local development, engineers use `kubefwd svc -n ds-model-prod --tui`.

## Confidence and Sensitivity

Per-label confidence thresholds are configured in `raw_metrics` within each camera's feature deployment (settings.json). The default `minimum_confidence` is 50 (i.e., 50%). Sensitivity levels (HIGH/MEDIUM/LOW) in the `metrics` block control the sliding window behavior at the product layer via `thresh` and `denominator` settings in [[actuate-libraries|actuate-config]]'s `StreamDeploymentConfig`.

## Pipeline Position

Frames flow through the [[data-science/_summary|Data Science Methodology]]: camera ingestion, FDMD motion detection, YOLO inference on this model, then post-processing filters (stationary, confidence, [[ignore-zones|ignore zones]], IOU, blacklist). Filtered detections reach product-specific observers. The model feeds into the IntruderObserver sliding window, PersonLoitererObserver, VehicleLoitererObserver, LineCrossingObserver, CrowdViolationPresentStep, and BlacklistObserver depending on which products are configured.

## Products Using This Model

The model is referenced by the `EKS to EKS intruder` and `ECS to EKS intruder` model names in [[vms-connector]] settings. Product classification (`check_for_plus()` in `base_connector_factory.py`) maps these to the **Intruder** product (ID 43). Other model name variants map to **Intruder+** (ID 206) or **Motion+** (ID 325).

## Current Status

The v5 model is **active in production** but scheduled for replacement by the [[models/intruder-v8|intruder v8 model]] (`int07-actuate003-v8`). The rollout is tracked under epic **AI-180** with 13 sub-tasks, all currently in "To Do" status. Until the v8 rollout completes, the v5 model serves all production intruder traffic worldwide except on-prem sites using the `watchman-single-class` OpenVINO model.

## Related Jira

- **AI-180** -- v8 intruder rollout epic (replaces this model)
- **AI-211** -- YAM re-evaluation (re-evaluating all endpoints including v5 after chip generation change)

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- broader model catalog and evaluation methodology
- [[data-science/_summary|Data Science Methodology]] -- [[detection-pipeline|detection pipeline]] and training infrastructure
- [[models/intruder-v8]] -- the approved successor model
