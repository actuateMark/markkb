---
title: Shadow Testing Methodology
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [evaluation, shadow-testing, mcnemar, statistics, methodology]
---

# Shadow Testing Methodology

## Overview

Shadow testing is the DS team's method for comparing a candidate model against the production model on **live customer traffic** with full statistical rigor. Rather than relying solely on offline mAP benchmarks, shadow testing captures real-world conditions -- varied lighting, camera angles, weather, and scene complexity -- and produces a statistically defensible answer to the question: "Is the new model actually better?"

## How It Works

During a shadow test, the candidate model runs in the `ds-model-dev` Kubernetes namespace while the production model continues serving from `ds-model-prod`. Both models receive the same frames from the same cameras via the [[detection-pipeline]]. Their outputs are recorded and compared at the **sequence (alert) level**, not just at the frame level.

This dual-path architecture means the candidate model is exercised on real production traffic without affecting customer-facing alerts. Only the production model's outputs reach customers.

## McNemar's Paired Test

The core statistical tool is **McNemar's test**, a non-parametric test for paired nominal data. It is applied to a 2x2 contingency table:

|  | Model B Correct | Model B Incorrect |
|---|---|---|
| **Model A Correct** | Both agree (correct) | Only A correct |
| **Model A Incorrect** | Only B correct | Both agree (incorrect) |

McNemar's test focuses on the **discordant pairs** -- cases where one model is right and the other is wrong. It asks whether the number of discordant pairs is statistically asymmetric (i.e., one model is systematically better). This is more powerful than comparing raw accuracy numbers because it controls for scene difficulty: easy and hard scenes that both models handle identically are excluded from the comparison.

The implementation lives in two repositories:
- `shadow-test-eval` -- alert-level model comparison tooling
- `shadow-testing-stats` -- statistical analysis and reporting

## Sequence-Level vs Frame-Level Evaluation

A critical distinction in the methodology is the **unit of analysis**:

- **Frame-level** evaluation (mAP@0.5 via [[actuate-eval]]) measures detection accuracy on individual images. It answers: "Does the model find the right bounding boxes?" This is useful for development but can be misleading for production quality -- a model might have high mAP but still generate excessive false alerts due to single-frame spikes.

- **Sequence-level** (alert-level) evaluation measures whether the end-to-end system produces correct alerts. After post-processing filters (stationary filter, confidence filter, sliding window) and observer logic ([[IntruderObserver]], [[PersonLoitererObserver]]), what matters is whether the *alert* is correct. A model that produces occasional frame-level FPs but gets filtered out before alert generation may perform identically at the alert level.

Shadow testing operates at the sequence level, making it the most production-representative evaluation tier in the [[model-evaluation-framework]].

## Statistical Rigor

The methodology enforces several practices to avoid false conclusions:

- **Paired design** eliminates scene-level confounders (both models see identical inputs)
- **Sufficient sample size** -- tests run on enough cameras and time windows to achieve statistical power
- **Multiple [[evaluation-tiers|evaluation tiers]]** -- shadow testing is one layer; it complements frame-level mAP, FP stress testing (Genesis sets), confidence sweeps, and the cumulative misses validation set

**Uladzimir Sapeshka (Vlad)** is the primary owner of shadow testing execution and analysis.

## Related Notes

- [[model-evaluation-framework]] -- the full multi-level evaluation process
- [[intruder-v8-model]] -- validated via shadow testing before rollout approval
- [[detection-pipeline]] -- the system under test
