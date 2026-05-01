---
title: Line Crossing Detection
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [line-crossing, tracking, trajectory, observer, alert-reduction]
---

# Line Crossing Detection

## Overview

Line crossing detection identifies when a tracked object crosses a customer-defined virtual line in the camera's field of view. Unlike intruder detection (which triggers on presence) or loitering (which triggers on dwell time), line crossing requires **directional trajectory analysis** -- the system must determine that an object moved from one side of the line to the other. This product is implemented in the **LineCrossingObserver** using a **TrajectoryManager** component.

## TrajectoryManager

The TrajectoryManager is responsible for maintaining object trajectories -- sequences of positions over time -- and evaluating them against configured crossing lines. It is distinct from the [[botsort-tracking|BoTSORT tracker]] used for loitering, though it serves a similar purpose of linking detections across frames.

Key parameters:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `max_link_dist` | 250 pixels | Maximum distance between detections in consecutive frames to be considered the same object. Prevents linking detections that are too far apart (likely different objects). |
| `max_age` | 15 frames | How many frames a trajectory survives without a matching detection before termination. Higher than BoTSORT's loitering values because line crossing needs to track objects across longer distances. |

The higher `max_age` (15 vs 5 for person loitering) reflects the different use case: a person crossing a line may briefly pass behind an obstacle or exit the detection zone momentarily while still on a crossing trajectory. Premature track termination would cause missed crossings.

## Sign-Change Crossing Condition

The core logic for detecting a line crossing uses a **sign-change** method. For each tracked object, the system computes the signed distance from the object's position to the configured line at each frame. The sign indicates which side of the line the object is on:

- **Positive** = one side of the line
- **Negative** = the other side

A crossing is detected when the sign **changes** between consecutive trajectory points (or within a short window). This is mathematically simple and robust: it does not require the object to follow a straight path or approach the line at any particular angle.

## Directional Filtering

Customers can configure line crossing to trigger only for crossings in a **specific direction** (e.g., entering a restricted area but not exiting). The sign-change method naturally supports this: a positive-to-negative transition represents one direction, and negative-to-positive represents the other. The observer checks whether the observed transition matches the configured trigger direction before raising an alert.

## Beta Results: Alert Volume Reduction

Line crossing detection was tested in beta with the **Edgeworth customer**, producing dramatic results:

- **86-98% alert volume reduction** compared to standard intruder detection on the same cameras

This reduction occurs because line crossing is inherently more selective than zone-based intruder detection. An intruder alert triggers whenever a person is detected in a zone; a line crossing alert triggers only when a person crosses a specific boundary in a specific direction. For cameras monitoring doorways, gates, or perimeters, this filters out the vast majority of innocuous activity (people standing near but not crossing the line, vehicles passing parallel to the line).

The 86-98% range reflects variation across different camera placements and line configurations at the Edgeworth site.

## Position in the Pipeline

Within the [[detection-pipeline]], the LineCrossingObserver receives filtered YOLO detections (after stationary filter, confidence filter, [[ignore-zones|ignore zones]], IOU filter, and blacklist filter). It feeds these detections to the TrajectoryManager, evaluates trajectories against configured lines, and generates alerts when valid crossings are detected. Alerts follow the standard path: frames to S3, alert messages to SQS.

## Related Notes

- [[detection-pipeline]] -- the full [[pipeline-architecture|pipeline architecture]]
- [[botsort-tracking]] -- the alternative tracking approach used for loitering
- [[motion-detection-challenge]] -- FDMD issues that can affect detection input quality
