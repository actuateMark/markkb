---
title: "ADR — actuate-instrumentation v1 Design"
type: synthesis
topic: actuate-libraries
tags: [adr, actuate-instrumentation, profiling, instrumentation, design]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
sources:
  - "[[2026-05-12_profiling-toolkit-and-roadmap]]"
  - "[[actuate-instrumentation]]"
  - "[[in-process-hooks]]"
  - "[[tooling-inventory]]"
incoming:
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-12_actuate-instrumentation-v1-installed.md
  - topics/profiling-and-performance/notes/concepts/2026-05-14_actuate-profile-report-subcommand.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-12_actuate-instrumentation-v1-verification-plan.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-14_first-hotspot-findings.md
incoming_updated: 2026-05-27
---

# ADR — `actuate-instrumentation` v1 Design

**Status:** Accepted (2026-05-12) — implementation in progress on `feature/actuate-instrumentation-v1`.
**Context:** [[2026-05-12_profiling-toolkit-and-roadmap]] §30 Phase 2 — kickoff item 3a (README) is done; this ADR sets the contract for item 3b (implementation).

## Decision summary

`actuate-instrumentation` v1.0.0 ships three new submodules — `timing/`, `memory/`, `sampling/` — alongside the existing `data_dump/`. The library remains zero-dep at install time; `memory/` uses optional `psutil`. The version bump from 0.0.3 to 1.0.0 is rename-of-intent only — `data_dump` API is unchanged.

## Module layout

```
src/actuate_instrumentation/
  __init__.py            # re-export the curated public surface
  data_dump/             # unchanged from 0.0.3
  timing/
    __init__.py          # exports: TimedBlock, timed, ReservoirHistogram, LegacyLogTimedMixin
    timed.py             # TimedBlock ctx mgr + @timed decorator (perf_counter)
    histograms.py        # ReservoirHistogram (bounded reservoir for p50/p95/p99)
    legacy_mixin.py      # LegacyLogTimedMixin = deprecated alias for LogTimeElapsedMixin
  memory/
    __init__.py          # exports: start_tracemalloc, tracemalloc_top, rss_mb, uss_mb, pss_mb
    tracemalloc_helpers.py
    psutil_helpers.py    # imports psutil lazily; raises ImportError-with-hint if missing
  sampling/
    __init__.py          # empty namespace today
    README.md            # tracking note: 3.15 PEP 799 wrappers will live here
tests/
  test_timing.py
  test_memory.py
  test_data_dump.py      # backfill — currently no tests
```

## Decisions

### 1. Module layout: shallow, named after measurement *type*, not tool

**Decision:** Three flat submodules grouped by **what is being measured** (`timing`, `memory`, `sampling`), not by **which tool produces the measurement** (no `tracemalloc/`, no `perf_counter/`).

**Why:** The tool is a detail consumers shouldn't bind to. Tomorrow's psutil might be replaced by `resource` for USS; tomorrow's `perf_counter` might be replaced by `time.monotonic_ns`. Module names framed by *intent* outlive tool churn.

**Alternative rejected:** `actuate_instrumentation.tracemalloc` / `actuate_instrumentation.psutil` — would force consumers to know which tool produces the answer.

### 2. Naming conventions

| Surface | Form | Example |
|---|---|---|
| Public class | PascalCase | `TimedBlock`, `ReservoirHistogram` |
| Decorator | snake_case verb | `@timed`, `@traced` (future) |
| Function returning value | snake_case noun | `rss_mb()`, `tracemalloc_top()` |
| Function with side effect | snake_case verb | `start_tracemalloc()` |
| Env var | `ACTUATE_<DOMAIN>_<FLAG>` | `ACTUATE_TRACEMALLOC=1` (existing — keep) |
| Deprecated alias | `Legacy<OriginalName>` | `LegacyLogTimedMixin` |

Re-export the curated public surface from each submodule's `__init__.py`. Do not re-export from the top-level package — consumers import `from actuate_instrumentation.timing import TimedBlock` (explicit path > shorter import).

### 3. Env-var conventions

Mirror the existing connector pattern (`ACTUATE_TRACEMALLOC`, `ACTUATE_MEMORY_DEBUG`):

- Truthy: `1`, `true`, `yes` (case-insensitive). Empty / unset / anything else → false.
- Library does **not** read env vars in module top-level imports. Callers gate at the call site; the library exposes the primitive. Rationale: gating-in-library means importing the module changes process state (e.g. `tracemalloc.start()`), which surprises consumers.

Single helper `_truthy(name: str) -> bool` lives in `actuate_instrumentation/_env.py` so all submodules use the same parsing.

### 4. OpenTelemetry — explicit no

**Decision:** v1 does not depend on, integrate with, or expose OpenTelemetry types.

**Why:**
- OTel adds a tracer-provider lifecycle, an SDK installation, and a wire-format contract that we don't need for in-process measurement.
- Our consumers log via `logging` + ship to [[new-relic|New Relic]] via the Kubernetes log pipeline. There is no OTLP collector in the data path.
- Adopting OTel later is non-breaking — `TimedBlock` can emit an OTel span as an output strategy if/when needed (constructor-injected `on_close` callback).

**Revisit if:** Actuate adopts OTel platform-wide, or NR APM is wired up. Until then, the decision is "no".

### 5. Dependencies — keep zero-runtime at install

**Decision:** `actuate-instrumentation` declares zero runtime deps. `psutil` is an optional extra:

```toml
[project.optional-dependencies]
process = ["psutil>=5.9"]
```

**Why:**
- Forcing psutil onto every consumer is overkill — `actuate-config`, `actuate-alarm-senders`, etc. don't need RSS readers.
- The connector already depends on psutil 5.9 directly; nothing changes for it.
- Optional-extra pattern: `psutil_helpers.py` does a deferred import at call time with a clear error message: `"psutil is required for actuate_instrumentation.memory.rss_mb() — install with actuate-instrumentation[process]"`.

### 6. Version bump: 0.0.3 → 1.0.0

**Decision:** Jump straight to 1.0.0. Squash-merge subject tag: `[major:actuate-instrumentation]`.

**Why:**
- The README change alone moves the library from "stub" to "scope contract" — semver argues for at least 1.0.0.
- `data_dump` API is unchanged, so there's no breakage for current consumers.
- Going to 1.0.0 (vs 0.1.0) signals that the surface is now load-bearing — the README, tests, and submodule contracts are real commitments.

### 7. LogTimeElapsedMixin migration

**Decision:** `LegacyLogTimedMixin` lives in `actuate_instrumentation.timing.legacy_mixin` as a behaviour-identical copy of the `actuate-log` original, decorated with a `DeprecationWarning` on `__init_subclass__`.

`actuate-log` keeps `LogTimeElapsedMixin` exported through one full minor cycle. No connector code imports it today (verified `grep -rln LogTimeElapsedMixin vms-connector/` → empty), so the deprecation is defensive.

**Deletion plan:** `LogTimeElapsedMixin` deletion from `actuate-log` happens in `actuate-log 1.x` after `actuate-instrumentation 1.1.0` lands (one-version overlap).

### 8. Test coverage commitment

Tests/ directory ships with v1. Coverage targets:

- `timing/` — `TimedBlock` records elapsed; `@timed` preserves signature + return value; `ReservoirHistogram` p95 within 5% of true value at N=1000 samples.
- `memory/` — `tracemalloc_top()` returns sorted list when `start_tracemalloc()` has been called; raises informative error otherwise.
- `data_dump/` — round-trip test (currently no tests at all — backfill).

`tests/` directory at the package root is consistent with `actuate-log` and most other libraries.

## Public API — committed surface

```python
# timing
from actuate_instrumentation.timing import TimedBlock, timed, ReservoirHistogram, LegacyLogTimedMixin

with TimedBlock("inference.predict") as t:
    ...
# t.elapsed_s, t.elapsed_ms

@timed(logger=logging.getLogger(__name__))
def expensive():
    ...

hist = ReservoirHistogram(size=1000)
hist.record(elapsed_ms)
hist.p95()  # → float

# memory
from actuate_instrumentation.memory import start_tracemalloc, tracemalloc_top, rss_mb

start_tracemalloc(depth=10)
top = tracemalloc_top(limit=20, group_by="lineno")
# returns list[TracemallocEntry] (NamedTuple: file, line, size_mb)

rss_mb()  # → int
```

Everything else (helpers, internal histograms structure) is implementation detail and may change in minor versions.

## Out of scope (deferred)

- **Aggregation/export to NR** — consumers log; we don't push.
- **Async timing** — `@async_timed` is trivial to add later but not in v1.
- **Cross-process aggregation** — shard children each report locally.
- **GPU memory** — separate domain; revisit when GPU pipelines need observability.
- **`profiling.sampling` wrappers** — placeholder only; revisit when connector reaches 3.15.

## Risks

| Risk | Mitigation |
|---|---|
| Reservoir histogram math wrong → bad percentiles | Use Vitter's Algorithm R; test against `numpy.percentile` at N=1000 |
| `tracemalloc.start()` called twice → no-op confusion | Wrap with `is_tracing()` check; log a debug line if already started |
| psutil optional-extra forgotten by consumer | Deferred import raises `ImportError` with install hint |
| Version 1.0.0 sounds heavier than it is | README "Status" section explicitly calls out "rename-of-intent" |

## Tracking

- mark-todos §30 Item 3b — the implementation work
- Squash subject must be `[major:actuate-instrumentation]` — uses the per-library bump tag
- Connector dogfood — wire `_log_memory_breakdown`'s tracemalloc top through `actuate_instrumentation.memory.tracemalloc_top` in a separate connector PR after the library lands

## 2026-05-13 Addendum — profiling-suite harness lives in the library

**Change:** The original ADR scoped flamegraph / speedscope rendering and profile-session orchestration out of the library, leaving those in `vms-connector` (`cpu_profile.sh`, `memory_profile.sh`). That out-of-scope item is partially reversed: a `harness/` submodule now lives in `actuate-instrumentation` itself, exposing an `actuate-profile` console script with two subcommands — `session` (RTSP-local profile run against the connector, dropping py-spy speedscope, memray flamegraph, RSS-over-time CSV, captured connector log, parsed `_log_memory_breakdown` JSON) and `verify` (the pre-push experiments from [[2026-05-12_actuate-instrumentation-v1-verification-plan]]).

**Why the reversal:**
- The verification gate (Experiments 1–3) is a property of the library, not the connector. Keeping the runner in `vms-connector` would force every connector consumer to fork it, and would smear the gate's source of truth across two repos.
- Cross-repo reuse: the same harness runs against future scenarios (replay traffic, synthetic load) without needing a vms-connector clone.
- The connector's existing shell scripts (`cpu_profile.sh`, `memory_profile.sh`, `monitor_memory.sh`, `scripts/benchmark_*.py`, `test_vms/test_gil_benchmarks.py`) **stay where they are**. The harness invokes py-spy and memray via subprocess and reads the connector's stdout; it does not replace any of those.

**Dependency posture preserved:** py-spy and memray are added behind a **new** optional extra, not promoted to runtime deps. Consumers that only want timing/memory primitives stay zero-dep:

```toml
[project.optional-dependencies]
process = ["psutil>=5.9"]
profiling-suite = ["psutil>=5.9", "py-spy>=0.3.14", "memray>=1.10"]

[project.scripts]
actuate-profile = "actuate_instrumentation.harness.__main__:main"
```

**Module layout (additions only):**

```
src/actuate_instrumentation/harness/
  __init__.py
  __main__.py              # CLI entrypoint
  session.py               # session orchestrator
  artifacts.py             # dated dir + manifest
  parser.py                # _log_memory_breakdown log → JSON
  scenarios/
    rtsp_local.py
  runners/
    pyspy.py
    memray.py
    rss_monitor.py
  verify/
    exp1_tracemalloc.py    # comparison primitive (in-connector probe wired separately)
    exp2_timed_vs_pyspy.py # comparison primitive (in-connector probe wired separately)
    exp3_histogram.py      # standalone — runs today
```

**Status (2026-05-13):** scaffold landed locally on `feature/actuate-instrumentation-v1`, tests green (38 total: 30 original + 8 harness). `actuate-profile verify --experiment 3` returns a verdict end-to-end. Exp 1 and Exp 2 comparison primitives exist; the connector-side probes that feed them are next. Session command is wired but not yet exercised against the live [[rtsp-deep-dive|RTSP]] simulator.

## Related

- [[2026-05-12_profiling-toolkit-and-roadmap]] — parent roadmap, §30 source
- [[actuate-instrumentation]] — library entity note
- [[in-process-hooks]] — connector's existing memory hook (the dogfood target)
- [[tooling-inventory]] — pre-v1 state of the ecosystem
