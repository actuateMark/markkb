---
title: "actuate-instrumentation v1 — Local Verification Plan"
type: synthesis
topic: profiling-and-performance
tags: [actuate-instrumentation, verification, profiling, tracemalloc, timing, local-test, gate]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/syntheses/2026-05-12_adr-actuate-instrumentation-v1.md
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-12_actuate-instrumentation-v1-installed.md
incoming_updated: 2026-05-14
---

# `actuate-instrumentation` v1 — Local Verification Plan

**Purpose:** Before pushing the unpushed `feature/actuate-instrumentation-v1` branch, verify that each primitive in the v1 surface returns useful, plausible signal against the **real connector workload** — not just synthetic unit tests. Unit tests prove the API behaves; this plan proves the API *measures the right things*.

**Gate:** Push and PR are blocked until at least the three core experiments below pass (`tracemalloc parity`, `@timed hotspot cross-check`, `histogram stability`). Optional experiments can land after the PR opens.

## Where this plugs in

- **Library shipped:** [[2026-05-12_actuate-instrumentation-v1-installed]] — branch + commits + API surface
- **Design rationale:** [[2026-05-12_adr-actuate-instrumentation-v1]]
- **Roadmap context:** [[2026-05-12_profiling-toolkit-and-roadmap]] §30 Phase 2
- **Existing instrumentation being compared against:** [[in-process-hooks]] — `_log_memory_breakdown` and `_log_tracemalloc_top`

## Environment

```bash
# Use the standard local RTSP simulator settings — never a production export
cd /home/mork/work/vms-connector
cp test_settings/VMS_CONNECTOR_LOCAL_RTSP.setting.json settings.json
uv sync

# Point the connector at the local actuate-libraries checkout so our branch is in scope
# (uv workspace already wires libraries via path; verify with):
grep actuate-instrumentation uv.lock | head
```

If the lock file doesn't yet pin to the local branch, do a one-off:
```bash
uv add actuate-instrumentation --path /home/mork/work/actuate-libraries/actuate-instrumentation
```
(do **not** commit this lockfile change — verification is local-only).

## Experiment 1 — tracemalloc parity (REQUIRED)

**Question:** Does `actuate_instrumentation.memory.tracemalloc_top()` return the same hotspots as the connector's existing `_log_tracemalloc_top()` for the same snapshot?

**Why it matters:** v1 is supposed to *replace* the inline tracemalloc code in `_log_memory_breakdown`. If the structured output disagrees with the existing log output, the dogfood PR will regress operator-visible diagnostics.

**Procedure:**

1. Start the connector with both env vars set:
   ```bash
   ACTUATE_TRACEMALLOC=1 ACTUATE_MEMORY_DEBUG=1 python connector.py -l
   ```
2. Let the simulator run ≥ 3 minutes (long enough for the memory hook's `sleep_time` cycle to fire at least twice and produce a `tracemalloc_lines:` log line).
3. From a second shell, attach via `python -c` or a one-shot script to the same process — actually no, tracemalloc is per-process — instead, **patch in a side-by-side log block**:
   - In `site_manager/connector/analytics_site_manager.py::_log_tracemalloc_top`, immediately after the existing snapshot, add a temporary block that imports `tracemalloc_top` from the new library and logs both top-5 lists with a `verify_parity:` prefix.
4. Run for ≥ 1 hook cycle and capture the log output.
5. **Pass criteria:**
   - Top-5 entries by file:line match between old and new (set equality on `(file, line)` pairs).
   - Size totals agree within ±0.1 MB (rounding only).
6. Revert the temporary patch.

**Cleanup:** the side-by-side log line is a throwaway diff; do not commit it.

## Experiment 2 — `@timed` hotspot cross-check vs py-spy (REQUIRED)

**Question:** When `@timed` is added to a known hot function, does the recorded distribution agree with py-spy's CPU profile of the same window?

**Why it matters:** v1's value proposition is replacing ad-hoc `perf_counter` blocks. If the decorator's measurements don't agree with the external sampling profiler on what's slow, we don't trust it for future hotspot calls.

**Target:** the pre-processing step in `pipeline/image_pipeline.py` — known-busy, runs per frame, hot enough to register on a 3-minute sample.

**Procedure:**

1. Patch the target function (locally, do not commit):
   ```python
   from actuate_instrumentation.timing import timed, ReservoirHistogram
   from actuate_instrumentation._env import truthy

   _PREPROCESS_HIST = ReservoirHistogram(size=2000) if truthy("ACTUATE_VERIFY") else None

   @timed(on_close=lambda label, s: _PREPROCESS_HIST.record(s * 1000) if _PREPROCESS_HIST else None)
   def pre_process(self, frame):
       ...  # existing body
   ```
2. Add a sibling line that logs the histogram every N seconds (piggyback on `_log_memory_breakdown` cycle).
3. Run two back-to-back 3-minute sessions:
   ```bash
   # Session A — instrumented
   ACTUATE_VERIFY=1 python connector.py -l
   # Session B — py-spy on identical settings
   py-spy record -o profile_b.speedscope.json -f speedscope -- python connector.py -l
   ```
4. **Pass criteria:**
   - `ReservoirHistogram.p95()` is within ±15% of the py-spy-derived p95 for the same function (open `profile_b.speedscope.json` in https://www.speedscope.app, inspect the function's per-invocation samples; py-spy at default 100 Hz over 3 min ≈ 18000 samples).
   - The decorator's overhead is < 5% of the median elapsed (compute by running a no-op control: same procedure with body replaced by `return frame`).

**Cleanup:** revert the patch; record the measured numbers in this note's "Results" appendix below.

## Experiment 3 — `ReservoirHistogram` percentile stability (REQUIRED)

**Question:** Across 10 independent reservoir-sampled runs of the same distribution, is the p95 stable?

**Why it matters:** Reservoir sampling has variance proportional to (population/reservoir-size). For reservoir=1000 and N≈18000 samples, the unit test verified ±10 absolute error against true value. We need the *empirical* spread across multiple runs to be small enough that operators can trust the percentiles without averaging.

**Procedure:** Standalone — no connector needed.

```bash
cd /home/mork/work/actuate-libraries/actuate-instrumentation
uv run python -c '
import random
from actuate_instrumentation.timing import ReservoirHistogram

# Simulate 18000 samples from a log-normal — typical for latencies
rng = random.Random(42)
def sample():
    return rng.lognormvariate(mu=2.0, sigma=0.6)

p95s = []
for trial in range(10):
    h = ReservoirHistogram(size=1000, seed=trial)
    for _ in range(18000):
        h.record(sample())
    p95s.append(h.p95())

print(f"p95s: {[f\"{p:.2f}\" for p in p95s]}")
print(f"mean: {sum(p95s)/len(p95s):.2f}  spread: {max(p95s)-min(p95s):.2f}")
'
```

**Pass criteria:**
- Spread (max − min) across 10 trials ≤ 8% of the mean.

Record the output in the Results appendix.

## Experiment 4 — `start_tracemalloc` overhead measurement (OPTIONAL)

**Question:** What's the steady-state RSS overhead of enabling tracemalloc at depth=10 for a 4-camera connector?

**Why it matters:** The connector's `CLAUDE.md` claims tracemalloc adds "~10-30% memory overhead." With the new library publishing a typed API, we should re-measure once with v1 wiring and update the doc number if reality has drifted.

**Procedure:**

1. Run two 5-minute back-to-back sessions; log RSS via `psutil_helpers.rss_mb()` every 30s in each:
   - Session A: `python connector.py -l` (no tracemalloc)
   - Session B: `ACTUATE_TRACEMALLOC=1 python connector.py -l`
2. Compute steady-state RSS = median of last 5 samples.
3. Report `(RSS_B - RSS_A) / RSS_A` as a percentage.

**Pass criteria:** result is consistent with the 10-30% range claimed in `CLAUDE.md`; if outside, update `CLAUDE.md` and `docs/CONNECTOR-OPERATIONS.md`.

## Experiment 5 — psutil-extra optional-dep failure mode (OPTIONAL)

**Question:** Does the optional-extra ImportError message correctly point users at the install command?

**Procedure:**

```bash
uv venv /tmp/no-psutil --python 3.11 && source /tmp/no-psutil/bin/activate
uv pip install /home/mork/work/actuate-libraries/actuate-instrumentation
python -c 'from actuate_instrumentation.memory import rss_mb; rss_mb()'
# Expected: ImportError mentioning "actuate-instrumentation[process]"
deactivate && rm -rf /tmp/no-psutil
```

**Pass criteria:** error message includes the install hint string `actuate-instrumentation[process]` and the function name `rss_mb`.

## Results appendix (fill in during runs)

| Experiment | Date | Status | Notes |
|---|---|---|---|
| 1 — tracemalloc parity | | | |
| 2 — @timed vs py-spy | | | |
| 3 — histogram stability | | | |
| 4 — tracemalloc overhead | | | |
| 5 — psutil ImportError msg | | | |

## After verification passes

1. Push the branch: `cd /home/mork/work/actuate-libraries && git push -u origin feature/actuate-instrumentation-v1`.
2. Open PR — verify squash subject preserves `[major:actuate-instrumentation]`, strip any auto-generated bump-bot lines from the body before merging.
3. [[watch-entity|Watch]] `bump-dev` CI publish `1.0.0.devN+feature.actuate.instrumentation.v1`.
4. Open the connector dogfood PR — rewrite `_log_memory_breakdown`'s tracemalloc block to call `actuate_instrumentation.memory.tracemalloc_top`. Keep the existing log-format string so operator-facing logs don't shift.

## Anti-pattern: skipping this gate

This verification suite exists because:

- **The README + ADR + 30 unit tests all pass without proving the library measures anything real.** Unit tests use synthetic allocations; the connector workload is the actual measurement target.
- **`_log_tracemalloc_top` already produces operator-trusted log lines.** A silent regression in the structured replacement would be invisible in CI but visible in incident triage.
- **The "lib publishes, connector consumes, fleet sees" loop has a 1-2 day latency** once stable publishes. Catching a hotspot-shape regression in local before pushing avoids that cycle.

Bias toward landing experiments 1, 2, 3 before pushing. Experiments 4, 5 can land after the PR opens.

## Related

- [[2026-05-12_actuate-instrumentation-v1-installed]] — the v1 surface this plan verifies
- [[2026-05-12_adr-actuate-instrumentation-v1]] — design decisions
- [[in-process-hooks]] — the existing instrumentation being compared against
- [[out-of-process-samplers]] — py-spy reference (Experiment 2's external profiler)
- [[tooling-inventory]] — one-shot script catalog
