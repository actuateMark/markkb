---
title: In-Process Profiling Hooks (vms-connector)
type: concept
topic: profiling-and-performance
tags: [profiling, memory, tracemalloc, jemalloc, malloc-trim, smaps, runtime-hooks]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
sources:
  - "[[memory-management]]"
  - "[[performance-optimization-landscape]]"
incoming:
  - topics/actuate-libraries/notes/syntheses/2026-05-12_adr-actuate-instrumentation-v1.md
  - topics/profiling-and-performance/_summary.md
  - topics/profiling-and-performance/notes/concepts/2026-05-12_actuate-instrumentation-v1-installed.md
  - topics/profiling-and-performance/notes/concepts/out-of-process-samplers.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_actuate-instrumentation-v1-verification-plan.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_profiling-toolkit-and-roadmap.md
incoming_updated: 2026-05-13
---

# In-Process Profiling Hooks (vms-connector)

What runs **inside** every connector process, every cycle, with no external attach. Production-safe by construction (no ptrace, no capability grants), bounded overhead, integrated with the existing log pipeline so [[new-relic|New Relic]] ingests it automatically.

## The memory-recording loop

`AnalyticsSiteManager` starts a daemon thread that wakes every `fps_and_processing_sample_period` seconds (configurable, default 30–100 s depending on integration) and calls `_log_memory_breakdown()`. This is the single hook that drives all per-cycle memory telemetry — every other helper either contributes data or runs conditionally inside it.

The breakdown emits a single multi-line log block per cycle, structured so NRQL can `aparse` individual fields. Categories:

1. **jemalloc stats** (`allocated`, `resident`, `retained`, `mapped`) — via `mallctl()` over the jemalloc C API. Always emitted. These are the most reliable indicators of fragmentation: `resident − allocated` is "fragmentation overhead held by the allocator," and `retained` is "munmap-deferred regions waiting on `purge`."
2. **Frame cache** — per-camera numpy + JPEG bytes in `PooledTTLImageCache`. Currently only the aggregate is logged; the `FrameBufferPool.get_stats()` hit-rate is **not yet wired in** (roadmap item 1).
3. **Executor queue depth** — sliding-window observer backlog. Growing queues indicate downstream stall (inference saturation or alert-sender throttling).
4. **`/proc/smaps_rollup`** — RSS by mapping type (`Rss`, `Anonymous`, `Shared_Clean`, `Shared_Dirty`). Cheaper than walking full `/proc/PID/smaps`; rolled out as the default in #1634.
5. **Per-segment walk** (`ACTUATE_MEMORY_DEBUG=1` only) — full `/proc/PID/smaps` parsed into heap / anon_large / thread_stacks buckets. Expensive enough that it stays gated.
6. **tracemalloc top-10** (`ACTUATE_TRACEMALLOC=1` only) — Python allocations by `(file, line)`. 10-frame call depth. Adds 10–30% memory overhead (the tracemalloc cost itself); only run on diagnostic deployments.

## jemalloc as the primary allocator

The connector runs with **jemalloc preloaded** (`LD_PRELOAD=/.../libjemalloc.so`) in production. Reasons (full rationale in [[memory-management]]):

- glibc's `ptmalloc2` fragments badly under repeated 2–4 MB numpy allocations across many threads — characteristic slow upward RSS trend that never stabilizes.
- jemalloc exposes a profiling API (`mallctl(prof.dump)`) the connector can call programmatically.
- Per-thread arenas with the `narenas:4` cap give us back tail latency without paying full per-thread arena cost.

Production `MALLOC_CONF`:
```
narenas:4,dirty_decay_ms:1000,oversize_threshold:20MB,background_thread:true
```

- `dirty_decay_ms:1000` — was 5000, tightened in #1624 to release dirty pages faster.
- `narenas:4` — was unlimited (per-thread), capped to bound RSS.
- `oversize_threshold:20MB` — allocations over 20 MB skip arenas, mmap'd directly so `free()` releases to the OS.
- `background_thread:true` — jemalloc's purger; lost across `fork()` (see fork-safety section below).

## Fork safety

`ChunkedSiteManager` forks child processes after cameras and pipelines are built. Two profiling-relevant consequences:

1. **`background_thread` dies in children.** The connector re-arms it in each child via `mallctl("background_thread", true)` in `AnalyticsSiteManager.run()`. Without this, child processes accumulate dirty pages indefinitely.
2. **tracemalloc state inherits but timers don't.** Each child's `_log_memory_breakdown` thread is restarted post-fork (see [[memory-and-fork-safety]]). Don't add new profiling threads in `__init__` of any class instantiated by the factory — they will die silently in shard children.

Any future profiling sidecar / in-process sampler must follow the same rule: start in `run()`, not `__init__`.

## tracemalloc gating

`ACTUATE_TRACEMALLOC=1` is **opt-in per deployment**, not fleet-wide. Reasons:

- Memory overhead (10–30%) breaks the 270 MB/camera budget for high-density pods.
- Per-frame call stacks aren't useful most of the time; turn it on when chasing a specific leak.
- It does not survive across forks if started after children are spawned — start it from `connector.py` startup, not from `_log_memory_breakdown`.

Pattern when investigating: deploy a single problem site with `ACTUATE_TRACEMALLOC=1` set via `connector_deployer`, let it run for an hour, inspect logs in NR for the top-allocation table. Disable when done.

## What the hooks **don't** cover

| Dimension | Currently | Plan |
|---|---|---|
| CPU time per function | not logged | out-of-process samplers ([[out-of-process-samplers]]) |
| Per-frame pipeline-stage latency | partial — `AsyncInferencePool` logs `queue_ms` / `network_ms` / `gil_reacquire_ms` only | roadmap: extend to other stages via `actuate-instrumentation` |
| FrameBufferPool hit-rate | exposed via `get_pool_stats()`, **never called** | roadmap item 1 |
| Disk I/O wait | not logged | not currently a known bottleneck |
| GPU utilization (where applicable) | not logged from connector | DCGM on the inference container; out of scope |

## Operational tips

- **Don't read raw logs.** Use the parse rules in `/nr-connector-metrics` to pull memory fields as NRQL attributes.
- **[[watch-entity|Watch]] `resident − allocated`** trending up over hours = fragmentation; `retained` growing = purge isn't keeping up.
- **`smaps_rollup` anonymous growth** with stable `allocated` = native C-side leak ([[pyav-entity|PyAV]]/libavcodec frame ref retention, see #1634).
- **For one-off investigations** prefer enabling `ACTUATE_MEMORY_DEBUG=1` on the affected pod rather than tracemalloc — cheaper and surfaces the smaps walk that pinpoints C-side leaks.

## Related

- [[memory-management]] — the 32 MB/camera budget rationale and FrameBufferPool design
- [[out-of-process-samplers]] — when to reach for py-spy / memray instead
- [[memory-and-fork-safety]] — fork survival rules (the constraint behind hook placement)
- [[tooling-inventory]] — full list of hooks with env-var gates
- §30 in [[mark-todos]] — roadmap tracking
