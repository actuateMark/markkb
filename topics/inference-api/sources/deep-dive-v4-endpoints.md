---
type: source
topic: inference-api
author: kb-bot
ingested: 2026-04-15
---

# Deep Dive: v4 Endpoint Signatures

The v4 router (`inference_api/api/endpoints/v4.py`) defines 9 POST endpoints plus Swagger docs endpoints. All endpoints share a common parameter pattern and return `List[List[DetectedObject]]` (one inner list per frame). v4 is the most feature-rich stable version, serving as the blueprint for [[v5-api-design]].

## Common Parameters (All Endpoints)

| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `frames` | `List[bytes]` | required | JPEG uploads or downloadable URLs (mixed), via `get_frames_from_request` dependency |
| `ignore_labels` | `List[str]` | `[]` | Endpoint-specific allowed values |
| `stationary_filter` | `str` | `"false"` | `"true"` / `"tag"` / `"false"` -- controls [[deep-dive-filter-chain]] FDMD + IoU filters |
| `sensitivity` | `str \| float` | `"medium"` | `"low"` / `"medium"` / `"high"` or float (0,1). See [[sensitivity-to-confidence-mapping]] |
| `id` | `str \| None` | `None` | Echoed in `X-Request-Id` response header |

## Standard Detection Endpoints

1. **POST /v4/intruder/detections** -- Role: `intruder` / `full_access`. Labels: person, bicycle, car, motorcycle, bus, truck.
2. **POST /v4/weapon/detections** -- Role: `weapon` / `full_access`. Labels: pistol, gun.
3. **POST /v4/pet/detections** -- Role: `pet` / `full_access`. Labels: pet classes (cat, dog).
4. **POST /v4/intruderplus/detections** -- Role: `intruder_plus` / `full_access`. Labels: person.
5. **POST /v4/intruderpluswithvehicle/detections** -- Role: `intruder_plus_with_vehicle` / `full_access`. Labels: person, bicycle, car, motorcycle, bus, truck, machinery. Uses [[inference-context-pattern]] with `InferenceContext` + `ModelContext`.
6. **POST /v4/motionplus/detections** -- Role: `motion_plus` / `full_access`. Requires **2+ frames**. Uses `frame_differences` frame type and custom confidence thresholds (low=0.4, med=0.2, high=0.1).

## Sliced Inference

7. **POST /v4/intruderpluswithvehicle/slice/detections** -- Role: `sliced_intruder_plus_with_vehicle` / `full_access`. Adds `max_slices` (1-9, default 1) and `stationary_filter_excluded_labels`. Uses [[multi-model-inference]] SAHI backend.

## Legacy Format Endpoints

8. **POST /v4/intruderpluswithvehicle/vs/detections** -- Returns `LegacyResponse` format. Required `id` parameter. Optional `include_pets` (default `true`). Runs sliced-intruder-plus-with-vehicle + optionally pet model concurrently via [[multi-model-inference]].
9. **POST /v4/motionplus/vs/detections** -- Legacy format. Complex dual-path: single-frame runs intruder-plus-with-vehicle; multi-frame runs motion-plus + first-frame intruder detection concurrently via `asyncio.gather()`. Also supports `include_pets`.

## Response Shapes

- **Standard:** `200 OK` with `List[List[DetectedObject]]` -- each inner list = detections for one frame. `DetectedObject` has `label`, `confidence`, `center_x`, `center_y`, `width`, `height`, optional `tags`.
- **Legacy:** `200 OK` with `LegacyResponse` wrapping detections per filename with request `id`.
- **Errors:** `400` (`Error`), `403` (no body), `500` (`Error`).

## Key Architecture Notes

Endpoints 1-4 and 6 use the simple `infer()` path. Endpoints 5, 7-9 use `InferenceContext` / `ModelContext` / `infer_multi_model()` for caching and concurrent model execution. All endpoints call `make_filters()` from [[deep-dive-filter-chain]] to build the filter chain. Security is via `check_api_key` (dummy for OpenAPI) + `check_*_roles` (real [[deep-dive-rust-authorizer]] RBAC).
