---
type: concept
topic: actuate-libraries
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
incoming:
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/fleet-architecture/notes/concepts/library-decomposition-required.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/vms-connector/notes/concepts/motion-detection-internals.md
  - topics/vms-connector/notes/concepts/sliding-window-mechanics.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
  - topics/vms-connector/notes/syntheses/performance-optimization-landscape.md
incoming_updated: 2026-05-01
---

# Filter Architecture

The [[actuate-filters]] library (v2.0.4) implements a set of detection filter classes that sit between the inference step and the observer step in the video analytics pipeline. Each filter accepts a list of `Detection` objects from [[actuate-inference-objects]] and returns a filtered subset. Filters are composed in sequence within [[actuate-pipeline-objects]]'s pipeline types, forming a chain that progressively narrows raw model output to actionable detections.

## The BaseFilter Pattern

All filters inherit from a common abstract base class, `BaseFilter`. This ABC defines the `filter(detections)` contract: accept a list of detections, return a filtered list. The base class also provides shared infrastructure for logging, metrics, and configuration access. Concrete filters implement the filtering logic while conforming to a uniform interface that the pipeline can invoke polymorphically.

This pattern means adding a new filter type requires only subclassing `BaseFilter` and implementing `filter()`. The pipeline does not need to know which specific filters are in the chain -- it iterates over a list of `BaseFilter` instances and calls each in turn.

## Filter Implementations

### ConfidenceFilter

The simplest filter. Removes detections whose confidence score falls below a configurable threshold. Applied early in the chain to discard obvious false positives before more expensive filters run.

### LabelFilter

Keeps only detections matching a whitelist of class labels (e.g., `person`, `vehicle`). This gates which object types the pipeline processes downstream. Different camera configurations may enable different label sets depending on the analytics features deployed.

### LabelwiseConfidenceFilter

A more granular version of the confidence filter that applies per-label thresholds. For example, `person` detections might require 0.6 confidence while `vehicle` detections need only 0.4. This accounts for the fact that detection models perform differently across object classes.

### IoUFilter

Removes duplicate detections of the same object by computing Intersection over Union (IoU) between detection pairs. When two detections overlap above a threshold, the lower-confidence one is discarded. This is effectively a non-maximum suppression (NMS) step, complementing any NMS already performed by the model server. IoU computation delegates to [[actuate-math]].

### StationaryFilter

Identifies objects that have not moved between frames by comparing current detections against a maintained history of prior positions. Objects flagged as stationary receive a `STATIONARY_VEHICLE` tag via [[actuate-inference-objects]]'s `DetectionTag` system. This filter is important for loitering detection -- [[actuate-connector-observers]]'s `LoitererObserver` uses stationary status to determine dwell time.

### BlacklistFilter

Compares detections against known blacklists (license plates, faces) loaded from [[actuate-daos]]'s `BlacklistDAO`. Matching detections are flagged for the `BlacklistObserver` in [[actuate-connector-observers]]. This filter bridges the [[detection-pipeline|detection pipeline]] with the access-control use case.

### PolyZoneFilter (ignore_polygonal_zones)

Removes detections whose bounding boxes fall within configured polygonal [[ignore-zones|ignore zones]]. Uses Shapely geometry to compute intersection between detection bounding boxes and zone polygons. Zones are defined per-camera in [[actuate-config]]'s `CameraConfig` and typically mask areas like roads, trees, or sky that produce irrelevant detections. The [[actuate-viz]] library can render these zones as semi-transparent overlays for debugging.

## Pipeline Integration

Within the pipeline (see [[actuate-pipeline-objects]]), filters are applied in a defined order after inference and before observer dispatch. A typical chain looks like:

1. **LabelFilter** -- restrict to configured object classes
2. **ConfidenceFilter** or **LabelwiseConfidenceFilter** -- remove low-confidence detections
3. **PolyZoneFilter** -- mask [[ignore-zones|ignore zones]]
4. **IoUFilter** -- deduplicate overlapping boxes
5. **StationaryFilter** -- tag stationary objects
6. **BlacklistFilter** -- flag blacklist matches

The ordering matters: applying the label filter first reduces the input to subsequent (potentially more expensive) filters. The stationary filter must run after deduplication to avoid comparing an object against its own duplicate.

## Planned Consolidation with inference-api

There is a planned consolidation where some filter logic currently in [[actuate-filters]] will move closer to the inference layer. The goal is to push simple filters (confidence, label) to the model server side via the inference API, reducing the volume of detections that traverse the network. More complex filters (stationary, blacklist, poly-zone) will remain client-side because they require state or configuration not available at the model server. This split aligns with the broader migration from [[actuate-classic-inference-client]] to [[actuate-inference-client]], where the new client's `infer()` method already accepts a confidence threshold parameter, effectively performing server-side confidence filtering.

## Relationship to Observers

Filters do not trigger alerts themselves -- they prepare the detection list for the observers in [[actuate-connector-observers]]. The `ObservableManager` dispatches the filtered detection list to all attached observers, which then apply their own behavioral logic (dwell time, trajectory analysis, blacklist matching). The clean separation means filter changes affect detection quality without touching alert logic, and observer changes affect alert behavior without touching detection filtering.
