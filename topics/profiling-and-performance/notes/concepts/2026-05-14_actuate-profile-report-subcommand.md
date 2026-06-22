---
title: "actuate-profile report — per-session hotspot extraction"
type: concept
topic: profiling-and-performance
tags: [actuate-instrumentation, profiling, report, speedscope, memray, tool]
created: 2026-05-14
updated: 2026-05-14
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/daily/2026-05-15.md
  - topics/personal-notes/notes/daily/2026-05-18.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_handoff-cv2-dst-stage-deploy.md
  - topics/profiling-and-performance/notes/syntheses/2026-05-14_first-hotspot-findings.md
incoming_updated: 2026-05-27
---

# `actuate-profile report` — per-session hotspot extraction

Third subcommand in the `actuate-profile` CLI (alongside `session` and `verify`). Reads the artifact directory produced by `actuate-profile session` and emits a `report.md` summarising the run's CPU hotspots, allocation hotspots, RSS trajectory, and connector-breakdown deltas.

**Why it exists.** Profiling sessions produce large blobs that are tedious to open by hand — py-spy speedscope JSON (≥ 100 KB), memray flamegraph HTML (7+ MB), memray binary, RSS CSVs, connector logs. The report squeezes them into a single page that says *what* the run found, so a session is reviewable in seconds and is diffable across runs.

## Invocation

```
actuate-profile report <artifact-dir>
```

Reads `<artifact-dir>/manifest.json` to discover per-runner inputs by convention; writes `<artifact-dir>/report.md`. Missing inputs degrade gracefully (an absent runner is just omitted; an absent breakdown section says so honestly).

## What's in the report

- **Run header** — scenario, duration, libraries + connector git SHAs, host, Python version, start/finish timestamps.
- **Per-runner section** for each runner in the manifest:
  - **CPU hotspots** (py-spy runs only) — top-15 by self-time, with total-time alongside. Aggregated across every thread profile in the speedscope file. Excludes `<frozen importlib._bootstrap>`, `<unknown>`, and thread/process root frames.
  - **Allocation hotspots** (memray runs only) — top-10 by cumulative bytes and top-10 by allocation count. Shells out to `memray stats --json` via `uv run --with memray`, mirroring the runner.
  - **RSS trajectory** — samples, duration, start/end/peak/mean MB, slope (MB/min, end-vs-start over duration).
  - **Connector breakdown summary** — record count, first/last smaps RSS and jemalloc resident, plus top-10 tracemalloc sites aggregated across cycles. Falls through to a one-line "no cycles captured" notice when the run was shorter than the connector's `_log_memory_breakdown` interval (100 s default).

## Implementation

- **Module:** `src/actuate_instrumentation/harness/report.py` (~340 lines, single file).
- **Speedscope parsing:** handles `sampled` profiles natively (the format py-spy emits). Self-time accrues to top-of-stack only; total-time accrues to every distinct frame seen in the sample (set-deduplicated, so recursion doesn't double-count). Unit-scale aware (seconds / milliseconds / microseconds / nanoseconds).
- **Memray hand-off:** invokes `memray stats --json -o stats.json -f -n N <output.bin>` in the libraries cwd. The `stats.json` is dropped next to `output.bin` and reused if the report is re-run.
- **CSV parsing:** `rss_monitor.py`'s monitor_memory.csv. Skips rows with empty `target_rss_mb` (those appear briefly when the memray runner hasn't yet identified the target child).
- **Breakdown summary:** reuses the existing `harness/parser.py` (jemalloc / smaps_rollup / per-camera / tracemalloc_lines regexes).
- **Tests:** 9 new unittest cases in `tests/test_harness_report.py` cover speedscope aggregation (self vs total), noise-frame filtering, RSS slope/peak/mean, `_split_location`, and markdown shape. Memray analyzer not unit-tested (shells out to binary). 47 tests total in the suite, all passing.

## CLI shape (after this addition)

```
actuate-profile session  --scenario … --duration …    # produce artifacts
actuate-profile report   <artifact-dir>               # emit report.md
actuate-profile verify   --experiment {1,2,3,all}     # pre-push gate
```

## Limitations

- The memray run in the smoke session exited `-9` (SIGKILL escalation from the duration timer) — the `.bin` is intact and parseable, but the run wasn't graceful. Not a report problem, but worth knowing.
- No diff-between-reports yet — each report is standalone. A future `actuate-profile diff <a> <b>` would close the A/B loop for optimization PRs.
- Breakdown sections came up empty in both validated sessions; the connector's 100 s `_log_memory_breakdown` interval is longer than the runs. Either lengthen runs or shorten the interval for verify-mode workloads.

## Related

- First findings against real artifacts: [[2026-05-14_first-hotspot-findings]]
- Library install record: [[2026-05-12_actuate-instrumentation-v1-installed]]
- Design ADR: [[2026-05-12_adr-actuate-instrumentation-v1]]
- Workstream: §30 in `mark-todos.md`
- Source: `actuate-libraries/actuate-instrumentation/src/actuate_instrumentation/harness/report.py`
