---
type: concept
topic: inference-api
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
incoming:
  - topics/inference-api/_summary.md
  - topics/inference-api/notes/concepts/2026-04-17_v5-motion-plus-500-fix.md
  - topics/inference-api/notes/concepts/multi-model-inference.md
  - topics/inference-api/notes/concepts/sensitivity-to-confidence-mapping.md
  - topics/inference-api/sources/deep-dive-v4-endpoints.md
incoming_updated: 2026-05-01
---

# InferenceContext Pattern

`InferenceContext` (`api/contexts/inference_context.py`) is a lazy-caching context object that avoids duplicate frame processing when multiple models need different views of the same input frames. Paired with [[multi-model-inference]] via `ModelContext`, it forms the core data-sharing pattern for v4 multi-model endpoints and all v5 inference.

## Problem It Solves

In endpoints like `/v4/motionplus/vs/detections`, the same set of frames must be:
1. Downloaded (if URLs) -- expensive I/O
2. Processed into frame differences (for motion-plus) -- expensive CPU
3. Kept as originals (for pet model or intruder-plus-with-vehicle)

Without caching, each model call would re-download and re-process frames.

## Implementation

`InferenceContext` stores:
- `original_frames: List[bytes]` -- raw input (may be URLs or bytes)
- `sensitivity: Union[str, float]`
- `confidence_function: Callable` -- model-specific threshold function (default: `get_confidence_thresholds`)
- `_processed_frames: Optional[List[bytes]]` -- cached downloaded/validated frames
- `_frame_differences: Optional[List[bytes]]` -- cached `cv2.absdiff` between consecutive frames
- `_confidence_data: Optional[Tuple]` -- cached `(default_confidence, label_confidences)`

All getters are lazy with `if self._field is None: compute()` guards.

## Key Methods

- **`get_processed_frames()`** -- async, downloads URLs if needed, caches result
- **`get_frame_differences()`** -- async, calls `get_processed_frames()` then `compute_frame_differences()`. Uses [[opencv-entity|OpenCV]] `cv2.absdiff` between consecutive frames, re-encodes as JPEG bytes.
- **`get_frames_for_model(frame_type)`** -- dispatcher: `"frame_differences"` returns diffs, anything else returns processed originals
- **`get_confidence_data()`** -- sync, calls the configured confidence function with sensitivity

## Frame Differences Algorithm

`compute_frame_differences()` decodes all frames via `cv2.imdecode`, computes `cv2.absdiff(frame[i], frame[i-1])` for consecutive pairs, then re-encodes as JPEG. For N input frames, produces N-1 difference frames.

## ModelContext Companion

`ModelContext` (`api/contexts/model_context.py`) is a simple config object per model:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `client` | `BaseInferenceClient` | required | Which model server to call |
| `confidence` | `float` | required | Confidence threshold |
| `return_empty` | `bool` | `True` | Return `[]` on no detections |
| `prepend_empty_frame` | `bool` | `False` | Pad frame list for motion models |
| `max_slices` | `int \| None` | `None` | SAHI slice count |
| `frame_type` | `str` | `"original"` | `"original"` or `"frame_differences"` |

## Usage in v5

The v5 `POST /v5/detect` endpoint creates an `InferenceContext` for motion-plus models (`frame_type == "frame_differences"`) and uses the standard `_infer()` path for all others. The [[v5-api-design]] static registry stores `frame_type` and `prepend_empty_frame` per model.
