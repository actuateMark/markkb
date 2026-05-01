---
title: "actuate-botsort"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, object-tracking, kalman-filter, botsort, multi-object-tracking]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/observer-pattern.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/vms-connector/_summary.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# actuate-botsort

BoT-SORT (Bag of Tricks for SORT) multi-object tracker that maintains persistent identity for detected objects across video frames. Uses Kalman filtering for motion prediction and IoU-based data association. Version **1.2.0**.

## Purpose

After the inference step produces per-frame detections, the tracker assigns consistent track IDs across frames. This is essential for observers that reason about object behavior over time (loitering, line crossing, intrusion duration). BoT-SORT improves on basic SORT with two-stage association (high-confidence and low-confidence), feature-based re-identification support, and robust lost-track management.

## Key Classes

- **`BoTSORT`** -- the main tracker. Initialized with `frame_rate`, `match_thresh`, and `second_match_thresh`. Call `update(output_results)` each frame with an Nx6 numpy array of `[x1, y1, x2, y2, score, class]` detections. Returns a list of active `STrack` objects with assigned `track_id` values.
- **`STrack`** -- represents a single tracked object. Maintains Kalman filter state (`mean`, `covariance`), feature history for re-identification, class histogram for label stability, and lifecycle state (New/Tracked/Lost/Removed). Supports `activate()`, `re_activate()`, `update()`, and `predict()`.
- **`BaseTrack`** -- base class with shared state management (`TrackState` enum, global ID counter, `mark_lost()`/`mark_removed()` lifecycle methods).
- **`KalmanFilter`** -- 8-state Kalman filter (center x, center y, width, height, and their velocities) for motion prediction. Supports batch `multi_predict()` for efficiency.

## Public API

```python
from actuate_botsort import BoTSORT
```

## Update Loop (per frame)

1. Separate detections into high-confidence and low-confidence sets.
2. Predict existing tracks forward using the Kalman filter.
3. First association: match high-confidence detections to predicted tracks via IoU.
4. Second association: match remaining tracks to low-confidence detections.
5. Handle unconfirmed tracks, initialize new tracks for unmatched detections.
6. Mark lost tracks as removed after `track_buffer` frames (default 30).
7. Deduplicate tracks with high IoU overlap.

## Dependencies

- **Internal**: `actuate-filterpy ~=1.0`
- **External**: `matplotlib >=3.9.2`, `scikit-image >=0.24.0`, `cython_bbox <=0.1.5`, `lap ~=0.5.12`

## Consumers

Used by `vms-connector` observer pipelines, particularly loiterer detection, line-crossing, and general intrusion monitoring that require stable object identities over time.

## Notable Patterns

- The `_removed_track_ids` set (integers only) provides a memory-efficient safety net preventing removed tracks from reappearing in the lost pool.
- `match_thresh` defaults to 0.95 (very permissive); line-crossing uses 1.0 for first association and 0.5 for second.
- Class histogram (`cls_hist`) stabilizes the label: even if a single frame misclassifies an object, the most-voted class wins.
- Global track ID counter (`BaseTrack._count`) is reset on tracker initialization via `clear_count()`.
