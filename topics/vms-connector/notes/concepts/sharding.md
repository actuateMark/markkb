---
title: "Camera Sharding"
type: concept
topic: vms-connector
tags: [connector, sharding, multiprocessing, scaling, GIL]
created: 2026-04-13
updated: 2026-04-14
sources:
  - "[[worklog-sharding-strategy]]"
author: kb-bot
---

# Camera Sharding

When a customer site has more cameras than the configured `shard_size` (default 24), the connector splits cameras across multiple Python processes to reduce GIL contention. This is managed by `ChunkedSiteManager` (`site_manager/connector/chunked_site_manager.py`).

## When Sharding Activates

The decision lives in `get_sharding_strategy()` in `connector_factories/shared/factory.py`. The logic:

1. **AutoPatrol/VCH/Patrol** integrations return a shard size of 2000, effectively disabling sharding -- these integrations handle cameras differently.
2. **Explicit config**: If `config.customer.shard_size` is set to a positive integer, that value is used (capped at `camera_count`).
3. **Default**: 24 cameras per shard. If total cameras <= 24, no sharding occurs.

In `generate_site()`, when `camera_count > shard_size`, a `ChunkedSiteManager` is created instead of the normal `AnalyticsSiteManager`.

## Fork Architecture

`ChunkedSiteManager.run()` performs the fork:

1. **Chunk distribution**: The `chunks()` method uses round-robin distribution, not sequential slicing. For 50 cameras with shard_size=24, it creates 3 chunks and distributes cameras [0,3,6...], [1,4,7...], [2,5,8...]. This balances camera load across shards.

2. **Shard construction**: For each chunk, an `AnalyticsSiteManager` instance is created with `in_shard=True`. This flag affects signal handler registration (deferred to post-fork) and logging (shard children re-initialize async logging).

3. **Site-level init**: Only the first shard runs `init_site_level_processes()` to avoid duplicating site-level metrics and monitoring.

4. **Fork boundary**: `Process(daemon=True, target=site.run)` forks each shard. This is the critical boundary -- all camera objects, pipelines, and configs are already built in the parent. Threads started during `__init__` (e.g., upload_slices, observer pools) do NOT survive the fork and must be restarted post-fork in `AnalyticsSiteManager.run()`.

5. **Parent role**: After forking, the parent starts a monitoring thread and enters a sleep loop. It handles SIGTERM by coordinating shutdown.

## Fork Safety Constraints

The fork model imposes strict rules documented in CLAUDE.md under "Fork-safety (multiprocessing)":

- **No threads in `__init__`**: Any `threading.Thread` started during factory build or `__init__` of pipeline steps, cameras, or clients will die in the fork. The `AnalyticsSiteManager.run()` method explicitly starts threads post-fork: the `AsyncInferencePool`, `upload_slices` threads, observer pool assignment, and GC collection thread.
- **Signal handlers post-fork**: The `if not self.in_shard` guard on signal registration in `__init__` is intentional. Shard children register their own SIGTERM handler in `run()` to avoid the parent's handler running in the child.
- **jemalloc re-init**: jemalloc kills its background thread after fork via `pthread_atfork`. `AnalyticsSiteManager.run()` re-enables it with `mallctl("background_thread", ...)` so dirty page decay continues in child processes.
- **Async logging re-init**: The parent's `QueueListener` thread dies in the fork. Shard children call `setup_async_logging()` in `run()` to rebuild the log pipeline.

## Graceful Shutdown

When `ChunkedSiteManager.endrun()` receives SIGTERM:

1. **Signal children first**: Sends SIGTERM to all child processes so they start their own `camera.endrun()` (closing detection windows, observer cleanup, inference pool shutdown) in parallel.
2. **Parent cleanup**: Concurrently sends `site_product_ended` events for all cameras via the event library.
3. **Join with deadline**: Waits up to 30 seconds for children to complete. K8s `terminationGracePeriodSeconds` is 90s, so parent events (~5-10s) plus child cleanup (~5s per camera with parallel threads) fits within budget.
4. **Logout**: Calls `logout()` on the first shard for any integration-specific session cleanup (e.g., Avigilon API logout).

## Memory Implications

Each shard process carries its own copy of all pre-fork state (~270 MB/camera steady-state RSS). The trade-off is explicit: smaller shards reduce GIL contention (each shard's cameras compete for the GIL only with each other) but increase total memory from process isolation overhead. GIL breakdown logging has confirmed that inference latency -- not GIL contention -- is typically the bottleneck, which is why the default shard size was raised to 24.

## Multiprocessing Cost (Empirical)

The single most expensive operation in the connector is crossing a shard boundary into multiprocessing. Empirical testing showed that splitting into multiple processes incurs a CPU increase of at least 50-80%. If even one additional camera can stay on the same process (e.g., 25 instead of 24), it saves approximately 0.5-2 CPU -- enough to offset CPU increases across 10 other sites.

## Dynamic Sharding (Future)

A long-term strategy has been proposed but not yet implemented:

1. **Short-term**: Determine the comfortable maximum cameras-per-process for a given native resolution/FPS combination and configure different shard sizes per-site rather than using a single default.
2. **Long-term**: Log per-site performance data to DynamoDB, analyse whether each site is lagging or over-provisioned, and set shard sizes dynamically based on observed performance.
