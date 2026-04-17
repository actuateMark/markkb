---
title: "Source: Scene Change Detection Approach"
type: source
topic: camera-health-monitoring
tags: [worklog, scene-change, detection, reference-image]
ingested: 2026-04-14
author: kb-bot
---

# Scene Change Detection Approach

Brief worklog notes on the implementation approach for sudden scene change detection within CHM.

## Method

The approach is straightforward: save the first frame received from the camera as the reference image at the start of each healthcheck run. When a scene change question arises during the run, save the incoming frame and compare it against the reference. If a change is detected, set the sudden scene change flag.

The key insight is that scene change detection only needs to run at the start of each healthcheck cycle -- capture the first frame as a baseline, then compare subsequent frames against it. This is not a continuous real-time comparison but a periodic check aligned with the healthcheck schedule.

## Relationship to SIFT

The actual implementation evolved to use SIFT (Scale-Invariant Feature Transform) keypoint matching via the `actuate-suddenscenechange` library, as documented in [[health-check-types]]. The worklog note here captures the initial design intent before the SIFT approach was fully specified.

## See Also

- [[health-check-types]] -- covers scene change detection in the context of all check types
