---
title: "cv2 dst= preallocation — soak status tracker"
type: concept
topic: profiling-and-performance
tags: [actuate-movement, vms-connector, cv2-dst-preallocation, soak, status-tracker, §30]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
outgoing:
  - topics/profiling-and-performance/notes/concepts/2026-05-19_handoff-cv2-dst-stage-deploy.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/personal-notes/notes/daily/2026-05-20.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_handoff-cv2-dst-stage-deploy.md
  - topics/profiling-and-performance/notes/concepts/2026-05-20_memray-runner-investigation.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-status.md
incoming_updated: 2026-05-27
---

# cv2 dst= preallocation — soak status tracker

The durable status surface for the §30 Phase 2.5 [[opencv-entity|cv2]] `dst=` preallocation rollout (actuate-libraries#348 → PR #349 → vms-connector PR #1696 → soak → stable promotion). Companion to the handoffs that accumulate per-session under [[2026-05-19_handoff-cv2-dst-stage-deploy|the cv2-dst handoff]] (and any successors); this note keeps state across sessions so each handoff stays a focused next-day plan rather than the whole history.

> **Convention.** Append to **History** chronologically; edit the **Current State** + **Pending Steps** sections in place. Don't rewrite history.

## Current State

| Aspect | Value |
|---|---|
| Library PR | [aegissystems/actuate-libraries#349](https://github.com/aegissystems/actuate-libraries/pull/349) — **draft**, CI green for 3 days |
| Library branch | `feature/actuate-movement-cv2-dst-preallocation` |
| Library dev version | `actuate-movement==1.2.7.dev1+feature.actuate.movement.cv2.dst.preallocation` (auto-republished on every push) |
| Connector PR | [aegissystems/vms-connector#1696](https://github.com/aegissystems/vms-connector/pull/1696) — **draft**, CI green |
| Connector branch | `feature/test-actuate-movement-cv2-dst` (worktree `/tmp/vms-connector-cv2`) |
| Connector pin | `actuate-movement==1.2.7.dev1+...` (dev pin intact) |
| Webcam fixture | Lives in connector PR #1696 (`test_settings/webcam_rtsp/`, `VMS_CONNECTOR_LOCAL_WEBCAM.setting.json`, `run-webcam-profile.sh`) |
| Last validation | 90 s webcam run 2026-05-18: `_decode_packet` 35 % self-time confirmed; RSS slope 153 MB/min warmup-dominated; flamegraph render hung (now fixed 2026-05-19) |
| Soak target | **TBD** — avoid co-stacking with #1703 soak candidate cust 41399 (Eyeforce AmeriGas Sacramento) |
| Verdict | **Pending** — staged-release plan revised 2026-05-19: real-customer soak required before #349 stable promotion |

## Pending Steps

In order:

1. ⬜ **Pick soak target site.** Constraint: not cust 41399 (held for #1703). Need a steady-state real-customer signal — RSS slope + motion-event counts + alert verdicts vs the same site on `rearchitecture` as baseline.
2. ⬜ **Deploy `feature/test-actuate-movement-cv2-dst` (dev pin intact) to the soak target — PREFER §29's new admin-API custom-branch deploy flow once wired** (per [[2026-05-20_deploy-branch-full-scope]] + §29 mark-todos), connector_deployer as fallback. Bundled changes on the branch: cv2-dst pin + #1694 mem-breakdown env-var + harness changes. Verify the cronjob's `container_image` tag is slash-encoded either way (`feat-foo` not `feat/foo`) — see `feedback_check_image_tag_after_deployer_push`. *(2026-05-21: this is the natural first end-to-end customer of the §29 flow; if §29 per-customer surface lands today, route through it; if it slips, take the connector_deployer path same-day rather than wait.)*
3. ⬜ **Soak 24–48 h.** Capture RSS slope, motion-event counts, alert verdicts, alert-confusion-matrix vs same-site `rearchitecture` baseline.
4. ⬜ **Verdict.**
   - Clean → ready PR #349 for review → merge to stable → bump #1696 pin from dev to `1.2.7` stable → merge #1696 to `stage` → stage soak.
   - Regressed → keep dev pin, iterate on `feature/actuate-movement-cv2-dst-preallocation`.

## Harness papercuts (parallel to soak)

Working copy: `/tmp/actuate-instrumentation-v1` (branch `feature/actuate-instrumentation-v1`, stash applied, uncommitted). Tracked in detail in [[2026-05-19_handoff-cv2-dst-stage-deploy#harness-papercuts-not-blocking-step-1-but-worth-landing-before-the-next-long-run]].

- ✅ **`render_flamegraph` no longer hangs** — `subprocess.run` → `Popen` + `wait(timeout=180)` + process-group kill, returns 124 on timeout, log line on timeout. Backwards-compat. 17 harness tests pass. *(landed 2026-05-19, uncommitted in worktree)*
- ✅ **Webcam wrapper default `DURATION` 5m → 90s** — matches 2026-05-18 clean validation length. *(landed 2026-05-19, uncommitted in [[opencv-entity|cv2]] worktree)*
- 🔴 **memray runner produces no usable output — DEFERRED 2026-05-20.** Post-fix run still fails cleanly (180 s flamegraph timeout fires, 120 s stats timeout fires, allocation-hotspots section empty, total ~5+ min slow-failing tail per memray run). memray runner now **skipped by default** in `run-webcam-profile.sh` (`SKIP_MEMRAY=1`); py-spy is unaffected and produces the primary CPU-hotspot signal. Full hypothesis list + investigation plan: [[2026-05-20_memray-runner-investigation]]. Re-enable with `SKIP_MEMRAY=0` once the runner produces output.
- ✅ **Configurable `_log_memory_breakdown` interval** ([vms-connector#1694](https://github.com/aegissystems/vms-connector/issues/1694)) — implemented 2026-05-20. `ACTUATE_MEMORY_BREAKDOWN_INTERVAL_S` env var spawns a dedicated `mn_mem` thread when set; `monitor_metrics` skips the breakdown call when decoupled. Default behavior unchanged. Webcam wrapper sets `MEMORY_BREAKDOWN_INTERVAL_S=15` by default. *(landed in [[opencv-entity|cv2]] worktree, uncommitted; lands on PR #1696 bundled with cv2-dst pin per [[2026-05-19_cv2-dst-soak-status#bundling-decision-2026-05-20|bundling decision]])*
- ✅ **`--connector-dir` flag on `actuate-profile session`** — added 2026-05-20 to harness CLI + `run_session`. Lets the harness target a non-default connector worktree (e.g. `/tmp/vms-connector-cv2`). Without it, the wrapper's settings substitution affects the [[opencv-entity|cv2]] worktree but the connector runs against `/home/mork/work/vms-connector` — the bug that masked the #1694 implementation in the first post-fix run. *(landed in instrumentation worktree, uncommitted)*
- ⏭️ **Drop `--idle` from py-spy invocation** — **no-op, papercut closed 2026-05-20.** Inspected `runners/pyspy.py`; `--idle` was never set (default off). The remaining idle-loop dominance in the speedscope report (`expire_items` 15.7 %, `monitor_metrics` 12.3 %, `_memory_breakdown_loop` 10.4 % in the 2026-05-20 17:31:59Z run) reflects py-spy's "show traces unless thread is not in any frame" semantics, NOT a misconfigured flag. Adding `--gil` would filter further but at the cost of hiding C-extension CPU (libav decode, NumPy, [[opencv-entity|OpenCV]]) — exactly the work cv2-dst affects. Resolved by running an apples-to-apples baseline on `rearchitecture` against the same fixture instead.
- ⬜ **Native `webcam-local` harness scenario** — drop the LOCAL_WEBCAM→LOCAL_RTSP swap in `run-webcam-profile.sh` once the harness lands stable.

## Caveat for short runs

`_log_memory_breakdown` ticks every 60 s by default. The new `DURATION=90s` webcam-wrapper default captures only ~1 cycle — sufficient for py-spy + memray hotspot reads, **not** for RSS-slope analysis. Bump `DURATION=180s` or longer if RSS-slope data is the goal until #1694 lands.

## Decision Log

- **2026-05-19** — Do **not** promote #349 to stable directly from stage. Plan revised: real-customer soak (dev-pinned connector branch via connector_deployer) **before** stable promotion. Reason: stage carries the historical "dev-pin pollution" cost; the connector_deployer path is the right venue for dev-version validation per CLAUDE.md "Dev versions" rule.
- **2026-05-19** — Webcam wrapper `DURATION` default shortened 5m → 90s. Reason: 2026-05-18 90 s pass produced clean hotspot read; 5 min was over-budgeted and amplified the flamegraph-render hang.
- **2026-05-20 — Bundling decision** {#bundling-decision-2026-05-20}: connector PR #1696 will bundle **#1696 (cv2-dst pin bump) + #1694 (memory-breakdown interval env-var)** into a single soak. #1693 (SSL-context churn) stays separate — it's still investigative (unknown if intentional per-tenant isolation), would couple a low-risk numerically-equivalent change to an unknown-risk hoist, and bisecting is cheaper when those two live on separate branches. #1694 directly improves measurement quality for the cv2-dst soak (gives ~6 breakdown cycles per 90 s instead of 0), which is why it goes in the same bundle.
- **2026-05-20** — memray runner deferred. After the 180 s flamegraph timeout fix, memray still produces no usable output (5+ min slow-failing tail per run, empty allocation-hotspots). Skipped by default (`SKIP_MEMRAY=1` in wrapper). py-spy carries the CPU-hotspot signal for the soak. Investigation note: [[2026-05-20_memray-runner-investigation]].
- **2026-05-21** — Soak-deploy path bound to §29's new admin-API custom-branch flow when ready. Rationale: bundling the cv2-dst soak against §29's first real customer is the cleanest end-to-end validation of the §29 lifecycle (register-branch → deploy → audit → expire) on a known-shape change with a clear regression signal. Connector_deployer remains the same-day fallback if §29's per-customer surface slips. Cross-cut tracked in `mark-todos.md` §30 Phase 2.5 ([[opencv-entity|cv2]] sub-items) + §29 (per-customer endpoint bodies).

## History

- **2026-05-14** — First hotspot read ([[2026-05-14_first-hotspot-findings]]) — [[opencv-entity|cv2]] `dst=` preallocation identified as highest-EV easy fix: −42 % cumulative bytes, −86 % in `actuate_movement`.
- **2026-05-15** — PRs #349 (library) + #1696 (connector) pushed as drafts.
- **2026-05-18** — Webcam fixture landed on #1696. 90 s validation pass clean except for flamegraph render hang (process `S` state, 0% CPU, killed after 17 min).
- **2026-05-19** — Plan revised: soak required before stable promotion ([[2026-05-19_handoff-cv2-dst-stage-deploy]]). Harness papercut #1 (flamegraph render timeout) landed in worktree; webcam wrapper `DURATION` default lowered to 90s. This status tracker created during session-wrap.

## Related

- Handoff (active): [[2026-05-19_handoff-cv2-dst-stage-deploy]]
- First hotspot findings: [[2026-05-14_first-hotspot-findings]]
- Profiling toolkit roadmap: [[2026-05-12_profiling-toolkit-and-roadmap]]
- Workstream: §30 in `mark-todos.md`
- GH issues: actuate-libraries#348, vms-connector#1693, vms-connector#1694
- Jira: ENG-246
- Sibling tracker (longer-arc project this slots under): [[2026-05-19_live-streaming-v1-status]]
