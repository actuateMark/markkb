---
title: Motion Detection Challenge (FDMD & Clip-Based Cameras)
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [fdmd, motion-detection, clip-based, rtsp, stationary-filter]
---

# Motion Detection Challenge

## Overview

The Frame Difference Motion Detector (FDMD) is a core component of the [[detection-pipeline]], responsible for identifying motion regions before frames are sent to YOLO inference. However, FDMD was architected for **continuous [[rtsp-deep-dive|RTSP]] streams** where frames arrive at a steady cadence (e.g., 15-30 fps). A large portion of the camera fleet -- approximately **32,000 cameras** -- operates on clip-based connections (SMTP, AILink, [[sentinel-components|Sentinel]]) where frames arrive in sporadic bursts separated by minutes or even hours. This mismatch is a significant source of missed detections and degraded alert quality.

## How FDMD Works

FDMD computes pixel-level differences between consecutive frames to detect regions of change. When the difference exceeds a threshold, the changed region is marked as a **motion polygon**. These polygons serve two purposes:

1. **Gating inference** -- only regions with detected motion are forwarded to YOLO, reducing GPU cost
2. **Stationary filter input** -- the stationary filter in the post-processing stage uses motion polygons to suppress detections on static objects (parked cars, permanent fixtures)

For [[rtsp-deep-dive|RTSP]] streams, this works well: consecutive frames are temporally close, so genuine motion (a person walking) produces clear pixel differences while static backgrounds remain stable.

## The Clip-Based Problem

On clip-based cameras, the temporal gap between frames can be **minutes or hours**. When a new clip arrives:

- The first frame may differ dramatically from the last frame of the previous clip due to lighting changes, camera repositioning, or simply the passage of time
- FDMD may either flag the **entire frame** as motion (everything changed) or fail to detect motion at all if internal state has decayed
- The stationary filter, which relies on FDMD output, becomes unreliable -- it may suppress genuine detections or pass through false ones

The result is a systematic accuracy degradation on clip-based cameras that does not show up in standard frame-level mAP evaluations (which assume independent frames).

## Fixes in Progress

### Cumulative Motion Blob (MISS-652)

The cumulative blob fix enables FDMD to accumulate motion evidence across frames within a clip rather than relying on single frame-to-frame differences. This produces more stable motion polygons when frame timing is irregular. The cumulative approach smooths out the noise of large temporal gaps and provides a more reliable motion signal for downstream filters.

### Skip FDMD for Single-Frame Clips (MISS-630)

For clips containing only a single frame, there is no previous frame to diff against, making FDMD fundamentally inapplicable. The fix is to **bypass FDMD entirely** for single-frame clips and send the full frame directly to inference. This trades increased GPU cost (no motion gating) for correct detection behavior. The stationary filter is also skipped since it depends on FDMD output.

### Parameter Research

Additional work is needed to tune FDMD thresholds and parameters specifically for clip-based scenarios. The current parameters were optimised for [[rtsp-deep-dive|RTSP]] streams, and different decay rates, sensitivity thresholds, and blob merging strategies may be needed for the clip-based fleet.

## Impact

The 32,000 clip-based cameras represent a substantial portion of the total camera fleet. Fixing FDMD behavior for these cameras is expected to meaningfully improve system-wide detection rates, particularly for the intruder product where missed detections directly impact customer trust.

## Related Notes

- [[detection-pipeline]] -- FDMD sits at stage 2 of the pipeline
- [[intruder-v5-model]] -- the model whose effectiveness depends on correct FDMD gating
- [[model-evaluation-framework]] -- standard evaluations may not capture clip-based issues
