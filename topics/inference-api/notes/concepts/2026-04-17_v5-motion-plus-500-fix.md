---
title: "v5 Motion-Plus Frame Size Validation: Root Cause 500 Error"
type: concept
topic: inference-api
tags: [bug-fix, v5, motion-plus, error-handling, frame-processing]
jira: "ENG-126"
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# v5 Motion-Plus Frame Size Validation Bug Fix

## Symptom

`POST /v5/detect` with `model_id: "motion-plus"` returned `500 Internal Server Error` with generic JSON `{"code":500,"message":"Internal Server Error"}` instead of a client-actionable 4xx response. Reproduced locally against dev API when submitting a multipart request with frames of different dimensions.

## Root Cause

In `inference_api/api/contexts/inference_context.py::compute_frame_differences`, the motion-plus inference pipeline called `cv2.absdiff(decoded_frames[i], decoded_frames[i-1])` without verifying both frames shared the same shape `(H, W, C)`.

When any two consecutive frames had mismatched dimensions, [[opencv-entity|OpenCV]] raised:

```
OpenCV(4.11.0) arithm.cpp:662: error: (-209:Sizes of input arguments do not match)
```

This exception bubbled up through `infer_multi_model` in `v5.py` and was caught by the generic `except Exception` handler at line 318. It then passed to `_inference_exception_as_json_response` in `common.py`. The exception handler chain uses `isinstance()` checks ordered by specificity; anything not matching a typed exception branch falls through to the catch-all `if isinstance(e, Exception):` → `500 "Internal Server Error"`.

This is the wrong response code for a client-supplied input error.

## Fix (PR #56)

**Changes:**

1. **New exception type** (`inference_context.py`): Created `FrameSizeMismatchException` to signal client-provided shape misalignment.

2. **Validation before [[opencv-entity|OpenCV]] call** (`inference_context.py::compute_frame_differences`):
   - Before any `cv2.absdiff` call, validate all decoded frames match the first frame's shape.
   - Raise `FrameSizeMismatchException` with a message naming the offending frame's index and actual dimensions.

3. **Handler mapping** (`common.py::_inference_exception_as_json_response`):
   - Added branch: `if isinstance(e, FrameSizeMismatchException):` → return `400` with the exception's message.
   - Ensures the handler chain fails fast and loud on shape mismatch, not silently into a 500.

4. **Regression tests** (`test_v5.py`):
   - Test case: multipart motion-plus request with mismatched frame sizes → expects `400` with "size mismatch" message.
   - Test case: same request with matched frame sizes → expects `200` with valid response.

5. **Documentation** (`docs/api/v5/models/motion-plus.md`):
   - Added client constraint: "All frames must have identical dimensions (height, width, channels)."
   - Added response section: "400 Bad Request if frames differ in size."

## Pattern: Exception-to-HTTP Mapping

The `_inference_exception_as_json_response` handler is the authoritative translation layer from Python exceptions to HTTP status codes. **When adding a new code path that can raise a client-caused error:**

1. Define a **new typed exception** (not a generic `ValueError` or `RuntimeError`).
2. Add a matching `isinstance()` branch in `_inference_exception_as_json_response` with the appropriate 4xx status.
3. Place the branch **before** the catch-all `Exception` branch so it matches first.

Omitting the handler branch forces callers to infer intent from generic 500 errors and spikes alert noise.

## Why This Wasn't Caught in v4

v4's motion-plus endpoint (`/v4/motion-plus/detections`) uses the same `InferenceContext.compute_frame_differences` code path and has the same latent bug. It wasn't exposed in production because:

- v4 callers send frames as raw binary (in multipart requests) from a single camera.
- Single-camera streams are almost always same-resolution; no motivation to transcode or mix sources.

v5's request format (base64-encoded single frame + optional URL-downloadable alternate frames) gave partners more flexibility. Partners can now mix sources or test with heterogeneous data, exposing the shape validation gap.

## Cross-Links

- [[multi-model-inference]] — Describes the motion-plus asyncio pipeline
- [[inference-context-pattern]] — Frame caching mechanism and processing flow
- [[v5-implementation-patterns]] — v5 endpoint architecture and validation strategy
- [[inference-api/_summary|Inference API topic]]

## Impact

- Merged to `develop` 2026-04-17
- No breaking changes; only tightens validation and error reporting
- All existing valid requests (same-sized frames) unaffected
