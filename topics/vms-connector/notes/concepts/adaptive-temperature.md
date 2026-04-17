---
title: "Adaptive Temperature (Frame Processing)"
type: concept
topic: vms-connector
tags: [connector, temperature, adaptive, frame-rate, optimization, downsampling]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
sources:
  - "[[worklog-temperature-adaptive-processing]]"
---

# Adaptive Temperature (Frame Processing)

A proposed but not-yet-implemented mechanism for dynamically adjusting the connector's frame processing rate based on recent detection activity. The concept addresses the tension between cost efficiency (low default analytics FPS) and detection accuracy (risk of missing brief events between sampled frames).

## Concept

A "temperature" value would be maintained per-camera in the pipeline. When a detection occurs, the temperature increases. Elevated temperature makes the pipeline more willing to process subsequent frames -- effectively increasing the analytics FPS or reducing downsampling aggressiveness for a window of time. When no detections occur, the temperature decays back to baseline and normal (lower) processing rates resume.

## Motivation

The connector typically downsamples from native FPS (15-30) to analytics FPS (1-3). This aggressive downsampling saves inference cost but can miss objects that appear briefly between sampled frames. Temperature provides context-awareness: once something is detected, the system "heats up" to capture the full event, then "cools down" when the scene returns to normal.

## Potential Implementation

If implemented, temperature would likely be:

- A decaying float value carried on the `ImageDataPacket` or stored per-camera on the camera object.
- Read by a pre-processing step that modifies the downsampling interval before the frame reaches inference.
- Increased by a fixed increment on each detection, decayed by a time-based factor each frame.

## Status

Proposed only (as of April 2026). No implementation exists in the codebase. Related to broader [[pipeline-architecture]] optimisation efforts.
