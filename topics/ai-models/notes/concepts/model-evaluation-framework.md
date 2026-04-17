---
title: Model Evaluation Framework
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [evaluation, methodology, mAP, shadow-testing, confidence, annotation]
---

# Model Evaluation Framework

## Overview

The DS team employs a rigorous, multi-level evaluation framework to validate any model before it reaches production. No single metric is trusted in isolation; instead, a model must pass through a ladder of increasingly production-representative tests. This framework was developed to prevent regressions and ensure that gains observed in offline benchmarks translate to real-world alert quality.

## Evaluation Tiers

### 1. Frame-Level mAP (Offline)

The baseline evaluation uses **mAP@0.5** computed on labeled datasets containing 28,828+ images. The tool is [[actuate-eval]], the team's custom evaluation harness. This measures pure detection quality: does the model place bounding boxes on the right objects with sufficient overlap?

Frame-level mAP is fast and reproducible but has known limitations -- it does not account for temporal context, post-processing filters, or observer logic. A model with high mAP can still produce excessive false alerts in production.

### 2. Point-Based Annotation

Developed by **Mladen Lukic**, point-based annotation is a fast evaluation method that uses **centroid matching** instead of full bounding-box IoU. Annotators mark object centres rather than drawing precise boxes, dramatically reducing labeling time while still providing meaningful detection accuracy metrics. This enables rapid evaluation cycles, particularly useful during the UK/EU bespoke model experiments where multiple training iterations needed quick turnaround.

### 3. FP Stress Testing (Genesis Sets)

Genesis image sets are curated collections of **hard real-world conditions**: reflections, wildlife, weather artifacts, swaying vegetation, headlights at night, and other scenes known to trigger false positives. Running a candidate model against Genesis sets specifically tests false-positive resilience -- the dimension most directly tied to customer satisfaction.

### 4. Confidence Threshold Sweep

A systematic sweep of confidence thresholds from **0.10 to 0.80**, combined with different sliding window configurations, maps the full precision-recall trade-off surface. This is critical for setting production sensitivity levels (e.g., the [[weapon-v8-model]] thresholds of HIGH=0.65, MED=0.60, LOW=0.55). The sweep reveals whether a model's operating points are well-separated and whether small threshold changes cause dramatic behavior shifts.

### 5. Shadow Testing (Live Traffic)

The most production-representative tier. The candidate model runs in `ds-model-dev` alongside the production model in `ds-model-prod`, processing identical live camera feeds. Results are compared at the **alert (sequence) level** using [[shadow-testing-methodology|McNemar's paired statistical test]]. This captures the full [[detection-pipeline]] including FDMD motion detection, all post-processing filters, and observer logic.

Tools: `shadow-test-eval` (alert-level comparison), `shadow-testing-stats` (statistical analysis).

### 6. Cumulative Misses Validation Set

A continuously maintained dataset of **production misses** -- real events the system failed to detect. Every candidate model is tested against this set to ensure it does not regress on known failure cases. This serves as a regression gate: even if a new model improves overall mAP, it cannot ship if it re-introduces previously fixed misses.

## Decision Process

A model must demonstrate improvement (or at minimum parity) at each tier before advancing. The framework was applied to approve [[intruder-v8-model]] for rollout, to validate [[weapon-v8-model]] for deployment, and to make the data-driven decision to shelve the UK/EU bespoke model in favour of the generalist v8.

## Key People

- **Uladzimir Sapeshka (Vlad)** -- runs evaluations and shadow tests
- **Zack Schmidt** -- owns model decisions for YAM and weapon
- **Mladen Lukic** -- developed point-based annotation method

## Related Notes

- [[shadow-testing-methodology]] -- deep dive on McNemar's test and shadow testing
- [[intruder-v8-model]] -- model validated through this framework
- [[weapon-v8-model]] -- model validated through this framework
- [[detection-pipeline]] -- the system evaluated at the shadow testing tier
