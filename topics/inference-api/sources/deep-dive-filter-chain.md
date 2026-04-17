---
type: source
topic: inference-api
author: kb-bot
ingested: 2026-04-15
---

# Deep Dive: Filter Chain in Inference API

The inference API has its own filter chain implementation, distinct from [[actuate-filters]] in actuate-libraries. Filters are composed by `make_filters()` in `endpoints/filter_builder.py` and applied sequentially in `common.py:_infer()` (single-model) or `common.py:infer_multi_model()` (multi-model).

## Filter Interface

All filters implement `BaseFilter` (`inference/filters/base_filter.py`):

```python
class BaseFilter:
    def filter(self, detected_objects: List[List[DetectedObject]], *args, **kwargs) -> List[List[DetectedObject]]
```

Input/output: `List[List[DetectedObject]]` -- outer list = frames, inner list = detections per frame.

## Filter Chain Composition (`make_filters()`)

The `filter_builder.py` module builds the chain used by both v4 and v5 endpoints. Order is fixed:

1. **LabelFilter** -- removes detections whose `label` is in the `ignore_labels` list. Always applied.
2. **LabelwiseConfidenceFilter** -- per-label confidence thresholds with a default fallback. Driven by [[sensitivity-to-confidence-mapping]]. Always applied.
3. **FdmdStationaryFilter** -- Frame Diff Motion Detection. Identifies motion regions using `cv2.absdiff` between consecutive frames and removes/tags detections in stationary regions. Only active when `stationary_filter` is `"true"` or `"tag"`. Supports `excluded_labels` (labels that bypass filtering, e.g., fire). Tags with `"stationary_detection"`.
4. **IoUFilter** -- Intersection over Union across adjacent frames. Detections overlapping (IoU >= 0.8) across frames are considered stationary and removed or tagged `"stationary_object"`. Only active when stationary filtering is enabled. Default threshold 0.8; weapons effectively disabled at 1.0.

When `stationary_filter == "false"`, filters 3 and 4 are `None` and skipped during iteration.

## Application Points

**Single-model path** (`_infer()`): Filters applied inside the inference loop after `inference_client.infer_frames()` returns predictions. Each filter transforms the prediction list in sequence.

**Multi-model path** (`infer_multi_model()`): Filters are NOT applied per-model. Instead, all models run concurrently with `filters=[]`, their predictions are combined frame-wise (`combined[i].extend(model_results[i])`), and then the shared filter chain runs on the combined output. This is architecturally important -- it means cross-model detections interact during IoU filtering.

## Key Difference from actuate-filters

The inference API filters operate on `DetectedObject` (Pydantic model with `center_x`, `center_y`, `width`, `height`, `list[str]` tags). The [[actuate-filters]] library in actuate-libraries uses `Detection` objects with `BoundingBox` and `set[DetectionTag]`. ADR-002 proposes consolidating via an adapter layer but this is not yet implemented.

## Deprecated Filters

- `MotionFilter` -- older frame-difference algorithm, replaced by FDMD.
- `StationaryVehicleFilter` -- vehicle-specific stationary filter, replaced by `FdmdStationaryFilter` with `excluded_labels`.

## Custom FDMD Implementation

The `filters/algos/motion/fdmd/` directory contains a custom Frame Diff Motion Detection algorithm used by `FdmdStationaryFilter` and `FdmdMotionFilter`. This generates motion boxes from frame differences using the `FrameDiffMotionDetector`.

## v5 Reuse

The v5 endpoint calls the exact same `make_filters()` function, extracting `stationary_filter`, `ignore_labels`, and `stationary_filter_excluded_labels` from the validated `data` payload. The filter chain is identical for equivalent parameters.
