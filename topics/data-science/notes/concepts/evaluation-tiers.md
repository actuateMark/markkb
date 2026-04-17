---
title: "Evaluation Tiers: The 6-Level Framework"
type: concept
topic: data-science
tags: [evaluation, mAP, mcnemar, shadow-testing, genesis, confidence-sweep, point-annotation, cumulative-misses]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Evaluation Tiers: The 6-Level Framework

## Overview

The DS team's evaluation methodology is a ladder of six increasingly production-representative tiers. No single metric is trusted in isolation -- a model must demonstrate improvement (or at minimum parity) at every level before advancing toward deployment. The framework was developed to prevent the common failure mode where offline mAP improvements fail to translate into better real-world alert quality, and it was applied to approve [[intruder-v8-model]], validate [[weapon-v8-model]], and make the data-driven decision to shelve the UK/EU bespoke model.

## Tier 1: Frame-Level mAP (Offline Benchmark)

**What it measures:** Pure bounding-box detection accuracy on individual frames.

**Tool:** [[actuate-eval]] (`actuate-eval map`), the team's custom evaluation harness.

**Method:** Predictions from detection CSV or Parquet records (produced by [[actuate-inference]]) are compared against hand-labeled ground truth in YOLO TXT format. The primary metrics are mAP@0.5, mAP@0.5:0.95, per-class AP, precision, recall, and F1. PR curves are exported at 1000 points per class for detailed analysis.

**Dataset:** The standard labeled dataset contains 28,828+ images. Ground truth is maintained in the [[actuate-data-registry-dvc]] and referenced by `datasets/dataset_manifest.yaml` in [[ds-training-pipeline]].

**When used:** Every model evaluation. This is the baseline gate -- fast, reproducible, and objective. However, frame-level mAP has known limitations: it does not account for temporal context, post-processing filters ([[actuate-filters]]), or observer logic ([[detection-pipeline]]). A model with high mAP can still produce excessive false alerts in production due to single-frame spikes or poor threshold calibration.

**Typical workflow:**
1. Run `shadow-infer` (from [[actuate-inference]]) to produce detection Parquet
2. Evaluate with `actuate-eval map --from-detections` against ground truth
3. Compare models with `actuate-eval plot-pr` for side-by-side PR curves

## Tier 2: Point-Based Annotation (Rapid Evaluation)

**What it measures:** Detection accuracy using centroid matching instead of full bounding-box IoU.

**Developer:** Mladen Lukic.

**Method:** Annotators mark object centres rather than drawing precise bounding boxes. Detection predictions are matched to centroids using proximity thresholds rather than IoU overlap. This dramatically reduces labeling time (minutes per image set vs. hours for full bounding boxes) while still providing meaningful precision/recall metrics.

**When used:** Rapid iteration cycles where turnaround speed matters more than pixel-precise accuracy. This was particularly valuable during the UK/EU bespoke model experiments (euromodel-int01-actuate004-v8), where multiple training-labeling iterations needed quick feedback to decide whether the bespoke approach was outperforming the generalist [[intruder-v8-model]]. Also useful for initial screening before committing to a full Tier 1 evaluation.

**Documented in:** Confluence page "A High-Speed Framework for Model Evaluation: Point-Based Annotation" by Mladen Lukic.

## Tier 3: FP Stress Testing (Genesis Sets)

**What it measures:** False-positive resilience under hard real-world conditions.

**Method:** Genesis image sets are curated collections of scenes known to trigger false positives: reflections on glass, wildlife (birds, deer, cats), weather artifacts (rain, fog, snow), swaying vegetation, headlights at night, HVAC steam, shadows, and cluttered backgrounds. Running a candidate model against Genesis sets tests the dimension most directly tied to customer satisfaction -- excessive FP is the leading cause of customer churn.

**When used:** Every candidate model, after passing Tier 1. A model that improves overall mAP but regresses on Genesis sets is not suitable for deployment. The weapon v8 evaluation specifically examined FP rates on Genesis scenes and found that most v5-era false positives were single-frame spikes that the sliding window filter in the [[detection-pipeline]] already eliminates, giving the v8 model an inherently lower FP residual.

## Tier 4: Confidence Threshold Sweep

**What it measures:** The full precision-recall trade-off surface across operating points.

**Method:** A systematic sweep of confidence thresholds from 0.10 to 0.80, combined with different sliding window configurations (varying `frame_thresh` in the [[detection-pipeline]]'s IntruderObserver). This maps how the model behaves at every possible operating point and reveals whether sensitivity levels (HIGH/MEDIUM/LOW) map to well-separated precision-recall trade-offs. See [[confidence-threshold-calibration]] for how thresholds are ultimately set per model.

**When used:** After Tier 3, to determine production operating points. Critical for:
- Setting per-model sensitivity thresholds (e.g., [[weapon-v8-model]]: HIGH=0.65, MED=0.60, LOW=0.55)
- Identifying whether v8 thresholds are approximately 10% lower than v5 for equivalent performance (the "v8 threshold gap")
- Detecting pathological models where small threshold changes cause dramatic behavior shifts (unstable calibration)
- Understanding how the [[actuate-filters]] confidence filter and [[actuate-filters]] labelwise confidence filter interact with the model's score distribution

## Tier 5: Shadow Testing (Live Traffic + McNemar)

**What it measures:** Alert-level quality on real production traffic, with statistical rigor.

**Tools:** [[shadow-test-pipeline]] (orchestration, Athena queries, alert matching, labeling), [[actuate-eval]] (`actuate-eval compare` for McNemar/Wilcoxon), `shadow-testing-stats` (statistical analysis and reporting).

**Method:** The candidate model runs in `ds-model-dev` alongside the production model in `ds-model-prod`, processing identical live camera feeds. Both models see the same frames through the full [[detection-pipeline]] including FDMD motion detection, all post-processing filters, and observer logic. Results are compared at the **alert (sequence) level** -- not frame level -- using McNemar's paired statistical test.

McNemar's test constructs a 2x2 contingency table of discordant pairs (cases where one model gets it right and the other gets it wrong) and tests whether the asymmetry is statistically significant. This is more powerful than comparing raw accuracy numbers because it controls for scene difficulty. See [[shadow-testing-methodology]] for the full statistical treatment.

The [[shadow-test-pipeline]] automates the full workflow: querying AWS Athena for alert data, classifying alerts as prod/dev based on model identifier substrings in `custcam_id`, matching paired alerts using a sliding-window + greedy algorithm (25s time delta, 0.3 IoU threshold), downloading frames, and presenting them for manual TP/FP labeling via OpenCV tools, Streamlit interface, or Encord integration.

**When used:** The most production-representative evaluation tier. Applied to validate [[intruder-v8-model]] before rollout approval. The February 2026 shadow test run compared `int07-actuate003-v8` (DEV) against `intruder-384h-512w-svc` (PROD) at the alert-sequence level. **Uladzimir Sapeshka (Vlad)** is the primary owner of shadow test execution and analysis.

## Tier 6: Cumulative Misses Validation

**What it measures:** Regression on known failure cases.

**Method:** A continuously maintained dataset of **production misses** -- real events the system failed to detect in the field. Every candidate model is tested against this set as a regression gate: even if a new model improves overall mAP and passes shadow testing, it cannot ship if it re-introduces previously fixed misses.

**When used:** Final gate before deployment approval. The cumulative misses set grows over time as new failure modes are discovered, making this an increasingly stringent check. It ensures that the institutional memory of past failures is encoded into the evaluation process rather than relying on individuals remembering specific edge cases.

## Decision Flow

```
Candidate Model
  |
  v
[Tier 1] Frame-level mAP  --> Fail? Stop. Retrain.
  |
  v
[Tier 2] Point-based annotation (optional, for rapid iteration)
  |
  v
[Tier 3] Genesis FP stress  --> Fail? Stop. Investigate FP sources.
  |
  v
[Tier 4] Confidence sweep   --> Set operating points (HIGH/MED/LOW)
  |
  v
[Tier 5] Shadow testing     --> McNemar p-value insignificant? Investigate.
  |
  v
[Tier 6] Cumulative misses  --> Regression? Stop. Fix before deploying.
  |
  v
Deployment approved --> [[ds-server-container]] to ds-model-prod
```

## Related Notes

- [[model-evaluation-framework]] -- summary-level overview of the framework
- [[shadow-testing-methodology]] -- deep dive on McNemar's test
- [[confidence-threshold-calibration]] -- how thresholds are determined per model
- [[actuate-eval]] -- evaluation toolkit
- [[shadow-test-pipeline]] -- shadow testing infrastructure
- [[actuate-inference]] -- inference client that produces detection records
- [[training-pipeline-architecture]] -- how models are trained before evaluation
- [[model-lifecycle-end-to-end]] -- the full lifecycle context
