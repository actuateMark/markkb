---
title: "Model: Thermal Intruder"
type: summary
topic: models/thermal-intruder
tags: [model, thermal, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Thermal Intruder

## Overview

The thermal intruder model is a specialised variant of intruder detection optimised for **thermal (infrared) camera feeds**. Thermal cameras produce greyscale heat-signature images rather than standard RGB video, requiring a model trained on thermal imagery to accurately detect people and vehicles. This model extends the Actuate platform's coverage to low-light and nighttime scenarios where standard optical cameras are ineffective.

## Detection Classes

The thermal intruder model detects similar classes to the standard intruder model -- primarily **person** and vehicle classes -- but trained on thermal imagery where objects appear as heat signatures against cooler backgrounds. The thermal model's class set is optimised for the distinct visual characteristics of infrared imaging (silhouettes, heat gradients, lack of color/texture detail).

## K8s Endpoint

The thermal model runs as a Kubernetes service in the `ds-model-prod` namespace. The [[actuate-libraries|actuate-inference-client]] supports thermal model endpoints, and the `actuate-inference` CLI tool includes `k8s-thermal` as a named endpoint for evaluation and debugging:

```
http://{thermal-model}-svc.ds-model-prod.svc.cluster.local:8080/infer
```

## Thermal-Specific Pipeline Behavior

The [[vms-connector]] pipeline tracks whether a frame originates from a thermal camera via the `is_thermal` flag on the frame packet. This flag is passed through the pipeline and can be used to adjust processing behavior. In the `base_stream_camera.py` processing path, `is_thermal` is forwarded alongside skip flags for stationary and IOU filters.

The thermal flag enables the pipeline to:
- Route frames to the correct thermal model endpoint
- Potentially adjust post-processing filter parameters for thermal imagery characteristics
- Handle the different noise profiles and detection patterns of thermal vs. optical frames

## Confidence and Sensitivity

Per-label confidence thresholds are configured in `raw_metrics` within each camera's feature deployment in settings.json. Thermal cameras may require different confidence thresholds than standard optical cameras due to the different characteristics of heat-signature imagery -- thermal images can have higher contrast between people and backgrounds (making detection easier) but also produce different false-positive patterns (heat reflections, warm surfaces, animals).

## Pipeline Position

Thermal intruder detection follows the same [[data-science/_summary|Data Science Methodology]] architecture as standard intruder detection: frame ingestion, FDMD motion detection, YOLO inference on the thermal model, then post-processing filters (confidence, [[ignore-zones|ignore zones]], IOU, stationary), and sliding window alert generation. The same observers (PersonLoitererObserver, VehicleLoitererObserver, LineCrossingObserver, BlacklistObserver) from [[actuate-libraries|actuate-connector-observers]] can be attached to thermal cameras.

## Use Cases

- **Perimeter security** -- Detecting intruders at night or in low-visibility conditions
- **Critical infrastructure** -- 24/7 monitoring where optical cameras cannot provide consistent coverage
- **Environmental challenges** -- Fog, rain, and smoke conditions where thermal imaging outperforms optical

## Configuration

Thermal intruder detection is configured as a feature deployment in settings.json with the thermal model specified via `model_name`. The camera's stream configuration identifies it as a thermal source, setting the `is_thermal` flag. All standard detection products (intruder, loitering, line crossing) can operate on thermal camera feeds.

## Current Status

The thermal intruder model is listed as an active specialised model in the [[ai-models/_summary|AI Models & Evaluation]] model catalog. It serves customers with thermal camera installations for nighttime and low-visibility security monitoring.

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- detection [[pipeline-architecture|pipeline architecture]]
- [[models/intruder-v5]] -- the standard optical intruder model
- [[models/fire-detection]] -- another specialised detection model
