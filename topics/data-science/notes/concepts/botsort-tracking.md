---
title: BoTSORT Tracking for Loitering
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [tracking, botsort, loitering, dwell-time, observer]
---

# BoTSORT Tracking for Loitering

## Overview

BoTSORT (Bag of Tricks for SORT) is the multi-object tracking algorithm used by Actuate's loitering detection products. It provides the temporal identity linkage needed to measure how long a person or vehicle has been present in a scene -- the fundamental requirement for loitering detection. Without tracking, each frame's detections are independent and dwell time cannot be computed.

## How Tracking Works in the Pipeline

Within the [[detection-pipeline]], tracking sits inside the observer layer. After raw YOLO detections pass through post-processing filters (stationary, confidence, ignore zones, IOU, blacklist), the filtered detections for each frame are fed to the BoTSORT tracker. The tracker maintains a set of **tracks** -- each track represents a single real-world object persisting across frames.

BoTSORT associates detections to existing tracks using a combination of:

1. **Motion prediction** -- a Kalman filter predicts where each track should appear in the next frame based on its velocity and position history
2. **Appearance features** -- visual embeddings (re-identification features) help re-associate tracks when motion prediction alone is ambiguous (e.g., after occlusion or a brief detection gap)
3. **IoU matching** -- bounding box overlap between predicted and detected positions as a spatial consistency check

This multi-signal approach makes BoTSORT more robust than simpler trackers (e.g., vanilla SORT) in crowded scenes or when objects temporarily disappear behind obstacles.

## max_age Parameter

The `max_age` parameter controls how many frames a track survives **without a matching detection** before it is terminated. This is critical for handling intermittent detection gaps caused by occlusion, motion blur, or model misses:

| Product | max_age | Rationale |
|---------|---------|-----------|
| **PersonLoitererObserver** | 5 frames | People are smaller and more prone to momentary detection loss; a higher max_age prevents premature track termination |
| **VehicleLoitererObserver** | 3 frames | Vehicles are larger and detected more reliably; a lower max_age reduces the risk of incorrectly linking two different vehicles |

If a track exceeds `max_age` without re-association, it is deleted. Any accumulated dwell time for that track is lost. Conversely, if `max_age` is too high, two distinct objects (e.g., one person leaving and another arriving) may be incorrectly linked into a single track, inflating dwell time and causing false loitering alerts.

## Dwell Time and Alert Triggering

Each active track accumulates **dwell time** -- the elapsed time since the track was first created. When dwell time exceeds a configurable threshold (set per camera or per product), the observer triggers a loitering alert.

The dwell-time threshold is customer-configurable and depends on the use case: a convenience store might set 5 minutes, while a critical infrastructure site might set 60 seconds.

## Stationary Filter Interaction

A notable implementation detail: the **stationary filter** (which uses FDMD motion polygons to suppress detections on static objects) is applied only on the **first frame** of a tracking sequence. This design choice avoids a subtle failure mode where a person who stops moving (and thus produces no FDMD motion) would be filtered out by the stationary filter, terminating their track precisely when they are exhibiting loitering behavior. By only applying the stationary filter at track initialization, the system ensures that objects which enter a scene (producing motion) and then stop (genuine loitering) continue to be tracked.

## Related Notes

- [[detection-pipeline]] -- the full pipeline in which tracking operates
- [[line-crossing-detection]] -- the other tracking-based product (uses TrajectoryManager instead)
- [[motion-detection-challenge]] -- FDMD issues that affect stationary filter reliability
