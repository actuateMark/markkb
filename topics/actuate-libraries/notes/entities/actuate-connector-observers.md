---
title: "actuate-connector-observers"
type: entity
topic: actuate-libraries
tags: [library, integration-alerting, observer-pattern, detection-pipeline, tracking]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-connector-observers

Stateful observer classes that interpret video analytics pipeline results and trigger alerts. This library implements the Observer design pattern to decouple detection processing from the connector's main pipeline loop. Version **3.6.18**.

## Purpose

After the inference pipeline produces detections on each frame, these observer classes consume the results, maintain tracking state across frames (loitering timers, line-crossing trajectories, object persistence), and decide when to fire alerts through [[actuate-alarm-senders]]. Each observer type corresponds to a distinct analytics feature.

## Observer Types

| Observer | Module | Description |
|---|---|---|
| `LoitererObserver` | `loiterer_observer.py` | Abstract base for loitering detection. Tracks objects via BoTSORT, monitors dwell time, opens/closes detection windows based on configurable `window_length`. |
| `PersonLoitererObserver` | `person_loiterer.py` | Concrete loiterer for person class detections. |
| `VehicleLoitererObserver` | `vehicle_loiterer.py` | Concrete loiterer for vehicle class detections. |
| `LineCrossingObserver` | `line_crossing_observer.py` | Abstract base for line-crossing detection. Tracks object centroids relative to a configured line, detects directional crossings (A-to-B, B-to-A), with diagonal line normalization. |
| `PersonLineCrossingObserver` | `person_linecrossing.py` | Concrete line-crossing for person class. |
| `VehicleLineCrossingObserver` | `vehicle_linecrossing.py` | Concrete line-crossing for vehicle class. |
| `BlacklistObserver` | `blacklist_observer.py` | License plate / face blacklist matching. Uses `BlacklistFilter` from `actuate-filters` to compare detections against known lists. |
| `PeopleFlowObserver` | `people_flow.py` | People counting and heatmap generation. Tracks cumulative person counts over time, persists hourly heatmaps and flow data via `people_flow_dao`. |
| `LeftObjectObserver` | `left_object_detection.py` | Abandoned/left object detection. Uses background subtraction and contour analysis (via `skimage.measure`) to identify objects that remain stationary beyond a configured threshold. |
| `DummyObserver` | `dummy_observer.py` | No-op observer for testing or placeholder use. |

## Key Classes

**`BaseObserver`** (abstract) -- Defines the observer interface. Holds a dict of `MultiAlertSender` instances keyed by product name, plus a reference to the shared `ImageCache`. Abstract methods: `notify()`, `update()`, `endrun()`. The `update()` method receives pre-captured numpy frames and JPEG bytes that are shared across all observers and must not be modified in-place.

**`ObservableManager`** -- Central dispatcher that manages observer lifecycle. `attach(observer)` registers observers; `notify(observable, callback, image_cache)` pre-captures the frame on the caller thread (preventing cache race conditions) then submits `update()` to each observer via a single-worker `ActuateThreadPoolExecutor`. Supports an optional `_camera_lock` for serialized processing.

## Detection Window Lifecycle

Loiterer and line-crossing observers manage detection windows (`WindowDataPacket`):

1. **Open**: First alert-worthy detection triggers window creation with a `window_id` derived from `{custcam_id}{label}{timestamp}`.
2. **Active**: Each frame's capture timestamp is appended; frames are saved to S3 via `save_frame`.
3. **Close**: After `window_length` seconds elapse. Timestamp list is persisted via `window_ids_dao.create_detection_window()`.
4. **Force-close**: On `endrun()`, any open windows are closed.

## Shared Utilities

`create_coors(obj)` in `observer_shared.py` converts raw detection tuples `(label, score, [x, y, w, h])` into BoTSORT format: `[x1, y1, x2, y2, score, class_label]` where `class_label` is `0` for person, `1` for vehicles (including bicycle, car, motorcycle, bus, truck, machinery).

## Public API

The primary public API is the observer instantiation and the `ObservableManager` attach/notify pattern. Consumers create concrete observers with their required configuration, attach them to an `ObservableManager`, and the manager dispatches pipeline frames to all attached observers.

## Dependencies

- `actuate-alarm-senders` -- `MultiAlertSender` for alert dispatch
- `actuate-config` -- `CameraConfig`, `StreamDeploymentConfig`, `BaseConnectorConfig`
- `actuate-pipeline-objects` -- `ImageDataPacket`, `WindowDataPacket`, `get_model_response`
- `actuate-filters` -- `BlacklistFilter`, `ignore_polygonal_zones`
- `actuate-botsort` -- `BoTSORT` tracker (loiterer observers)
- `actuate-daos` -- `DaoManager` for persistence (metrics, windows, S3)
- `actuate-frames` -- `save_frame` for S3 frame persistence
- `actuate-sort` -- sorting utilities
- `actuate-imutils` -- image manipulation (left object detection)
- `actuate-image-cache` -- `ImageCache` for frame retrieval
- `actuate-threadpool`, `actuate-inference-objects`

## Consumers

- `vms-connector` and other connector services -- instantiate observers and attach them to the `ObservableManager` during camera stream setup

## Notable Patterns

- **Observer pattern** with pre-captured frame sharing: frames are captured once on the caller thread and shared read-only across all observers to prevent cache expiration races.
- **Thread-pool dispatch**: `ObservableManager` uses a 1-worker executor, optionally with a camera lock for full serialization.
- **Abstract/concrete split**: `LoitererObserver` and `LineCrossingObserver` are abstract bases; person and vehicle variants are separate concrete classes that configure class-specific tracking parameters.
- **Shapely geometry** used for ignore zone intersection calculations and line-crossing direction detection.
