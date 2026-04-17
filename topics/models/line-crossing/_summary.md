---
title: "Model: Line Crossing"
type: summary
topic: models/line-crossing
tags: [model, trajectory, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Line Crossing

## Overview

Line crossing detection identifies when a tracked object crosses a customer-defined virtual line in the camera's field of view. Unlike intruder detection (presence-based) or loitering (dwell-time-based), line crossing requires **directional trajectory analysis** -- the system determines that an object moved from one side of a line to the other. This product is implemented in the `LineCrossingObserver` using a `TrajectoryManager` component in [[actuate-libraries|actuate-connector-observers]].

## Architecture

Line crossing does not use a separate inference model. It uses the output of the intruder model (currently [[models/intruder-v5|intruder-384h-512w-svc]]) and applies trajectory-based crossing logic on top. The `TrajectoryManager` is distinct from the BoTSORT tracker used for [[models/loitering|loitering]] -- it uses IoU-based matching with class-specific parameters and FPS-aware distance scaling.

Key `TrajectoryManager` parameters:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `max_link_dist` | 250 pixels (base, scaled by FPS) | Maximum distance between detections to link |
| `max_age` | 15 frames | How long a trajectory survives without a match |

The higher `max_age` (15 vs 5 for person loitering) reflects the need to track objects across longer distances during a crossing.

## Sign-Change Crossing Condition

The core detection logic uses a **sign-change** method. For each tracked object, the system computes the signed distance from the object's position to the configured line at each frame. A crossing is detected when the sign changes between consecutive trajectory points. This is mathematically robust: it does not require a straight path or specific approach angle.

Line endpoints are normalized via `normalize_line_endpoints()` to ensure consistent direction detection: vertical lines are ordered top-to-bottom, horizontal lines left-to-right. This guarantees that L2R movement corresponds to positive-to-negative sign changes and R2L to negative-to-positive.

## Directional Filtering

Customers can configure crossings to trigger only in a specific direction: `L2R` (left-to-right), `R2L` (right-to-left), or `BOTH`. The `LineCrossingObserver.DIRECTION_MAP` normalizes various input formats. Only crossings matching the configured trigger direction generate alerts.

## Sensitivity Levels

The `LineCrossingObserver` supports three sensitivity levels configured per camera:

| Level | Tracking Point | Inflate Scale | Min Movement | Centroid Confirmation |
|-------|---------------|--------------|-------------|----------------------|
| **high** | Bottom-center of bbox | 1.2 | 5px | No |
| **medium** (default) | Blended toward centroid (0.25) | 1.0 | 10px | Yes |
| **low** | Closer to centroid (0.5) | 1.0 | 20px | Yes |

## Observers

Two observer subclasses exist in [[actuate-libraries|actuate-connector-observers]]:

- **PersonLineCrossingObserver** -- Tracks `person` detections against configured lines in the `intruder` metric.
- **VehicleLineCrossingObserver** -- Tracks vehicle labels against configured lines in the `vehicle` metric.

## Beta Results

Testing with the **Edgeworth customer** produced **86-98% alert volume reduction** compared to standard intruder detection on the same cameras. This dramatic reduction occurs because line crossing is inherently more selective -- it triggers only when objects cross a specific boundary in a specific direction.

## Pipeline Position

When line-crossing-only mode is active (`is_line_crossing_only = True` in [[actuate-libraries|actuate-config]]'s `StreamDeploymentConfig`), the IOU, blacklist, and stationary filters are skipped for the affected labels, and the sliding window is suppressed via `line_crossing_suppressed_labels`. The observer handles its own alert lifecycle. Pre-alarm is automatically set to a minimum of 5 seconds for line crossing features.

## Current Status

Line crossing is **active in production** and showing strong results in reducing alert volume. Observers are automatically attached via `build_observers()` in the [[vms-connector]] factory when `line_crossings` is present in the intruder or vehicle metric configuration.

## Related Topics

- [[ai-models]] -- model catalog
- [[data-science]] -- trajectory-based detection and pipeline architecture
- [[models/loitering]] -- alternative tracking-based product using BoTSORT
- [[models/intruder-v5]] -- the underlying detection model
