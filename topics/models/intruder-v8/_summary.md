---
title: "Model: Intruder v8"
type: summary
topic: models/intruder-v8
tags: [model, yolov8, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Intruder v8

## Overview

The intruder v8 model (`int07-actuate003-v8`) is the approved next-generation intruder detection model, built on the YOLOv8 architecture. It has been validated through the DS team's full multi-level evaluation framework and is approved to replace the current production [[models/intruder-v5|intruder v5 model]]. As of April 2026, the rollout epic (AI-180) is defined but all 13 sub-tasks remain in "To Do" status.

## Detection Classes

The model detects the same **seven classes** as its predecessor: person, car, bicycle, motorcycle, bus, truck, and machinery. Maintaining class parity ensures a drop-in replacement with no downstream observer or filter changes required at the class level. The upgrade targets improved accuracy, particularly in challenging conditions where the v5 model produced false positives or missed detections.

## K8s Endpoint

The v8 model will be deployed in the `ds-model-prod` namespace following the standard inference URL pattern:

```
http://int07-actuate003-v8-svc.ds-model-prod.svc.cluster.local:8080/infer
```

During evaluation, it ran in the `ds-model-dev` namespace for shadow testing alongside the production v5 model on live customer traffic.

## Evaluation Results

The model passed every level of the [[ai-models/_summary|AI Models & Evaluation]]:

1. **Frame-level mAP** -- via `actuate-eval` on the 28,828+ image dataset, showing improvement over v5 baselines.
2. **Shadow testing** -- McNemar's paired statistical test via `shadow-test-eval` and `shadow-testing-stats`.
3. **FP stress testing** -- Genesis image sets with hard real-world conditions (reflections, wildlife, weather).
4. **Confidence threshold sweep** -- Systematic sweep from 0.10 to 0.80 with sliding window configurations.

The v8 model was also evaluated for UK/EU cameras alongside the bespoke `euromodel-int01-actuate004-v8`. After two labeling/training cycles, the bespoke model did not outperform the generalist, so the decision was made to deploy `int07-actuate003-v8` globally.

## Rollout Plan (AI-180)

The rollout contains 13 sub-tasks: deploy v8 endpoint, build container, register model, create v8-calibrated sensitivity settings, pilot site selection, model-aware sensitivity, bulk model swap tooling, decouple raw metrics, and model change audit trail. **Vlad (Uladzimir Sapeshka)** owns v8 performance evaluation; **Zack Schmidt** owns the broader YAM epic.

## YAM Re-evaluation (AI-211)

Commit `788bed7` changed chip generation from processed-frame to original-frame resolution (SAHI-style), requiring all YAM endpoints -- including v8 -- to be re-evaluated for updated mAP, recall, and F1. This is the **highest priority** item and must complete before deployment proceeds. Vlad is running this re-evaluation.

## Pipeline and Products

The v8 model will slot into the same [[data-science/_summary|Data Science Methodology]] position as the v5 model. All products that currently use the v5 model (Intruder, Intruder+, loitering, line crossing, crowd, blacklist) will use the v8 model after migration. The [[vms-connector]] product classification and [[actuate-libraries|actuate-connector-observers]] remain unchanged.

## Related Jira

- **AI-180** -- v8 intruder rollout epic (13 sub-tasks)
- **AI-211** -- YAM re-evaluation (highest priority, blocking deployment)

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog and evaluation methodology
- [[data-science/_summary|Data Science Methodology]] -- detection pipeline and training infrastructure
- [[models/intruder-v5]] -- the current production model being replaced
- [[models/weapon-v8]] -- sibling v8 model for weapon detection
