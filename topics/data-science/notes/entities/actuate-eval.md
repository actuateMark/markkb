---
title: "actuate-eval"
type: entity
topic: data-science
tags: [evaluation, mAP, mcnemar, wilcoxon, precision-recall, metrics, cli, python]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/ai-models/notes/concepts/model-evaluation-framework.md
  - topics/ai-models/notes/concepts/shadow-testing-methodology.md
  - topics/ai-models/notes/entities/actuate-inference.md
  - topics/ai-models/notes/entities/intruder-v5-model.md
  - topics/ai-models/notes/entities/intruder-v8-model.md
  - topics/ai-models/notes/entities/weapon-v8-model.md
  - topics/data-science/notes/concepts/evaluation-tiers.md
  - topics/data-science/notes/concepts/training-pipeline-architecture.md
  - topics/data-science/notes/entities/shadow-test-pipeline.md
incoming_updated: 2026-05-01
---

# actuate-eval

Evaluation and metrics toolkit for Actuate ML models. Consolidates mAP computation, McNemar/Wilcoxon statistical comparison, format conversion, and PR curve visualization into a single package. Has no runtime dependency on [[actuate-inference]] -- the two communicate via file format contracts (CSV, Parquet, YOLO TXT).

## CLI Commands

- **`actuate-eval map`** -- Computes mAP@0.5, mAP@0.5:0.95, per-class AP, precision, recall, and F1. Accepts ground truth in YOLO TXT format and predictions either as YOLO TXT files (`--pred-dir`) or directly from detection CSV/Parquet records (`--from-detections`, recommended). Supports per-connector/camera grouping, confidence thresholds, endpoint filtering, and PR curve export (1000 points per class).
- **`actuate-eval compare`** -- McNemar statistical comparison between two model endpoints. Reads detection CSV, sweeps across configurable confidence thresholds, and reports statistical significance with optional threshold sensitivity plots. Also supports Wilcoxon signed-rank tests.
- **`actuate-eval convert`** -- Converts detection CSV or Parquet to YOLO normalized TXT format. Supports class maps (`intruder`, `weapon`, `postal` built-in, or custom YAML), endpoint/label/confidence filtering, and optional image copying.
- **`actuate-eval plot-pr`** -- Visualizes precision-recall curves from one or more result JSON files. Useful for comparing models side by side.

## Architecture

The package is organized into: `metrics/` (mAP, IoU, AP, PR curves), `stats/` (McNemar, Wilcoxon), `reporting/` (PR plots, scatter, threshold visualization), `loader/` (CSV, Parquet, YOLO, conversion), and `cli/` (entry points).

## Installation

Uses `uv` (recommended) or pip. Optional extras: `stats` (pandas, scipy for McNemar/Wilcoxon), `viz` (matplotlib, seaborn for plots), `parquet` (pyarrow for Parquet input), `full` (everything), `dev` (pytest, ruff).

## Typical Workflow

1. Run inference with [[actuate-inference]] (`shadow-infer`) to produce detection CSV/Parquet.
2. Evaluate with `actuate-eval map --from-detections` against ground truth labels.
3. Compare models with `actuate-eval compare` for statistical significance.
4. Visualize with `actuate-eval plot-pr`.

The `--from-detections` path is recommended as it skips the intermediate YOLO TXT conversion step. The legacy two-step path (`convert` then `map`) is still supported for cases where YOLO TXT files are needed by other tools.

## Class Maps

Three built-in class maps are provided: `intruder`, `weapon`, and `postal`. Custom class maps can be supplied as YAML files mapping label names to integer class IDs.

## Format Contracts

The primary interchange format is the Detection CSV (produced by `actuate-inference`), with columns: `frame_path`, `label`, `confidence`, `bbox_x1/y1/x2/y2`, `image_width/height`, `endpoint_name`, plus optional fields like `alert_id`, `camera_identifier`, and `inference_time_ms`.
