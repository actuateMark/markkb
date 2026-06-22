---
title: "Follow-up: extend multi-frame entropy/blur sampling to non-VCH CHM"
type: concept
topic: camera-health-monitoring
tags: [chm, vch, healthcheck, entropy, blur, sampling, follow-up, backlog]
created: 2026-05-14
updated: 2026-05-14
author: mark
[]
incoming:
  - No backlinks found.
incoming_updated: 2026-05-15
---

# Follow-up: extend multi-frame entropy/blur sampling to non-VCH CHM

## What

On 2026-05-14 we shipped a feature branch (`feat/vch-multi-frame-quality-sampling`, PR'd into `stage`) that flips VCH from single-first-frame to whole-clip max-aggregated entropy/blur scoring. Implementation is in `BaseHealthcheckCamera` and is gated by a class attribute `_score_full_clip` defaulting to `False`; only `VCHCamera` flips it to `True`.

**The change is therefore VCH-only by intent.** All other `BaseHealthcheckCamera` subclasses (`RTSPHealthcheckCamera`, `DWHealthcheckCamera`, `AvigilonHealthcheckCamera`, `ExacqHealthcheckCamera`, `HikcentralHealthcheckCamera`, `OpeneyeHealthcheckCamera`, `Star4LiveHealthcheckCamera`, …) still score the first drained frame only.

## Why this is a follow-up rather than a same-PR change

VCH was the loud incident driver — Eyeforce reported "Low Entropy View" alarms on almost every patrol, traced to first-frame warmup blackness on Immix-served ~2-second clips (see `[[2026-05-06_immix-streamfailed-worker-lifespan]]` for VCH's 2s default). For the feature test on 2026-05-14 we wanted minimum blast radius: change VCH behavior, leave standard CHM (continuous detection cronjob) behavior alone.

The same sampling weakness exists in standard CHM in principle — the consumer-side loop at `vms-connector/camera/shared/base_healthcheck_camera.py::start_healthcheck_job` is shared — but CHM's clip semantics are different per integration ([[rtsp-deep-dive|RTSP]] keeps a long-lived stream; DW/Eagle Eye/[[hikcentral-components|Hikcentral]] etc. each have their own puller cadence) and the failure-mode profile is unknown. We don't want to ride the VCH validation cycle with a fleet-wide behavior change.

## Decision questions for the follow-up

1. **Per-integration enablement, or a global config flip?** A `_score_full_clip = True` override on each integration's `*HealthcheckCamera` subclass mirrors the VCH pattern but requires per-integration risk review. A single `customer.healthcheck.score_full_clip` config field on `BaseConnectorConfig` is more centralized but loses per-integration granularity for the rollout.
2. **Aggregation choice.** Max-of-clip is right for VCH because the question is "did the camera ever return a real picture in the 2s window?". For CHM where multi-second clips can include legitimately transitioning frames (PTZ moves, light changes, sleep-frame insertions), median-of-clip may better reflect "is this stream typically healthy?". Worth a metric histogram before deciding.
3. **Does the existing CHM `frame_key` upload pattern survive the change?** Today CHM saves a single frame per bad verdict. Multi-frame max-aggregation preserves that — frame_key is only saved once on the first bad sample, and the alert path only consults it when the final verdict is invalid (so transient bad frames that get max'd away leave an orphaned S3 object harmlessly unreferenced). Same trade-off as VCH; need to confirm S3 cost impact is negligible.
4. **What about the live (non-healthcheck) pipeline path?** `BaseCamera.image_quality_check` at `camera/shared/base_camera.py:394` is already invoked per-frame inside the continuous [[detection-pipeline|detection pipeline]], so it doesn't have the single-frame sampling weakness. No change needed there.

## Source pointers

- `vms-connector/camera/shared/base_healthcheck_camera.py` — the shared healthcheck loop and `image_quality_check`. The `_score_full_clip` gate is at the top of the class.
- `vms-connector/camera/autopatrol/vch_camera.py` — only override today; flips the gate to `True`.
- `vms-connector/test_vms/test_healthcheck.py::TestVCHMultiFrameQualityScoring` — unit tests covering both gate states. Reuse the harness for any per-integration enablement.
- `actuate-libraries/actuate-blur/.../blur_handler.py::calculate_entropy` — the underlying scorer. Returns 0 on `hist.sum() == 0` (all-zero frame) and 0 on any exception.

## 2026-05-18 update — VCH validation outcome shifts the criteria

VCH validation finished 2026-05-18 with **0/39 NOVIDEO alerts** on Eyeforce site 16258 (down from 39/39 baseline). The fix landed in three parts, not just the originally-scoped multi-frame scoring:

1. Multi-frame scoring (consumer-side, this note's original scope) — required but insufficient on its own.
2. Drain-after-`thread.join()` ordering fix — the original drain raced against the puller, so multi-frame stayed at 1 frame/camera in practice.
3. **libav decoder warmup-frame skip** on the puller side (`actuate-pullers/.../autopatrol_websocket_stream_puller.py`) — the root cause of the residual 5 cameras still firing NOVIDEO after parts 1+2. libav yields an uninitialized zero-pixel buffer as the first decoded frame after a fresh `av.open()` on a fragmented MP4 (P-frame without its reference I-frame in the new decoder context). MD5-identical pure-black 720x480 JPEGs across cameras confirmed it empirically. Full story: [[2026-05-18_libav-decoder-warmup-frame-fix]].

**This changes the prereqs for CHM extension.** Part 3 (warmup-frame skip) is a *generic* [[pyav-entity|PyAV]] artifact — it likely affects **any** healthcheck puller path that uses `av.open()` on a fragmented MP4 stream, not just `AutopatrolWebSocketStreamPuller`. Part 1 (multi-frame scoring) alone won't fix CHM if the underlying healthcheck stream has the same warmup-frame issue.

## Prerequisites before flipping CHM on

- **Audit which CHM puller(s) use fragmented-MP4 + `av.open()` per fragment** (the libav warmup-frame artifact applies). For each, decide whether the warmup-skip is also needed. Candidate pullers to check first: any subclass of `AvUrlFramePuller`, anything that opens av containers per-fragment.
- ~~Pull NR distributions of per-camera entropy values from `"Calculated entropy for"` log lines across non-VCH integrations for ~7 days and confirm the long-tail of "fails first-frame, passes subsequent frames" is non-trivial.~~ Reframed: with the VCH validation evidence in hand, we know the warmup-frame phenomenon is real and systemic. The NR-distribution question now reduces to "do non-VCH integrations *also* drop the warmup frame downstream (silent in continuous mode), or do they accept it as a healthcheck signal?" Worth a targeted NR query per integration before flipping.
- Decide aggregation (max vs median) per the metric review. (Max still seems right; median is only better if multi-second clips include legitimately transitioning frames — PTZ moves, light changes — which is uncommon for [[healthchecks]].)
- Pick enablement strategy (per-integration vs global config).
- **Confirm `frame_key` upload semantics** in the multi-frame path — the current implementation uploads once on the first bad sample. If `StreamQualityPacket` is held across runs (`self._BaseCamera__stream_quality[puller_name]`), verify the `frame_key` gets reset between runs so a once-bad camera re-uploads on subsequent failures. Flagged in actuate-pr-reviewer pass on PR #1699.

## Cross-references

- [[vch-components]] — VCH per-camera 2s clip duration, sampling notes (updated 2026-05-18 post-validation).
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — origin of the "Duration=2" Immix default for VCH.
- [[2026-05-18_libav-decoder-warmup-frame-fix]] — Part 3 of the VCH fix; the libav warmup-frame artifact that this note now folds in as a CHM-extension prereq.
- [[chm-diagnostics-architecture]] — overall CHM diagnostic structure.
