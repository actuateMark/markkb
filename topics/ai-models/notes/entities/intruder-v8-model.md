---
title: "Intruder v8 Model (int07-actuate003-v8)"
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [model, yolov8, intruder, rollout]
incoming:
  - topics/ai-models/notes/concepts/confidence-threshold-calibration.md
  - topics/ai-models/notes/concepts/model-evaluation-framework.md
  - topics/ai-models/notes/concepts/shadow-testing-methodology.md
  - topics/ai-models/notes/entities/intruder-v5-model.md
  - topics/ai-models/notes/entities/weapon-v8-model.md
  - topics/data-science/notes/concepts/detection-pipeline.md
  - topics/data-science/notes/concepts/evaluation-tiers.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/models/intruder-v8/_summary.md
  - topics/team-structure/notes/entities/vlad-sapeshka.md
incoming_updated: 2026-05-27
---

# Intruder v8 Model (int07-actuate003-v8)

## Overview

`int07-actuate003-v8` is the approved next-generation intruder detection model, built on the [[YOLOv8]] architecture. It has been validated through the team's full [[model-evaluation-framework]] and is approved to replace the current production [[intruder-v5-model]] (`intruder-384h-512w-svc`). As of April 2026, the rollout epic (AI-180) is defined but all sub-tasks remain in "To Do" status.

## Architecture & Classes

Like its predecessor, the v8 model detects the same **seven classes**: person, car, bicycle, motorcycle, bus, truck, and machinery. Maintaining class parity ensures a drop-in replacement with no downstream observer or filter changes required at the class level. The upgrade targets improved accuracy, particularly in challenging conditions where the v5 model produced false positives or missed detections.

## Evaluation Results

The model passed every level of the team's [[model-evaluation-framework]]:

1. **Frame-level mAP** -- Evaluated via [[actuate-eval]] on the standard 28,828+ image dataset at mAP@0.5, showing improvement over v5 baselines.
2. **Shadow testing** -- Run in the `ds-model-dev` namespace alongside the production v5 model on live customer traffic. Statistical comparison used [[shadow-testing-methodology|McNemar's paired test]] via the `shadow-test-eval` and `shadow-testing-stats` repositories.
3. **FP stress testing** -- Tested against Genesis image sets containing hard real-world conditions (reflections, wildlife, weather artifacts) to verify false-positive resilience.
4. **Confidence threshold sweep** -- Systematic sweep from 0.10 to 0.80 with sliding window configurations to determine optimal operating points.

The v8 model was also evaluated as a potential replacement for UK/EU cameras alongside the bespoke `euromodel-int01-actuate004-v8`. After two labeling and training cycles, the bespoke model did not outperform the generalist v8, so the decision was made to deploy `int07-actuate003-v8` globally, including UK/EU sites.

## Rollout Plan (AI-180)

The rollout epic contains **13 sub-tasks**:

- Deploy v8 inference endpoint in `ds-model-prod`
- Build and publish container image
- Register model in model registry
- Create v8-calibrated sensitivity settings (confidence thresholds differ from v5)
- Select pilot sites for phased deployment
- Implement model-aware sensitivity (so platform knows which model is active per camera)
- Build bulk model swap tooling for fleet-wide migration
- Decouple raw metrics from model version for clean comparison
- Establish model change audit trail

**Uladzimir Sapeshka (Vlad)** owns v8 performance evaluation, while **[[zack-schmidt|Zack Schmidt]]** owns the broader YAM epic.

## YAM Re-evaluation Dependency (AI-211)

Commit `788bed7` changed chip generation from processed-frame to original-frame resolution (SAHI-style), affecting all YAM endpoints. This is the **highest priority** item: all endpoints -- including v8 -- need re-evaluation for updated mAP, recall, and F1 before deployment proceeds. Vlad is running this re-evaluation.

## Related Notes

- [[intruder-v5-model]] -- the model being replaced
- [[shadow-testing-methodology]] -- how the v8 was statistically validated
- [[model-evaluation-framework]] -- the multi-level evaluation process
- [[weapon-v8-model]] -- sibling v8 model for weapon detection
