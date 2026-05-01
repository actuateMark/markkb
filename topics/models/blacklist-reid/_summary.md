---
title: "Model: Blacklist Re-ID"
type: summary
topic: models/blacklist-reid
tags: [model, re-identification, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Blacklist Re-ID

## Overview

Blacklist re-identification (Re-ID) identifies specific known individuals by comparing person detection embeddings against a database of known embeddings stored in S3. This enables both blacklisting (alert on match) and whitelisting (suppress alerts for known individuals). The feature is implemented via the `BlacklistObserver` in [[actuate-libraries|actuate-connector-observers]] and the `BlacklistFilter` with R-tree spatial indexing in [[actuate-libraries|actuate-filters]].

## Architecture

Blacklist Re-ID is not a separate inference model but a post-detection filter that operates on the output of the intruder model (currently [[models/intruder-v5|intruder-384h-512w-svc]]). The system maintains groups of detection embeddings and matches incoming detections against them using bounding box overlap metrics.

### BlacklistFilter

The `BlacklistFilter` in `actuate-filters` manages detection groups and uses an **R-tree spatial index** (`RTreeManager`) for efficient candidate lookup. Key parameters from `StreamDeploymentConfig`:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `iou_threshold` | 0.85 | Minimum IOU overlap to match a detection to a group |
| `ios_threshold` | 0.0 | Minimum intersection-over-smaller for matching |
| `detection_percentage` | 0.6 | Hit percentage threshold to blacklist a detection |
| `queue_length` | 100 | Size of the hit history queue per group |
| `clean_up_threshold` | 0.15 | Groups below this hit rate are pruned |
| `max_blacklist_groups` | 200 | Maximum number of tracked groups (evicts weakest when exceeded) |

### R-tree Spatial Index

The `RTreeManager` wraps Python's `rtree` library to provide O(log n) spatial queries for candidate group lookup. When a new detection arrives, the R-tree's `intersection()` method finds all groups whose bounding boxes overlap, avoiding O(n) linear scans. Groups are indexed by their representative bounding box and updated when the box changes.

## BlacklistObserver

The `BlacklistObserver` in [[actuate-libraries|actuate-connector-observers]] orchestrates the blacklist process:

1. Receives unfiltered raw model responses from the pipeline
2. Applies confidence filtering per label against `raw_metrics` thresholds
3. Applies ignore zone filtering
4. Passes filtered detections to the `BlacklistFilter`
5. Returns blacklisted detections via callback

The observer runs periodic cleanup (every `clean_up_timer * 60` seconds, default 15 minutes) to prune stale groups and refresh data.

## Configuration

Blacklist Re-ID is enabled per feature deployment with `use_blacklist: true` in settings.json. When enabled, the [[vms-connector]] factory's `build_observers()` attaches a `BlacklistObserver` to the camera alongside any other observers (loiterer, line crossing). The observer receives pre-captured frames from the camera thread for embedding extraction.

## Pipeline Position

The `BlacklistStep` in the [[data-science/_summary|Data Science Methodology]] runs after IOU filtering and before the stationary filter in the post-processing chain. The `BlacklistObserver` also receives unfiltered model responses directly, operating in parallel with the main pipeline. Blacklist results are reported via callback to the alert system.

## Current Status

Blacklist Re-ID is **active in production** for cameras with `use_blacklist: true` configured. The R-tree spatial index and group eviction logic were added to handle high-density scenes without unbounded memory growth (capped at `max_blacklist_groups`, default 200, with eviction of the 100 weakest groups when exceeded).

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- [[detection-pipeline|detection pipeline]]
- [[models/intruder-v5]] -- the underlying person detection model
- [[models/loitering]] -- another observer-based product
