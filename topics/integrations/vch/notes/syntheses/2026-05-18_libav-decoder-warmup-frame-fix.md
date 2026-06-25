---
title: "VCH NOVIDEO root cause: libav decoder warmup-frame artifact (validated fix)"
type: synthesis
topic: integrations/vch
tags: [vch, healthcheck, libav, pyav, decoder, downsampling, novideo, false-positive, root-cause, fix, autopatrol]
created: 2026-05-18
updated: 2026-05-18
author: mark
[]
incoming:
  - topics/camera-health-monitoring/notes/concepts/2026-05-14_chm-multi-frame-quality-sampling-followup.md
  - topics/integrations/lisa/notes/concepts/2026-05-18_lisa-alert-sender-credential-logging.md
  - topics/integrations/vch/notes/entities/vch-components.md
  - topics/personal-notes/notes/daily/2026-05-18.md
incoming_updated: 2026-05-19
---

# VCH NOVIDEO root cause: libav decoder warmup-frame artifact (validated fix)

## TL;DR

Eyeforce was seeing "Low Entropy View" (NOVIDEO) alerts on nearly every VCH camera at site 16258 ("ABC Liquor Store 27"). After 4 days of incremental fixes and live-traffic validation, the root cause turned out to be a **libav ([[pyav-entity|PyAV]]) decoder artifact**: when a fragmented MP4 fragment from Immix starts mid-GOP, a fresh `av.open()` decoder context yields its first decoded frame as an **uninitialized zero-pixel buffer** (P-frame with no reference I-frame in the decoder's buffer pool). Empirically confirmed by **MD5-identical pure-black 720x480 JPEGs** (`344acf395...`) saved as `current_image` on multiple cameras' NOVIDEO alerts.

This frame is silently dropped by downstream filters in continuous-detection mode. In VCH healthcheck mode the ~2s clip plus the 1s downsampling gate frequently collapse the queue to exactly that one zero-buffer push, the entropy score is 0, and a spurious "Camera Image Blank" alert fires.

The full validated fix has three independent pieces, all required for end-to-end correctness. Shipped on `feat/vch-multi-frame-quality-sampling` (vms-connector) + `feat/autopatrol-tier-from-configured-codes` (actuate-libraries, merged as PR #350).

## Symptoms

- Eyeforce VCH cronjob `connector-40799-vch-1069-chm-cronjob` firing 20-39 NOVIDEO alerts per run (varying with active camera count). Site has been "in maintenance" status for weeks because dispatchers see constant blank-camera alarms.
- Mark visually inspected real clips from these cameras: **first few frames blank, then real content.** Not a customer-side NVR problem.
- Saved `current_image` JPEGs in the alert payloads were 6027 bytes each, MD5 `344acf395044ac0d362ca3c7f22fa5eb5`, 720x480 RGB with **one unique pixel value: (0, 0, 0)**. Identical across cameras → systemic decoder behaviour, not real video.

## Three-part fix (in dependency order)

### Part 1 — Multi-frame entropy/blur scoring (`vms-connector`)

Pre-fix: `BaseHealthcheckCamera.start_healthcheck_job` consumed the first frame from the per-camera queue, scored it via `image_quality_check`, then drained the rest of the queue without scoring. So a single warm-up bad frame at the head of the clip condemned the camera even when later frames carried real content.

Post-fix: `BaseHealthcheckCamera` gains a `_score_full_clip` class attribute (default `False` to preserve non-VCH CHM behaviour). `VCHCamera` overrides to `True`. When enabled, the drain loop runs `image_quality_check` on every frame, and `image_quality_check` max-aggregates entropy and blur across the clip (first sample sets, subsequent samples take max). Single S3 upload of a representative bad frame per run via a `frame_key` guard.

**Side effect:** alert copy fix on the VCH path — `"Low Entropy View"` → `"Camera Image Blank"` (matches the existing healthcheck-email wording in `StreamQualityHealthcheckAlertGenerator`).

### Part 2 — Drain-after-puller-finishes ordering fix (`vms-connector`)

Part 1 alone produced **identically 1 frame scored per camera** despite the loop being structurally correct. Root cause: the drain loop ran *while the puller thread was still pushing* — `while not frame_queue.empty()` checked `empty()` faster than the puller's `put_nowait()` arrived for late frames, exited the loop early, and the puller's remaining frames went into the queue after the drain had quit and were thrown away during `_cleanup_camera_resources`.

Fix: move the drain to **after** `thread.join()`. The puller has finished pushing by then; the queue is static; `while not empty: get()` is race-free because no producer is active. First-frame block-get still happens before join (for early-fail on connection issues), so the diagnostic semantics are preserved.

Generalisable lesson: `while not queue.empty(): queue.get()` is fundamentally racy when there's a concurrent producer. Either drain after the producer is joined, or use blocking `get(timeout=X)` until `Empty` is raised.

### Part 3 — libav decoder warmup-frame skip (`actuate-libraries/actuate-pullers`)

After Part 1 + Part 2 landed, NOVIDEO alerts dropped from 39/39 to ~5/39 on site 16258 — a 87% improvement. The 5 cameras still failing had `Frame Count` log values of 1-4 (decoded frames) but **only 1 entropy line each** with entropy=0.0. The saved-frame MD5 evidence then surfaced: the one scored frame for those cameras was identical pure-black across all 5 cameras, identical to other unrelated cameras' first frame in different runs. Conclusion: libav's first decoded frame from each fragment is an uninitialized buffer.

Fix in `AutopatrolWebSocketStreamPuller.consume_stream`: skip exactly the first frame yielded by `container.decode(video=0)` per fragment when `healthcheck_mode=True`. (The `healthcheck_mode` parameter already existed in the signature but had been dead code for months — repurposed.) Non-healthcheck callers (continuous AutoPatrol monitoring) are unaffected.

**Behaviour change to flag:** cameras whose `Frame Count` is exactly 1 (decoder produced no second frame) flip from NOVIDEO → CNCTNFAIL after this fix. They now produce zero pushed frames → consumer times out → `broken_stream=True` → connection-failure alert. This is more accurate (the camera really didn't deliver usable video in the 2s clip) but it IS a different alert code on Hedrick's dashboard.

## Why downsampling makes this worse for VCH

The puller applies `frame_interval = 1.0 / self.highest_fps` as a per-frame downsampling gate. For VCH with `highest_fps = 1`, only frames spaced ≥1s apart get pushed. Combined with Immix's 2-second VCH clip duration, that means a typical clip yields 1-2 pushes — often 1, depending on frame timing. When the only push is the warmup zero buffer, the entropy verdict has no other signal.

We considered disabling downsampling entirely for healthcheck mode (the dead-code `healthcheck_mode` parameter's original documented purpose) and rejected it as too risky — downsampling is load-bearing in every other puller context and the per-integration FPS budget assumptions would need to be re-audited. Mark explicitly preferred Part 3 (skip first frame) over Part 2-style alternative (block-with-timeout in the drain).

## Validation outcomes (Eyeforce site 16258, 2026-05-15 → 2026-05-18)

| Stage | NOVIDEO per run | Frames scored / camera | Notes |
|---|---|---|---|
| Pre-fix baseline | 39 / 39 cameras | 1 (first warm-up frame) | All entropy=0.0 |
| Part 1 + 2 only | ~5 / 39 cameras | 2 on most cameras | 22/28 cameras have median entropy 6.61; 5 stuck on warmup zero |
| Parts 1 + 2 + 3 | **0 / 39 cameras** | 2 real-content lines per camera, both > 1.5 | Range 6.55–6.79 on the 5 previously-failing cameras |

The 19:23 UTC 2026-05-18 firing was the first run with the complete fix; zero NOVIDEO alerts on the 39-cohort that had been alerting daily for weeks.

## Adjacent / follow-up

- **CHM extension** ([[2026-05-14_chm-multi-frame-quality-sampling-followup]]): the multi-frame + drain-ordering fix is currently gated behind `_score_full_clip = True` on `VCHCamera` only. Extending it to non-VCH `*HealthcheckCamera` subclasses ([[rtsp-deep-dive|RTSP]]/DW/Avigilon/Exacq/[[hikcentral-components|Hikcentral]]/Openeye/Star4Live) is a separate decision. The libav warmup-frame finding (Part 3) is a generic [[pyav-entity|PyAV]] artifact that may exist on *any* fragmented-MP4 puller path, not just `AutopatrolWebSocketStreamPuller` — worth a separate audit if other healthcheck paths use the same decoder pattern.
- **`connector_deployer` slash-in-tag bug**: discovered during this validation cycle. Branch names with `/` written verbatim into K8s image tags cause `Waiting: InvalidImageName`. Filed as [aegissystems/connector_deployer#171](https://github.com/aegissystems/connector_deployer/issues/171); workaround was to manually `kubectl patch` the cronjob. See [[feedback-check-image-tag-after-deployer-push]].
- **Lisa logging credential leak** discovered as collateral during the security review of the alarm-senders bump that this PR pulls in: [[2026-05-18_lisa-alert-sender-credential-logging]].
- **AutoPatrol patrol-wide tier reporting**: shipped in the same library PR (#350). VCH stays Tier 1 per spec; AutoPatrol now sends the highest-configured tier on both `get_patrol_stream` and `raise_patrol_alert` (was hardcoded `THREAT` for alerts, default `HEALTHCHECK` for stream fetches). Live validation on a non-VCH AutoPatrol site is a separate follow-up tracked in [[mark-todos]].

## Source pointers

- `vms-connector/camera/shared/base_healthcheck_camera.py` — `start_healthcheck_job` consumer-side drain + `image_quality_check` multi-frame aggregation
- `vms-connector/camera/autopatrol/vch_camera.py` — `_score_full_clip = True` override
- `vms-connector/healthcheck/alerts/senders/vch_alert_sender.py:265` — alert copy fix
- `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py` — warmup-frame skip (search `skip_warmup_frame`)
- vms-connector PR [#1699](https://github.com/aegissystems/vms-connector/pull/1699)
- actuate-libraries PR [#350](https://github.com/aegissystems/actuate-libraries/pull/350)

## Cross-references

- [[vch-components]] — VCH integration entity (per-camera 2s clip, sampling notes)
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — Immix-side worker lifecycle (origin of the 2s VCH clip duration)
- [[2026-05-14_autopatrol-tier-model-and-detection-types]] — Immix tier spec
- [[2026-05-14_autopatrol-tier-api-cross-reference]] — tier-spec ↔ code gap analysis
- [[2026-05-14_chm-multi-frame-quality-sampling-followup]] — CHM extension prereqs
- [[feedback-check-image-tag-after-deployer-push]] — deployer slash-in-tag trap
- [[feedback_no_manual_jobs_on_customer_sites]] — validation cadence discipline
