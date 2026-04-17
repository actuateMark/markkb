---
title: AI Models & Evaluation
type: summary
topic: ai-models
tags: [ai, models, yolo, v8, weapon, evaluation, mcnemar, shadow-testing]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/DS/"
jira: "AI"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# AI Models & Evaluation

## Production Models

| Model | Architecture | Classes | Status |
|-------|-------------|---------|--------|
| `intruder-384h-512w-svc` | YOLOv5 | 7 (person, car, bicycle, motorcycle, bus, truck, machinery) | Current PROD |
| `int07-actuate003-v8` | YOLOv8 | Same 7 classes | Approved for rollout (replaces v5) |
| `weapon-v8-XL-736` | YOLOv8 XL | Weapon | Decision made: deploying |
| `euromodel-int01-actuate004-v8` | YOLOv8 | UK/EU bespoke intruder | Parked (didn't outperform generalist) |
| `watchman-single-class` | OpenVINO INT8 | Single-class intruder | On-prem baseline established |
| Other: `fpfinder`, `hardhat`, `fire`, `motion+`, `thermal intruder`, `package` | Various | Various | Various states |

## Active Initiatives (April 2026)

### YAM Re-evaluation (AI-211, Highest Priority)
After commit `788bed7` changed chip generation from processed_frame to original frame resolution (SAHI-style), all YAM endpoints need re-evaluation for updated mAP/recall/F1. **Vlad (Uladzimir Sapeshka)** is running this.

### v8 Intruder Rollout (AI-180)
Large epic with 13 sub-tasks: deploy v8 endpoint, build container, register model, create v8-calibrated sensitivity settings, pilot site selection, model-aware sensitivity, bulk model swap tooling, decouple raw metrics, model change audit trail. **All still To Do.**

### Weapon v8 Deployment (PROD-98)
New YOLOv8 XL weapon model trained by Carlos Torres. "Improvement by many orders of magnitude" over v5. New confidence thresholds: HIGH=0.65, MED=0.60, LOW=0.55. Most old-model FP were single-frame spikes eliminated by sliding window filter.

### UK/EU Bespoke Model
After 2 labeling/training cycles, bespoke model didn't outperform generalist. Decision: deploy `int07-actuate003-v8` to UK/EU now, continue bespoke effort with larger dataset.

### Multi-head Inference (AI-204)
6 tasks: design review, load testing, latency measurement, cost savings estimation, optimization, staged deployment. **Not yet started.**

## VLM Models in Evaluation

For AutoPatrol FP reduction and [[settings-automation]]:
- Qwen3-VL-8B-Instruct (primary)
- Qwen2.5-VL-32B-Instruct-AWQ
- Gemma-3-12B-IT-FP8
- GPT-4o-mini (LLM-as-Judge baseline)
- Claude Haiku (LLM-as-Judge comparison)

## Evaluation Methodology

The DS team uses a rigorous multi-level framework:

1. **Frame-level:** mAP@0.5 on labeled datasets (28,828+ images). Tool: `actuate-eval`
2. **Sequence/alert-level:** McNemar's paired statistical test. Tool: `shadow-test-eval`
3. **FP stress testing:** Genesis image sets (hard real-world conditions)
4. **Shadow testing:** Run DEV alongside PROD on real traffic with statistical comparison. Repo: `shadow-testing-stats`
5. **Confidence threshold sweep:** Systematic sweep (0.10-0.80) with sliding window configs
6. **Point-based annotation:** Fast evaluation via centroid matching (Mladen Lukic's method)
7. **Cumulative misses validation set:** Production misses prevent regression

## Inference Architecture

- **K8s hosting:** `ds-model-prod` / `ds-model-dev` namespaces
- **URL pattern:** `http://{model}-svc.ds-model-{env}.svc.cluster.local:8080/infer`
- **Client:** `actuate-inference-client` (KubernetesModelUri)
- **Local dev:** `kubefwd svc -n ds-model-prod --tui`
- **VLM inference:** K8s via SQS queues, vLLM backend, EC2 g5.2xlarge (~$1.21/hr)

## Key People

| Person | Focus |
|--------|-------|
| Uladzimir Sapeshka (Vlad) | YAM evaluation, v8 performance, shadow testing |
| Zack Schmidt | YAM epic owner, weapon model decisions |
| Alena Prashkovich | UK camera screening, prompt engineering |
| Mladen Lukic | UK/EU bespoke model labeling, point-based annotation |
| Otzar Jaffe | PPF pipeline, site classification, model merging |
| Carlos Torres | Weapon model training, VLM FP filter, model routing |
| Laura Reno | Release communications |
