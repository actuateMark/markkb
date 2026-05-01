---
title: "CHM End-to-End Flow: From CronJob to Alert Email"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, flow, architecture, baseline-reference, dynamodb]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# CHM End-to-End Flow: From CronJob to Alert Email

This document traces the complete lifecycle of a single Camera Health Monitoring run, from K8s trigger through per-camera analysis to alert email delivery. It serves as the **baseline reference** that all phase proposals ([[chm-phase1-network-probe]], [[chm-phase2-stream-probe]], etc.) build upon.

```
K8s CronJob
    |
    v
connector.py -hc  -->  generate_site()  -->  Factory
    |
    v
BaseHealthcheckCamera.__init__()
    |  - HealthcheckConfig loaded (checks enabled/disabled, emails, thresholds)
    |  - HealthcheckFactory.make_healthchecks() --> 7 runner types instantiated
    |  - HealthcheckAggregator built (per-email routing map)
    |  - LRUImageCache sized (batch_size * 2)
    |  - init_frame_queues() per camera_stream
    |
    v
.run()  -->  motion_listen thread  +  job_manager thread  +  start_healthcheck()
    |
    v
ThreadPoolExecutor(max_workers=batch_size)
    |
    +--[ per camera ]-----------------------------------------------+
    |  start_healthcheck_job(puller, job_id, duration=12s)          |
    |    |                                                          |
    |    |-- HealthcheckDataPacket + SceneChangePacket +             |
    |    |   StreamQualityPacket initialized                        |
    |    |                                                          |
    |    |-- PRE-PROCESSING RUNNERS (ServerHC, ActiveCamHC)         |
    |    |     runner.healthcheck() = check() + generate() +        |
    |    |                            incident_analysis()           |
    |    |                                                          |
    |    |-- puller.run_healthcheck(data, 12s) [background thread]  |
    |    |     pulls frames --> frame_queue                          |
    |    |                                                          |
    |    |-- frame_queue.get() --> image_quality_check()             |
    |    |     BlurHandler.calculate_and_update()                    |
    |    |       -> FFT blur metric + Shannon entropy                |
    |    |     IntegratedSACDetectorBank.start_detector()            |
    |    |       -> SIFT scene change (if blur/entropy pass)        |
    |    |     Resolution from frame.shape[1]                       |
    |    |                                                          |
    |    |-- POST-PROCESSING RUNNERS (Connectivity, StreamQuality,  |
    |    |     SceneChange, MotionStatus, Recording)                |
    |    |     runner.healthcheck() = check() + generate() +        |
    |    |                            incident_analysis()           |
    |    |                                                          |
    |    |-- _cleanup_camera_resources()                             |
    |    +----------------------------------------------------------+
    |
    v
send_healthcheck_results(job_id)
    |-- save_healthcheck() per camera --> DynamoDB
    |-- alert_aggregator.run_sender()
    |     |-- per email recipient: compile changed alerts
    |     |-- compile_alerts() --> SES email + SNS text
    |     |-- _mark_emails_sent() --> DynamoDB stamp
    |     +-- _stamp_unattempted_emails()
    |
    v
_wait_for_alert_threads()  -->  endrun()  -->  exit()
```

## 1. Trigger

A CHM run starts as a **K8s CronJob** that launches the connector container with the `-hc` flag. `connector.py` parses this and passes `healthcheck=True` into `generate_site()`. For [[vch-components|VCH]] integrations, `-hc` is forced on; for [[autopatrol-integration-components|AutoPatrol]], forced off. The factory selects the integration-specific camera class and returns a site with `BaseHealthcheckCamera` as the orchestrator superclass.

## 2. Initialization

[[chm-diagnostics-architecture|BaseHealthcheckCamera.__init__()]] performs the following setup:

- **Config loading**: [[HealthcheckConfig|HealthcheckConfig]] is parsed from the settings JSON, establishing which checks are enabled (`connectivity_check`, `scene_change_check`, `motion_status_check`, `recording_check`, `stream_quality_check`, `image_quality_check`), per-check alert email lists, `disabled_cameras`, `ssc_sensitivity_level`, `minimum_resolution` (default 360), and `health_monitoring_emails`.
- **Runner instantiation**: `HealthcheckFactory.make_healthchecks()` creates the active runner set. Standard sites get up to 7 runners: [[ActiveCamHealthcheckRunner]], [[ConnectivityHealthcheckRunner]], [[ServerHealthcheckRunner]], [[SceneChangeHealthcheckRunner]], [[MotionStatusHealthcheckRunner]], [[RecordingHealthcheckRunner]], [[StreamQualityHealthcheckRunner]].
- **Alert aggregator**: [[HealthcheckAggregator]] maps each email address to its subscribed check types. `health_monitoring_emails` receive all types with severity filtering; per-check emails receive without severity gating.
- **Cache and queues**: [[LRUImageCache]] sized at `effective_batch * 2`. Frame queue per `camera_stream`. `batch_size` = 400, `healthcheck_duration` = 12s.

## 3. Per-Camera Healthcheck Loop

`BaseHealthcheckCamera.run()` starts a daemon `motion_listen` thread (polls motion queues from the main connector) and a `job_manager` thread (handles async alert-send jobs), then calls `start_healthcheck()`.

`start_healthcheck()` creates a `ThreadPoolExecutor(max_workers=batch_size)` and submits one `start_healthcheck_job()` per enabled, non-dummy puller. Cameras in `disabled_cameras` are skipped.

For each camera, `start_healthcheck_job()`:

1. Creates a fresh [[HealthcheckDataPacket]] (wraps [[ConnectivityPacket]], [[StreamQualityPacket]], [[SceneChangePacket]], [[MotionStatusPacket]], [[RecordingPacket]], [[ServerStatusPacket]]).
2. Runs **pre-processing runners** via `healthcheck_diagnostics(puller, job_id, ProcessingStepEnum.pre)` -- this executes `ServerHealthcheckRunner` and `ActiveCamHealthcheckRunner`, which have `processing_step=pre`.
3. Starts `puller.run_healthcheck(healthcheck_data, 12s)` in a background thread -- the puller connects to the stream, pulls frames for 12 seconds, and enqueues them via `frame_queue`.
4. Blocks on `frame_queue.get(timeout=32s)` to receive frames. If no frames arrive, connectivity is likely broken.
5. For each received frame, calls `image_quality_check()` (see section 4).
6. Joins the puller thread (timeout: 37s). If it hangs, `broken_stream` is force-set.
7. Runs **post-processing runners** via `healthcheck_diagnostics(puller, job_id, ProcessingStepEnum.post)` -- this executes Connectivity, StreamQuality, SceneChange, MotionStatus, and Recording runners.
8. Calls `_cleanup_camera_resources()` to free memory.

## 4. Frame Analysis Pipeline

When a frame arrives from the puller, `image_quality_check()` performs two analyses gated by config flags:

**Stream quality analysis** (if `stream_quality_check` enabled):
- [[BlurHandler]].`calculate_and_update()` runs **FFT blur detection** (removes center frequencies, measures remaining magnitude -- below threshold of 15 means blurry) and **Shannon entropy** (128-bin grayscale histogram -- below 1.5 means blank/black frame). Results populate [[StreamQualityPacket]].`blur_metric` and `.entropy`.
- `resolution` is extracted from `frame.shape[1]` (width).
- FPS is set from `puller.highest_fps` during the stream quality runner's `check()`.
- If blur or entropy fail, the frame is saved to S3 (`spray_bucket`) for email attachment.

**Scene change analysis** (if `scene_change_check` enabled AND blur+entropy pass AND camera is not PTZ):
- Frames over 1080p height are downsized via `cv2.resize` to reduce memory/compute.
- [[IntegratedSACDetectorBank]].`start_detector()` determines whether enough time has passed to compare this frame against the stored background.
- If ready, `process_frame()` runs **SIFT keypoint matching** between the current frame and the stored reference, comparing across modality/hour_tick detector instances. Scene change results (detected type, background/detected frame S3 keys) populate [[SceneChangePacket]].

## 5. Health Check Runners (7 Types)

Each runner follows the `BaseHealthcheckRunner.healthcheck()` template: `check()` -> `generate()` -> `incident_analysis()`.

- **ActiveCamHealthcheckRunner** (pre): Stub. Creates a `healthy` incident as a heartbeat record. Uses [[DummyAlertGenerator]].
- **ServerHealthcheckRunner** (pre): Dispatches to [[DiagnosticRunner]] for integration-specific server checks (e.g., [[milestone-components|Milestone]] management/recording server connectivity). Runs `incident_analysis()` with the standard create/update/resolve cycle.
- **ConnectivityHealthcheckRunner** (post): Checks `connectivity.valid` (based on `broken_stream` and `nvr_error`). If invalid, dispatches to [[DiagnosticRunner]] for integration-specific diagnostics. The `generate()` step classifies the failure topic (broken, ip, cred, port, nvr, etc.) using error message pattern matching. `incident_analysis()` manages the DynamoDB incident lifecycle.
- **StreamQualityHealthcheckRunner** (post): Merges puller-reported FPS/resolution with BlurHandler results. Validates against thresholds: `min_fps` (1), `max_fps` (11), `min_res` (360), `max_res` (1080), `blur_amount` (15), `entropy_amount` (1.5). Skipped if connectivity is down.
- **SceneChangeHealthcheckRunner** (post): Reads the [[SceneChangePacket]] populated by `image_quality_check()`. `valid = not detected`. Scene change incidents auto-resolve from `pending` to `resolved` after 1 day.
- **MotionStatusHealthcheckRunner** (post): Reads motion signal queue status via `camera.get_motion_status()`. Creates `healthy` bookkeeping incidents alongside actual motion-loss incidents. Uses a 24-hour no-motion threshold.
- **RecordingHealthcheckRunner** (post): Dispatches to [[DiagnosticRunner]] for integration-specific recording checks (DW hard drive status + per-camera recording, Exacq session-based recording check). Skipped if connectivity is down.

## 6. Diagnostic Dispatch

When a runner's `check()` calls `DiagnosticRunner().run_diagnostic()`, the runner resolves the integration-specific [[BaseDiagnostics]] subclass:

| Integration | Diagnostics Class | What It Does |
|---|---|---|
| `digital_watchdog` | [[DWDiagnostics]] | NVR status (REST v1/v2), hard drive health, per-camera recording status, footage recency |
| `exacq` | [[ExacqDiagnostics]] | Session login (`get_session_id`), recording status query |
| `milestone` | [[MilestoneDiagnostics]] | Management/recording server connectivity via `MilestoneService` |
| `rtsp` | [[RTSPDiagnostics]] | Basic HTTP GET to `base_url` for reachability |
| `avigilon` | [[AvigilonDiagnostics]] | Stub implementations (see [[chm-diagnostics-gap-analysis]]) |
| All others | [[DummyDiagnostics]] | No-op passthrough |

Local [[rtsp-deep-dive|RTSP]] mode uses `DummyDiagnostics` to avoid real network calls during development.

## 7. Incident Lifecycle

Each runner manages incidents in DynamoDB via `BaseHealthcheckRunner` methods:

- **`create_incident()`**: Writes a new record with `status=ongoing`, capturing site/camera IDs, error type, and diagnostic data. Fires a [[new-relic|New Relic]] metric in a background thread.
- **`update_incident()`**: Updates `last_updated_timestamp`, optionally sets `end_timestamp` and transitions status. Also fires [[new-relic|New Relic]] metric.
- **State machine**: `ongoing` -> `pending` -> `resolved`. The `pending` state is a grace period -- scene change and connectivity runners auto-resolve `pending` incidents after 1 day.
- **`check_unsent_emails()`**: After `incident_analysis()`, this method catches incidents whose open or close emails failed to send in a prior run and re-triggers them by setting `current_run_status` to OPENED or RESOLVED.

## 8. Alert Generation

After all cameras complete, `send_healthcheck_results()` calls `alert_aggregator.run_sender()`:

1. Queries Admin API for site-level error/warning counts (7-day window).
2. Per email recipient, builds an [[AlertDataPacket]] with subscribed check types, filtered to cameras whose `current_run_status_changed` is true.
3. Severity gating: `health_monitoring_emails` only receive MEDIUM/HIGH. Per-check emails receive all severities.
4. `compile_alerts()` builds the email subject (`"Actuate Health Check Results: {site_name} - {N} Issues Detected"`), loads S3 frame attachments, and calls `send()`.
5. `send()` dispatches via SES email + SNS text. For [[vch-components|VCH]]/[[autopatrol-integration-components|AutoPatrol]] sites, `VCHAlertSender` sends detection codes to the AutoPatrol API instead.
6. `_mark_emails_sent()` stamps `open_email_sent`/`closed_email_sent` in DynamoDB. `_stamp_unattempted_emails()` stamps packets filtered by severity or missing recipients to prevent infinite retry.

## 9. Results Storage

- **DynamoDB healthcheck records**: `save_healthcheck()` writes per-camera results (connectivity, stream quality, motion, scene change, recording, error text) via `healthcheck_dao.update_healthcheck()`.
- **DynamoDB incidents**: Created/updated by each runner's `incident_analysis()` (see section 7).
- **S3 frame storage**: Blurred/blank frames saved to `spray_bucket` during `image_quality_check()`. Scene change background and detected frames saved by the SAC detector bank.
- **[[new-relic|New Relic]] metrics**: `put_healthcheck_run()` fires per-camera and per-check-type metrics. `put_healthcheck_incident()` fires on incident create/update as fire-and-forget daemon threads.

## 10. Cleanup

Per-camera cleanup happens in `_cleanup_camera_resources()` immediately after each camera's healthcheck job completes (not at end of run):

- **Frame cache**: All analyzed frame IDs are deleted from [[LRUImageCache]]. Background frames stored by SAC sub-detectors (per modality/hour_tick) are also deleted.
- **SAC analyzer state**: The [[IntegratedSACDetectorBank]] instance for this camera is deleted from `scene_change_analyzers`, freeing SIFT structures, MOG2 subtractors, and numpy arrays.
- **BlurHandler state**: The [[BlurHandler]] instance is deleted from `blur_analyzers`, freeing histogram state.

After all cameras complete, `_wait_for_alert_threads()` joins any async alert-send threads (30s timeout each). `endrun()` sends CHM product events per camera. Finally, `exit()` terminates the container.
