---
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [chm, sift, scene-change, actuate-suddenscenechange, computer-vision]
incoming:
  - topics/actuate-libraries/notes/entities/actuate-daos.md
  - topics/actuate-libraries/notes/entities/actuate-healthcheck-objects.md
  - topics/actuate-libraries/notes/entities/actuate-suddenscenechange.md
  - topics/camera-health-monitoring/_summary.md
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/concepts/health-check-types.md
  - topics/integrations/vch/_summary.md
  - topics/team-structure/notes/entities/mark-barbera.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-27
---

# Scene Change Detection

Scene change detection in [[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]] (CHM) uses the `actuate-suddenscenechange` library to identify when a camera's field of view has been physically altered. This is a critical security capability -- camera tampering (covering, rotating, or repositioning a camera) is a common precursor to criminal activity.

## The actuate-suddenscenechange Library

`actuate-suddenscenechange` is an internal Actuate library that implements SIFT-based image comparison. It is a standalone component used by the CHM product to detect tampering and environmental changes to camera views.

## How SIFT Works

SIFT (Scale-Invariant Feature Transform) is a classical computer vision algorithm that detects and describes local features in images. It was chosen for scene change detection because of its robustness to changes in scale, rotation, and illumination -- properties that make it well-suited for comparing camera frames taken at different times under varying lighting conditions.

### The Detection Pipeline

1. **Reference image capture** -- When a camera is first configured (or when the reference is manually updated), the system captures a baseline frame and extracts SIFT keypoints and descriptors. These represent the stable structural features of the scene: edges of buildings, corners of doorways, signage, fixed objects.

2. **Periodic comparison** -- At regular intervals, CHM captures a current frame from the camera and extracts its SIFT keypoints.

3. **Keypoint matching** -- The system matches keypoints between the reference and current frames using descriptor similarity. Good matches indicate features that exist in both frames at similar relative positions.

4. **Similarity scoring** -- The ratio of matched keypoints to total keypoints produces a similarity score. A high score means the scene is structurally unchanged. A low score indicates the camera's view has shifted significantly.

5. **Threshold evaluation** -- If the similarity score drops below a configured threshold, a scene change event is recorded in the SceneChange DynamoDB table and an alert is generated.

### Why SIFT Over Simpler Methods

Simpler approaches like pixel-difference or histogram comparison would trigger on any change -- a cloud passing overhead, lights turning on, or a vehicle parking in frame. SIFT's feature-based approach is robust to these transient changes because it matches structural landmarks rather than raw pixel values. A parked car does not eliminate the building corners, doorframes, and signage that anchor the keypoint set.

However, SIFT is not immune to false positives. Gradual changes like seasonal foliage, accumulated snow, or new construction can slowly shift the keypoint landscape until the reference no longer matches. This is why CS3-31 (auto-update reference images) is a Highest-priority backlog item -- it would allow the system to periodically refresh its reference baseline, accommodating legitimate gradual change while still catching sudden tampering.

## Data Storage

Scene change results are stored in a dedicated SceneChange table in DynamoDB, separate from the general Healthcheck table used by other [[health-check-types]]. This separation likely reflects the richer data payload: SIFT results include keypoint counts, match ratios, and potentially the descriptors themselves for debugging.

## Limitations and Known Issues

- **Reference staleness** -- Without auto-update (CS3-31), references drift over time, increasing false positive rates
- **Nighttime performance** -- SIFT keypoint detection degrades in low-light conditions where features become less distinct
- **Per-camera configuration** -- CS3-58 (Ready to Deploy) would allow per-camera tuning of detection thresholds, addressing the reality that some cameras have more dynamic scenes than others

## Relationship to Watchman

CHM's scene change detection patterns are listed as reused technology in [[watchman/_summary|Actuate Watchman]]. The Connectivity Agent or a health monitoring subsystem will likely incorporate `actuate-suddenscenechange` to detect tampering as part of [[watchman-repo|Watchman]]'s camera health layer.
