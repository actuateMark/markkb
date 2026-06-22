---
title: "memray runner — open investigation"
type: concept
topic: profiling-and-performance
tags: [memray, harness, actuate-instrumentation, investigation, status-tracker, §30]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
outgoing:
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_handoff-cv2-dst-stage-deploy.md
incoming:
  - topics/personal-notes/notes/daily/2026-05-20.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
incoming_updated: 2026-05-27
---

# memray runner — open investigation

The memray runner in `actuate-instrumentation/src/actuate_instrumentation/harness/runners/memray.py` produces no usable output on the webcam fixture today. After landing the `render_flamegraph` timeout (2026-05-19) we now fail *cleanly* instead of hanging indefinitely, but we still don't get a flamegraph or allocation hotspots out of the runner.

**Status:** Skipped by default in `run-webcam-profile.sh` (`SKIP_MEMRAY=1`). Re-enable with `SKIP_MEMRAY=0` once the runner produces usable output. py-spy runner is unaffected and remains the primary cpu-hotspot signal.

## Observed symptoms

From the 2026-05-20 11:43–11:52 webcam run (`/tmp/profile-webcam/2026-05-20/profile_20260520T154546Z/`):

- memray runner exit code **1**; `output.bin` is **8.5 MB** (small — not a huge-bin problem).
- `render_flamegraph` hit the new 180 s timeout cleanly — log line `[render_flamegraph] timed out after 180s — killing process group`, exit code 124. **Fix from 2026-05-19 confirmed working.** Underlying renderer still wedges.
- `memray stats --json` (in `report.allocation_hotspots_from_memray`) presumably also wedged — `report.md` allocation-hotspots section came up empty. Already has a 120 s timeout; would benefit from explicit logging of the timeout fact.
- Total run duration **~8 minutes** (vs ~3-4 min expected). py-spy ran fine (~80 s), memray run extended past its 90 s `duration_s` mark, then flamegraph timed out at +180 s, then stats wedged for +120 s. Net ~5+ min of slow-failing tail per memray run.
- The connector run-under-memray showed **zero `_log_memory_breakdown` cycles** in the connector log — but the run we did was against `/home/mork/work/vms-connector` (the main tree, no #1694 edits) because `rtsp_local.RtspLocalScenario._DEFAULT_CONNECTOR_DIR` is hardcoded. That has since been fixed with a `--connector-dir` CLI flag (lands with the rest of the harness work). So the zero-cycles signal is NOT a memray problem; it's a connector-tree-selection problem and is already resolved.

## Hypotheses to investigate

In rough order of suspicion:

1. **`--native --follow-fork` overhead.** The memray runner always passes both flags (runners/memray.py:75-79). `--native` enables C-frame stack capture; `--follow-fork` is essential for shard children. Either could explode metadata in `output.bin` in ways the renderer struggles to consume. Test: run memray without `--native` (Python frames only) and see if the renderer succeeds.
2. **memray version + python 3.12 + libav interaction.** memray 1.x had known issues with native captures over fork on some Python minor versions. Check pinned version in `actuate-instrumentation/pyproject.toml` (`memray>=1.10` per the `profiling-suite` extra). Upgrade to current 1.x and retest.
3. **SIGINT not stopping memray cleanly.** The runner sends SIGINT to the process group at `duration_s`; we then `proc.wait(timeout=duration_s + 30)`. If memray's signal handler defers flushing to its own teardown, the bin may end up incompletely written → renderer chokes on partial data. Test: increase the post-SIGINT wait, or use SIGTERM/SIGUSR1 if memray supports a "graceful flush" signal.
4. **uv ephemeral install drift.** Runner uses `uv run --with memray memray run`. Each invocation may resolve a different patch version of memray since `--with memray` has no version pin. Test: pin to a specific memray version with `--with memray==1.X.Y` and lock in a known-good baseline.
5. **The wrapper's `--follow-fork` is unnecessary for the webcam fixture.** Webcam runs against the LOCAL_WEBCAM settings; the connector spawns a `ChunkedSiteManager` only when camera count > `shard_size` (24). The webcam fixture has 1 camera — fork doesn't happen. Dropping `--follow-fork` for the local-webcam scenario should be safe and may help.

## Recommended next steps

1. **Add timeout-aware logging to `allocation_hotspots_from_memray`** (`report.py:248`) — currently silently returns empty tuples on timeout. Log the timeout fact + the seconds elapsed so future report.md generations make the failure visible. ~5 min.
2. **Reproduce on a smaller, controlled load** — `python -c "import time; time.sleep(60)"` under memray with the same `--native --follow-fork`. If renderer + stats succeed on a trivial target, the issue is in the connector's allocation patterns; if they fail, the issue is in the memray invocation itself.
3. **Bisect the flags** — drop `--native`, then drop `--follow-fork`. Whichever flag restores working flamegraph/stats is the smoking gun.
4. **Try memray latest stable** — `uv run --with memray==X.Y.Z memray run …` (pin to current 1.x or whatever is current in 2026).
5. **Compare against memray-on-rtsp-simulator** — the 2026-05-14 first-hotspot read used the [[rtsp-deep-dive|RTSP]] simulator scenario and produced a flamegraph + hotspots successfully. Diff the two runs to find what changed (webcam load is heavier? bin is bigger? both?).

## Caveats / out of scope

- This investigation is downstream of the cv2-dst soak. py-spy alone produces the CPU-hotspot signal needed to validate the soak; allocation hotspots are useful but not blocking.
- The harness lives on the unpushed `feature/actuate-instrumentation-v1` branch. Any fix here lands as part of that branch's eventual push, not on its own.
- Re-investigating the memray invocation may surface separate issues with `memray stats --json` (e.g., JSON schema changes across memray versions); track those as siblings if they emerge.

## Files of interest

- Runner: `actuate-instrumentation/src/actuate_instrumentation/harness/runners/memray.py` (180 s flamegraph timeout already landed)
- Stats parser: `actuate-instrumentation/src/actuate_instrumentation/harness/report.py:227-291` (`allocation_hotspots_from_memray`, 120 s timeout already)
- Wrapper default: `vms-connector/test_settings/run-webcam-profile.sh` (SKIP_MEMRAY=1 added 2026-05-20)
- pyproject extras: `actuate-instrumentation/pyproject.toml` (`profiling-suite = ["psutil>=5.9", "py-spy>=0.3.14", "memray>=1.10"]`)

## Related

- Status tracker: [[2026-05-19_cv2-dst-soak-status]] (where this is tracked as an open papercut)
- Handoff: [[2026-05-19_handoff-cv2-dst-stage-deploy]]
- First successful memray run (baseline to compare against): [[2026-05-14_first-hotspot-findings]]
- Roadmap: [[2026-05-12_profiling-toolkit-and-roadmap]]
- Workstream: §30 in `mark-todos.md`
