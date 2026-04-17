---
title: Confidence Threshold Calibration
type: concept
topic: ai-models
tags: [confidence, thresholds, sensitivity, calibration, v8, v5, weapon, filters, evaluation]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Confidence Threshold Calibration

## Overview

Confidence threshold calibration determines the operating points at which a YOLO model's raw detection scores are translated into actionable alerts for customers. The Actuate platform exposes three sensitivity levels -- LOW, MEDIUM, and HIGH -- to customers, and each level maps to a per-model, per-label confidence cutoff in the [[detection-pipeline]]. Getting these thresholds right is critical: too low and customers are flooded with false positives; too high and genuine intrusions are missed.

## The Sensitivity Level System

Every camera in the Actuate platform has a configurable **sensitivity level** that governs how aggressively the system detects and alerts. The three levels map to confidence thresholds in the post-processing filter chain:

| Sensitivity | Meaning | Threshold Direction |
|-------------|---------|---------------------|
| **LOW** | Conservative -- fewer alerts, minimal FP | Highest confidence threshold |
| **MEDIUM** | Balanced -- moderate alert volume | Middle threshold |
| **HIGH** | Aggressive -- maximum detection, tolerates more FP | Lowest confidence threshold |

These sensitivity levels are set per camera in `settings.json` and parsed by [[actuate-config]]. The actual confidence cutoff is applied by two filters in [[actuate-filters]]:

- **ConfidenceFilter** -- a single global minimum confidence threshold (`min_confidence`, default 0.5). Detections below this score are dropped regardless of label.
- **LabelwiseConfidenceFilter** -- per-label confidence thresholds via a `label_confidences` dictionary, with a `default_confidence` fallback. This enables different thresholds for person vs. vehicle vs. weapon detections on the same camera.

The labelwise filter is the more precise instrument, allowing the platform to run tight thresholds on well-calibrated labels while being more permissive on others.

## How Thresholds Are Determined

Thresholds are not guessed or copied from academic defaults. They emerge from [[evaluation-tiers|Tier 4 of the evaluation framework]] -- a systematic **confidence threshold sweep** from 0.10 to 0.80, combined with different sliding window configurations. This sweep:

1. Runs inference at each threshold on the standard labeled dataset (28,828+ images) and Genesis FP stress sets
2. Computes precision, recall, F1, and false-positive rate at each point
3. Maps the full precision-recall trade-off surface
4. Identifies natural breakpoints where small threshold increases yield large FP reductions with minimal recall loss

The three sensitivity levels are then placed on this surface at points that give well-separated behavior: LOW should have near-zero FP rate, HIGH should catch nearly everything, and MEDIUM should balance the two. If the breakpoints are too close together (e.g., moving the threshold by 0.05 causes a dramatic behavior shift), the model has poor calibration and may not be suitable for production.

## The v8 vs v5 Threshold Gap

A critical finding during the [[intruder-v8-model]] evaluation was that v8 models produce systematically **lower raw confidence scores** than v5 models for equivalent detection quality. Optimal v8 thresholds are approximately **10% lower** than their v5 counterparts for the same precision-recall trade-off.

This means that v5-era threshold settings cannot be directly applied to v8 models -- doing so would over-filter detections and cause missed events. The v8 rollout epic (AI-180) explicitly includes a sub-task for creating **v8-calibrated sensitivity settings** to account for this gap. The platform needs **model-aware sensitivity** (another AI-180 sub-task) so that it knows which threshold table to apply based on which model is serving a given camera.

The threshold gap arises from architectural differences between YOLOv5 (anchor-based) and YOLOv8 (anchor-free). The v8 detection head produces scores calibrated differently -- not "worse," just on a different scale. The v8 model actually provides better-separated predictions (clearer distinction between true detections and background), but the absolute score values sit lower.

## Weapon Model Thresholds

The [[weapon-v8-model]] (`weapon-v8-XL-736`) has its own threshold calibration, distinct from intruder models:

| Sensitivity Level | Confidence Threshold |
|-------------------|---------------------|
| **HIGH** | 0.65 |
| **MEDIUM** | 0.60 |
| **LOW** | 0.55 |

These thresholds are notably tight -- only a 0.10 spread from LOW (0.55) to HIGH (0.65). This reflects two factors:

1. **Well-calibrated model**: The v8 XL architecture with 736px input resolution produces highly confident and well-separated predictions. The model is rarely uncertain about whether something is a weapon.
2. **Safety-critical domain**: Weapon detection operates in a regime where false negatives (missed weapons) carry severe consequences. Even the LOW sensitivity level uses a relatively low threshold (0.55) compared to intruder models, because the cost of missing a weapon far exceeds the cost of an extra false alarm.

A key finding during weapon v8 evaluation was that most v5-era weapon false positives were **single-frame spikes** -- brief, spurious high-confidence detections that disappeared in the next frame. The existing sliding window filter (IntruderObserver's `frame_thresh` parameter) in the [[detection-pipeline]] already eliminates these temporal anomalies. Combined with the v8 model's inherently lower FP rate, the production system should see dramatic FP reduction.

## Per-Label Threshold Patterns

The `LabelwiseConfidenceFilter` enables different thresholds per detection class on the same camera. This is important because:

- **Person** detections are the primary alert trigger for intruder products and need the most carefully tuned threshold
- **Vehicle** detections (car, bus, truck, motorcycle) may need different thresholds depending on whether the camera monitors a parking lot (where vehicles are expected) vs. a restricted area
- **Weapon** detections always use their own dedicated threshold table regardless of the camera's intruder sensitivity

The per-label approach also supports future multi-head inference (AI-204), where a single model might detect multiple categories with varying reliability per class.

## Interaction with Sliding Window

Confidence thresholds do not operate in isolation. The IntruderObserver's sliding window (`frame_thresh`) acts as a temporal filter: a detection must persist across N consecutive frames before triggering an alert. The confidence sweep (Tier 4) tests threshold-window combinations jointly, because a lower confidence threshold paired with a stricter sliding window can achieve the same alert-level precision as a higher threshold with a looser window, while catching more transient real events.

## Related Notes

- [[evaluation-tiers]] -- Tier 4 confidence sweep in detail
- [[model-evaluation-framework]] -- the full evaluation process
- [[weapon-v8-model]] -- weapon-specific thresholds and rationale
- [[intruder-v8-model]] -- v8 threshold gap and calibration needs
- [[intruder-v5-model]] -- v5 baseline thresholds
- [[detection-pipeline]] -- where confidence filtering happens in the stack
- [[model-lifecycle-end-to-end]] -- lifecycle context for threshold calibration
