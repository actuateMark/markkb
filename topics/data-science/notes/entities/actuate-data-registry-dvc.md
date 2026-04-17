---
title: "actuate-data-registry-dvc"
type: entity
topic: data-science
tags: [dvc, data-registry, s3, datasets, computer-vision, ml-pipeline, versioning]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-data-registry-dvc

The central data hub for all Actuate computer vision datasets. This Git repository uses DVC (Data Version Control) backed by Amazon S3 to provide versioned, deduplicated, and traceable storage for the entire multi-stage ML data pipeline -- from raw production data through curation to final labeled training sets.

**Repo:** `aegissystems/actuate-data-registry-dvc` (GitHub, private)
**Last updated:** 2026-04-10

## Core Architecture ("Coordinator Model")

The system separates compute from storage across three pillars:

1. **Compute repositories** (e.g., `ai-kb-scripts`) -- where engineers write Python curation scripts, active learning loops, and data tools.
2. **This registry** -- a pure catalog storing lightweight `.dvc` pointer files and `meta.yaml` metadata in Git. No heavy data lives here.
3. **S3 backend** -- the actual pixel storage, using DVC's content-addressable storage (MD5 hashing). An image used across multiple models or pipeline stages is stored only once.

## Standard Folder Structure

Data is organized by model name with a strict convention:

- `{model_name}/base_training_sets/` -- "golden" production datasets (e.g., `v1.0_prod/`) containing raw images and `.txt` labels (no zips). Each version has a `.dvc` pointer and a `meta.yaml`.
- `{model_name}/incremental_batches/{date}_batch/` -- new data passing through the curation pipeline in three stages: `01_raw/` (uncurated from data lake), `02_pre_encord/` (curated subset ready for labeling), `03_post_encord/` (human-verified labels from Encord).

## Data Curation Workflow

1. **Raw ingestion** -- download production data into `01_raw/`, immediately `dvc add` and commit to freeze the starting point.
2. **Curation** -- run active learning or framing scripts reading from `01_raw/`, output to `02_pre_encord/`, version with DVC.
3. **Metadata linking** -- every curated folder must contain a `meta.yaml` recording the source code repo, commit hash, script path, curator name, and creation date.
4. **Push** -- `dvc push` sends pixels to S3, `git push` sends pointers to GitHub.

## Team Onboarding

New engineers clone the repo and run `dvc pull` to download the exact dataset matching the current Git state. "Time travel" is supported by checking out any prior Git commit and running `dvc pull` to restore that version's data.

## Prerequisites

- DVC installed system-wide (`pipx install dvc[s3]` or `snap install dvc --classic`)
- AWS CLI configured with read/write access to the S3 bucket

## Related Services

- **Encord** -- external labeling platform used in the `02_pre_encord` to `03_post_encord` stage
- **ai-kb-scripts** -- primary compute repo containing curation pipelines
- **[[training-data-sampler]]** -- samples production data for labeling batches upstream of this registry
