---
title: "Verifier / video-clip integration — 'no alerts found' for confirmed clip detection"
type: synthesis
topic: vms-connector
tags: [verifier, video-integration, alerts, window_ids, create-detection-window, working-as-intended, sliding-window]
created: 2026-06-03
updated: 2026-06-03
author: kb-bot
---

# Verifier / video-clip "no alerts found" investigation

**Context:** 2026-06-01, clip `pistol-short.mp4` uploaded to connector-34952 (integration_type=video, product=Gun, user automation-test@actuate.ai). Pistol detected @84%, detection window opened+closed cleanly, but `create-detection-window` logged `no alerts found for {window_id}` and nothing appeared in the admin alert view.

## Alert-creation precondition chain (file:line)

The admin alert view is backed by the **`WindowIdsV2`** DynamoDB table:
- Admin reads it via monitoring-api; `actuate_admin/monitoring/alert_helpers.py:24` (`WindowIdsV2 = dynamodb.Table("WindowIdsV2")`), GSI `customer_name-approx_capture_timestamp-index` (line 28). AlertRecord fields (`window_id`, `approx_capture_timestamp`, `alert_labels`, `mp4_bucket`, `mp4_path`) map 1:1 to the WindowIdsV2 schema.
- The standalone `alertviewer` and camera-ui read the same records (`alertviewer/CLAUDE.md`, `useAlert.js:47` throws `No alerts found` when `records.length===0`).

The **only writer** of a WindowIdsV2 record is `WindowIdsDAO.put_detection_window` (`actuate-libraries/actuate-daos/src/actuate_daos/window_ids.py:91`), and it is called from exactly one place: `MultiAlertSender.trigger_alert` (`actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/shared_alert/multi_alert_sender.py:177`). `put_detection_window` runs **before** the `if feature.live_alert:` dispatch gate (line 189), so the admin RECORD is written even when live dispatch/recipients are absent.

`trigger_alert` only runs when `send_alerts` decides `fire_now/fire_deferred` (`vms-connector/camera/shared/base_stream_camera.py:893, 914, 932`). `fire_now = window.send_alert and not window.alert_sent` (line 893). `window.send_alert` is set only when the sliding window's alert threshold is reached: `threshhold_reached` → `send_alert = True` (`actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/post_processors/sliding_window_step.py:179`), gated by `thresh <= confirmed_frame_count` (line 94). Default window is `thresh=2, denominator=5` (`actuate-pipeline-objects/.../window_packet.py:5-6`) — needs 2 confirmed frames in a 5-frame window.

**The precondition that, if missing, yields "no alerts found":** a WindowIdsV2 record (written by `put_detection_window`), which requires the sliding window to reach its **alert threshold** (`confirmed_frame_count >= thresh`), not merely to **open**.

## The divergence / break

A detection window **opens** on the first per-frame confirmed label (`sliding_window_step.py:78-82`, gated by per-frame confidence `detection_percentage` default 0.6). A window **closes** on time/frame-budget exhaustion (line 58/61). `close_window` POSTs to the create-detection-window MP4 service for **every** window that closes, regardless of whether it alerted (`sliding_window_step.py:106-110`). `base_stream_camera.endrun()` does the same for every entry in `current_window_ids` (line 1306-1311), and `current_window_ids` is populated for every window seen (line 888-891) — again independent of alerting.

So a window can OPEN (window_id assigned) and CLOSE (POST fired → "window closed cleanly") **without ever reaching the alert threshold**, meaning `put_detection_window` never runs. The MP4 service receives the POST, queries `WindowIdsV2` by window_id GSI (`create_detection_window/app/core.py:465-474`, `config.py:31`), finds zero items, and logs `no alerts found for {window_id}` (`core.py:637`). Same root cause makes the admin view empty.

For `pistol-short.mp4`: 84% clears the per-frame open gate (>60%), so a window opened. But a SHORT clip likely did not accumulate `confirmed_frame_count >= 2` before the window/clip ended (sparse frames, absolute window length, clip exhausted). Window opened+closed, POST fired, no WindowIdsV2 record.

## Video path vs RTSP — two camera classes

The video factory (`vms-connector/connector_factories/video/videoclip_factory.py`) builds **two different camera classes**:
- `default()`/`dev()`/`local()` → `VerifierCamera` (`camera/videoclip/verifier_camera.py:14`) which **extends `BaseStreamCamera`** — full alert pipeline (send_alerts, trigger_alert, put_detection_window, create_detection_window in endrun). Uses `S3FramePuller`.
- `robo()`/`healthcheck()` → `VideoClipCamera` (`camera/videoclip/videoclip_camera.py:14`) which extends `BaseVerifierCamera` (`camera/shared/base_verifier_camera.py:26`) which extends `BaseCamera` (NOT BaseStreamCamera). This path has **NO MultiAlertSender, NO send_alerts, NO trigger_alert, NO put_detection_window, NO create_detection_window**; its `run()` drains the result_buffer and discards results (line 95-96), and `endrun()` is a no-op (line 140). Clip uploads launched via `--robo <batch_id>` (`connector.py:208,281`; `factory.py:143`) take this path → never writes WindowIdsV2 at all.

Both video camera classes route through the same admin/config plumbing (group/customer/feature_deployment) as RTSP — there is **no provisioning gap** on group/location/alert-config. The break is in the **runtime alert path**, not config.

## Verdict

Since the user observed create-detection-window being POSTed (it logged "no alerts found"), connector-34952 was running the `VerifierCamera`/BaseStreamCamera path (the robo path never POSTs). Most-likely cause **(b)+(threshold)**: the window opened and closed without reaching the 2-of-5 alert threshold on the short clip, so `put_detection_window` never wrote the WindowIdsV2 record. This is **largely by-design behaviour of the sliding window** (a 1-2 frame detection shouldn't necessarily alert) colliding with a **gap**: the create-detection-window POST and the admin-record write are decoupled, so a closed-but-not-alerted window produces a spurious "no alerts found" and zero admin visibility even though a high-confidence detection occurred.

It is **not** the no-recipient explanation (a) — `put_detection_window` precedes the `live_alert` dispatch gate, so a recipient-less test site would STILL get the admin record IF the threshold were reached. It is **not** a group/location/alert-config provisioning gap (c) — video uses the same config plumbing as RTSP.

## Where a fix would go

- If short authentic clips SHOULD alert: lower the alert threshold (`thresh`/`window_length`/`window_length_absolute`) for the video product config, OR special-case the video integration so a single high-confidence confirmed frame on a finite clip reaches threshold before the clip ends. Config-side in `actuate_admin` product/metric defaults for integration_type=video.
- If the gap itself is the bug: gate the `create_detection_window` POST in `sliding_window_step.close_window` (`sliding_window_step.py:106`) and `base_stream_camera.endrun` (`base_stream_camera.py:1309`) on `alert_sent`/a WindowIdsV2 record having been written, so the MP4 service is never asked to build a video for a window that never minted an alert. This removes the spurious "no alerts found" log but does NOT make the detection admin-visible.
- Verify the deployed runtype for connector-34952 (default VerifierCamera vs robo VideoClipCamera) in NR; if clip uploads run via `--robo`, the alert path is structurally absent and the fix is to give `BaseVerifierCamera` an alert/window-persist path or route video-clip processing through the BaseStreamCamera-based `VerifierCamera`.

## Key files
- `actuate-libraries/actuate-daos/src/actuate_daos/window_ids.py:62,91` — create_detection_window POST + put_detection_window (sole WindowIdsV2 writer)
- `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/shared_alert/multi_alert_sender.py:177,189` — put_detection_window before live_alert gate
- `actuate-libraries/actuate-pipeline/src/actuate_pipeline/steps/post_processors/sliding_window_step.py:94,106,179` — threshold + unconditional close POST
- `vms-connector/camera/shared/base_stream_camera.py:888,893,932,1306` — current_window_ids + fire gating + endrun POST
- `vms-connector/camera/shared/base_verifier_camera.py:95,140` — robo path discards results, no-op endrun
- `vms-connector/connector_factories/video/videoclip_factory.py:23,43` — VerifierCamera vs VideoClipCamera
- `create_detection_window/app/core.py:465,637` + `config.py:31` — WindowIdsV2 query + "no alerts found"
- `actuate_admin/monitoring/alert_helpers.py:24,28` — admin view reads WindowIdsV2

## RESOLUTION — confirmed 2026-06-03 (root cause = stale weapon conf gate, NOT a code bug)

Runtime evidence (NR, connector-34952, 2026-06-01 19:34 UTC) settles it:

- **Run mode = default**, not robo: camera class `actuate_config.connector.video.videoclip_config.VideoCameraStream`; `production_sliding_window_0` present (gauntlet has no sliding window). Zero robo/batch_metadata/gauntlet signals. → the structural robo gap (commit `9cdd4681`) does NOT apply here.
- **Slicing fully engaged** (ruled out as the conf-suppressor): live `upload_slices` thread, EKS-to-EKS Slicing Microservice (weapon) at 2.8 fps, slice frames routed to low-conf bucket. The conf scores are post-slice.
- **Per-frame detections on the clip:** pistol@ 13,16,34,40,48,59,62,66,80,**84**. The gun was visible throughout and detected on ~10 frames — but the site's conf gate is **`pistol>80` / `gun>80`** (logged: `production raw model: conf thresholds: gun>80 pistol>80`), and only `{84}` clears a strict `>80`. → sliding window reached only **"confirmed frame count: 1 of 2"** → window closed at clip EOF → no `trigger_alert` → no `put_detection_window` → no `WindowIdsV2` row → no admin alert + cdw "no alerts found."

**Why the >80 gate is suspect:** weapon-**v8** documented thresholds are **0.55 (LOW) / 0.60 (MED) / 0.65 (HIGH)** (`topics/models/weapon-v8/_summary.md:37-43`); the **80% gate is the legacy v5 value** held for v5's false-positive problems. At a v8-appropriate gate this clip fires:
```
>80 (v5 legacy): {84}             = 1 → NO fire   (actual)
>65 (v8 HIGH):   {66,80,84}       = 3 → fires
>60 (v8 MED):    {62,66,80,84}    = 4 → fires
```
**Fleet check (24h, production weapon sites):** ~50/50 split between `>80` and `>60`; no live sites at 55. So ~half the production weapon fleet — including 34952 — is **still on the legacy v5 `>80` gate**, suggesting an **incomplete v8 threshold migration**.

### Verdict
Not a verifier code bug. Slicing + the default video/`VerifierCamera` alert path + admin-only persistence (`put_detection_window` before the dispatch gate) all work correctly. The no-alert is the mechanically-correct result of the **stale `>80` weapon conf gate** × the 2-confirmed-frame window, on a small (~51×54px) low-confidence pistol.

### Actions
1. **Immediate (Vini's test):** set connector-34952's weapon conf gate to `>60`/`>65`; re-run pistol-short.mp4 → expect a fired alert + `WindowIdsV2` row + admin-view entry. (Live-test in progress.)
2. **Escalate (fleet-wide, possibly safety-relevant):** ~half the production weapon fleet may still be on the legacy v5 80% gate vs v8's 55–65% → real weapons at 60–80% conf may be silently NOT alerting. Audit the weapon-threshold rollout fleet-wide; confirm intended v8 gate; migrate the `>80` cohort if it's a stale default. Open question (needs admin DB / provisioning, not telemetry): was 34952's `>80` intentional or a stale default.

---

## CORRECTION — 2026-06-04 (root cause was misattributed)

The mechanics above are correct (80 gate × 2-of-5 → only the @84 frame clears → window never fires → "no alerts found"). **The root cause is not.** Two stacked errors:

1. **Wrong camera examined.** The 06-03 snapshot (`/tmp/c34952_settings.json`) contained a *single* camera, **"pistol C"**, on `Sensitivity=Medium`. The actual subject (admin URL `camera/396242`) is **"pistol A"**, never in that file. connector-34952 is a 7-camera automation test site (intruder A/B/C, pistol A, bike, vehicle A/B).

2. **The 80 is not "stale v5" — it is the current Gun/Medium fixture, applied by a generator override.** `settings_generator.py:316-319` (`if metric.sensitivity: raw_metrics[...].update(sensitivity.get_raw_metric_settings())`) and `metric_model.py:650-655` make the admin **Sensitivity dropdown override the hand-entered `minimum_confidence`/`thresh`/`denominator`**. `fixtures/sensitivity.json` product 50 (Gun): **Low=85/3-of-5, Medium=80/2-of-5, High=40/1-of-1**. So a hand-entered raw `minimum_confidence` (e.g. 10) is **non-operative whenever a Sensitivity is selected**.

**Live re-pull** (`s3://actuate-settings/connector-34952/settings.json`, regenerated 2026-06-04 15:42): camera **396242 / pistol A is now `Sensitivity=High` → deployed `40 / 1-of-1`**. At that gate the clip fires (detections 40,48,59,62,66,80,84 ≥40; 1-of-1). So the original "no alert" was the camera being on **Medium (80/2-of-5)** at clip time; it is now configured to alert.

**Reframed escalation:** the open DS question is **"is the Gun/Medium *fixture* value (80) the intended weapon-v8 gate?"** (weapon-v8 docs ≈0.60) — a *fixture* question, not a per-camera-stale-value question. "~half the fleet on >80" simply = ~half on **Medium** (80) vs ~half on **High** (40). Tooling note: S3 holds only the post-override output; the raw form value is admin-DB-only. Full reconciliation: [[2026-06-04]].
