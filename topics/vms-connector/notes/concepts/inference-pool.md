---
title: "AsyncInferencePool AIMD Congestion Control"
type: concept
topic: vms-connector
tags: [connector, inference, async, AIMD, congestion-control, httpx]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/ai-models/notes/syntheses/yolo-vs-vlm-detection-future.md
  - topics/autopatrol/_summary.md
  - topics/autopatrol/notes/concepts/generic-patrol-mode.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/fleet-architecture/notes/concepts/inference-api-interaction.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
incoming_updated: 2026-05-27
---

# AsyncInferencePool AIMD Congestion Control

The `AsyncInferencePool` (`inference/async_inference_pool.py`) consolidates all HTTP inference calls within a shard onto a single asyncio event loop, replacing direct per-thread `requests.post()` calls. It implements AIMD (Additive Increase, Multiplicative Decrease) adaptive concurrency control to protect the inference server from overload.

## Problem Solved

Without the pool, each camera thread (20+ per shard) makes synchronous `requests.post()` calls to the inference server. Because `requests` holds the GIL during DNS resolution and connection setup, this creates a GIL convoy effect: threads serialize around the GIL lock even though they are logically doing independent I/O. At scale, this causes inference latency to spike and throughput to collapse.

## Architecture

The pool runs a single daemon thread (`async_inf_pool`) with its own `asyncio` event loop. Camera threads call `pool.post()`, which:

1. Submits an `_async_post()` coroutine to the event loop via `asyncio.run_coroutine_threadsafe()`.
2. Blocks on `future.result()` -- this releases the GIL so other camera threads can run.
3. Returns the `httpx` response to the caller.

The HTTP client is `httpx.AsyncClient` with `http2=False` and `Connection: close` headers (no keep-alive). The default executor is capped at 4 threads to prevent Python from spawning threads proportional to host CPU count (which in a container reads the host's cores, not the cgroup limit).

## AIMD Window

The pool maintains an adaptive concurrency window that controls how many inference requests can be in-flight simultaneously:

| Parameter | Value | Description |
|---|---|---|
| `INITIAL_WINDOW` | 48 | Starting concurrency |
| `WINDOW_FLOOR` | 8 | Minimum concurrency (never goes below) |
| `LATENCY_TARGET_MS` | 200 | Threshold for "healthy" response time |
| `DECREASE_FACTOR` | 0.75 | Multiplicative decrease on bad signal |
| `max_concurrent` | 200 (default) | Hard ceiling |

**Additive increase**: On each response faster than 200ms, the window grows by `1/window` (slow, sublinear growth). This means the window grows by 1 full unit after `window` successful fast responses.

**Multiplicative decrease**: On each timeout, error, or response slower than 200ms, the window is cut to `window * 0.75`. This rapid contraction applies backpressure immediately when the server is saturated.

The slot mechanism uses an `asyncio.Event` (`_slot_available`). `_acquire_slot()` awaits the event when `in_flight >= int(window)`, and `_release_slot()` sets it after adjusting the window.

## Timing Instrumentation

The pool tracks three latency components for every request:

- **queue_ms**: Time from `post()` call to coroutine pickup (waiting for a concurrency slot).
- **network_ms**: Time for the actual HTTP round-trip.
- **gil_reacquire_ms**: Time from HTTP response to the calling thread getting the GIL back.

If total latency exceeds 300ms, a warning is logged with all three components plus the current window size and in-flight count. This makes it straightforward to diagnose whether slowness is from server saturation (high network_ms), local congestion (high queue_ms), or GIL contention (high gil_reacquire_ms).

## Resurrection

If the event loop thread dies (crash, unhandled exception), the next `post()` call detects `not self._thread.is_alive()` and recreates the entire pool under a lock (`_resurrect_lock`). The old loop's default executor is shut down to prevent thread leaks, and a resurrection counter is logged. This provides self-healing without requiring a full connector restart.

## Lifecycle

The pool is created in `AnalyticsSiteManager.run()` (post-fork in sharded deployments). It is shared across all cameras in the shard by setting `camera.yolo_client.inference_pool = self._inference_pool` for each camera. Shutdown is handled by `pool.shutdown()`, which:

1. Sets `_shutting_down = True` to reject new requests.
2. Closes the `httpx.AsyncClient` via `aclose()`.
3. Stops the event loop with `loop.call_soon_threadsafe(loop.stop)`.
4. Joins the loop thread with a 1-second timeout.
5. Shuts down the default executor.

## Integration Point

The `YoloClient` in `actuate-classic-inference-client` checks for an `inference_pool` attribute. If present, it routes `post()` calls through the pool instead of using `requests.post()` directly. This makes the pool opt-in and backward-compatible -- local dev without the pool falls back to synchronous requests.
