---
title: "shadow-test-pipeline"
type: entity
topic: data-science
tags: [shadow-testing, model-comparison, athena, streamlit, prod-vs-dev, alerts, labeling]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# shadow-test-pipeline

Modular shadow-testing infrastructure for comparing production vs development object-detection models. Orchestrates data collection from AWS Athena, alert matching between dev and prod endpoints, frame downloading, manual labeling, and visualization through a Streamlit UI.

## Core Workflow

1. **Data collection** -- Queries AWS Athena for alert data within a configurable date range and camera set (specified via CSV). Alerts are fetched in bulk with AWS session reuse for performance (~99% reduction in auth overhead vs per-query sessions).
2. **Prod/dev classification** -- Automatically classifies alerts as `prod` or `dev` based on model identifier substrings found in `custcam_id` (case-insensitive). Dev identifiers are configurable via `SHADOW_DEV_MODEL_IDENTIFIERS`.
3. **Alert matching** -- Pairs dev and prod alerts using a sliding-window + greedy algorithm with configurable time delta (`SHADOW_MAX_DELTA`, default 25s) and IoU overlap threshold (`SHADOW_OVERLAP_THRESHOLD`, default 0.3). Identifies alerts that are only in prod, only in dev, or matched between both.
4. **Frame download** -- Downloads individual frame images and raw detection labels from Athena's `frame_repository` via `scripts/download_frames.py`. Features partition pruning, resumable downloads, disk space checks, and Athena query timeout protection.
5. **Labeling** -- Manual TP/FP labeling via OpenCV-based tools (`shadow_label_local.py`, `shadow_label_s3.py`) or a Streamlit labeling interface. Also integrates with Encord for external labeling workflows.
6. **Visualization** -- Streamlit dashboard for monitoring pipeline runs and viewing results.

## Project Structure

The main orchestrator is `src/pipeline_runner.py`, with core logic in `src/core.py` (Athena fetch, camera processing, matching dispatch). Key submodules: `config/` (schema validation, camera blocklist), `classification/` (site type classification), `data/` (loader, frame fetcher, preprocessor, validator), `analysis/` (matching, timing, labeling, [[new-relic|New Relic]] log analysis), and `visualization/` (plots).

A separate `uk_eu_pipeline/` directory contains a numbered script pipeline (scripts `00` through `12`) for UK/EU camera evaluation, including its own labeling tools.

## Configuration

Controlled via `.env` file with required variables for date range, camera CSV, AWS secrets, S3 bucket, and Encord SSH key. Optional variables control artifacts path, matching thresholds, log level/format, and dev model identifiers.

## Security

Implements SQL injection prevention (strict regex validation), [[secrets-management|secrets management]] via environment variables, and no hardcoded credentials.

## Relationship to Other Repos

Works closely with [[actuate-inference]] (runs inference on downloaded frames) and [[actuate-eval]] (evaluates detection quality). The shadow-label tools in this repo produce `labels.csv` files consumed by `shadow-eval` in the [[actuate-inference]] repo.
