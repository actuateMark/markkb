---
title: "actuate-sort"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, object-tracking, kalman-filter, sort, multi-object-tracking]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# actuate-sort

SORT (Simple Online and Realtime Tracker) implementation for tracking bounding boxes over time using Kalman filtering and IoU-based assignment. A simpler, lighter alternative to BoT-SORT. Version **1.0.2**.

## Purpose

Provides basic multi-object tracking by associating detections across consecutive frames. Each tracked object gets a `KalmanBoxTracker` that predicts its next position using a constant-velocity Kalman filter. The Hungarian algorithm (via `lap` or `scipy`) matches predictions to new detections by IoU. Objects that go unmatched for `max_age` frames are removed.

## Key Classes and Functions

- **`Sort`** -- the main tracker class. Initialized with `max_age` (frames before track deletion, default 1), `min_hits` (minimum detections before a track is reported, default 3), and `iou_threshold` (minimum IoU for association, default 0.3). Call `update(dets)` each frame with an Nx6 numpy array of `[x1, y1, x2, y2, score, original_id]`.
- **`KalmanBoxTracker`** -- per-object tracker wrapping a 7-state Kalman filter from `actuate-filterpy`. State vector is `[x, y, s, r, dx, dy, ds]` (center position, scale/area, aspect ratio, and their velocities). Provides `predict()`, `update(bbox)`, and `get_state()`.
- **`associate_detections_to_trackers()`** -- computes the IoU matrix between detections and predictions, runs linear assignment, and returns matched pairs, unmatched detections, and unmatched trackers.
- **`iou_batch()`** -- vectorized IoU computation using numpy broadcasting.
- **`linear_assignment()`** -- wraps `lap.lapjv` with fallback to `scipy.optimize.linear_sum_assignment`.

## Public API

```python
from actuate_sort import Sort
```

The `update()` method returns an Nx6 array where columns are `[x1, y1, x2, y2, track_id, original_id]`. The `original_id` column preserves the detection's original identifier through tracking, which is useful for correlating tracked objects back to their source detections.

## Dependencies

- **Internal**: `actuate-filterpy ~=1.0` (KalmanFilter for state estimation)
- **External**: `matplotlib >=3.9.2`, `scikit-image >=0.24.0`

## Consumers

Used in simpler tracking scenarios within `vms-connector` where the full BoT-SORT feature set (two-stage association, re-identification features, class histograms) is not needed. Also useful for benchmarking and as a baseline tracker.

## Notable Patterns

- Modified from the original Alex Bewley SORT implementation to pass a 6th column (`original_id`) through the tracker, enabling correlation between detections and tracked outputs.
- Uses `lap.lapjv` for O(n^3) linear assignment with fallback to `scipy` if `lap` is not installed.
- The constant-velocity Kalman filter models position in scale-ratio space `(x, y, s, r)` rather than pixel space, which is more robust to changes in object distance.
- Track IDs are globally incremented via `KalmanBoxTracker.count` class variable (not reset between tracker instances unless done explicitly).
