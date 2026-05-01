---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [chm, health-checks, connectivity, scene-change, stream-quality, recording, motion]
incoming:
  - topics/camera-health-monitoring/notes/concepts/healthcheck-architecture.md
  - topics/camera-health-monitoring/notes/entities/scene-change-detection.md
  - topics/camera-health-monitoring/sources/worklog-chm-email-design.md
  - topics/camera-health-monitoring/sources/worklog-dashboard-spec.md
  - topics/camera-health-monitoring/sources/worklog-hard-drive-health-fields.md
  - topics/camera-health-monitoring/sources/worklog-integration-diagnostics.md
  - topics/camera-health-monitoring/sources/worklog-project-structure.md
  - topics/camera-health-monitoring/sources/worklog-setup-procedure.md
  - topics/camera-health-monitoring/sources/worklog-sudden-scene-change.md
incoming_updated: 2026-05-01
---

# Health Check Types

[[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]] (CHM) performs five categories of health checks to ensure cameras are functioning correctly and their feeds are usable for detection. Health data is stored in DynamoDB across Healthcheck and SceneChange tables. When issues are detected, CHM generates email alerts and surfaces data in monitoring dashboards.

## 1. Connectivity Checks

The most fundamental check: can the system reach the camera? Connectivity monitoring verifies that the camera is online, responding to network requests, and streaming video. A connectivity failure means the camera is effectively blind -- no detection, no recording, no value.

Connectivity checks run continuously and are the first thing operators see when a camera goes offline. They trigger the highest-urgency alerts because a disconnected camera represents a complete coverage gap.

## 2. Scene Change Detection (SIFT-based)

[[scene-change-detection|Scene change detection]] identifies when a camera's view has been physically altered -- the camera has been bumped, rotated, covered, or deliberately tampered with. CHM uses the [[scene-change-detection|actuate-suddenscenechange]] library, which implements SIFT (Scale-Invariant Feature Transform) keypoint matching to compare the current frame against a stored reference image.

This is distinct from motion detection. [[scene-change-detection|Scene change detection]] looks for permanent structural changes to the field of view, not transient movement within it. A person walking through the scene is motion; someone pushing the camera to face a wall is a scene change.

Related backlog item: CS3-31 (Highest priority, Ready to Deploy) would auto-update reference images, reducing false scene change alerts caused by gradual legitimate changes like seasonal foliage shifts.

## 3. Stream Quality Checks

Stream quality monitoring assesses whether the video feed is degraded even if the camera is technically online. This covers:

- **Resolution drops** -- the camera switches to a lower resolution stream
- **Compression artifacts** -- excessive blockiness indicating bandwidth or encoding issues
- **Frame rate degradation** -- frames dropping below the expected rate
- **Image clarity** -- blur, fog, or condensation on the lens

A camera can be "online" but producing unusable video. Stream quality checks catch these soft failures that would otherwise reduce detection accuracy silently.

## 4. Recording Status

Verifies that the camera's feeds are being recorded as expected. This check ensures that even if live monitoring misses an event, the footage exists for post-incident review. Recording failures are particularly insidious because they are invisible until someone needs the footage and discovers it does not exist.

## 5. Motion Detection

Baseline motion monitoring tracks whether a camera is seeing expected levels of activity. A camera pointed at a busy entrance that suddenly reports zero motion for an extended period may indicate a problem -- the feed could be frozen, the camera could be covered, or the stream could be delivering stale frames.

Motion checks work in conjunction with [[scene-change-detection|scene change detection]]. Together they cover both sudden view alterations (scene change) and subtle feed failures (motion anomaly).

## Storage and Alerting

All health data lands in DynamoDB. The Healthcheck table stores results from connectivity, stream quality, recording, and motion checks. The SceneChange table stores SIFT comparison results separately, likely due to the larger data payload (keypoint descriptors, similarity scores).

Email alerts are the primary notification channel. There is backlog work to send alerts to Immix (CS3-44) and to build a generic API for external consumers (CS3-42), but both are in the backlog and not actively staffed.

## Current State

CHM is the most mature H1.x product and is in maintenance mode. Most epics (Scene Change CS3-73, New Integrations CS3-74, Feature Enhancements CS3-72, Bug Fixes CS3-71) were last updated on March 9 and appear stale.
