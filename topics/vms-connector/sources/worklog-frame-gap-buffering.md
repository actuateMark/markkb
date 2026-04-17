---
title: "Source: Timestamp Gap Buffering Algorithm"
type: source
topic: vms-connector
tags: [worklog, timestamps, frame-gap, puller, buffering]
ingested: 2026-04-14
author: kb-bot
---

# Timestamp Gap Buffering Algorithm

**Origin:** `/home/mork/Documents/worklog/worklog/frame gap buffering.md`

A concise algorithm sketch for smoothing timestamp irregularities in pulled video frames. The puller receives frames from RTSP or HTTP streams, but network jitter, camera clock drift, and reconnection events can cause gaps or compression in the timestamp sequence.

## Algorithm

The approach tracks previous frame timestamps and applies three rules based on the gap between the current frame's timestamp and the previous one:

1. **Small gap (within 1 second)**: Set the current timestamp to `previous_timestamp + native_fps_gap`, where `native_fps_gap` is the expected inter-frame interval at the camera's native FPS. This smooths out minor jitter.
2. **Sub-gap (less than native_fps_gap)**: Bump the timestamp to exactly `native_fps_gap` ahead of the previous frame. This prevents frames from arriving "too fast" and collapsing the timeline.
3. **Large gap (more than 1 second)**: Reset the timestamp to approximately `time.time() - 1 second + (native_fps_gap * (native_fps - 1))` behind real time. This anchors the stream back to wall-clock time after a significant interruption (e.g., reconnection) without creating a sudden forward jump.

## Significance

This algorithm addresses a practical reliability problem in production: irregular timestamps can cause downstream issues with downsampling logic (which relies on consistent inter-frame intervals), window calculations, and alert timing. The smoothing approach trades strict timestamp accuracy for temporal consistency, which is the right trade-off for analytics where relative ordering and consistent intervals matter more than absolute time precision.
