---
title: "Motion Detection Internals"
type: concept
topic: vms-connector
tags: [connector, motion-detection, FDMD, GPU, CUDA, Shapely, contours, performance]
created: 2026-04-15
updated: 2026-04-15
sources:
  - "[[worklog-optimization-research]]"
  - "[[worklog-tech-doc-video-pipeline]]"
author: kb-bot
---

# Motion Detection Internals

Motion detection is the first filter in the connector's processing path -- it runs at full inbound FPS (15-30) in the puller thread, before any frame reaches the [[pipeline-architecture|inference pipeline]]. When the scene is static, motion detection saves the entire cost of YOLO inference for that frame. Across ~32K cameras, this gate is responsible for the largest single resource saving in the platform. The implementation lives in [[actuate-movement]], orchestrated by `MotionDetector` in `core/base_motion_detector.py`.

## FDMD Algorithm (Frame-Diff Motion Detector)

`FrameDiffMotionDetector` in `actuate_movement.fdmd` implements background-subtraction motion detection through a multi-stage pipeline:

### 1. Preprocessing

Each incoming frame is resized to `frame_width` (default: original width, configurable for speed), optionally histogram-equalised (for low-contrast or IR streams), converted to grayscale via `cv2.cvtColor(BGR2GRAY)`, and Gaussian-blurred with a configurable kernel to suppress sensor noise. If histogram matching is enabled, the grayscale frame is further normalised against the background frame to compensate for gradual illumination changes.

### 2. Frame Differencing

The absolute difference between the current preprocessed frame and the stored background frame is computed via `cv2.absdiff()`. This delta image highlights pixels that have changed intensity beyond noise levels.

### 3. Thresholding and Morphology

The delta image is thresholded with configurable `pixel_sensitivity` bounds (default `[15, 255]` for normal mode, `[7, 255]` for high-sensitivity features like fire/smoke/loitering). Morphological dilation (3 iterations with a 3x3 rect kernel) fills gaps in detected regions, then erosion (2 iterations) removes small noise blobs. These cached structuring elements avoid per-frame allocation.

### 4. Contour Extraction and Area Filtering

`cv2.findContours(RETR_EXTERNAL, CHAIN_APPROX_SIMPLE)` extracts outer contour boundaries. Contour areas are computed via vectorised `cv2.contourArea()` calls, then filtered against `min_area` and `max_area` bounds (derived from `pct_area` configuration, default 0.05%-50% of frame area). A hard cap of 1000 contours prevents processing explosion on high-noise frames.

### 5. Shapely Polygon Construction

Valid contours are converted to Shapely `Polygon` objects for downstream use by the [[filter-architecture|StationaryFilterStep]]. This conversion handles several topology edge cases:

- **Self-intersecting contours:** Morphological operations can produce contours that cross themselves. `_contour_to_valid_polygon()` first attempts direct construction, then clips to frame bounds (closing edge-touching contours using the frame edge), then falls back to `make_valid()`.
- **GeometryCollection results:** `make_valid()` can return mixed geometry types. `_extract_polygons()` filters to only `Polygon` and `MultiPolygon` with sufficient area (>= 1.0 px^2).
- **Degenerate contours:** Contours with fewer than 3 points or zero area are silently discarded.

The resulting `MultiPolygon` is stored on `MotionDetector.motion_boxes` and propagated to `ImageDataPacket.motion_boxes` for the stationary filter to consume.

### 6. Cumulative Blob Merging

When NMS is enabled (`with_nms=True`), overlapping motion bounding boxes are merged via `non_max_suppression()` from [[actuate-math]]. This reduces fragmented motion regions (e.g., a walking person producing separate upper-body and lower-body blobs) into unified regions, improving the accuracy of the downstream stationary filter's overlap calculation.

### 7. Background Update

The background frame is updated when motion is detected and at least 1 second has elapsed since the last update, or unconditionally after 10 seconds of no motion. This adaptive update rate prevents the background from becoming stale during long static periods while avoiding rapid updates during active motion that would "learn" moving objects into the background.

## Adaptive Sensitivity

`MotionDetector` adjusts sensitivity based on two factors:

- **Feature-driven:** If any feature deployment uses slicing (non-gun), fire, smoke, or loiterer metrics, sensitivity is raised (`min_pct_area=0.0001`, `min_pixel_sensitivity=7`). This is flagged as `is_high_motion_sensitivity` and propagated to the `StationaryFilterStep` for threshold adjustment.
- **Infrequent frames:** When frames arrive more than 20 seconds apart (common with SMTP cameras or idle streams), pixel sensitivity is bumped to 50 to prevent large ambient scene changes (illumination shifts, doors opening) from merging with real object contours via dilation.

## GPU CUDA Variant

`GPUFrameDiffMotionDetector` extends the CPU implementation with OpenCV CUDA operations. When `cv2.cuda.getCudaEnabledDeviceCount() > 0`, it uses GPU-accelerated paths for:

- **Grayscale conversion:** `cv2.cuda.cvtColor()` on a `GpuMat`.
- **Gaussian blur:** Pre-created `cv2.cuda.createGaussianFilter()` applied via CUDA stream.
- **Frame differencing:** `cv2.cuda.absdiff()`.
- **Thresholding:** `cv2.cuda.threshold()`.
- **Morphological operations:** Pre-created `cv2.cuda.createMorphologyFilter()` for dilate/erode, applied iteratively via CUDA stream.

The GPU variant uses a dedicated `cv2.cuda.Stream` for async operations and synchronises (`waitForCompletion()`) before downloading results to CPU. Contour extraction still runs on CPU since `cv2.findContours()` has no CUDA equivalent, but the preceding operations (which dominate compute) are fully GPU-accelerated.

Graceful fallback: if any GPU operation fails (driver errors, OOM, resource contention), the detector falls back to CPU for that frame and logs a debug warning. The `_set_detection_params()` override recreates the GPU Gaussian filter after kernel size scaling to maintain GPU/CPU consistency.

## The Clip Camera Challenge

`ClipMotionDetector` (in `core/clip_motion_detector.py`) handles the ~32K clip-based cameras differently. On each new video clip, it reinitialises the FDMD background model from scratch (`new_video=True`), because clips are discontinuous -- the background from the previous clip is irrelevant. The `new_video_motion_return` flag controls whether the first frame of a new clip is treated as motion (allowing immediate inference) or no-motion (requiring the second frame to establish a delta). This is configurable per-integration.

## Ignore Zone Integration

Motion detection honours two types of ignore zones, applied before contour extraction:

- **Polygonal zones:** Defined per-camera in [[actuate-config]], converted from RLE format to pixel coordinates, then burned into a binary mask via `cv2.fillPoly()`. The mask is applied to the threshold image, zeroing out motion in ignored regions.
- **Box zones:** Legacy format, applied by directly zeroing rectangular regions in the threshold image.

Additionally, **timestamp zones** are detected automatically by sending the first frame to an internal OCR service (`timestamp-ocr-svc`), which returns bounding boxes of on-screen timestamps. These are added to the FDMD mask to prevent clock digits from triggering false motion. This OCR call is submitted asynchronously via a single-worker executor to avoid blocking the puller's first-frame processing.

## Performance Profile

Motion detection is the most CPU-intensive per-frame operation after JPEG encoding. At 720p with the CPU path, a single `get_delta_noise()` call takes ~2-5ms. The GPU path reduces this to ~1-2ms but adds PCIe transfer overhead. The primary performance lever is `frame_width` -- resizing to a smaller width before processing reduces contour extraction time quadratically. The tradeoff is reduced spatial resolution for motion regions, which can cause the stationary filter to miss small-object motion overlap.
