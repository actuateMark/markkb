---
title: "Filter Pipeline Ordering"
type: concept
topic: vms-connector
tags: [connector, pipeline, filters, ordering, cost-model, performance, stationary, IOU, blacklist]
created: 2026-04-15
updated: 2026-04-15
sources:
  - "[[worklog-tech-doc-video-pipeline]]"
  - "[[worklog-rearch-main-loop]]"
author: kb-bot
---

# Filter Pipeline Ordering

The post-processing filter chain in the [[pipeline-architecture]] is not arbitrary -- steps are ordered by ascending computational cost so that cheap filters eliminate detections before expensive ones run. This cost-aware ordering is critical because every camera thread runs the full filter chain on every inferenced frame, and the connector typically processes 1-3 frames/second across 24+ cameras per shard. The chain is assembled in `PipelineFactory.build_post_processing_subpipeline()` within [[actuate-pipeline]], reading bottom-to-top (last constructed = first executed).

## The Filter Chain (Production Order)

Reading the factory code from the return statement upward reveals the execution order:

```
1. StoreLowConfidenceStep      -- archive low-confidence detections for analysis
2. RawModelFilterStep           -- confidence + label filtering (cheapest)
3. TagZonesStep                 -- tag-zone intersection (if configured)
4. IgnoreMotionPolygonalZonesStep -- motion-aware polygon masking
5. IgnorePolygonalZonesStep     -- static polygon zone masking (per-label)
6. LogFilteredStep              -- log state after zone filtering
7. IouStep                      -- cross-frame IOU deduplication (expensive)
8. BlacklistStep                -- stateful blacklist matching (if enabled)
9. StationaryFilterStep         -- motion-geometry intersection (most expensive)
10. ExtractLabelsStep           -- extract confirmed labels for window logic
11. CheckConfirmationStep       -- threshold confirmation against config
12. SlidingWindowStep           -- temporal windowing and alert gating
13. SaveFrameMetaStep           -- persist frame metadata to DynamoDB/S3
14. CleanupStep                 -- mark frames for deletion
```

## Cost Model

### Tier 1: Near-Zero Cost (Steps 1-2)

**`RawModelFilterStep`** applies the `ConfidenceFilter` and `LabelFilter` from [[actuate-filters]]. These are simple list comprehensions -- `[d for d in detections if d.confidence >= threshold]` and a label whitelist check. O(n) in detection count with no external calls, no geometry, no state. This is why it runs first: it can eliminate 30-70% of raw YOLO detections (low-confidence noise, irrelevant labels) before any expensive processing begins.

**`StoreLowConfidenceStep`** runs before the filter (in pipeline order) but only archives detections below the confidence threshold to S3 via a thread pool. It does not modify the detection list and its I/O is fully async.

### Tier 2: Geometry -- Static Zones (Steps 3-6)

**`IgnorePolygonalZonesStep`** and **`IgnoreMotionPolygonalZonesStep`** use Shapely polygon intersection to remove detections falling within configured [[ignore-zones|ignore zones]]. The polygons are pre-computed at pipeline construction from [[actuate-config]] zone definitions, so the per-frame cost is just the `polygon.contains(point)` or `polygon.intersection(box)` check per detection. `TagZonesStep` is similar but tags detections with zone metadata rather than filtering them out. These steps use `PolygonZoneMixin` for shared geometry logic.

Cost: O(n * z) where n = detections and z = zones. Typically 0-5 zones per camera, making this cheap in practice.

### Tier 3: Cross-Frame IOU (Step 7)

**`IouStep`** compares each current-frame detection against previous frames' detections to identify objects that have appeared in the same location across multiple frames (indicating a real object rather than a transient artifact). The implementation in [[actuate-pipeline]]'s `IouStep` pre-builds per-label numpy arrays of previous bounding boxes and uses vectorised `iou_one_to_many()` from [[actuate-math]] for efficient batch computation.

Cost: O(n * p) where p = previous detections across the lookback window (5 frames for people, 15 frames for vehicles). Vehicle lookback is longer because vehicles move slowly and the IOU threshold (`resolve_iou_threshold()`) varies per label. The numpy vectorisation helps, but the lookback window can accumulate hundreds of previous detections on busy scenes.

### Tier 4: Blacklist Matching (Step 8)

**`BlacklistStep`** invokes the `BlacklistFilter` from [[actuate-filters]], which maintains stateful `BlacklistGroup` objects with an R-tree spatial index. Each detection is checked against candidate groups via IOU/IOS overlap, and groups maintain a rolling hit queue to track detection frequency. The R-tree query is O(log g) per detection (where g = groups), but the overhead comes from group lifecycle management: creating new groups for unmatched detections, evicting weak groups when the cap is reached (`_evict_weakest_groups`), and periodic cleanup via `update_data()`.

Cost: O(n * log g + maintenance). The `max_blacklist_groups` cap prevents unbounded growth, but on cameras with many distinct objects passing through, group churn can be significant. The `save_frame_results()` diagnostic logging is sampled at `save_result_probability` and offloaded to a single-worker executor to avoid blocking the pipeline.

### Tier 5: Stationary Filter (Step 9)

**`StationaryFilterStep`** is the most computationally expensive filter. It determines whether each detection overlaps with motion regions from [[motion-detection-internals|the FDMD motion detector]]. Detections that do not overlap with motion are considered stationary (parked vehicles, permanent fixtures) and are filtered out.

Two modes exist (selectable via config and environment variable):

- **Default (Shapely):** For each detection, constructs a `shapely.geometry.box`, then checks intersection area against each `prepared` motion geometry. `prep()` pre-computes spatial indices for the motion polygons, but the `intersection().area` call is still O(v) per motion vertex. With fragmented motion producing 10+ polygons, this can take 1-5ms per detection.
- **Cumulative mode:** Merges all motion regions into a single `unary_union` before checking overlap. This handles fragmented motion (multiple small regions that individually miss the threshold but collectively represent motion) at the cost of an additional union computation. A compare-and-log mode runs both paths for A/B evaluation.
- **Bbox mode (vectorised):** Uses numpy bbox-overlap computation (`_bbox_any_overlap()`) which releases the GIL, allowing other threads to run. Faster but less geometrically precise than Shapely polygon intersection.

The threshold varies: vehicles with high motion sensitivity require 30% overlap (`VEHICLE_HIGH_SENSITIVITY_AREA_RATIO`), everything else requires 10% (`DEFAULT_AREA_RATIO`). Fire and smoke detections bypass the filter entirely (`PASSTHROUGH_LABELS`).

## Line Crossing Bypass

When a feature deployment is `is_line_crossing_only`, the pipeline short-circuits after `RawModelFilterStep`, skipping the entire filter chain. Line crossing [[observer-pattern|observers]] receive the unfiltered `raw_model_response` and perform their own filtering internally via trajectory analysis. This avoids the stationary filter incorrectly suppressing objects that are "stationary" relative to the motion detector but actually crossing a line at low speed.

## Why This Order Matters

The ordering follows a strict cost-reduction principle: each tier eliminates detections that would otherwise flow into more expensive downstream tiers. In a worst-case frame with 50 raw YOLO detections:

1. RawModelFilter eliminates ~20 (low confidence, wrong labels) -- 30 remain
2. Polygon zones eliminate ~3 (in [[ignore-zones|ignore zones]]) -- 27 remain
3. IOU eliminates ~10 (duplicates from previous frames) -- 17 remain
4. Blacklist flags ~2 (known objects) -- 15 remain for stationary check
5. Stationary filter eliminates ~8 (no motion overlap) -- 7 confirmed detections

Running the stationary filter first on all 50 detections would require 50 * (Shapely intersection cost) instead of 15 * (Shapely intersection cost) -- a 3.3x reduction in the most expensive operation. At 3 FPS across 24 cameras, this ordering saves ~200ms of Shapely computation per second per shard.

## Extensibility

New filters slot into the chain by their cost profile. The recently added `VLMValidationStep` (post-cleanup, pre-metrics) runs a Vision Language Model validation call via [[actuate-vlm]] -- the most expensive per-detection operation in the system. It is placed after all other filters to minimise the number of detections sent to the VLM, and only activates when `vlm_enabled` is set on the customer config.
