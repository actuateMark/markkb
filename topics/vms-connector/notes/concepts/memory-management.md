---
title: "Memory Management"
type: concept
topic: vms-connector
tags: [connector, memory, jemalloc, numpy, buffer-pool, GIL, TurboJPEG, image-cache, fragmentation]
created: 2026-04-15
updated: 2026-04-15
sources:
  - "[[worklog-optimization-research]]"
  - "[[worklog-sharding-strategy]]"
author: kb-bot
---

# Memory Management

Memory is the scarcest resource in the vms-connector. The deployment formula `cameras * 32MB + 500MB base` (documented in the [[vms-connector]] summary) sets the Kubernetes memory request, and VPA over-provisioning (ENG-78) already inflates actual requests to 2x this target. Every optimisation in the memory path directly reduces infrastructure cost across the fleet of ~32K cameras.

## The 32MB/Camera Budget

A single camera at 720p resolution (1280x720x3 channels) produces numpy frames of ~2.7 MB each. At the default cache size of 15 frames (covering the TTL window plus pipeline depth), raw frame storage alone consumes ~40 MB. Adding JPEG-encoded copies (~100-200 KB each), pipeline packet overhead, motion detection background frames, and per-camera thread stacks, the steady-state RSS lands at approximately 32 MB per camera. This budget assumes [[actuate-image-cache]] eviction works correctly -- a single leaked frame reference can grow RSS by megabytes.

## PooledTTLImageCache and FrameBufferPool

The dominant memory management innovation is `PooledTTLImageCache` in [[actuate-image-cache]], which replaced the plain `TTLImageCache` as the production default. The problem it solves: glibc's memory allocator (`ptmalloc2`) handles small allocations well but fragments badly when the application repeatedly allocates and frees large blocks (2-4 MB numpy arrays). Over hours of operation, glibc hoards freed memory in per-thread arenas rather than returning it to the OS, causing RSS to grow monotonically -- a pattern visible in [[new-relic|New Relic]] as a slow upward memory trend that never stabilises.

`FrameBufferPool` addresses this by recycling numpy arrays. When a frame is evicted from the cache (TTL expiry, LRU eviction, or explicit delete), its backing numpy array is returned to a per-shape pool (`defaultdict(deque)`) rather than freed. The next `set_frame()` call acquires a buffer from the pool and copies into it via `np.copyto()`, reusing the same virtual memory mapping. This eliminates the malloc/free churn that causes fragmentation.

Key design details:

- **Shape-keyed pools:** Buffers are pooled by `(height, width, channels)` tuple, so resolution changes (e.g., main/sub stream switching) don't poison the pool with wrong-sized buffers.
- **Streak-based eviction (M6):** Old shape pools are only cleared after 10 consecutive frames at a new resolution, preventing pool thrashing during brief main/sub stream flapping.
- **Double-release protection (C2):** A `_released_ids` set tracks buffer identity to prevent the same array from being released twice -- critical because `PoolAwareTTLCache` can trigger eviction from both `expire()` and `popitem()` during a single `__setitem__` call.
- **Copy-on-get:** `get_frame()` returns `frame.copy()` rather than the pooled buffer itself, ensuring callers never hold references to pooled arrays that could be overwritten on reuse. This creates ~108 MB/sec alloc churn at 24 cameras / 3 FPS / 720p, which is why jemalloc is essential.
- **Max pool size of 2:** Each camera keeps at most 2 spare buffers per resolution. This caps pool memory at ~5.4 MB per camera (2 * 2.7 MB at 720p) while achieving >90% hit rates in steady state.

## jemalloc Allocator Tuning

The connector Docker images `LD_PRELOAD` jemalloc to replace glibc's allocator. jemalloc uses thread-local caches with background dirty-page decay, returning memory to the OS much more aggressively than glibc. Without jemalloc, the copy-on-get pattern in `PooledTTLImageCache` would create rapid alloc/free cycles of transient numpy arrays that glibc fragments, negating the pool's benefits.

Critical fork-safety detail: jemalloc kills its background thread after `fork()` via `pthread_atfork`. In [[sharding|sharded deployments]], `AnalyticsSiteManager.run()` must re-enable it post-fork with `mallctl("background_thread", ...)` so dirty page decay continues in child processes. Without this, child process RSS grows without bound.

## TurboJPEG GIL Release

JPEG encoding is the most frequent CPU-intensive operation in the pipeline -- every frame must be encoded before inference submission. The `TurboJpegEncodeStep` in [[actuate-pipeline]] uses libturbojpeg (via PyTurboJPEG) instead of [[opencv-entity|OpenCV]]'s `cv2.imencode()`. The performance advantage is 2-3x faster encoding, but the more important benefit is GIL behaviour: TurboJPEG's C library releases the GIL during the encoding operation, allowing other camera threads in the same shard to run concurrently. `cv2.imencode()` holds the GIL for most of its execution, creating a serialisation point for all threads in the process.

The `PipelineFactory._get_encode_step()` method selects TurboJPEG by default (`use_turbojpeg = True`) with a graceful fallback to [[opencv-entity|cv2]] if the library is not installed. The import is deferred (lazy) because `turbojpegencode_step.py` has an unconditional top-level `from turbojpeg import TurboJPEG` that would fail at module load time on systems without the native library.

## Frame Lifecycle and Explicit Deletion

Frames follow a deterministic lifecycle managed by the [[pipeline-architecture]]:

1. **Capture:** The puller decodes a frame and stores it in the image cache via `set_frame()`.
2. **Encode:** `TurboJpegEncodeStep` (or `Cv2EncodeStep`) generates JPEG bytes and stores them via `set_frame_jpg_bytes()`.
3. **Inference + Post-processing:** The frame is read from cache as needed by pipeline steps.
4. **Evict numpy:** After encoding, the raw numpy array can be evicted via `evict_frame_numpy()`, keeping only the compact JPEG bytes. This halves per-frame memory from ~2.7 MB to ~150 KB.
5. **Explicit delete:** `CleanupStep` populates `result.frames_to_delete`. The camera's `finish_pipeline()` collects these into `_pending_frame_deletions`, and `_delete_pending_frames()` runs after alert sending completes, returning pooled buffers via `delete_frame()`.
6. **TTL fallback:** A background `expire_items` thread (15-second interval) catches frames that slipped through explicit deletion -- e.g., after pipeline crashes or abort signals.

## Multiprocessing Memory Overhead

[[Sharding]] creates separate Python processes, each carrying a full copy of pre-fork state. The empirical finding from [[worklog-sharding-strategy]] is stark: crossing a single shard boundary incurs 50-80% CPU overhead and proportional memory duplication. Each shard maintains its own `PooledTTLImageCache` instances, jemalloc arenas, and [[inference-pool|AsyncInferencePool]]. The memory formula scales linearly within a shard but has step-function jumps at shard boundaries, which is why the default shard size was raised to 24 and per-site tuning is planned.

## Monitoring

Memory health is observable through several channels:

- **`FrameBufferPool.get_stats()`:** Returns hit rate, miss count, and per-shape pool sizes. A hit rate below 80% suggests resolution instability or cache sizing issues.
- **[[new-relic|New Relic]] RSS tracking:** Steady-state RSS should plateau after the first few minutes of operation. Monotonic growth indicates a leak or jemalloc misconfiguration.
- **`MemoryError` in `get_frame()`:** The `PooledTTLImageCache` catches `MemoryError` on the `frame.copy()` call and returns `None` rather than crashing, logging a warning. Repeated occurrences indicate the pod is at its memory limit.
