---
title: "actuate-instrumentation v1 — Installed (Local)"
type: concept
topic: profiling-and-performance
tags: [actuate-instrumentation, profiling, timing, memory, tracemalloc, reservoir-histogram, installed, unpushed]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-14_actuate-profile-report-subcommand.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_actuate-instrumentation-v1-verification-plan.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-14_first-hotspot-findings.md
incoming_updated: 2026-05-27
---

# `actuate-instrumentation` v1 — Installed (Local)

What shipped on the unpushed branch `feature/actuate-instrumentation-v1` in `actuate-libraries`. This note is the durable record of the v1 surface; for the *why*, see [[2026-05-12_adr-actuate-instrumentation-v1]]; for the broader roadmap, see [[2026-05-12_profiling-toolkit-and-roadmap]].

## Status

- **Branch:** `feature/actuate-instrumentation-v1` (unpushed as of 2026-05-12)
- **Commits:**
  - `81b0c6a3` — `docs(actuate-instrumentation): expand README to v1 scope contract`
  - `877f8b1f` — `[major:actuate-instrumentation] v1: timing, memory, sampling submodules`
- **Tests:** 30 unittest cases, all passing locally. One skipped (`rss_mb` — psutil optional in the lib but always installed in the connector).
- **Lint/format:** ruff clean.
- **Version in `pyproject.toml`:** still `0.0.3`. CI's `bump-dev` workflow applies `1.0.0.devN+...` on first push; squash-merge applies stable `1.0.0` via the commit tag.
- **Local verification:** not yet done — see [[2026-05-12_actuate-instrumentation-v1-verification-plan]] for the planned suite that must pass before pushing.

## Module surface

```
src/actuate_instrumentation/
  _env.py                    # shared truthy() env-var helper
  data_dump/                 # unchanged from 0.0.3
  timing/
    timed.py                 # TimedBlock, @timed
    histograms.py            # ReservoirHistogram (Vitter's Algorithm R)
    legacy_mixin.py          # LegacyLogTimedMixin — deprecated alias for LogTimeElapsedMixin
  memory/
    tracemalloc_helpers.py   # start_tracemalloc, tracemalloc_top, tracemalloc_total_mb, is_tracing, TracemallocEntry
    psutil_helpers.py        # rss_mb, uss_mb, pss_mb — optional [process] extra
  sampling/                  # empty placeholder + README, Python 3.15 wrappers go here later
tests/                       # 30 cases — test_timing.py, test_memory.py, test_data_dump.py
```

## Public API — committed surface

### timing

```python
from actuate_instrumentation.timing import TimedBlock, timed, ReservoirHistogram

with TimedBlock("inference.predict", logger=log) as t:
    do_work()
# t.elapsed_s : float — seconds
# t.elapsed_ms : float — milliseconds
# logger (if given) emits "<label> took <ms>ms" at INFO on exit
# on_close (if given) receives (label, elapsed_s) — useful for histogram.record()

@timed(logger=log)
def expensive():
    ...

hist = ReservoirHistogram(size=1000)
for elapsed in samples:
    hist.record(elapsed)
hist.p50(), hist.p95(), hist.p99()   # → float
hist.count                            # total recorded (may exceed size)
hist.reset()
```

### memory

```python
from actuate_instrumentation.memory import (
    start_tracemalloc, is_tracing, tracemalloc_top, tracemalloc_total_mb,
    rss_mb, uss_mb, pss_mb,
    TracemallocEntry,
)

if not is_tracing():
    start_tracemalloc(depth=10)

entries: list[TracemallocEntry] = tracemalloc_top(limit=20, group_by="lineno")
# Each entry: NamedTuple(filename, lineno, size_mb)
# Sorted largest-first. Default filters drop tracemalloc + importlib bootstrap.

total_mb = tracemalloc_total_mb()   # Python-tracked allocation total
rss = rss_mb()                       # process RSS — requires psutil
```

### Behaviour notes

- **`TimedBlock`** uses `time.perf_counter()` — monotonic, highest-available resolution.
- **`TimedBlock` exception path:** elapsed is recorded; exception propagates normally. Logger and `on_close` still fire.
- **`@timed`** preserves signature via `functools.wraps`; default label is `f"{func.__module__}.{func.__qualname__}"`.
- **`ReservoirHistogram`** thread-safe under contention (single `threading.Lock`). Percentile is a linear interpolation between bracketing samples after sort.
- **`start_tracemalloc`** is idempotent — returns `True` if started by this call, `False` if already running.
- **`tracemalloc_top` raises** `RuntimeError` if not tracing. Caller is expected to gate with `is_tracing()` or call `start_tracemalloc()` first.
- **psutil helpers** import lazily; `ImportError` includes install hint pointing at the `[process]` extra.

## Env-var convention

The library does **not** read env vars at import time. Callers gate at the call site using a shared truthy helper:

```python
from actuate_instrumentation._env import truthy

if truthy("ACTUATE_TRACEMALLOC"):
    start_tracemalloc(depth=10)
```

Existing connector env vars (`ACTUATE_TRACEMALLOC`, `ACTUATE_MEMORY_DEBUG`) are unchanged; the library reads neither.

## Deprecation: `LogTimeElapsedMixin`

- `actuate_instrumentation.timing.LegacyLogTimedMixin` is behaviour-identical to `actuate_log.LogTimeElapsedMixin`, plus a `DeprecationWarning` on `__init_subclass__`.
- `actuate-log` retains `LogTimeElapsedMixin` for one full minor cycle.
- **No connector code imports the original today** — confirmed via `grep -rln LogTimeElapsedMixin vms-connector/` → empty. Deprecation is defensive against unknown consumers.

## Dependencies

- Runtime: zero. Hard requirement is Python ≥ 3.11.
- Optional `[process]` extra: `psutil>=5.9` — only needed for `rss_mb`/`uss_mb`/`pss_mb`. The connector already depends on psutil 5.9 directly, so connector consumers don't need to add the extra.

## What's NOT in v1

Anchored by the ADR's out-of-scope list:
- OpenTelemetry SDK integration — deferred until Actuate adopts OTel platform-wide.
- Async timing (`@async_timed`) — trivial follow-up, not needed yet.
- GPU memory readers — separate domain.
- `profiling.sampling` wrappers — empty placeholder; revisit when connector reaches Python 3.15.
- Flamegraph / speedscope rendering — stays in connector one-shot scripts (`cpu_profile.sh`, `memory_profile.sh`).
- Cross-process aggregation across shard children.

## Open follow-ups

1. **Local verification suite** — [[2026-05-12_actuate-instrumentation-v1-verification-plan]]. Must pass before pushing the branch.
2. **Push branch + open PR** — once verification passes; preserve `[major:actuate-instrumentation]` in the squash subject.
3. **Connector dogfood PR** — wire `_log_memory_breakdown`'s tracemalloc block through `actuate_instrumentation.memory.tracemalloc_top`. Separate PR on `vms-connector`. Establishes that the library actually replaces what it claims to replace.
4. **Remove `LogTimeElapsedMixin` from `actuate-log`** — next minor after `actuate-instrumentation` 1.0.0 publishes stable.

## Related

- [[2026-05-12_adr-actuate-instrumentation-v1]] — design decisions and rationale
- [[2026-05-12_profiling-toolkit-and-roadmap]] — §30 parent roadmap
- [[2026-05-12_actuate-instrumentation-v1-verification-plan]] — local verification suite (next step)
- [[actuate-instrumentation]] — library entity note (pre-v1 state)
- [[in-process-hooks]] — connector's existing memory hook (the dogfood target)
- [[tooling-inventory]] — pre-v1 ecosystem state
- mark-todos §30 — workstream tracking
