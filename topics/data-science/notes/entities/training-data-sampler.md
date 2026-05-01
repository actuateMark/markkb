---
title: "training-data-sampler"
type: entity
topic: data-science
tags: [training-data, sampling, encord, labeling, postgres, s3, data-pipeline]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/data-science/_summary.md
  - topics/data-science/notes/concepts/training-pipeline-architecture.md
  - topics/data-science/notes/entities/actuate-data-registry-dvc.md
  - topics/data-science/notes/entities/spektar.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
incoming_updated: 2026-05-01
---

# training-data-sampler

A suite of Python tools for sampling production data and enqueuing it for labeling via the Encord platform. It provides a structured workflow for creating batches of frames (images) or windows (videos) from production databases, uploading them to S3, and creating labeled projects in Encord.

**Repo:** `aegissystems/training_data_sampler` (GitHub, private)
**Description:** Tools to sample production data and enqueue it for labeling
**Language:** Python
**Last updated:** 2025-07-28

## Core Concept: Batches

All functionality revolves around the `Batch` class, which encapsulates a set of production data to be sampled, uploaded, and labeled. A batch requires:

- **run_mode** -- `test` or `prod` (determines which database tables to use)
- **df** -- a DataFrame defining the batch contents, with required columns varying by batch type (`frame`: `s3_bucket`, `s3_key`, `image_id`; `window`: `window_id`)
- **target_bucket** -- S3 destination for media (recommended: `actuate-training-data-new`)
- **definition** -- the command used to generate the DataFrame (for reproducibility)
- **description** -- freeform text describing the batch purpose
- **batch_type** -- `frame` (images) or `window` (videos)

Optional parameters control Encord integration: `ontology_hash` (defaults to a 7-class+cover ontology), `workflow_template_hash` (defaults to a Selection and Labeling workflow), `min_label_conf`, and `label_classes`.

## Repository Structure

- `src/sample_data.py` -- core batch sampling logic
- `src/queries.py` / `query_tester.py` -- SQL queries for scraping specific production data
- `src/encord_integration.py` -- Encord platform integration for project creation and label upload
- `src/postgres_functions.py` -- database access layer
- `src/json_to_yolo_converter.py` -- converts JSON label data to YOLO-compatible format (Ultralytics)
- `notebooks/` -- example Jupyter notebooks demonstrating sampling workflows

## Data Flow

1. **Query** production data from Postgres using predefined or custom queries.
2. **Create a Batch** with the resulting DataFrame.
3. **Upload** media (images or videos) to the target S3 bucket.
4. **Create Encord project** with the batch metadata, which enqueues data for human labeling.

## Relationship to Other Services

- **[[actuate-data-registry-dvc]]** -- labeled data produced through this tool's Encord workflow feeds into the DVC data registry as `03_post_encord` batches.
- **Encord** -- external labeling platform where sampled data is sent for human annotation.
- **Production Postgres** -- source database from which frames and windows are sampled.
- **S3 (`actuate-training-data-new`)** -- staging bucket for sampled media before Encord ingestion.
