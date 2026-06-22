---
title: "First Hotspot Findings — actuate-profile vs RTSP-local"
type: synthesis
topic: profiling-and-performance
tags: [actuate-instrumentation, profiling, vms-connector, hotspots, motion-detection, optimization]
created: 2026-05-14
updated: 2026-05-14
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/daily/2026-05-15.md
  - topics/personal-notes/notes/daily/2026-05-18.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-14_actuate-profile-report-subcommand.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_handoff-cv2-dst-stage-deploy.md
  - topics/profiling-and-performance/notes/concepts/2026-05-20_memray-runner-investigation.md
incoming_updated: 2026-05-27
---

# First Hotspot Findings — `actuate-profile` vs RTSP-local

First analytical output from the [[2026-05-12_actuate-instrumentation-v1-installed|actuate-instrumentation v1]] profiling suite. The session orchestrator validated against the [[rtsp-deep-dive|RTSP]] simulator on 2026-05-13 produced ~15 MB of artifacts (py-spy speedscope, memray bin + flamegraph, RSS CSVs, connector logs). On 2026-05-14 we added an `actuate-profile report` subcommand ([[2026-05-14_actuate-profile-report-subcommand]]) that extracts top CPU functions, top allocators, and the RSS trajectory into a single `report.md` per session. This is the first read of what the suite actually surfaces.

## Source artifacts

- Run: `profile_20260513T194937Z`, scenario `rtsp-local`, 60 s per runner.
- Connector SHA `da3161f536cd`, libraries SHA `877f8b1f4eb3` (the v1 branch).
- Single camera, single-stream RTSP-sim, motion-detection pipeline active.

## CPU hotspots (60 s py-spy, sampled at 100 Hz across 23 thread profiles)

| Rank | Self % | Function | Site |
|------|--------|----------|------|
| 1 | 25.3 | `_decode_packet` | `actuate_pullers/url/av_url_puller.py:774` |
| 2 | 11.2 | `expire_items` | `actuate_image_cache/ttl_image_cache.py:40` |
| 3 | 9.8 | `run` (puller loop) | `actuate_pullers/url/av_url_puller.py:1270` |
| 4–5 | 11.2 | `monitor_metrics` + `monitor_event_clips` | `analytics_site_manager.py:355,379` |
| 6 | 4.1 | `preprocess_frame` | `actuate_movement/fdmd/frame_diff_motion_detector.py:316` |

The #1 result confirms the known CPU-only [[h264-deep-dive|H.264]] decode finding — [[rtsp-deep-dive|RTSP]] packet decode dominates the CPU budget on a CPU-only build. Rank #2 is a **measurement artifact**: `expire_items` is `while True: time.sleep(15); …` — it can only appear unless py-spy was invoked with `--idle`. Need to check `runners/pyspy.py` and drop the flag if so.

## Allocation hotspots (60 s memray, native, follow-fork)

Total: 2.1 M allocations, 3.0 GB cumulative bytes, 278 MB peak.

| Rank | Size | % | Function | Site |
|------|------|---|----------|------|
| 1 | 552 MB | 18.4 | `resize` | `actuate_movement/core/motion_utils.py:111` |
| 2 | 276 MB | 9.2 | `run` | `actuate_pullers/url/av_url_puller.py:1365` |
| 3 | 191 MB | 6.4 | `preprocess_frame` | `actuate_movement/fdmd/frame_diff_motion_detector.py:316` |
| 4 | 187 MB | 6.2 | `get_delta_noise` | `actuate_movement/fdmd/frame_diff_motion_detector.py:725` |
| 5 | 184 MB | 6.1 | `preprocess_frame` | `actuate_movement/fdmd/frame_diff_motion_detector.py:314` |
| 8–10 | 275 MB combined | 9.2 | `get_threshold_img` | `frame_diff_motion_detector.py:384–392` |

The frame-diff motion-detection pipeline (`actuate-movement`) accounts for **~40% of cumulative bytes**. Every site is a `cv2.<op>(src)` returning a fresh `numpy` array per frame: `resize`, `cvtColor`, `GaussianBlur`, `absdiff`, `threshold`, `dilate`, `erode`. The #1 line (`motion_utils.py:111`) is the same site that caused the snapshot-drift bug during Exp 1 development.

**By count:** `ssl_wrap_socket` `urllib3/util/ssl_.py:461` is **60% of all allocations** (1.25 M calls), with `load_default_certs` at #2. This points to SSL-context churn on the connector's outbound HTTPS calls — most likely frame-preview uploads creating a new SSL context per request instead of reusing a session.

## RSS trajectory

- py-spy run (60 s): 11 → 425 MB, slope +414 MB/min. Warm-up dominates; not a leak signal.
- memray run (390 s): 89 → 432 MB, peak 459, slope **+53 MB/min steady state** after warm-up. The growth pattern §30 was set up to find.

## What is and isn't easy to fix

**Easily fixed (library-scoped, repeatable pattern):**

- **`cv2.foo(src)` → `cv2.foo(src, dst=…)`** in `actuate-movement` — every [[opencv-entity|cv2]] op in the frame-diff path supports a preallocated output buffer. Per-detector buffer allocation gated on shape (re-allocate when shape changes; in practice resolution is per-camera-stream stable). Estimated **~40% reduction in cumulative bytes** across `motion_utils.resize`, `preprocess_frame`, `get_threshold_img`, `get_delta_noise`. ~50 LOC in `actuate-movement`, one PR.

**Easy but in vms-connector, not the library:**

- **SSL-context churn** — find the outbound HTTPS call sites making 1.25 M handshakes and switch to a module-scope `requests.Session()` (or rely on boto3's built-in pooling for S3). Mechanical fix once the call site is located.

**Measurement gotcha:**

- Drop `--idle` from py-spy invocation if set — `expire_items` is sleeping, not working.

**Hard (out of scope for now):**

- `_decode_packet` 25% CPU — [[h264-deep-dive|H.264]] decode is genuine work; only fix is hardware-accelerated decode (already tracked) or a different codec path.

## Recommended next move

Start with the `cv2.dst=` preallocation in `actuate-movement`. Highest-payoff single change, scoped to one library, repeatable pattern, and we have the artifact baseline to A/B against: re-run the same scenario after the change and diff the two `report.md` files. The SSL-session fix is similar effort but lives in the connector; pair it as a follow-up rather than bundling.

## Related

- Tooling: [[2026-05-14_actuate-profile-report-subcommand]]
- Library: [[2026-05-12_actuate-instrumentation-v1-installed]]
- Design: [[2026-05-12_adr-actuate-instrumentation-v1]]
- Roadmap: [[2026-05-12_profiling-toolkit-and-roadmap]]
- Connector inventory (one-shot tooling pre-suite): [[tooling-inventory]]
- Workstream: §30 in `mark-todos.md`
- Jira: ENG-246
