---
title: Profiling and Performance
type: summary
topic: profiling-and-performance
tags: [profiling, performance, optimization, memory, cpu, jemalloc, tracemalloc, py-spy, memray, benchmarks]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
---

# Profiling and Performance

Cross-repo topic for **measurement** disciplines and **optimization** work — what we instrument, what we sample, what we benchmark, and what we're missing. Distinct from the connector-specific [[performance-optimization-landscape|performance optimization landscape]] (which catalogs solutions to known bottlenecks); this topic catalogs the **toolkit and methodology** that lets us find new bottlenecks and verify fixes.

Scope spans:
- `vms-connector` — runtime memory hooks, one-shot CPU/memory profilers, GIL benchmarks, NR skills
- `actuate-libraries` — currently near-empty surface; `actuate-instrumentation` stub is the natural home for shared timing/memory primitives
- `ds-server-container`, `connector_deployer` — adjacent, mostly out of scope for now

## What lives here

| Note | Type | Purpose |
|---|---|---|
| [[tooling-inventory]] | entity | Every script, runtime hook, env var gate, NR skill currently in play |
| [[in-process-hooks]] | concept | `_log_memory_breakdown`, tracemalloc, jemalloc tuning, `malloc_trim` — what's wired into the running connector |
| [[out-of-process-samplers]] | concept | `py-spy`, `memray`, `austin`, `scalene`, the new stdlib `profiling.sampling` — when and how to use each |
| [[2026-05-12_python-3.15-profiling-sampling-watchlist]] | synthesis | PEP 799 / `profiling.sampling` brief. **Decision: not adoptable until ≥2027** (3.15 final + connector on 3.12; profiler must match minor) |
| [[2026-05-12_profiling-toolkit-and-roadmap]] | synthesis | Gap analysis, prioritized roadmap covering connector + libraries |

## Key cross-links

- [[performance-optimization-landscape]] — the connector-side **solutions** catalog (GIL, AIMD, frame-deletion, allocator tuning)
- [[memory-management]] — concept note on the 32 MB/camera budget, `FrameBufferPool`, jemalloc tuning rationale
- [[memory-and-fork-safety]] — fork-time thread-survival rules; intersects with profiling sidecar design
- `docs/OPTIMIZED-CONNECTOR.md` in vms-connector — 82 KB authoritative optimization roadmap (29 sections)
- §30 in [[mark-todos]] — initiative tracker

## Quick reference — what to reach for

| You want to… | Use this |
|---|---|
| See per-cycle memory in a running connector pod | jemalloc + smaps lines logged by `_log_memory_breakdown` (always on) |
| Find Python allocation hotspots in a stage pod | set `ACTUATE_TRACEMALLOC=1` on the deployment, [[watch-entity|watch]] logs |
| Capture a CPU flamegraph locally | `./cpu_profile.sh` (wraps `py-spy record -f speedscope`) |
| Capture native-allocation profile locally | `./memory_profile.sh` (wraps `memray run --native`) |
| [[watch-entity|Watch]] RSS/USS/PSS over time for a PID | `python scripts/monitor_memory.py --pid <pid>` |
| Compare stage perf vs prod | `/stage-performance` skill |
| Compare two stage runs for regression risk | `/stage-regression-check` skill |
| Verify GIL contention under thread count | `uv run pytest test_vms/test_gil_benchmarks.py -v -s` |
| A/B frame-deletion memory savings | `./scripts/frame_deletion_test.sh` |

## Status

Topic scaffolded 2026-05-12 as part of the §30 profiling-and-optimization initiative. Inventory + 3.15 brief + roadmap synthesis written; implementation work tracked in mark-todos §30.
