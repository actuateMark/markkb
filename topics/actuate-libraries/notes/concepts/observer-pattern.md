---
type: concept
topic: actuate-libraries
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
incoming:
  - topics/actuate-libraries/notes/entities/actuate-connector-observers.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/fleet-architecture/notes/concepts/library-decomposition-required.md
  - topics/vms-connector/notes/concepts/filter-pipeline-ordering.md
  - topics/vms-connector/notes/concepts/sliding-window-mechanics.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# Observer Pattern

The [[actuate-connector-observers]] library implements the Observer design pattern to decouple the video analytics pipeline's detection output from the alerting and analytics logic that acts on it. At the center sits the `ObservableManager`, which dispatches filtered detection results to a set of stateful observer instances. Each observer type implements a distinct analytics feature -- loitering, line crossing, intrusion, blacklist matching, people flow, or left-object detection -- and decides independently whether to fire an alert through [[actuate-alarm-senders]].

## ObservableManager Dispatch

The `ObservableManager` is the central dispatcher. The connector's camera thread creates one `ObservableManager` per stream, attaches the observers configured for that camera, and calls `notify()` on each pipeline frame.

The dispatch mechanism has a critical design choice: **pre-captured frame sharing**. Before notifying any observer, the manager captures the current frame from the [[actuate-image-cache]] on the caller thread. This prevents a race condition where the image cache evicts a frame (due to TTL or LRU pressure) between the time the first observer reads it and the time the last observer tries to. All observers receive the same pre-captured numpy array and JPEG bytes, which they must treat as read-only.

After capturing the frame, the manager submits each observer's `update()` method to a single-worker `ActuateThreadPoolExecutor` from [[actuate-threadpool]]. The single-worker design serializes observer processing per camera, preventing thread-safety issues in the observers' tracking state. An optional `_camera_lock` provides further serialization when needed.

## Observer Types

### Loiterer Observers

`LoitererObserver` is the abstract base for dwell-time detection. It tracks objects across frames using [[actuate-botsort]]'s `BoTSORT` tracker, monitoring how long each tracked object remains in the scene. When an object's dwell time exceeds the configured threshold, the observer opens a detection window and triggers an alert.

Concrete implementations: `PersonLoitererObserver` and `VehicleLoitererObserver` configure class-specific tracking parameters (match thresholds, label sets) while inheriting the dwell-time logic from the base.

### Line Crossing Observers

`LineCrossingObserver` is the abstract base for directional line-crossing detection. It tracks object centroids relative to a configured boundary line and detects when an object crosses from side A to side B (or vice versa). The implementation normalizes diagonal lines and handles edge cases with Shapely geometry from [[actuate-filters]].

Concrete implementations: `PersonLineCrossingObserver` and `VehicleLineCrossingObserver`.

### BlacklistObserver

Handles license plate and face blacklist matching. Uses the `BlacklistFilter` from [[actuate-filters]] to compare detections against known lists stored in [[actuate-daos]]'s `BlacklistDAO`. When a match is found, the observer triggers an alert with the matched identity.

### PeopleFlowObserver

Tracks cumulative person counts and generates heatmaps. Unlike the alert-focused observers, this one persists hourly flow data and heatmaps through [[actuate-daos]]'s `PeopleFlowDAO` for analytics dashboards rather than real-time alerting.

### LeftObjectObserver

Detects abandoned or left objects using background subtraction and contour analysis (via `skimage.measure`). Objects that remain stationary beyond a configured time threshold trigger an alert.

### DummyObserver

A no-op implementation used for testing and placeholder scenarios.

## Detection Window Lifecycle

Loiterer and line-crossing observers manage detection windows through [[actuate-pipeline-objects]]'s `WindowDataPacket`:

1. **Open** -- the first alert-worthy event creates a window with an ID derived from `{custcam_id}{label}{timestamp}`.
2. **Active** -- each subsequent frame's capture timestamp is appended to the window. Frames are persisted to S3 via [[actuate-frames]]'s `save_frame`.
3. **Close** -- after `window_length` seconds elapse, the window closes and its timestamp list is written to DynamoDB via [[actuate-daos]]'s `WindowIdsDAO`.
4. **Force-close** -- when the pipeline shuts down (`endrun()`), any open windows are immediately closed.

The window mechanism groups related detections into a single alertable event rather than firing per-frame alerts. This batching reduces alert fatigue and provides the downstream [[actuate-alarm-senders]] with a coherent package of frames and metadata.

## Relationship to Alarm Senders

Each observer holds a dict of `MultiAlertSender` instances from [[actuate-alarm-senders]], keyed by product name. When the observer decides to fire, it calls `trigger_alert()` on the relevant sender. The `MultiAlertSender` then fans out to every configured alert integration (Immix, Milestone, webhook, email, etc.) for that camera.

The factory functions in [[actuate-alarm-senders]] (`build_alert_senders`, `build_chm_alert_senders`, `build_clips_alert_senders`) construct the sender instances during connector initialization. The connector passes them to the observers at construction time, establishing the observer-to-sender binding.

## Shared Utilities

The `create_coors()` function in `observer_shared.py` converts raw detection tuples from [[actuate-inference-objects]] into the `[x1, y1, x2, y2, score, class_label]` format expected by [[actuate-botsort]]. Class labels are mapped numerically: `0` for person, `1` for vehicles (bicycle, car, motorcycle, bus, truck, machinery). This normalization ensures consistent tracker input regardless of the upstream model's label scheme.

## Design Implications

The observer pattern's strength is extensibility: adding a new analytics feature means creating a new observer class, attaching it in the connector's initialization, and the rest of the pipeline remains untouched. The cost is the shared-state complexity within each observer (tracking state, detection windows, timer logic) and the serialized single-worker dispatch, which means observer processing time directly impacts pipeline throughput.
