---
title: Profiling & Performance Tooling Inventory
type: entity
topic: profiling-and-performance
tags: [inventory, profiling, tooling, scripts, benchmarks, vms-connector, actuate-libraries]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/syntheses/2026-05-12_adr-actuate-instrumentation-v1.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/_summary.md
  - topics/profiling-and-performance/notes/concepts/2026-05-12_actuate-instrumentation-v1-installed.md
  - topics/profiling-and-performance/notes/concepts/in-process-hooks.md
  - topics/profiling-and-performance/notes/concepts/out-of-process-samplers.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_actuate-instrumentation-v1-verification-plan.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_profiling-toolkit-and-roadmap.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-14_first-hotspot-findings.md
incoming_updated: 2026-05-15
---

# Profiling & Performance Tooling Inventory

Authoritative list of every profiling / memory / CPU / benchmark artifact across the Actuate codebase as of 2026-05-12. Source of truth for the §30 initiative. Keep this updated when new tooling lands.

## Runtime hooks (in-process, vms-connector)

All in `site_manager/connector/analytics_site_manager.py` unless noted.

| Hook | Cadence | Measures | Gated by |
|---|---|---|---|
| `_log_memory_breakdown()` | every `fps_and_processing_sample_period` (30–100 s) | jemalloc allocated/resident/retained (MB), frame cache (numpy + JPEG) per camera, executor queue depth, `/proc/smaps_rollup` RSS breakdowns | **always on**; detailed per-camera walk behind `ACTUATE_MEMORY_DEBUG=1` |
| `tracemalloc` start + `_log_tracemalloc_top()` | every breakdown cycle | top-10 Python allocation sites by file:line, 10-frame depth | `ACTUATE_TRACEMALLOC=1` |
| jemalloc `background_thread` re-arm | once post-fork in child processes | re-enables jemalloc's background purger after `fork()` (lost across fork) | **always on** in production |
| `_jemalloc_purge()` | every breakdown cycle | `mallctl("arena.<i>.purge")` to force arenas to release to OS | `ACTUATE_MEMORY_DEBUG=1` |
| `_jemalloc_prof_dump()` | every breakdown cycle | heap-profile dump to `/tmp` for offline analysis | `ACTUATE_MEMORY_DEBUG=1` + jemalloc built with profiling |
| `malloc_trim(0)` | connector startup; on `gc.collect()` cycle | explicit return of glibc heap to OS | always on; gc interval was tuned 30 s → 15 s in #1624 |
| `MALLOC_CONF` env tuning | startup | jemalloc: `narenas:4`, `dirty_decay_ms:1000`, `oversize_threshold:20MB` | always on |
| `MALLOC_MMAP_THRESHOLD_` (legacy glibc path) | startup, when glibc rather than jemalloc | force large allocs to mmap (released to OS on free) | conditional on allocator |

Key invariant: jemalloc breakdown is **the** primary memory observability surface in production. Anything new must integrate with the same log cycle so dashboards can pick it up.

## One-shot tools (vms-connector repo root)

| Script | What it wraps | Output | Status |
|---|---|---|---|
| `cpu_profile.sh` | `py-spy record -o profile.speedscope.json -f speedscope -- python connector.py -l` | speedscope JSON (drag into [speedscope.app](https://www.speedscope.app/)) | active; viztracer line commented out |
| `memory_profile.sh` | `memray run --native -o output.bin connector.py -l` | memray binary; `memray flamegraph output.bin` to render | active |
| `monitor_memory.sh` | `ps`-based RSS/VSZ logger | CSV with timestamp | active, low-overhead companion to `cpu_profile.sh` |
| `run-container-local.sh` | Docker dev wrapper | n/a (includes thread-count sanity check on startup) | active for dev |

## One-shot tools (vms-connector `scripts/`)

| Script | Purpose | Invocation |
|---|---|---|
| `monitor_memory.py` | RSS / VSS / USS / PSS over time, peak + delta tracking | `python scripts/monitor_memory.py --pid <pid>` or `--name connector` |
| `benchmark_thread_pinning.py` + `run_thread_pinning_comparison.sh` | [[opencv-entity|OpenCV]] / TBB / OpenMP thread pinning A/B | `--no-pinning` flag for control run |
| `benchmark_turbojpeg.py` | TurboJPEG vs `cv2.imencode` (GIL-release benefit) | `--duration N --resolution WxH` |
| `frame_deletion_memory_test.py` + `frame_deletion_test.sh` | Connector frame-cache memory A/B with frame deletion on/off | Docker-based, peak + steady-state RSS comparison |
| `test_memory_release.py` | glibc `malloc_trim` + `MALLOC_MMAP_THRESHOLD_` tuning verification | `--no-mmap-threshold` and `--no-malloc-trim` flags |
| `test_memory_release_realistic.py` | Memory-return-to-OS under realistic numpy churn | one-shot |
| `test_gil_contention.py` | GIL bottleneck under concurrent camera threads; TurboJPEG vs [[opencv-entity|cv2]] | wall-clock time |
| `test_shard_shutdown.py` | Multiprocess shard cleanup memory leak regression | unit-test style |
| `simulate_high_density.py` | 100 containers × 10 cameras TurboJPEG scaling | aggregate FPS, memory growth |
| `visualize_fdmd.py` | Frame-diff motion detector visualization for FDMD tuning | diagnostic |

## CI-relevant tests

| File | Tests | CI-gated? |
|---|---|---|
| `test_vms/test_gil_benchmarks.py` | GIL contention under threading; pickle overhead; capture redundancy | **No** — manual run only. Roadmap item: promote to nightly. |
| `test_vms/test_healthcheck.py::TestVCHGracefulShutdown` | Billing-emit lifecycle (not perf, but adjacent) | yes (regression test) |

## New Relic skills + dashboards

| Skill / Tile | Source | Purpose |
|---|---|---|
| `/stage-performance` | `.claude/commands/stage-performance.md` | Queries `K8sContainerSample` for CPU cores, memory (working set GB), error rate; compares stage vs prod baselines; 30-min default window |
| `/stage-regression-check` | `.claude/commands/stage-regression-check.md` | Combines log health, APM latency, GC pause overhead into a pre-merge risk assessment |
| `/nr-connector-metrics` skill | `.claude/skills/` | NRQL reference for connector metrics |
| Local operational dashboard | `~/Documents/worklog/dashboard/` | Includes `vch_billing_emit_24h` and a memory-RSS tile (per-pod) |

**Gap:** no NR tile for `avg(RSS / camera) by integration` — proposed in roadmap item 5.

## actuate-libraries (current surface)

**The libraries side is nearly empty.** No actuate-* library imports `tracemalloc`, `cProfile`, `psutil`, `memray`, `py-spy`, `austin`, or `line_profiler`. Three latent surfaces exist:

| Library | Surface | Status |
|---|---|---|
| `actuate-instrumentation` (v0.0.3) | Misnamed — currently `data_dump` / `data_load` writing local JSON. No telemetry despite the name. | **Roadmap target** — natural home for `timing` + `memory` submodules. |
| `actuate-log` | `LogTimeElapsedMixin.log_time_elapsed` decorator (`time.time()`-based) | **Unused** in vms-connector. Either retire or upgrade. |
| `actuate-image-cache` | `FrameBufferPool.get_stats()` → hit / miss / pool_sizes; `PooledTTLImageCache.get_pool_stats()` proxies it | **Exposed but never read** by connector. Roadmap item 1 wires it into `_log_memory_breakdown`. |
| `actuate-monitoring` | `ActuateMonitor` / `Datadog` / `Newrelic` / `Cloudwatch` monitors — outbound deployment health (process up, container running) | Production. Not a profiling primitive. |
| `actuate-inference-client` | Plain httpx wrappers. **No timing, no AIMD** — that lives in `vms-connector/inference/AsyncInferencePool`. | Production. |

## Documentation

| Doc | Scope |
|---|---|
| `vms-connector/docs/OPTIMIZED-CONNECTOR.md` | **82 KB authoritative roadmap.** 29 sections: TurboJPEG, GPU decode, FDMD, thread pinning, frame deletion, allocator tuning, GC, jemalloc profiling, language eval (C++/PyPy/Numba), Python 3.13/3.14 evals, NR integration |
| `vms-connector/docs/CONNECTOR-OPERATIONS.md` | Operational guidance including memory monitoring |
| `vms-connector/CLAUDE.md` "Diagnostics" + "Memory sizing" sections | Budget statement: ~270 MB/camera steady-state RSS, broken down (#1616) |

## Gaps (the roadmap addresses these)

1. **No continuous CI perf gate** — `test_gil_benchmarks.py` exists but is not enforced.
2. **No CPU flamegraph automation** — `cpu_profile.sh` is ad-hoc; no scheduled fleet sampling.
3. **Profile-on-stage sidecar never landed** — proposed in [[worklog-optimization-research]], not built.
4. **Library-side telemetry has no home** — `actuate-instrumentation` is a stub.
5. **`FrameBufferPool.get_stats()` exposed but unread** — cache hit-rate invisible to ops.
6. **`LogTimeElapsedMixin` unused** — dead code.
7. **No NR dashboard tile for memory budget compliance** vs the 270 MB/camera target.

See [[2026-05-12_profiling-toolkit-and-roadmap]] for prioritized work items addressing each gap.
