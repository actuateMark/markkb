---
title: "Image Cache Strategies"
type: concept
topic: actuate-libraries
tags: [library, image-cache, LRU, TTL, TLRU, pooled, numpy, fragmentation, memory, performance]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Image Cache Strategies

The [[actuate-image-cache]] library (v1.2.0) provides four implementations of the `ImageCache` abstract base class, each solving a different operational constraint in the [[pipeline-architecture]]. All four share the same interface (`get_frame`, `set_frame`, `set_frame_jpg_bytes`, `get_frame_jpg_bytes`, `delete_frame`, `evict_frame_numpy`, `set_frame_from_jpeg`), making them drop-in replaceable. The choice of implementation is made at camera construction time based on integration type and customer configuration.

## The Four Implementations

### 1. LRUImageCache -- The Simple Baseline

Built on `cachetools.LRUCache`. Evicts the least-recently-used entry when the cache reaches `maxsize` (default 15). No time-based expiration. Thread-safe via a single `threading.Lock`.

**When used:** Local development, healthcheck pipelines, and integrations where frame arrival is predictable and the pipeline processes frames faster than they arrive (no backlog). Also used as the reference implementation for testing.

**Tradeoffs:** Simple and fast, but frames can linger indefinitely if the cache is not full. No protection against stale frames -- a temporarily disconnected camera could leave old frames in cache that downstream code reads as "current." The lack of TTL means memory is reclaimed only via LRU eviction pressure, which requires the cache to stay full.

### 2. TTLImageCache -- Time-Bounded Eviction

Built on `cachetools.TTLCache`. Entries expire after `ttl` seconds (default 3), regardless of access pattern. A background `expire_items` thread wakes every 15 seconds to proactively clear expired entries when the camera is idle (no new frames for 15+ seconds). Thread-safe via separate get/set locks.

**When used:** The previous production default before `PooledTTLImageCache` was introduced. Still used for integrations where the buffer pooling overhead is not justified (very low camera counts, short-lived batch jobs).

**Tradeoffs:** Solves the stale-frame problem that LRU misses. The 3-second default TTL aligns with the typical pipeline processing window -- a frame enters the cache, traverses inference and post-processing, and is consumed by alert dispatch within 1-2 seconds. The risk is that deferred alerts (tag zones, flush-at-shutdown) may fire after the TTL expires, leading to the frame-loss bug that motivated [[s3-frame-fallback]]. The separate get/set locks were a legacy design; `PooledTTLImageCache` unified to a single `RLock`.

### 3. TLRUImageCache -- Adaptive TTL

Built on `cachetools.TLRUCache` (Time-aware LRU). The TTL per entry is dynamically computed by `set_ttl()` based on the frame queue depth: when the queue is shallow (pipeline keeping up), TTL is short (~1 second); when the queue is deep (pipeline falling behind), TTL extends to give frames more time to be processed before expiration.

**When used:** Experimental. Designed for high-FPS or variable-throughput integrations where a fixed TTL either evicts frames too early (during load spikes) or holds them too long (during idle periods). Requires a reference to the camera's frame `Queue` at construction time.

**Formula:** `time_to_live = 1 + (buffer_size * base_ttl) / 2`, where `buffer_size` is clamped to `[0, max_cache_size - max_cache_size/3]`. When the queue is empty, TTL is 1 second. When the queue is 2/3 full, TTL approaches `1 + (max_cache_size * base_ttl) / 3` -- roughly 3-5 seconds with default parameters.

**Tradeoffs:** Clever but adds complexity and coupling (the cache must know about the queue). Logging on every `set_ttl()` call (queue size, cache size, TTL) produces noisy output at scale. Not widely deployed as of April 2026.

### 4. PooledTTLImageCache -- Production Default

Built on a custom `PoolAwareTTLCache` (extending `cachetools.TTLCache`) paired with a `FrameBufferPool`. This is the production cache for all standard deployments. It solves the **numpy buffer fragmentation problem** that causes RSS growth in long-running connector processes.

**When used:** All production RTSP/stream-based integrations. Selected by default in the [[connector-factory]] camera construction path.

**The fragmentation problem:** Each 720p frame is a ~2.7 MB numpy array. The pipeline creates and discards these arrays at 1-3 FPS per camera. glibc's `ptmalloc2` allocator handles this poorly: freed large allocations are retained in per-thread arenas rather than returned to the OS, causing monotonic RSS growth over hours. See [[memory-management]] for the full analysis.

**How pooling solves it:** `FrameBufferPool` maintains a per-shape `deque` of recycled numpy arrays (max 2 per shape). When the cache needs to store a new frame, `pool.acquire(source_frame)` either pops a buffer from the pool and copies into it via `np.copyto()`, or falls back to `source_frame.copy()` if the pool is empty. When a cache entry is evicted (TTL, LRU, or explicit delete), its buffer is returned to the pool via `pool.release(buffer)`. All eviction paths are intercepted: `PoolAwareTTLCache` overrides both `expire()` (TTL) and `popitem()` (LRU) to release buffers, and `delete_frame()` releases before `del`.

**Thread safety:** A single `threading.RLock` guards all cache mutations and reads. The RLock (reentrant) is necessary because `TTLCache.__setitem__` internally calls `expire()` and `popitem()`, which also need the lock. The `copy-on-get` pattern (returning `frame.copy()`) ensures callers never hold references to pooled buffers, preventing use-after-reuse bugs.

**jemalloc dependency:** The copy-on-get pattern creates ~108 MB/sec of transient numpy allocations at 24 cameras / 3 FPS / 720p. Without jemalloc (`LD_PRELOAD`), glibc would fragment on these transient copies, negating the pool's benefit. See [[memory-management]] for jemalloc tuning.

## Lazy JPEG Decode

All four implementations share a common optimisation for integrations that receive JPEG snapshots rather than decoded video frames (JPG pullers, SQS pullers). `set_frame_from_jpeg()` stores only JPEG bytes with `[None, jpg_bytes]`, skipping the numpy allocation entirely. When `get_frame()` is called and the numpy slot is `None`, it lazily decodes via `decode_jpeg_bytes()` (TurboJPEG or cv2 fallback). The decode happens outside the lock to avoid blocking other cache operations. The decoded array is transient -- not cached back -- so it is allocated and freed in the caller's scope.

## Selection Guide

| Implementation | TTL | Pool | Use Case |
|---|---|---|---|
| `LRUImageCache` | No | No | Dev, healthcheck, batch |
| `TTLImageCache` | Fixed | No | Low-camera-count, legacy |
| `TLRUImageCache` | Adaptive | No | Experimental, variable-throughput |
| `PooledTTLImageCache` | Fixed | Yes | Production (all RTSP/stream) |

The migration path for new integrations is straightforward: start with `LRUImageCache` for local testing, switch to `PooledTTLImageCache` for production deployment. `TLRUImageCache` remains available as a research option for integrations with extreme throughput variability.
