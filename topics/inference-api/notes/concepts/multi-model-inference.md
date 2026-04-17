---
type: concept
topic: inference-api
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
---

# Multi-Model Inference

The inference API supports running multiple ML models concurrently on the same frame set and merging their results before filtering. This is implemented in `common.py:infer_multi_model()` and used by v4 legacy endpoints and v5's motion-plus path.

## Architecture

The multi-model system has three components:
1. **[[inference-context-pattern]]** -- `InferenceContext` caches shared frame data
2. **`ModelContext`** -- per-model configuration (client, confidence, frame type)
3. **`infer_multi_model()`** -- orchestrator that runs models concurrently and merges results

## Execution Flow

```
1. Create InferenceContext(frames, sensitivity)
2. Create [ModelContext(client_a, ...), ModelContext(client_b, ...)]
3. For each ModelContext:
   a. Get appropriate frames via context.get_frames_for_model(frame_type)
   b. Create asyncio task calling _infer(frames, client, filters=[], ...)
4. await asyncio.gather(*tasks)  -- all models run concurrently
5. Merge results frame-wise: combined[i].extend(model_results[i])
6. Apply shared filter chain to combined results
7. Return formatted JSONResponse
```

## Critical Design: Filters After Merge

Filters are NOT applied per-model. Each `_infer()` call runs with `filters=[]`. The shared [[deep-dive-filter-chain]] only runs after all model predictions are combined. This means:
- IoU filtering can detect duplicates across models (e.g., both intruder and pet models detect the same bounding box)
- Stationary filtering considers all detections together
- Label filtering removes labels regardless of which model produced them

## Frame-Wise Merge

Results are combined by extending per-frame detection lists:

```python
combined[0] = model_a_frame_0 + model_b_frame_0
combined[1] = model_a_frame_1 + model_b_frame_1
...
```

This preserves frame alignment, which is essential for IoU and stationary filtering.

## v4 Usage: Legacy Endpoints

**`/v4/intruderpluswithvehicle/vs/detections`** runs:
- `sliced_intruder_plus_with_vehicle` (main model, `max_slices=1`)
- `pet` (if `include_pets=True`, uses `frame_type="original"`)

**`/v4/motionplus/vs/detections`** is the most complex. Multi-frame path runs two `infer_multi_model` calls concurrently via `asyncio.gather()`:
1. First-frame context: `sliced_intruder_plus_with_vehicle` on frame[0] only
2. Full context: `motion_plus` (frame_differences) + optionally `pet` (original frames)

Results from call 1 are injected into frame 0 of call 2's output via `new_content[0].extend(first_frame_content[0])`.

## v5 Usage

The v5 `POST /v5/detect` endpoint uses `infer_multi_model()` only for the motion-plus model (which requires `InferenceContext` for frame differences). All other models take the simpler `_infer()` path directly. The v5 [[v5-api-design]] currently supports one model per request, but the architecture trivially extends to multi-model by adding more `ModelContext` entries.

## Concurrency Model

Each model inference itself is already concurrent: `BaseInferenceClient._query_all_frames()` sends all frames to the model server in parallel via `asyncio.gather()`. Multi-model adds a second layer of concurrency: multiple model servers are queried simultaneously. The total concurrency is `num_models * num_frames` HTTP requests.

## Connection to [[inference-context-pattern]]

`InferenceContext.get_frames_for_model()` is the dispatch point: `"original"` returns processed frames, `"frame_differences"` returns computed diffs. Both are cached, so the second model requesting the same frame type pays zero recomputation cost.
