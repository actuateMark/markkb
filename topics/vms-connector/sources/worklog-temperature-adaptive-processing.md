---
title: "Source: Temperature Concept for Adaptive Frame Processing"
type: source
topic: vms-connector
tags: [worklog, temperature, adaptive, frame-rate, optimization, missed-detections]
ingested: 2026-04-14
author: kb-bot
---

# Temperature Concept for Adaptive Frame Processing

**Origin:** `/home/mork/Documents/worklog/worklog/connector improvement ideas to prevent misses.md`

A brief but significant idea note proposing a "temperature" mechanism for the pipeline to dynamically adjust frame processing rates based on recent detection activity.

## Concept

Add a "temperature" value to the pipeline that increases when a detection occurs. When the temperature is elevated, the pipeline becomes more willing to process subsequent frames (i.e., temporarily increases the effective analytics FPS or reduces downsampling aggressiveness). When no detections occur for a period, the temperature cools back down and the pipeline reverts to its normal (lower) processing rate.

## Motivation

The connector typically downsamples from the camera's native FPS (15-30) to a much lower analytics FPS (1-3 FPS) to conserve inference resources. This aggressive downsampling can cause missed detections when an object appears briefly between sampled frames. The temperature concept addresses this by making the system context-aware: once something interesting is detected, the pipeline "heats up" and processes more frames to capture the full event, then "cools down" when the scene returns to baseline.

## Significance

This is a novel adaptive processing concept that has not yet been implemented as of April 2026. It sits at the intersection of cost optimisation (low default FPS) and detection accuracy (higher FPS during active events). If implemented, it would likely live as a pre-processing step that modifies the downsampling interval based on a decaying temperature value carried on the `ImageDataPacket`.
