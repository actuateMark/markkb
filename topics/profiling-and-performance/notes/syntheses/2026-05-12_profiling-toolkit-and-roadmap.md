---
title: "Profiling Toolkit Gaps and Optimization Roadmap"
type: synthesis
topic: profiling-and-performance
tags: [profiling, roadmap, optimization, vms-connector, actuate-libraries, instrumentation, ci, dashboard]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
sources:
  - "[[tooling-inventory]]"
  - "[[in-process-hooks]]"
  - "[[out-of-process-samplers]]"
incoming:
  - topics/actuate-libraries/notes/syntheses/2026-05-12_adr-actuate-instrumentation-v1.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/_summary.md
  - topics/profiling-and-performance/notes/concepts/2026-05-12_actuate-instrumentation-v1-installed.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
  - topics/profiling-and-performance/notes/concepts/2026-05-20_memray-runner-investigation.md
  - topics/profiling-and-performance/notes/concepts/out-of-process-samplers.md
  - topics/profiling-and-performance/notes/entities/tooling-inventory.md
incoming_updated: 2026-05-27
---

# Profiling Toolkit Gaps and Optimization Roadmap

Synthesis of the 2026-05-12 ecosystem survey across `vms-connector` + `actuate-libraries` + Python stdlib (3.15 watchlist). Establishes a prioritized work plan for the §30 profiling-and-optimization initiative.

## State of the toolkit — short form

- **Connector runtime hooks are mature.** `_log_memory_breakdown` with jemalloc / smaps / tracemalloc gating already lands in production logs. See [[in-process-hooks]].
- **Connector one-shot tools are mature** but ad-hoc. `cpu_profile.sh` (py-spy), `memory_profile.sh` (memray), `monitor_memory.py`, plus 7 scripts in `scripts/`. No CI integration.
- **`actuate-libraries` side is empty.** Zero libraries import any profiling toolkit. `actuate-instrumentation` is a misnamed stub. `LogTimeElapsedMixin` and `FrameBufferPool.get_stats()` are unused surfaces.
- **No CI perf gate.** `test_gil_benchmarks.py` exists but is not enforced.
- **No fleet dashboard tile** for memory budget compliance (the 270 MB/camera target from `CLAUDE.md` is not directly visible in NR).
- **Python 3.15 `profiling.sampling` is genuinely new** but blocked until the connector reaches 3.15 (~Oct 2027 earliest). See [[2026-05-12_python-3.15-profiling-sampling-watchlist]].

## Gaps inventory

| # | Gap | Concrete symptom | Risk |
|---|---|---|---|
| 1 | `FrameBufferPool.get_stats()` exposed but unread | Cache hit-rate invisible to ops | Bad pool-size choices go undetected; investigation requires code-reading |
| 2 | `test_gil_benchmarks.py` not CI-gated | GIL regressions only caught post-merge | Already cost time in #1616 timeline; recurrent risk |
| 3 | `actuate-instrumentation` is a stub | No shared place for library timing/memory primitives | Every new measurement gets reinvented in connector code |
| 4 | No `/profile-on-stage` skill | Stage profiling requires shell gymnastics | Slows down regression chasing |
| 5 | No NR tile for budget compliance | "Is the fleet on budget?" is a multi-query investigation | Slow detection of fleet-wide drift |
| 6 | No memory baseline file / PR diff | Memory regressions only caught in stage | Risky merges land |
| 7 | No production profiler sidecar | py-spy in stage requires debug pod theater | Investigations stall on access |
| 8 | 3.15 migration tracking is implicit | Watchlist item could be lost | Low risk — flagged in §30 |

## Roadmap (prioritized)

### Phase 1 — quick wins (S effort, immediate value)

**1. Wire `FrameBufferPool.get_stats()` into `_log_memory_breakdown`.**
- Where: `vms-connector/site_manager/connector/analytics_site_manager.py`, inside the memory breakdown function.
- Pull `PooledTTLImageCache.get_pool_stats()` for each camera and log aggregate hit-rate + per-shape pool sizes.
- NRQL impact: a new `frame_pool_hit_rate` field becomes filterable. Add to `/nr-connector-metrics`.
- Effort: ~30 min. Pure additive; no risk to memory budget (the call itself is O(unique-shapes), tiny).

**2. Promote `test_gil_benchmarks.py` to a nightly job.**
- Where: connector CI (GitHub Actions). New workflow `nightly-perf.yml`, runs on schedule, reports to a perf-baselines file.
- **Not blocking on PR** — too noisy on shared CI runners, and the test is already a wall-clock comparison.
- Outcome: regression notification (Slack/issue) when GIL contention metrics drift > 20% from baseline.
- Effort: ~2 h (workflow + baseline storage + comparison script).

**5. [[new-relic|New Relic]] dashboard tile — memory budget compliance.**
- NRQL: `SELECT average(memoryWorkingSetBytes/1024/1024 / cameraCount) AS RSS_per_camera FROM K8sContainerSample WHERE container_name = 'connector' FACET integration_type SINCE 1 day ago TIMESERIES`
- Threshold: 270 MB target (from `CLAUDE.md`), 320 MB warn, 400 MB critical.
- Add to the local operational dashboard sink too.
- Effort: ~1 h.

**8. Capture the 3.15 watchlist in mark-todos §30** — already done via the [[2026-05-12_python-3.15-profiling-sampling-watchlist]] note + §30 reference. No further action until 2027.

### Phase 2 — library-side foundation (M effort) ← **kickoff phase**

**3a. Expand `actuate-instrumentation` README first.** Cheapest possible first action: replace the unfilled template README with an About/Scope section describing v1 (timing/, memory/, sampling/ submodules + retained data_dump). Establishes the scope contract before any code or ADR. ~30 min.

**3b. Land `actuate-instrumentation` v1 with real telemetry primitives.**

Current state: `actuate-instrumentation` v0.0.3 ships only `data_dump`/`data_load` helpers and a template README. The `pyproject.toml` description ("Tools and otherwise for instrumenting the codebase for better visibility.") has always pointed to the broader scope — only the implementation and README never caught up. Keep `data_dump`, add real modules.

Proposed layout (post-design review):

```
actuate-instrumentation/
  src/actuate_instrumentation/
    data_dump/          # existing — keep
    timing/             # new
      __init__.py
      timed.py          # @timed decorator + TimedBlock context manager (perf_counter)
      histograms.py     # bounded reservoir histogram for p50/p95/p99
    memory/             # new
      __init__.py
      tracemalloc_helpers.py  # env-var gated, matching ACTUATE_TRACEMALLOC pattern
      psutil_helpers.py       # RSS / USS / PSS readers
    sampling/           # new (placeholder for 3.15 wrappers when relevant)
      __init__.py
      README.md          # tracking note for 3.15 migration
```

Migration path:
- Bump `actuate-instrumentation` to 1.0.0 (breaking only in name-of-intent; `data_dump` API unchanged).
- Move `LogTimeElapsedMixin` from `actuate-log` into `actuate-instrumentation/timing/` as `LegacyLogTimedMixin`; deprecate.
- Connector consumers: wire `_log_memory_breakdown`'s tracemalloc helper through `actuate_instrumentation.memory.tracemalloc_top` to dogfood the API.

Effort: ~1–2 days for the lib work + ~half-day for connector wiring + design ADR.

**Design ADR to write first**: `topics/actuate-libraries/notes/syntheses/2026-XX-XX_adr-actuate-instrumentation-v1.md` — what goes in vs not, naming, env-var conventions, OpenTelemetry compatibility decision (likely no — too heavyweight for our use, but document the decision).

### Phase 3 — workflow tooling (M effort)

**4. `/profile-on-stage` skill.**
- Input: pod name or site label, duration.
- Steps: kubectl debug a sidecar with py-spy + memray + ptrace cap; record for N minutes; pull artifacts; deposit in `~/Documents/worklog/profiles/YYYY-MM-DD/`; optionally compare to a previous run.
- Out of scope (yet): rendering speedscope; the user opens artifacts in browser.
- Effort: ~1 day. Largely orchestration over existing tools.

**6. Memory regression baseline file + PR diff comment.**
- Storage: `.perf-baselines/memory.json` in vms-connector — RSS steady-state from `frame_deletion_memory_test.py` runs per build profile.
- CI step: run the test, compare against the baseline, post PR comment if delta > threshold.
- Effort: ~1 day. Trickier than item 2 because it requires a deterministic environment (the test runs in Docker and Docker on a runner is noisy).

### Phase 4 — production observability (L effort)

**7. Profiler sidecar (`ACTUATE_PYSPY=1`).**
- Helm-chart-toggleable sidecar that runs py-spy on the main container's PID, dumps to a shared volume, uploads to S3 on shutdown.
- Requires `shareProcessNamespace: true` on the deployment and `CAP_SYS_PTRACE` on the sidecar.
- Design considerations:
  - Sample rate (1–100 Hz; default 10 Hz to bound storage).
  - Trigger conditions (always-on vs SIGUSR signal vs cron).
  - S3 retention policy (per-pod-day, age-out after 7 days).
  - Cost — adding ~50 MB/pod for the sidecar; only worth it if we can selectively enable on problem sites.
- Effort: ~3–5 days when scheduled. Touches `kubernetes-deployments`, `connector_deployer`, and connector entry-point env handling.

## Sequencing

```
Kickoff → Phase 2 item 3a (README expansion)   ~30 min  ← start here
Phase 1 connector quick wins (1, 2, 5)         ~1 day   ← parallel-safe
Phase 2 — ADR, then v1 implementation          ~3 days
Phase 3 — once Phase 2 lands                   ~2 days
Phase 4 — separate workstream (heavier)        ~1 week
```

The README expansion is the lowest-risk, lowest-cost first action and pins the scope contract before any code. Phase 1 connector items are independent and can run in parallel. Phase 2's ADR follows the README, then the actual v1 implementation.

## Out of scope for §30

- **Rust acceleration of hot loops** — open research thread from [[worklog-optimization-research]]; needs its own initiative if pursued.
- **[[gstreamer-entity|GStreamer]] puller alternative to [[ffmpeg-entity|FFmpeg]]** — same source; open.
- **scalene adoption** — overlaps memray for our needs, no compelling reason to add.
- **OpenTelemetry / proper APM stack** — orthogonal; if Actuate ever standardizes on OTel, this whole toolkit shifts.
- **Python version migration (3.12 → 3.15)** — covered in `docs/OPTIMIZED-CONNECTOR.md` 3.13/3.14 evaluation sections; not a profiling initiative per se.

## Decision log

| Decision | Rationale |
|---|---|
| Use new `profiling-and-performance` topic, not extend `vms-connector` | Initiative spans connector + libraries + future Rust work; keeping it cross-repo |
| `actuate-instrumentation` becomes the library-side home | Already a connector dep; misnamed stub; rename-of-intent is cheaper than a new package |
| Defer 3.15 `profiling.sampling` adoption to ≥ Oct 2027 | Python version constraint is hard; py-spy is functionally equivalent |
| Phase 1 items are non-blocking on PR (nightly only) | Perf tests are wall-clock and noisy on shared runners; nightly + Slack ping is the right gate |
| Keep `LogTimeElapsedMixin` deprecated, not deleted, in v1 | One in-flight library could still depend on it; one-version deprecation cycle is the contract |

## Tracking

- [[mark-todos]] §30 holds checkboxes per roadmap item
- Each Phase 1 item closes via Task Completion Ritual: mark `[x]`, log to KB under `topics/profiling-and-performance/notes/concepts/{date}_<slug>.md` (concept) or `notes/syntheses/{date}_<slug>.md` (synthesis), update daily note.
- Phase 2 ADR lands as a synthesis in `topics/actuate-libraries/notes/syntheses/`.

## Related

- [[tooling-inventory]] — what exists today
- [[in-process-hooks]] — production runtime hook reference
- [[out-of-process-samplers]] — py-spy/memray/Tachyon comparison
- [[2026-05-12_python-3.15-profiling-sampling-watchlist]] — 3.15 brief
- [[performance-optimization-landscape]] — connector-side **solutions** catalog (this synthesis is the **measurement** counterpart)
- [[memory-management]] — concept driving roadmap item 5
- [[memory-and-fork-safety]] — constraint on roadmap item 7's sidecar design
