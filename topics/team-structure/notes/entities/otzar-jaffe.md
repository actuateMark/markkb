---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, data-science, ppf, site-classification, yolov8, ignore-zones, classifyr]
---

# Otzar Jaffe

Otzar Jaffe is a data scientist at Actuate specializing in the PPF ([[pixels-per-foot|Pixels Per Foot]]) pipeline, site classification, [[ignore-zones|ignore zones]], and model development. His work underpins core automation features that reduce manual camera configuration effort.

## PPF Pipeline

Otzar develops and maintains the PPF ([[pixels-per-foot|Pixels Per Foot]]) pipeline, a key component of the [[settings-automation/_summary|Settings Automation (H1.4)]] initiative. PPF estimates the physical scale of objects in a camera's field of view by calculating how many pixels correspond to one foot of real-world distance. This metric is critical for setting detection sensitivity thresholds -- a person at 200 feet covers fewer pixels than one at 20 feet, so detection confidence thresholds must be calibrated per-camera. The pipeline feeds into the [[pixels-per-foot]] concept and the [[ppf-repo]] tooling. Accurate PPF values directly reduce false positives by preventing the system from alerting on objects that are too small or too far away to be actionable.

## Site Classification

Otzar works on automated site classification, which categorizes camera sites by type (e.g., parking lot, building entrance, perimeter fence, loading dock). Site classification enables automatic selection of detection models, sensitivity profiles, and ignore-zone templates -- replacing manual per-camera configuration that currently requires operator expertise.

## Ignore Zones

Closely related to site classification, Otzar develops automated ignore-zone generation. [[ignore-zones|Ignore zones]] mask out regions of a camera's field of view where detections should be suppressed (e.g., public sidewalks, busy roads, neighboring properties). See [[project-auto-ignore-zones]] for the broader initiative.

## YOLOv8 Entrance Model

Otzar trained a YOLOv8-based entrance detection model that identifies doorways, gates, and entry points in camera frames. This model supports the [[autopatrol/_summary|AutoPatrol (H1.2)]] initiative by enabling the system to focus patrol attention on entry/exit points.

## Classifyr

Otzar contributes to **Classifyr**, a classification service deployed via the [[kubernetes-deployments]] infrastructure. Classifyr provides real-time object classification as part of the [[detection-pipeline|detection pipeline]].

## See Also

- [[pixels-per-foot]] -- the PPF concept
- [[ppf-repo]] -- the PPF tooling repository
- [[project-auto-ignore-zones]] -- automated ignore zone initiative
- [[settings-automation/_summary|Settings Automation (H1.4)]] -- the parent initiative
