---
title: "actuate-movement"
type: entity
topic: actuate-libraries
tags: [library, camera-stream, motion-detection, frame-differencing, computer-vision]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-movement

## Purpose

actuate-movement implements motion detection for camera streams in the Actuate platform. It determines whether meaningful movement has occurred between frames, enabling the pipeline to skip inference on static scenes and saving GPU resources. The library provides both CPU and GPU frame-differencing detectors, adaptive sensitivity, and a delta-noise utility for quantifying inter-frame change.

**Version:** 1.2.5

## Key Classes and Functions

### `core` module
- **`MotionDetector`** -- The main orchestrator class used by pullers. Wraps a `FrameDiffMotionDetector`, manages polygonal ignore zones, motion sensitivity thresholds, metrics upload, and timestamp-zone masking via an internal thread pool. Exposes `detect_motion(frame, timestamp)` which returns a motion boolean and a list of motion regions.
- **`MotionDetector.initialize_motion()`** -- First-frame bootstrap: processes the initial frame, seeds the background model, submits async timestamp-zone masking, then swaps itself out for `check_motion` on subsequent calls.
- Adaptive sensitivity: when feature deployments include slicing (non-gun), fire, smoke, or loiterer metrics, sensitivity is raised (`min_pct_area=0.0001`, `min_pixel_sensitivity=7`). An infrequent-frame mode bumps pixel sensitivity to 50 when frames arrive more than 20 seconds apart.

### `fdmd` module (Frame-Diff Motion Detector)
- **`FrameDiffMotionDetector`** -- CPU-based background-subtraction detector using OpenCV. Computes contours from frame deltas, converts them to Shapely polygons (with robust handling of self-intersecting and edge-touching contours via `make_valid` and frame-boundary clipping), applies NMS, and returns motion polygons.
- **`GPUFrameDiffMotionDetector`** -- CUDA-accelerated variant; selected automatically when `is_cuda_available()` returns `True`.
- Histogram equalization support for low-contrast or IR streams.

### `delta_noise` module
- **`get_delta_noise()`** -- Computes a scalar noise metric between two frames, useful for distinguishing real motion from sensor noise.

## Public API

Primary entry point: instantiate `MotionDetector` with a `CameraStreamConfig`, `CustomerConfig`, and `DaoManager`. Call `detect_motion(frame, timestamp)` each iteration. The `motion_boxes` property returns the current Shapely `MultiPolygon` of active motion regions.

## Dependencies

`opencv-python-headless`, `shapely`, `actuate-math` (for NMS), `numpy`.

## Consumers

- **actuate-pullers** -- `BasePuller` creates a `MotionDetector` per camera stream and uses it to gate frame submission to the inference queue.
- **vms-connector** -- Indirectly through pullers.

## Notable Patterns

- Contour-to-polygon conversion uses a multi-step fallback: direct construction, frame-boundary clipping, then `make_valid`, ensuring topology exceptions do not crash the pipeline.
- Timestamp zones are detected via an HTTP call to an internal OCR service and masked out of the background model to prevent clock digits from triggering false motion.
- The `detect_motion` method reference is swapped at runtime from `initialize_motion` to `check_motion` after the first frame, avoiding a per-frame branch check.
