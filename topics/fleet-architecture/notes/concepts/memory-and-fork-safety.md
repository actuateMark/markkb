---
title: "Memory & Fork-Safety Topology per Proposal"
type: concept
topic: fleet-architecture
tags: [memory, jemalloc, fork-safety, pooled-ttl-cache, frame-buffer-pool, gil]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Memory & Fork-Safety Topology

Today's connector has a finely tuned memory story — `PooledTTLImageCache` + `FrameBufferPool` eliminate malloc/free churn, jemalloc with post-fork re-enablement handles fragmentation, and sharding isolates GIL contention at the cost of memory multiplication. See [[vms-connector/notes/concepts/memory-management]] and [[vms-connector/notes/syntheses/performance-optimization-landscape]] for the full landscape.

Every fleet proposal changes this story — sometimes for the better (no more forking), sometimes for the worse (frames serialize across network boundaries). This note catalogs the deltas.

## Today's in-process memory model

- **Per-camera budget:** 32 MB/camera + 500 MB base
- **Frame cache:** `PooledTTLImageCache` recycles numpy arrays by shape; `FrameBufferPool` backing
- **Allocator:** jemalloc via `LD_PRELOAD`; background_thread re-enabled after `fork()` via `mallctl`
- **GIL contention:** `AsyncInferencePool` + TurboJPEG + numpy release GIL; sharding via `ChunkedSiteManager` when 24+ cameras cause saturation
- **Sharding cost:** 50-80% CPU overhead per shard boundary; memory multiplies per shard (pre-fork state copied)

## Per-proposal memory deltas

### A — Minimal Split
- **Puller fleet:** small per-pod — just frame pulls + Redis XADD serialization. No frame cache needed if we stream immediately. Jemalloc optional (no sharding, no fragmentation dominance).
- **Pipeline worker:** unchanged from today.
- **Alert sender fleet:** trivial memory footprint.
- **Serialization cost:** JPEG already a byte blob — zero marshal overhead for Redis transport.
- **Fork safety:** unchanged — pipeline worker still shards internally.

### B — Stage Fleets
- **Puller:** as A
- **Motion fleet:** receives JPEG, decodes + runs FDMD, emits JPEG + motion regions. **Decode is the cost.** Per-pod frame-buffer-pool useful. Memory per camera: ~2-4 MB decode buffer × cameras per pod.
- **Inference-coord fleet:** buffers frames awaiting inference. **Biggest memory footprint of B.** Depends on AIMD window size and inflight count.
- **Observer+filter fleet:** per-camera tracker state (~200 KB × cameras). Memory-bound.
- **Each fleet benefits from jemalloc if it allocates numpy** — motion, inference-coord, observer.
- **Fork safety: **eliminated** — no in-process sharding; each stage pod is single-purpose, HPA-scaled.
- **Per-hop serialization:** JPEG bytes pass through streams 4 times — no re-encode, but each hop triggers a memcpy into the Redis client buffer. Measurable CPU cost per hop.

### C — Camera-Worker
- **In-process pipeline per camera:** preserves full performance story. `PooledTTLImageCache` per worker; per-camera cache slice.
- **Memory per worker:** `32 MB × cameras_per_worker + 500 MB base`.
- **Fork safety: **eliminated** — a worker is single-process. No multiprocessing. No jemalloc-after-fork dance. **This is a real simplification** — see [[vms-connector/notes/concepts/memory-management]].
- **GIL contention story:** unchanged — AsyncInferencePool + TurboJPEG keep threads productive. Per-worker camera count becomes the tunable.
- **Reassignment cost:** when a camera migrates, pool slice is freed and re-allocated on target worker. Jemalloc's `MADV_DONTNEED` returns pages.
- **Big win:** the fork-safety complexity that bit us historically [[vms-connector/notes/concepts/memory-management|(post-fork re-enablement, copy-on-get)]] becomes dead code.

### D — Event-Driven
- **Puller with FDMD:** memory for FDMD state per camera (~1-2 MB) + frame buffer. Manageable.
- **Detector:** receives S3 refs, GETs bytes, decodes, runs inference. Similar to B's motion+inference-coord.
- **Observer:** same as B.
- **S3 reference pattern:** frames live in MinIO/S3 Express, not in memory or streams. **Smaller in-cluster memory footprint than B.**
- **GET cost:** every frame touched = S3 GET. Add JPEG decode per stage that needs raw pixels.
- **Fork safety: eliminated.**

### E — Hybrid Sidecar
- **Smart puller:** FDMD state per camera, no full-frame cache needed (motion-filter drops most frames upstream of cache).
- **Detection core StatefulSet:** full pipeline in-process per camera group. `PooledTTLImageCache` per pod, slice per camera. **Preserves today's memory efficiencies** for the heavy work.
- **Memory per core pod:** `32 MB × cameras_in_group + 500 MB base` + inference buffers. Sized for 10-50 cameras.
- **Fork safety: eliminated** — camera-affinity StatefulSet scales by pod count, not by fork.
- **Net:** retains the best of today's in-process optimizations, eliminates the worst (forking).

## Summary matrix

| Proposal | Fork-safety story | Frame cache reuse | Per-hop serialization cost |
|----------|-------------------|-------------------|--------------------------|
| A | Unchanged (pipeline still shards) | Pipeline: yes; puller: light | 1 hop (~memcpy per frame) |
| B | **Eliminated** | Per stage (observer most valuable) | 4 hops (~4 memcpy per frame) |
| C | **Eliminated** | Full in-process (unchanged) | 0 |
| D | **Eliminated** | Per stage | 0 in-cluster; S3 PUT+GET per hop |
| E | **Eliminated** | Full in core (unchanged) | 1 hop (motion-filtered only) |

## Shared risks if we get this wrong

- **Memory fragmentation return:** if any new fleet allocates/frees large numpy buffers without jemalloc, we're back to the ptmalloc2 fragmentation problem. All Python fleets need jemalloc (or equivalent) via `LD_PRELOAD`.
- **Per-fleet image loading cost:** libraries like torch, opencv, TurboJPEG add ~1.5 GB to pod image. Universal-image fleets (C) cold-start slower; specialized-image fleets (B, D pullers) start faster but more deploys to manage.
- **OOMKills on reassignment:** for C/E, a pod receiving a camera assignment must have headroom for that camera's memory. If autoscaler lags the assignment controller, reassignment can OOM the target pod.

## Enhancement opportunities

- **Standardize jemalloc + tuned env-vars across all fleet images.** Extract the base-image work today for consistency across proposals. [[vms-connector/notes/concepts/memory-management]] has the details.
- **Expose `FrameBufferPool` stats as a metric.** Today it's internal; pool saturation is currently invisible. Useful per-fleet diagnostic.
- **Consider `shared_memory` cross-fleet.** For same-node fleets (e.g., B's motion and inference-coord potentially on same node via node-affinity), POSIX shared memory for frame handoff could eliminate Redis serialization. Niche but worth benchmarking for B's per-hop cost.
- **Right-size `cameras_per_worker` per workload class.** C especially: worker pods serving high-FPS 4K cameras need smaller counts than 2MP 3FPS cameras. Bin-packer should account for bytes-per-camera, not just count.

## References

- [[vms-connector/notes/concepts/memory-management]]
- [[vms-connector/notes/syntheses/performance-optimization-landscape]]
- [[actuate-libraries/notes/concepts/image-cache-strategies]]
- [[infrastructure/notes/concepts/vpa-behavior]] — VPA's role in memory requests
