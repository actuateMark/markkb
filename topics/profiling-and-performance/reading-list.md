# Reading List: Profiling and Performance

## Python stdlib

- [ ] [Python 3.15 — `profiling.sampling`](https://docs.python.org/3.15/library/profiling.sampling.html) — new in 3.15. PEP 799 ("Tachyon"). See [[2026-05-12_python-3.15-profiling-sampling-watchlist]].
- [ ] [Python 3.15 — `profiling.tracing`](https://docs.python.org/3.15/library/profiling.tracing.html) — relocation of `cProfile` under the new `profiling` namespace.
- [ ] [PEP 799 — Tachyon: Sampling Profiler for the Standard Library](https://peps.python.org/pep-0799/) — design rationale.
- [ ] [`tracemalloc` — Trace memory allocations](https://docs.python.org/3/library/tracemalloc.html) — already wired in via `ACTUATE_TRACEMALLOC=1`.
- [ ] [`gc` module](https://docs.python.org/3/library/gc.html) — generation tuning rationale for `gc.set_threshold` calls in connector startup.

## Third-party samplers / profilers

- [ ] [py-spy](https://github.com/benfred/py-spy) — currently wired into `cpu_profile.sh`. Rust binary, ptrace-based.
- [ ] [memray](https://github.com/bloomberg/memray) — currently wired into `memory_profile.sh`. Native allocation profiler.
- [ ] [austin](https://github.com/P403n1x87/austin) — alternative C sampler. Not currently used.
- [ ] [scalene](https://github.com/plasma-umass/scalene) — CPU + memory + GPU profiler. Not used; overlaps memray for our needs.
- [ ] [viztracer](https://github.com/gaogaotiantian/viztracer) — referenced in `cpu_profile.sh` but commented out; trace-based, not sampling.

## Allocator references

- [ ] [jemalloc man page](https://jemalloc.net/jemalloc.3.html) — `narenas`, `dirty_decay_ms`, `oversize_threshold`, `background_thread`, `prof.*`. Connector tunes all of these.
- [ ] [glibc malloc tunables](https://www.gnu.org/software/libc/manual/html_node/Memory-Allocation-Tunables.html) — `MALLOC_MMAP_THRESHOLD_`, `malloc_trim`.
- [ ] [Bloomberg memray architecture post](https://bloomberg.github.io/memray/architecture.html) — useful when interpreting `--native` output.

## Internal references

- [ ] [[performance-optimization-landscape]] — connector bottleneck → solution map.
- [ ] [[memory-management]] — 32 MB/camera budget, FrameBufferPool, allocator tuning.
- [ ] [[memory-and-fork-safety]] — fork survival rules for any profiler sidecar design.
- [ ] `docs/OPTIMIZED-CONNECTOR.md` in vms-connector — authoritative 82 KB optimization roadmap.
- [ ] Connector PRs: #1616 (memory sizing investigation), #1624 (BoundingBox leak, jemalloc tuning), #1634 (DW 4K codec retention, blacklist cap, smaps diagnostics).

## Open research threads (carried over from worklog)

- [ ] Rust acceleration for NumPy-adjacent hot loops — referenced in `worklog-optimization-research.md`, no concrete prototype.
- [ ] GStreamer puller as an FFmpeg alternative — referenced same place, no comparison done.
- [ ] Profiler sidecar (start py-spy at boot, dump on signal, S3 upload) — proposed, not built. See §30 roadmap item 7.
