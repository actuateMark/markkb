---
title: "actuate-inference-objects"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, domain-objects, detection, bounding-box]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/filter-architecture.md
  - topics/actuate-libraries/notes/concepts/inference-client-evolution.md
  - topics/actuate-libraries/notes/concepts/observer-pattern.md
  - topics/actuate-libraries/notes/entities/actuate-viz.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/vms-connector/notes/syntheses/connector-evolution.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# actuate-inference-objects

Shared domain objects for the AI inference subsystem. Defines the canonical `Detection`, `BoundingBox`, `Image`, and `InferenceModel` types used throughout the pipeline. Version **1.2.0**.

## Purpose

Provides the common data structures that flow between inference clients, slicing logic, filters, trackers, and observers. Any library that produces or consumes object detections depends on this package. It also includes an `OverridableConfig` base class for singleton pydantic-settings configuration.

## Key Classes

- **`Detection`** -- an object detection result: label, confidence, bounding box, image dimensions, optional tags (e.g., `STATIONARY_VEHICLE`). Supports creation from strings, iterables, or explicit arguments. Provides `format_detections()` for compact grouped logging, `iou()` for pairwise overlap, and list-style indexing for backward compatibility.
- **`BoundingBox`** -- center-format bounding box (x, y, width, height). Supports arithmetic operators for scale (`*`, `/`), pad (`+`), and depad (`-`). Provides `from_xyxy()`, `from_str()`, `from_iter()` constructors and properties for `xmin`/`ymin`/`xmax`/`ymax`/`xyxy` conversions. IoU calculation delegates to `actuate-math`.
- **`Image`** -- wraps a numpy array with dimension tracking, resize-with-centerpad, JPEG encoding, and cropping. Tracks `input_dims`, `padding`, and `scale` for reverse-mapping detections back to original coordinates.
- **`ImageCrop`** -- subclass of `Image` for working with sliced sub-regions, preserving the starting pixel offset and full image dimensions.
- **`InferenceModel`** -- combines `ImageDimensions` (model input resolution) with a `CategoryMapping` (int-to-label and label-to-int bidirectional lookup).
- **`CategoryMapping`** / **`Category`** -- bidirectional mapping between integer category IDs and string labels.
- **`OverridableConfig`** -- singleton + frozen pydantic `BaseSettings` for environment-overridable configuration.

## Public API

```python
from actuate_inference_objects import (
    BoundingBox, Detection, DetectionTag,
    Box, Coordinate, Image, ImageCrop, ImageDimensions, ImagePadding,
    Category, CategoryMapping, InferenceModel,
)
```

## Dependencies

- **Internal**: `actuate-imutils ~=1.0`, `actuate-math ~=1.0`
- **External**: `pydantic-settings ~=2.7`, `opencv-python-headless`, `imageio ~=2.37`, `numpy`

## Consumers

Foundational dependency -- consumed by `actuate-inference-client`, `actuate-inference-slicing`, `actuate-filters`, `actuate-connector-observers`, `actuate-viz`, `actuate-pipeline-objects`, and `vms-connector`.

## Notable Patterns

- `BoundingBox` uses operator overloading (`*`, `/`, `+`, `-`) to make scale/pad transformations read naturally in code.
- `Detection` preserves backward compatibility with list-style `[0]`..`[4]` indexing and iteration, easing migration from the legacy list-of-lists format.
- `format_detections()` groups same-label detections and factors out common dimensions for compact log lines.
- The `SingletonMixin` ensures only one config instance exists per process.
