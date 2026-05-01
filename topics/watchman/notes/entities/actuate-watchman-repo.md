---
title: "actuate-watchman"
type: entity
topic: watchman
tags: [watchman, on-premise, line-crossing, yolo, openvino, computer-vision, edge]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/watchman/notes/entities/actuate-watchman-internal.md
incoming_updated: 2026-05-01
---

# actuate-watchman

The public-facing [[watchman-repo|Watchman]] repository providing an on-premise video analytics platform for [[line-crossing-detection|line crossing detection]]. It combines motion detection, YOLO-based object detection, and object tracking into a three-stage pipeline designed for surveillance deployments at customer sites.

**Repo:** `aegissystems/actuate-watchman` (GitHub, private)
**Language:** Python
**Last updated:** 2026-04-09

## Pipeline Architecture

The system processes video through three sequential stages:

1. **Motion Detection** -- Frame differencing (FDMD) identifies frames containing movement. Additional detectors include Simple, Motion Filter, and SOF. Static frames are skipped entirely to save compute.
2. **Object Detection** -- YOLO inference runs only on frames with detected motion. Supports both PyTorch and OpenVINO backends with INT8 quantization for edge hardware.
3. **[[line-crossing-detection|Line Crossing Detection]]** -- Tracked objects are monitored against user-defined crossing lines. Counts are emitted when an object trajectory intersects a line boundary.

## Key Features

- **Multi-stream benchmarking** -- stress-test mode to evaluate throughput across multiple simultaneous camera feeds.
- **Stationary object filtering** -- removes detections that do not overlap with motion regions, reducing false positives from static objects.
- **Re-ID and appearance matching** -- color histogram matching for re-identifying objects across camera views.
- **Loiter detection** -- flags objects that remain in a defined zone beyond a configurable duration.
- **Encrypted model deployment** -- supports encrypted YOLO model files for secure distribution to customer hardware.
- **Web UI and live preview** -- a service layer with a browser-based interface for configuring lines, previewing detections, and monitoring counts in real time.
- **Multi-line crossing** -- supports multiple crossing lines per camera with independent counting.

## Installation

Installed via `pip install -e .` with an optional `[openvino]` extra for Intel hardware. Entry point is the `watchman` package, verified by importing `YAMApplication`.

## Relationship to actuate-watchman-internal

This repo is the customer-distributable version. The [[actuate-watchman-internal]] repo is the internal-only variant used by Actuate employees, containing the same core pipeline but potentially with additional internal tooling or unreleased features.
