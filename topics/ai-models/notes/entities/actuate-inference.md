---
title: "actuate-inference"
type: entity
topic: ai-models
tags: [inference, client, cli, batch, parquet, duckdb, shadow-testing, python]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/ai-models/notes/entities/ds-server-container.md
  - topics/data-science/notes/concepts/evaluation-tiers.md
  - topics/data-science/notes/entities/actuate-eval.md
  - topics/data-science/notes/entities/shadow-test-pipeline.md
incoming_updated: 2026-05-01
---

# actuate-inference

Standalone Python inference client for Actuate model endpoints. Provides batch and single-image processing with detection record output in CSV or Parquet format. Serves as the primary tool for running inference against both K8s internal endpoints (via kubefwd) and public API endpoints, producing data consumed by [[actuate-eval]] for evaluation.

## CLI Tools

- **`shadow-infer`** -- Batch inference on flat image folders. Sends every image to one or more endpoints, writes detections to CSV/Parquet. Supports parallel workers (4-8 recommended), multiple endpoints per run, slicing proxy endpoints, and configurable confidence thresholds.
- **`shadow-extract`** -- Shadow testing extraction from hierarchical alert data (`data-dev-misses/`, `data-prod-misses/`). Sends each frame to both dev and prod endpoints, writes combined output. Supports checkpointing for long runs and resume after interruption.
- **`shadow-eval`** -- Model evaluation on labeled alert datasets. Filters by TP/FP labels from a `labels.csv`, runs inference against selected endpoints. Supports both local frames and S3 sources. Designed for McNemar sensitivity tests.
- **`actuate-inference`** -- Interactive single-image and directory processing with visualization, annotation saving, and a resume-capable checkpoint system. Best for exploratory work and debugging.

## Output Formats

Supports CSV (default, backward compatible, best for small runs) and Parquet (recommended for large runs -- 8-15x compression, column pruning, predicate pushdown via DuckDB/PyArrow/Polars). Both formats follow the Detection CSV schema that [[actuate-eval]] consumes.

## DuckDB Analytics

With the `analytics` extra installed, provides embedded analytical queries on Parquet datasets: class distribution, confidence sweeps, confidence histograms, endpoint comparison, detection density, and raw SQL via `analytics_query()`.

## Supported Endpoints

- **K8s internal** (via kubefwd) -- `k8s-model`, `k8s-intruder`, `k8s-weapon`, `k8s-thermal`, plus named model services like `int07-actuate003-v8` and `intruder-384h-512w-svc`.
- **Slicing proxy** -- Routes through `slicing-svc` which tiles high-res images and dispatches to the underlying model. Any model can be wrapped: `slicing/{model-name}`.
- **Public API** -- `intruder-dev`, `intruder-prod`, `intruderplus-prod`, `weapon-prod` via `dev-api.actuateui.net` / `api.actuateui.net`.

## Important Operational Note

kubefwd port-forwards to a single pod and cannot load balance. Heavy batch inference causes runaway HPA scaling (observed up to 200 pods). For any significant batch run, use the shared DS EC2 instance in the VPC with ingress endpoints instead.

## Relationship to Other Repos

This is a **client** tool, not the production inference server. Production serving is handled by [[ds-server-container]] (Rust, Inferentia2). This repo's outputs feed into [[actuate-eval]] for mAP evaluation and [[shadow-test-pipeline]] for shadow testing workflows. The labeling tools in [[shadow-test-pipeline]] produce `labels.csv` files consumed by `shadow-eval` here.

## Installation

Uses `uv` or pip. Optional extras: `analytics` (pyarrow, duckdb), `gui` ([[opencv-entity|opencv]]), `dev` (pytest, ruff, mypy).
