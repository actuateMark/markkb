---
title: "Model: Loitering"
type: summary
topic: models/loitering
tags: [model, botsort, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Loitering

## Overview

Loitering detection identifies people or vehicles that remain in a monitored area beyond a configurable time threshold. Unlike intruder detection (which triggers on presence) or line crossing (which triggers on trajectory), loitering requires **temporal identity linkage** -- the system must track the same object across frames and measure its dwell time. This is implemented using BoTSORT multi-object tracking within the `PersonLoitererObserver` and `VehicleLoitererObserver` in [[actuate-libraries|actuate-connector-observers]].

## Architecture

Loitering does not use a separate inference model. It uses the output of the intruder model (currently [[models/intruder-v5|intruder-384h-512w-svc]], transitioning to [[models/intruder-v8|int07-actuate003-v8]]) and applies [[botsort-tracking|BoTSORT tracking]] on top. BoTSORT (Bag of Tricks for SORT) associates detections to existing tracks using three signals:

1. **Motion prediction** -- Kalman filter predicts where each track should appear
2. **Appearance features** -- Visual re-identification embeddings for re-association after occlusion
3. **IoU matching** -- Bounding box overlap as a spatial consistency check

## Observers

Two observer classes implement loitering in [[actuate-libraries|actuate-connector-observers]]:

- **PersonLoitererObserver** -- Tracks `person` detections with `max_age=5` (frames a track survives without a match), `inflate_bbox_scale=1.6`. The `conf_filter` always returns True (no additional confidence filtering beyond the pipeline's).
- **VehicleLoitererObserver** -- Tracks vehicle labels (`car`, `motorcycle`, `bus`, `truck`, `machinery`) with `max_age=3` (vehicles are larger, detected more reliably). Applies confidence filtering against `raw_metrics` thresholds.

## Dwell Time and Alert Logic

Each track accumulates dwell time. When `tracklet_len + 1 >= frame_thresh * fps`, the observer triggers an alert. Up to 3 alerts per track ID are sent, with cooldown spacing (the threshold for the second alert is `frame_thresh + 2 * frame_thresh`). The `frame_thresh` defaults to 60 seconds (configurable per camera in settings.json under the `loiterer`/`vehicle_loiterer` metric).

## Stationary Filter Interaction

The stationary filter is applied only on the **first frame** of a tracking sequence (`strack.tracklet_len == 0`). This prevents a person who stops moving (producing no FDMD motion) from being filtered out precisely when they are exhibiting loitering behavior. Both individual-blob and cumulative motion overlap modes are supported, with vehicle high-motion sensitivity requiring 30% overlap vs. the default 10%.

## Configuration

Loitering is configured in settings.json with `loiterer` or `vehicle_loiterer` in the `metrics` block. Key settings: `frame_thresh` (dwell time in frames), `thresh=1`/`denominator=1` (single confirmed frame triggers since temporal gating is in the observer). Product-specific [[ignore-zones|ignore zones]] can be set via `polygonal_zones` within the loiterer metric.

## Pipeline Position

Within the [[data-science/_summary|Data Science Methodology]], loitering observers sit at the observer layer. Filtered YOLO detections (after stationary, confidence, [[ignore-zones|ignore zones]], IOU, blacklist filters) are fed to the BoTSORT tracker. When the observer triggers, it injects a `loiterer` or `vehicle_loiterer` label into the pipeline results, which then passes through the sliding window and alert generation.

## Current Status

Loitering detection is **active in production**. The observers are automatically attached to cameras when `loiterer` or `vehicle_loiterer` appears in the feature deployment's metrics, via `build_observers()` in the [[vms-connector]] factory.

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- [[botsort-tracking|BoTSORT tracking]] and [[detection-pipeline|detection pipeline]]
- [[models/intruder-v5]] -- the underlying detection model
- [[models/line-crossing]] -- alternative tracking-based product
