---
type: concept
topic: inference-api
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
incoming:
  - topics/inference-api/_summary.md
  - topics/inference-api/notes/concepts/2026-04-29_v5-slicing-as-parameter.md
  - topics/inference-api/sources/deep-dive-filter-chain.md
  - topics/inference-api/sources/deep-dive-v4-endpoints.md
incoming_updated: 2026-05-01
---

# Sensitivity-to-Confidence Mapping

The inference API abstracts raw confidence thresholds behind three sensitivity presets (`low`, `medium`, `high`) plus a raw float override. This mapping is defined in `api/dependencies/filters/thresholds.py` and consumed by the [[deep-dive-filter-chain]] `LabelwiseConfidenceFilter`.

## How It Works

Each endpoint (or v5 model registry entry) references a `confidence_function` that takes a sensitivity value and returns `(default_confidence: float, label_confidences: dict)`. The `LabelwiseConfidenceFilter` uses `label_confidences` for per-label thresholds and `default_confidence` as fallback for unlisted labels. Detections below the threshold for their label are dropped.

## Standard Models

`get_confidence_thresholds()` is used by: intruder, weapon, intruder-plus, intruder-plus-with-vehicle, pet.

| Sensitivity | Default | person | pistol/gun | bicycle | car/motorcycle/bus/truck | machinery |
|-------------|---------|--------|------------|---------|--------------------------|-----------|
| **low** | 0.5 | 0.5 | 0.85 | 0.6 | 0.6 | 0.6 |
| **medium** | 0.4 | 0.4 | 0.75 | 0.3 | 0.3 | 0.3 |
| **high** | 0.1 | 0.1 | 0.6 | 0.1 | 0.1 | 0.1 |

Key observations:
- **Weapons always have elevated thresholds** -- even at "high" sensitivity, pistol/gun requires 0.6 confidence. This reduces false positives for the highest-stakes detection class.
- **"Low" sensitivity = higher thresholds** (fewer detections, more certain). "High" sensitivity = lower thresholds (more detections, more false positives).
- **Person tracks default** at low/medium but diverges from vehicles at low (0.5 vs 0.6).

## Motion-Plus and Sliced Models

`get_motion_plus_confidence_threshold()` and `get_slice_intruder_plus_with_vehicle_confidence_threshold()` use **uniform thresholds** (no per-label overrides):

| Sensitivity | Confidence |
|-------------|-----------|
| low | 0.4 |
| medium | 0.2 |
| high | 0.1 |

These are intentionally simpler because motion-plus operates on frame-difference images (different detection characteristics) and sliced inference already has its own confidence calibration via SAHI.

## Custom Float Override

When sensitivity is a raw float (0 < x < 1.0), all three functions return `(float_value, {})` -- the float becomes the uniform threshold for all labels with no per-label overrides. This allows advanced users to bypass presets.

## v5 Integration

The v5 model registry (`api/v5/registry.py`) stores `confidence_function` per `ModelRegistryEntry`. The `POST /v5/detect` endpoint validates sensitivity from the `data` payload, then calls `entry.confidence_function(sensitivity)` to get thresholds before building the [[deep-dive-filter-chain]].

## Connection to [[inference-context-pattern]]

`InferenceContext` also caches confidence data via `get_confidence_data()`, which calls the configured `confidence_function` once and stores the result. This avoids recalculation in multi-model scenarios.
