---
title: "Intruder v5 Model (intruder-384h-512w-svc)"
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [model, yolov5, intruder, production]
incoming:
  - topics/ai-models/notes/concepts/confidence-threshold-calibration.md
  - topics/ai-models/notes/entities/intruder-v8-model.md
  - topics/data-science/notes/concepts/detection-pipeline.md
  - topics/data-science/notes/concepts/motion-detection-challenge.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/team-structure/notes/entities/vlad-sapeshka.md
incoming_updated: 2026-05-01
---

# Intruder v5 Model (intruder-384h-512w-svc)

## Overview

`intruder-384h-512w-svc` is the current **production** intruder detection model deployed across the Actuate platform. Built on the [[YOLOv5]] architecture, it serves as the primary model behind [[IntruderObserver]] alerts for the vast majority of customer cameras. Its name encodes the input resolution: 384 pixels high by 512 pixels wide.

## Architecture & Classes

The model is a YOLOv5 detector trained to recognise seven object classes:

1. **Person**
2. **Car**
3. **Bicycle**
4. **Motorcycle**
5. **Bus**
6. **Truck**
7. **Machinery**

These seven classes cover the core intruder detection use case -- identifying people and vehicles entering monitored zones. The class set was chosen to balance detection breadth against false-positive risk; keeping the list tight avoids spurious detections on irrelevant object categories.

## Deployment Details

The model runs as a Kubernetes service inside the `ds-model-prod` namespace, accessible at the standard inference URL pattern:

```
http://intruder-384h-512w-svc.ds-model-prod.svc.cluster.local:8080/infer
```

Requests are routed through the [[actuate-inference-client]] library, which wraps calls behind a `KubernetesModelUri` abstraction. For local development, engineers forward the service using `kubefwd svc -n ds-model-prod --tui`.

## Performance Context

Frame-level evaluation uses the [[actuate-eval]] tool against labeled datasets of 28,828+ images, measuring mAP@0.5. The v5 model's mAP scores established the baseline that the successor [[intruder-v8-model]] had to exceed before being approved for rollout.

The model feeds into a multi-stage [[detection-pipeline]]: raw frames pass through [[motion-detection-challenge|FDMD motion detection]], then the YOLO inference result is filtered by a stationary filter, confidence filter, [[ignore-zones|ignore zones]], IOU filter, and blacklist filter before reaching product-specific observers.

## Succession Plan

The v5 model is being replaced by [[intruder-v8-model]] (`int07-actuate003-v8`), a YOLOv8 model covering the same seven classes. The rollout is tracked under epic **AI-180** and includes 13 sub-tasks: deploying the v8 endpoint, building the container, registering the model, creating v8-calibrated sensitivity settings, pilot site selection, model-aware sensitivity, bulk model swap tooling, decoupling raw metrics, and establishing a model change audit trail. As of April 2026, all sub-tasks remain in "To Do" status.

Until the v8 rollout completes, `intruder-384h-512w-svc` remains the model serving production traffic for intruder detection worldwide (except for on-prem sites using [[watchman-single-class]]).

## Related Notes

- [[intruder-v8-model]] -- the approved successor
- [[model-evaluation-framework]] -- evaluation methodology used to compare v5 vs v8
- [[shadow-testing-methodology]] -- statistical testing that validated the v8 upgrade
- [[detection-pipeline]] -- the full detection stack this model participates in
