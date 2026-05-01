---
title: "Performance Optimization Landscape"
type: synthesis
topic: vms-connector
tags: [synthesis, performance, optimization, GIL, memory, inference, sharding, AIMD, TurboJPEG, GPU, fragmentation, congestion-control]
created: 2026-04-15
updated: 2026-04-15
sources:
  - "[[worklog-optimization-research]]"
  - "[[worklog-sharding-strategy]]"
  - "[[worklog-frame-gap-buffering]]"
  - "[[worklog-tech-doc-video-pipeline]]"
  - "[[worklog-temperature-adaptive-processing]]"
author: kb-bot
---

# Performance Optimization Landscape

This synthesis maps the vms-connector's known performance bottlenecks to the solutions implemented or proposed, cross-referencing the accumulated source notes, concept articles, and source code analysis. The connector processes video from ~32K cameras across a fleet of Kubernetes pods, making every per-frame microsecond multiply into significant infrastructure cost.

## Bottleneck Map

### 1. GIL Contention

**Problem:** The connector runs 24+ camera threads per shard, all competing for Python's Global Interpreter Lock. Before optimisation, the primary GIL contenders were: synchronous `requests.post()` for inference (holding GIL during DNS and connection setup), `cv2.imencode()` for JPEG encoding (holding GIL for the C call duration), and Shapely geometry operations in the [[filter-pipeline-ordering|stationary filter]].

**Solutions implemented:**

- **[[inference-pool|AsyncInferencePool]] (AIMD):** Consolidates all HTTP inference calls onto a single asyncio event loop running in a daemon thread. Camera threads call `pool.post()`, which submits a coroutine via `asyncio.run_coroutine_threadsafe()` and blocks on `future.result()` -- this **releases the GIL** so other camera threads can run. The httpx async client handles all HTTP I/O without holding the GIL. Timing instrumentation (queue_ms, network_ms, gil_reacquire_ms) makes it possible to diagnose whether slowness comes from server saturation, local congestion, or GIL contention.

- **TurboJPEG encoding:** `TurboJpegEncodeStep` in [[actuate-pipeline]] replaces `cv2.imencode()` with libturbojpeg, which releases the GIL during the C-level encoding operation. This is a 2-3x speedup and, more importantly, unblocks concurrent threads during the most frequent CPU-intensive pipeline operation. See [[memory-management]] for details.

- **Numpy vectorisation in StationaryFilterStep:** The bbox overlap mode (`_bbox_any_overlap()`) uses numpy operations that release the GIL, allowing other camera threads to run during the most expensive post-processing step. See [[filter-pipeline-ordering]].

- **[[Sharding]]:** The nuclear option. When GIL contention still limits throughput (typically above 24 cameras), the connector forks into multiple processes via `ChunkedSiteManager`. Each shard has its own GIL. The empirical cost is 50-80% CPU overhead per shard boundary, so the default shard size of 24 represents the sweet spot between GIL contention and multiprocessing overhead.

### 2. Memory Fragmentation

**Problem:** glibc's `ptmalloc2` allocator fragments badly when the application repeatedly allocates and frees large blocks (2-4 MB numpy frame arrays). Over hours of operation, RSS grows monotonically as freed memory is retained in per-thread arenas rather than returned to the OS.

**Solutions implemented:**

- **`PooledTTLImageCache` + `FrameBufferPool`:** Recycles numpy arrays by shape, eliminating malloc/free churn for the dominant allocation pattern. See [[memory-management]] and [[image-cache-strategies]] for the full design.

- **jemalloc (`LD_PRELOAD`):** Replaces glibc's allocator with one that aggressively returns memory to the OS via background dirty-page decay. Essential for handling the ~108 MB/sec transient allocation churn from copy-on-get. Post-fork re-enablement of jemalloc's background thread is a critical detail in [[sharding|sharded deployments]].

- **Explicit frame deletion:** `CleanupStep` marks frames for deletion, and the camera's `_delete_pending_frames()` returns pooled buffers promptly. The `evict_frame_numpy()` method allows early release of the raw numpy while keeping compact JPEG bytes for deferred alert paths.

### 3. YOLO Inference Latency

**Problem:** Inference is the single largest per-frame latency contributor (50-200ms per frame). At 24 cameras * 3 FPS, the shard needs 72 inference calls/second. Without concurrency control, burst traffic saturates the model server and causes cascading latency.

**Solutions implemented:**

- **AIMD congestion control:** The [[inference-pool]] maintains an adaptive concurrency window (initial 48, floor 8, ceiling 200). Additive increase on fast responses (+1/window), multiplicative decrease on slow responses or errors (*0.75). The 200ms latency target acts as the congestion signal. This mirrors TCP's AIMD algorithm applied to HTTP inference throughput.

- **Resurrection:** If the async event loop thread dies, the next `post()` call recreates the pool under a lock. This provides self-healing without requiring pod restarts.

- **HTTP/2 via httpx:** The modern [[actuate-inference-client]] uses HTTP/2 multiplexing, sending multiple concurrent requests over a single TCP connection. This reduces connection setup overhead compared to the legacy [[actuate-classic-inference-client]]'s pool of individual TCP sockets.

### 4. Multiprocessing Overhead

**Problem:** [[Sharding]] is the most expensive operation in the connector. Splitting into N processes multiplies memory by ~N (each process copies pre-fork state) and adds 50-80% CPU overhead from OS scheduling, duplicated jemalloc arenas, and separate [[inference-pool]] instances per shard.

**Solutions implemented and proposed:**

- **Raised default shard size (24):** GIL breakdown logging confirmed that inference latency -- not GIL contention -- is typically the bottleneck, justifying larger shards.

- **Round-robin distribution:** `ChunkedSiteManager.chunks()` distributes cameras [0,3,6...], [1,4,7...], [2,5,8...] rather than sequential slicing, balancing load across shards.

- **Per-site shard sizing (proposed):** Short-term strategy from [[worklog-sharding-strategy]]: determine the comfortable maximum cameras-per-process for a given resolution/FPS combination and configure different shard sizes per site.

- **Dynamic [[sharding]] (proposed):** Long-term strategy: log per-site performance data to DynamoDB, analyse whether each site is lagging or over-provisioned, and set shard sizes automatically.

### 5. Motion Detection Cost

**Problem:** Motion detection runs at full inbound FPS (15-30) on every camera, making it the highest-frequency CPU operation. At 32K cameras, even small per-frame savings multiply.

**Solutions implemented:**

- **GPU CUDA variant:** `GPUFrameDiffMotionDetector` offloads grayscale conversion, Gaussian blur, frame differencing, thresholding, and morphology to the GPU via [[opencv-entity|OpenCV]] CUDA. See [[motion-detection-internals]]. Falls back to CPU transparently on failure.

- **Cached structuring elements:** Morphological kernels are pre-allocated and reused across frames, avoiding per-frame `getStructuringElement()` calls.

- **Adaptive sensitivity:** Higher pixel thresholds for infrequent frames prevent background staling from triggering false motion processing.

### 6. Frame Processing Efficiency

**Problem:** The connector downsamples from native FPS (15-30) to analytics FPS (1-3), but even sampled frames may be uninteresting (no motion, no objects).

**Solutions implemented and proposed:**

- **Motion gating in puller:** [[actuate-movement]]'s `MotionDetector` runs in the puller thread and suppresses frame submission when no motion is detected, saving the entire inference + post-processing cost for static scenes.

- **FPS downsampling:** `FpsDownSampleStep` in [[actuate-pipeline]] drops frames between the configured analytics FPS, applied after motion detection but before inference.

- **[[adaptive-temperature]] (proposed):** A per-camera "temperature" that increases on detection and decays to baseline. Elevated temperature would temporarily increase the effective analytics FPS, capturing the full event during active detection periods while conserving resources during quiet periods. Not yet implemented.

- **Timestamp gap buffering:** [[worklog-frame-gap-buffering]]'s algorithm smooths jitter and reconnection gaps, preventing downstream window calculations from being thrown off by irregular timestamps. This is a reliability optimisation that indirectly improves efficiency by keeping the downsampling logic's assumptions valid.

### 7. Filter Chain Cost

**Problem:** Post-processing filters (stationary, IOU, blacklist, polygon zones) run on every inferenced frame. The stationary filter's Shapely geometry operations are particularly expensive.

**Solutions implemented:**

- **Cost-ordered filter chain:** [[filter-pipeline-ordering]] ensures cheap filters (confidence, label) run first, reducing the detection count before expensive filters (IOU, stationary) execute. This yields ~3x reduction in Shapely computation compared to naive ordering.

- **Prepared geometries:** The stationary filter uses `shapely.prepared.prep()` to pre-compute spatial indices for motion polygons, enabling fast intersection checks.

- **Cumulative motion overlap:** The `stationary_cumulative` mode merges all motion regions via `unary_union` before checking overlap, handling fragmented motion that individual-region checks miss.

- **Server-side filtering (planned):** From [[filter-architecture]]: simple filters (confidence, label) will move to the model server via the inference API, reducing network transfer of discarded detections.

## Optimisation Status Summary

| Bottleneck | Solution | Status | Impact |
|---|---|---|---|
| GIL (inference) | AsyncInferencePool AIMD | Shipped | High -- eliminates GIL convoy on inference |
| GIL (encoding) | TurboJPEG | Shipped | Medium -- 2-3x encoding speedup + GIL release |
| GIL (filters) | Numpy bbox mode | Shipped | Low-Medium -- vectorised overlap |
| GIL (overall) | [[sharding|Sharding]] | Shipped | High -- but 50-80% CPU overhead |
| Memory fragmentation | PooledTTLImageCache | Shipped | High -- eliminates RSS growth |
| Memory fragmentation | jemalloc | Shipped | High -- essential companion to pooling |
| Inference latency | AIMD congestion control | Shipped | High -- adaptive backpressure |
| Inference latency | HTTP/2 (httpx) | Shipped | Medium -- multiplexed connections |
| Motion detection | GPU CUDA variant | Shipped | Medium -- GPU-accelerated FDMD |
| Frame processing | Motion gating | Shipped | High -- skips inference on static scenes |
| Frame processing | [[adaptive-temperature|Adaptive temperature]] | Proposed | Medium -- context-aware FPS |
| Filter cost | Cost-ordered chain | Shipped | Medium -- 3x stationary reduction |
| Filter cost | Server-side filters | Planned | Medium -- reduce network transfer |
| Multiprocessing | Dynamic shard sizing | Proposed | High -- eliminate unnecessary shards |
| Profiling | pyspy / memray sidecar | Adopted | Diagnostic -- enables future optimisation |
| Decoder | [[gstreamer-entity|GStreamer]]/[[ffmpeg-entity|FFmpeg]] pullers | Research | Unknown -- alternative to [[opencv-entity|OpenCV]] decode |
| Hot path | Rust acceleration | Research | Unknown -- rewrite numpy-adjacent ops |

## Cross-Cutting Themes

Three themes recur across the optimisation landscape:

1. **GIL awareness drives architecture.** The AsyncInferencePool, TurboJPEG selection, numpy vectorisation, and [[sharding]] strategy are all fundamentally about managing Python's single-threaded execution model. Every decision about where to place computation (C extension, async event loop, separate process) is a GIL trade-off.

2. **[[memory-management|Memory management]] is a systems problem.** The PooledTTLImageCache, jemalloc, explicit frame deletion, and post-fork re-initialisation form an interlocking system. Removing any one piece degrades the others -- jemalloc without pooling still fragments on large arrays; pooling without jemalloc fragments on copy-on-get transients; both without explicit deletion exhaust the cache before TTL expires.

3. **Cost-awareness scales linearly.** Ordering filters by cost, gating inference behind motion detection, and right-sizing shards are all instances of the same principle: do less work per frame, and the savings multiply across 32K cameras. The [[adaptive-temperature]] proposal extends this to the temporal dimension -- do less work per second when nothing is happening, more when something is.
