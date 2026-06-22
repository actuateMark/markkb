---
title: "ds-analysis-microservice"
type: entity
topic: data-science
tags: [experimentation, connector, analysis, kubernetes, fastapi, streamlit]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
incoming_updated: 2026-05-27
---

# ds-analysis-microservice

Connector component analysis and experimentation service. Enables granular testing of individual pipeline components in isolation, supporting single-variable experiments against production baselines.

## Purpose

The Actuate connector pipeline has multiple tunable components (puller, FDMD, filters, slicing, loiterer), each with parameters that affect detection quality and system performance. This microservice provides a structured way to run controlled experiments on any single component, compare results against production baselines, and make data-driven tuning decisions.

## Testable Components

- **Puller** -- [[ffmpeg-entity|FFmpeg]] parameters, stream stability, resource usage.
- **FDMD** (Frame Difference Motion Detection) -- `min_area`, `pixel_sensitivity`, code variants.
- **Filters** -- IOU filter, Blacklist filter, Stationary filter (`stationary` vs `stationary_cumulative` behavior).
- **Slicing** -- `num_slices` comparison for high-resolution image tiling.
- **Loiterer** -- `frame_thresh`, BoTSORT tracker parameters, FPS impact.

## Features

- **Production sampling** -- SQS-controlled recording from live cameras to capture real-world test data.
- **Camera selection by view type** -- Filter cameras by indoor/outdoor, site type, and installed components.
- **Single variable testing** -- Defaults to changing one parameter at a time; multi-variable experiments require explicit opt-in (`allow_multiple_changes: true`).
- **Experiment execution** -- Runs experiments as Kubernetes Jobs with GitHub code integration.
- **Filter state recording** -- Full state capture for playback and debugging.

## Tech Stack

Python with FastAPI (`uvicorn`), managed by `uv`. Includes a Streamlit dashboard (`dashboard/app.py`) for creating/monitoring experiments, comparing stationary filter behavior, managing samples, and viewing baselines.

## API

RESTful API with endpoints for: health/readiness probes (`/healthz`, `/readyz`), experiment CRUD and execution (`/experiments`, `/experiments/{id}/run`), sample management (`/samples/upload`, `/samples`), and production sampling control (`/sampling/start`, `/sampling/stop`).

## Deployment

Deployed to EKS via [[argocd|ArgoCD]]. Helm chart lives in the [[kubernetes-deployments]] repo. Internal URL: `https://ds-analysis.internal.actuateui.net/`. Requires IAM permissions for S3 (analysis bucket) and ECR. Enabled per-cluster via `cluster-values.yaml` under `actuate.applications.dsAnalysisMicroservice`.

## Development

Run locally with `uv run uvicorn src.main:app --reload --port 8080`. Lint with `ruff`, test with `pytest`. Docker build available for containerized local testing.
