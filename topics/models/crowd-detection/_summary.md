---
title: "Model: Crowd Detection"
type: summary
topic: models/crowd-detection
tags: [model, crowd, detection]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Model: Crowd Detection

## Overview

Crowd detection (also known as social distancing detection) identifies when multiple people are within proximity of each other. Rather than using a dedicated crowd-specific inference model, it performs **proximity analysis** on top of person detections from the intruder model (currently [[models/intruder-v5|intruder-384h-512w-svc]]). The logic is implemented in `CrowdViolationPresentStep` in [[actuate-libraries|actuate-pipeline]].

## Detection Algorithm

The crowd detection algorithm operates on `person` detections from the YOLO model and applies geometric distance estimation:

1. **Size candidacy check** -- For each pair of person detections, their bounding box heights must be within a configurable ratio window (`candidate_parameter`, default 0.7). This filters out perspective mismatches where one person is much closer to the camera than another.

2. **Proximity check** -- For candidate pairs, a circle is created at detection 1's bounding box center with a radius derived from the bbox dimensions multiplied by `crowd_six_foot_multiplier` (default 2.0, meaning approximately 12 feet). If detection 2's center falls inside the circle, they are considered in proximity.

3. **Crowd threshold** -- If a person has >= `min_crowd_size` neighbors within range (default 2, meaning 3+ people clustered together), a `crowd` detection label is created by deep-copying the person detection and relabeling it as `crowd`.

## Configuration

Crowd detection is configured in settings.json with `crowd` in the `metrics` block. Key settings:

| Setting | Typical Value | Purpose |
|---------|--------------|---------|
| `min_crowd_size` | 2 | Minimum neighbors to trigger (actual crowd = min_crowd_size + 1) |
| `crowd_six_foot_multiplier` | 1.0-2.0 | Scales the proximity radius |
| `thresh` | 10 | Confirmed frames needed in window |
| `denominator` | 20 | Window size in frames |

The high sliding window thresholds (10/20 vs 2/5 for intruder) reduce false alarms from momentary clustering.

## Raw Metrics Mapping

In [[actuate-libraries|actuate-config]]'s `StreamDeploymentConfig`, if `crowd` appears in `metrics` but not in `raw_metrics`, the crowd raw metrics are derived from the `person` raw metrics. If no person raw metrics exist, defaults are applied: `minimum_confidence: 50`, `iou_thresh: 0.9`.

## Pipeline Position

Crowd detection sits in the post-processing pipeline of the [[data-science/_summary|Data Science Methodology]], executed by `CrowdViolationPresentStep`. It runs after the standard filters (confidence, [[ignore-zones|ignore zones]], IOU, stationary) and before the sliding window. The step operates on the already-filtered `raw_model_response`, examining all pairs of person detections for proximity violations. Crowd detections are appended to the model response, then processed by the sliding window like any other label.

## Products and Observers

Crowd detection uses the standard sliding window pattern and does not have a dedicated observer in [[actuate-libraries|actuate-connector-observers]]. The `crowd` metric is recognized as an "other detection metric" in `StreamDeploymentConfig._check_line_crossing_only()`, meaning its presence alongside line crossing prevents line-crossing-only mode.

## Current Status

Crowd detection is **active in production**. It uses the same underlying intruder model as the Intruder product, so it will benefit from the [[models/intruder-v8|v8 intruder model]] upgrade when the AI-180 rollout completes.

## Related Topics

- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog
- [[data-science/_summary|Data Science Methodology]] -- [[detection-pipeline|detection pipeline]]
- [[models/intruder-v5]] -- the underlying person detection model
- [[models/fall-detection]] -- another derived product using intruder model output
