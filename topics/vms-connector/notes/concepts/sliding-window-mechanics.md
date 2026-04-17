---
title: "Sliding Window Mechanics"
type: concept
topic: vms-connector
tags: [connector, pipeline, sliding-window, detection-window, alerting, threshold, DynamoDB]
created: 2026-04-15
updated: 2026-04-15
sources:
  - "[[worklog-tech-doc-video-pipeline]]"
  - "[[worklog-rearch-main-loop]]"
author: kb-bot
---

# Sliding Window Mechanics

The sliding window is the temporal gating mechanism that decides when raw detections become actionable alerts. Implemented in `SlidingWindowStep` within [[actuate-pipeline]], it sits between the [[filter-architecture|filter chain]] and the alert dispatch path in the [[pipeline-architecture]]. Every detection product (intruder, weapon, fire/smoke) uses a sliding window to count confirmed detections over time before triggering an alert, preventing single-frame false positives from reaching customers.

## Core Data Structure

The window state lives on `WindowDataPacket` from [[actuate-pipeline-objects]], nested inside each `ProductDataPacket`. The `metric_counter` dict maps label names to `WindowDataPacket` instances -- one window per detectable class per product. This state is carried forward between frames via the camera's `last_data` reference on `ImageDataPacket`, making the window effectively stateful despite the [[pipeline-architecture]]'s stateless step design.

Key fields on `WindowDataPacket`:

| Field | Purpose |
|-------|---------|
| `window_id` | Composite key: `{product_name}{label}{timestamp}`. `None` when window is closed. |
| `in_alert` | Whether the window is currently open and tracking. |
| `confirmed_frame_count` | Count of frames with a confirmed detection (incremented by `hit()`). |
| `thresh` | Number of confirmed frames required to trigger an alert. |
| `remaining_frame_count` | Countdown frames until window closure. |
| `window_length` | Duration parameter controlling window lifetime. |
| `window_length_absolute` | Boolean selecting absolute vs relative mode. |
| `alert_sent` | Prevents duplicate alerts within a single window. |
| `alert_pending` | Deferred alert flag for tag-zone windows. |
| `approx_capture_timestamps` | Accumulated timestamps written to DynamoDB on close. |

## Window Lifecycle

### 1. Open

When `CheckConfirmationStep` (upstream) populates `confirmed_detection_labels` on the product and the label's window has `window_id = None`, `SlidingWindowStep.open_window()` fires. It generates the `window_id`, sets `in_alert = True`, records `window_start_timestamp`, and initialises `remaining_frame_count` to `denominator - thresh + 1`. If the feature uses MP4 clips, it signals `PipelineSignal.motion_off` to suppress motion gating and capture continuous video.

### 2. Active -- Threshold Counting

Each frame with the window open invokes `bump_window()` and decrements `remaining_frame_count` by the frame gap (estimated from FPS and time delta). When a confirmed detection arrives, `hit()` increments `confirmed_frame_count`. Once `confirmed_frame_count >= thresh`, `threshhold_reached()` fires.

### 3. Threshold Reached -- Alert or Defer

The behaviour on threshold crossing depends on the feature's tag-zone configuration:

- **Standard (no tag zones):** Sets `send_alert = True` on the window. The camera's `process_result()` reads this flag and dispatches the alert immediately via `trigger_alert()`.
- **Tag zones enabled:** Sets `alert_pending = True` instead. The alert is deferred until the window closes, so tag-zone hit counts from later frames can be included in the alert message. This deferred path is what motivated the [[s3-frame-fallback]] feature -- the LRU cache may evict the trigger frame before the deferred alert fires.

After threshold is reached, `reset_hits()` clears the counter so additional threshold crossings within the same window can re-fire (for ongoing events).

### 4. Close

A window closes when either condition is met:

- **Absolute mode** (`window_length_absolute = True`): Wall-clock time since `window_start_timestamp` exceeds `window_length` seconds. This gives a fixed-duration window regardless of frame rate.
- **Relative mode** (`window_length_absolute = False`): `remaining_frame_count` drops to zero. Each confirmed detection resets the countdown to `window_length * fps`, so continuous detections extend the window indefinitely (a "rolling" window).

On close, `close_window()` writes the accumulated `approx_capture_timestamps` to DynamoDB's `WindowIdsV2` table via the executor, resets all window state, and stores the old ID in `prev_window_id` for deferred alert resolution. If a deferred alert was pending but unsent, `prev_alert_pending` is set so `send_alerts()` can still fire it via the previous window context.

### 5. Force-Close (Shutdown)

During `endrun()`, the [[observer-pattern]] and camera shutdown logic force-close any open windows. `flush_deferred_alerts()` drains pending deferred alerts. This is the path where the [[s3-frame-fallback]] is most critical -- frames are likely expired from cache during a shutdown flush.

## Absolute vs Relative Mode

The mode selection is a per-feature configuration that changes the window's behavioural model:

**Absolute mode** is used for products where event duration matters (e.g., weapon detection with a 30-second confirmation window). The window opens for exactly N seconds regardless of detection density. This prevents runaway windows on cameras with persistent false positives.

**Relative mode** is the default for intruder detection. The countdown resets on each confirmed detection, so a continuous intrusion event stays in a single window. The window only closes when the scene goes quiet for `window_length / fps` frames -- effectively a "cooldown timer."

## Relationship to DynamoDB Detection Windows

The `WindowIdsV2` table in DynamoDB stores a record per closed window, keyed by `window_id`. The record contains the list of `approx_capture_timestamps` that constituted the detection event. Downstream consumers ([[queue-consumer]], the admin UI, customer dashboards) use these records to reconstruct event timelines, correlate with S3-stored frames, and audit detection accuracy. The `window_id` format (`{product}{label}{timestamp}`) ensures uniqueness and enables efficient range queries per camera-product.

## Observer-Managed Windows

The [[observer-pattern|observers]] (loitering, line crossing) manage their own `WindowDataPacket` lifecycle independently. `SlidingWindowStep` skips these by checking `last_processed_time == 0` (the default for observer-created windows). This prevents the pipeline's sliding window logic from interfering with the observer's dwell-time or trajectory-based window management. The two window systems coexist on the same `metric_counter` dict but are mutually exclusive per label.

## Performance Considerations

The sliding window step itself is computationally cheap -- it performs no image processing, only counter arithmetic and timestamp comparisons. Its performance impact comes from the DynamoDB writes on window close, which are offloaded to a single-worker `ActuateThreadPoolExecutor` to avoid blocking the pipeline. The window's `thresh` and `window_length` parameters directly affect alert latency: lower thresholds fire faster but risk false positives, while longer windows delay alerts but improve precision. Tuning these per-product per-customer is a key operational lever documented in [[actuate-config]].
