---
title: "actuate-viz"
type: entity
topic: actuate-libraries
tags: [library, utility, visualization, opencv, bounding-box, detection, drawing]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-viz (v1.1.5) is the visualization library for drawing detection results, [[ignore-zones|ignore zones]], trajectory arrows, and line crossings on video frames. It uses [[opencv-entity|OpenCV]] and numpy to render bounding boxes with configurable styles, labels, and colors onto images for alert frames, debugging, and analytics dashboards.

## Public API

### Detection Drawing

- **`draw_bbox(img, bbox, color, gap, height, width)`** -- Draws a single bounding box. When `gap=True` (default), renders stylised corner brackets with thick corners and thin inner lines; when `gap=False`, draws a simple rectangle. Corner thickness and line weight scale linearly with the smaller image dimension, clamped between min/max bounds.

- **`draw_boxes(detections, image, color, confidence_format, display_label, display_confidence, height, width)`** -- Draws multiple Detection objects on an image. For each detection, calls `draw_bbox` (with adaptive gap based on box size) and adds a text label above the box showing the class name and confidence.

- **`bbox2points(bbox)`** -- Converts YOLO-format bounding box (center x, center y, width, height) to corner points (xmin, ymin, xmax, ymax).

- **`get_text_label(detection, confidence_format, display_label, display_confidence)`** -- Builds a text string like `"person [0.93]"` from a Detection object.

- **`draw_trajectory_arrow(image, start_point, end_point, color, thickness, tip_length, min_travel_dist, label)`** -- Draws an arrowed line showing object movement direction. Only renders if travel distance exceeds `min_travel_dist` (default 20px), preventing noise from stationary detections. Adds a small circle at the start point and an optional text label.

- **`draw_line_crossings(frame, line_coordinates, line_colors)`** -- Draws line-crossing boundary lines on a frame, cycling through a default colour palette (yellow, magenta, cyan, orange, green).

### Colors and Zones

- **`Color`** -- Enum/class providing named BGR colour constants (MAGENTA, GREEN, CYAN, etc.) with an `ensure_tuple` class method for normalising Color-or-tuple arguments.

- **`get_class_color(class_name)`** -- Maps detection class names to consistent colours.

- **`overlay_ignore_zones(image, zones)`** -- Draws polygonal [[ignore-zones|ignore zones]] as semi-transparent overlays on frames.

- **`add_label(image, label)`** -- Adds a text label to an image.

## Dependencies

- **opencv-python-headless** >=4.8.0,<5.0 -- image drawing operations.
- **numpy** >=1.20.0 -- array operations.
- **[[actuate-inference-objects]]** >=1.0.6 -- `Detection` and `BoundingBox` types.
- **actuate-filters** ~=2.0 -- filtering utilities.

## Consumers

vms-connector alert pipeline (draws detection boxes on alert frames before S3 upload), debugging/analytics tools, any service that generates annotated video frames.

## Notable Patterns

- **Dimension-adaptive line thickness**: Corner thickness, inner line weight, and font scale all scale with image dimensions, ensuring readable annotations across resolutions from 480p to 4K.
- **Gap vs simple mode**: Small detections (below 5% of image dimensions) automatically switch to simple rectangles to avoid visual clutter.
- **BGR colour convention**: All colours follow [[opencv-entity|OpenCV]]'s BGR ordering, with the `Color` class providing named constants to avoid tuple mistakes.
