---
title: "actuate-inference-slicing"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, sahi, image-slicing, high-resolution]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-inference-slicing

SAHI-style sliced inference for detecting small objects in high-resolution images. Divides a large image into overlapping tiles, runs inference on each tile, and merges results back into full-image coordinates. Version **1.0.1**.

## Purpose

Standard object detection models have a fixed input resolution (e.g., 640x640). When the source image is much larger, small objects become undetectable after downscaling. This library implements Slicing Aided Hyper Inference (SAHI): it computes an optimal grid of overlapping slices, optionally resizes the image to limit the total slice count, runs inference on each slice independently, and then merges overlapping detections using a union-merge post-processor.

## Key Classes

- **`SlicingParameters`** -- the main orchestrator. Given an `Image`, slice dimensions, overlap ratio, confidence threshold, and max slice count, it computes the grid layout, resizes the image if needed, and produces the list of image slices with their starting pixel offsets.
- **`SlicedGrid`** -- computes the 2D grid of rows and columns for slicing, based on image dimensions, slice dimensions, and overlap. Calculates a resizing factor when the total slice count exceeds `max_slices`.
- **`OverlapRatio`** -- parameterizes the horizontal and vertical overlap between adjacent slices.
- **`SlicedImage`** -- produces the actual cropped image tiles and their shift amounts from the resized image.
- **`ObjectPrediction`** -- wraps a per-slice detection with its bounding box, score, category, and full image shape. Provides `shift_bbox()` for mapping slice-local coordinates back to full-image coordinates.
- **`PredictionResult`** -- aggregates per-slice detections, applies `UnionMergePostprocessor` to merge overlapping boxes (using IoS metric with 0.5 threshold, class-aware), and outputs a final `list[Detection]` in original image coordinates.
- **`UnionMergePostprocessor`** -- greedy NMS-like merge: picks the highest-scoring prediction, merges overlapping same-class predictions into a union bounding box, and repeats.

## Public API

```python
from actuate_inference_slicing import (
    SlicingParameters, SlicedGrid, OverlapRatio,
    SlicedImage, ObjectPrediction, PredictionResult,
)
```

## Dependencies

- **Internal**: `actuate-inference-objects ~=1.0`, `actuate-inference-client ~=1.0`
- **External**: none beyond transitive dependencies

## Consumers

Used by `vms-connector` pipelines that handle high-resolution cameras (4K+, thermal panoramic) where small-object detection is critical.

## Notable Patterns

- The `max_slices` parameter prevents excessive GPU load by resizing the image down when the grid would produce too many tiles. The resizing factor is `sqrt(max_slices / (rows * columns))`.
- Grid computation and resizing factor are LRU-cached (10,000 entries) since the same camera dimensions produce the same layout across frames.
- The merge step is class-aware by default, preventing a `car` detection from absorbing a `person` detection in an overlapping region.
