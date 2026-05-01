---
title: "actuate-watchman-internal"
type: entity
topic: watchman
tags: [watchman, on-premise, line-crossing, yolo, openvino, computer-vision, internal]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-watchman-internal

The internal-only variant of the [[watchman-repo|Watchman]] [[line-crossing-detection|line crossing detection]] pipeline, restricted to Actuate employees. It shares the same core architecture as [[actuate-watchman-repo|actuate-watchman]] but serves as the working development repository where internal features, experiments, and tooling live before they are promoted to the customer-facing distribution.

**Repo:** `aegissystems/actuate-watchman-internal` (GitHub, private)
**Description:** Internal Actuate version of watchman (employees only)
**Language:** Python
**Last updated:** 2026-04-10

## Core Pipeline

Identical three-stage architecture to the public repo:

1. **Motion Detection (FDMD)** -- frame differencing to identify active frames; additional detectors (Simple, Motion Filter, SOF) available.
2. **Object Detection (YOLO/OpenVINO)** -- person detection with PyTorch and OpenVINO backends, INT8 quantization for edge deployments.
3. **[[line-crossing-detection|Line Crossing Detection]]** -- object tracking with crossing-line counting against user-defined boundaries.

## Feature Set

The internal repo includes the full feature surface: multi-stream benchmarking, stationary object filtering, Re-ID with color histogram matching, loiter detection, encrypted model deployment, web UI with live preview, and multi-line crossing support. Because this is the employee-only version, it may also contain experimental branches, debug tooling, or unreleased capabilities not yet cleared for customer distribution.

## Development Workflow

Installed via `pip install -e .` (with optional `[openvino]` extra). The entry point is the `watchman` package, importable as `YAMApplication`. Configuration is done through JSON config files specifying the detection backend, line coordinates, and motion detector settings.

## Relationship to Other Repos

- **[[actuate-watchman-repo|actuate-watchman]]** -- the customer-distributable counterpart. Changes validated internally here are expected to flow outward to the public repo.
- **[[kubernetes-deployments]]** -- [[watchman-repo|Watchman]] is an on-premise deployment, so it is not managed through the standard [[argocd|ArgoCD]] GitOps pipeline. Distribution is handled separately for edge hardware.
