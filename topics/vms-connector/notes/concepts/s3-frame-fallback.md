---
title: "S3 Frame Fallback for Alert Delivery"
type: concept
topic: vms-connector
tags: [alerts, s3, cache, frame-fallback, deferred-alerts]
jira: "ENG-93"
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# S3 Frame Fallback for Alert Delivery

Shipped in PR #1639 (ENG-93). Prevents alerts from being silently dropped when the in-memory frame cache expires before a deferred alert fires.

## The Problem

The [[pipeline-architecture]] stores captured frames in an LRU image cache keyed by capture timestamp. Most alert paths are synchronous — the frame is still warm in cache when `trigger_alert` is called. Deferred alerts are different: they are held in a pending state (e.g., waiting for a tag-zone hit count threshold or a window-close event) and may not fire until several seconds after the frame was captured.

When the LRU cache evicts the frame before the deferred path runs, `result.frame_jpg_bytes(self.image_cache)` returns `None`. `trigger_alert` receives `frame=None` and returns early without sending. The alert is silently dropped — no exception, no error log, just a missing `Sending event_info` entry.

This is the gap documented in the validate-release skill as "Phase 3: Alert Delivery (THE GAP THAT GETS MISSED)".

## The Tag-Zones Incident

The tag-zones feature introduced threshold-gated deferred alerts: an alert window would not fire until a minimum number of tag-zone intersections had accumulated. In production, the accumulation period was long enough that the LRU cache had already evicted the trigger frame by the time the alert was ready to send. The site showed 48 `flush_deferred_alerts: firing` log lines and zero `Sending event_info` lines. All 48 alerts were lost.

The unit test suite had 25 passing tests covering the dispatch path. Every test mocked `send_executor.submit` and verified it was called. None verified that `trigger_alert` would succeed with the arguments provided. The bug lived entirely on the other side of that async boundary.

## The Solution

Rather than extend the LRU TTL (which has memory cost implications — see [[inference-pool]] for cache sizing context), PR #1639 adds a per-call S3 fallback: if `frame_to_send is None` and a `window_id` is available, `BaseStreamCamera` looks up the frame from the enriched frame table in DynamoDB and fetches the image bytes from S3.

The lookup is lazy and session-scoped. Within a single `process_result` call, results are memoised in a local `s3_fallback_cache` dict keyed by `window_id` to avoid duplicate DynamoDB/S3 round-trips for the same window when both `fire_now` and `fire_deferred` are true in the same cycle.

## How It Works in the Code

All logic lives in `camera/shared/base_stream_camera.py` in `BaseStreamCamera`, making it available to every integration subclass.

`_fetch_frame_from_s3(window_id, approx_capture_timestamp)` is the retrieval primitive. It queries `enriched_frame_dao.get_frames(window_id, approx_capture_timestamp, limit=1)` to get the DynamoDB item, then calls `s3_dao.get_image_bytes(bucket, key)` to retrieve the raw bytes, decodes with `cv2.imdecode`, and returns `(numpy_frame, jpg_bytes)`. On any failure it returns `(None, None)` and logs a warning rather than raising, preserving the existing graceful-degradation contract of `trigger_alert`.

The fallback is applied in three places:

1. **`process_result` — `fire_now` / `fire_deferred` path** (around line 926): before submitting to `send_executor`, checks `frame_to_send is None` and calls into `s3_fallback_cache`, populating it via `_fetch_frame_from_s3` on first miss for that `window_id`.
2. **`process_result` — `fire_prev_deferred` path** (around line 953): same pattern, keyed on `window.prev_window_id` for alerts that were displaced when a new window opened.
3. **`flush_deferred_alerts`** (around line 1055): called at run-end to drain any still-pending alerts. Applies `_fetch_frame_from_s3` directly (no local cache needed — each window appears at most once). Logs `frame_source=s3` or `frame_source=none` alongside the existing firing log so overnight log checks can distinguish the three cases.

The [[generic-patrol-mode]] alert path follows the same `BaseStreamCamera` code path and benefits automatically.

## Observability

Check these log patterns in [[new-relic|New Relic]] to verify the fallback is working correctly:

- `S3 frame fallback: retrieved frame for window` — fallback fired and succeeded
- `S3 frame fallback: failed to fetch frame for window` — fallback attempted but S3/DDB lookup failed (frame still dropped, but now visible)
- `frame_source=s3` in `flush_deferred_alerts` firing lines — confirms deferred alerts used fallback rather than cache

A healthy overnight run with deferred alerts should show `Sending event_info` count matching `flush_deferred_alerts: firing` count, and zero `Frame expired from cache` errors.

## Pattern Generalization

The S3 frame fallback is an instance of a broader pattern: **fallback data retrieval when a hot cache misses on a deferred path.** Future features that defer processing (queued alerts, batched sends, async analysis) will face the same issue — data captured into a short-lived cache may not survive to the deferred consumer. The pattern to follow:

1. Always check the hot cache first (zero-cost happy path)
2. On miss, fall back to durable storage (S3/DynamoDB) keyed by a stable identifier (window_id, alert_id, etc.)
3. Memoize within the call to avoid redundant lookups
4. Log the fallback source so overnight monitoring can distinguish hot-path vs fallback delivery

## Related Notes

- [[pipeline-architecture]] — window lifecycle, LRU cache, detection state machine
- [[inference-pool]] — async inference, concurrency control, frame retention budget
- [[generic-patrol-mode]] — deferred alert pattern this fix primarily protects
