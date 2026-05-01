---
title: "CHM Diagnostics Architecture"
type: concept
topic: camera-health-monitoring
tags: [chm, diagnostics, architecture, healthcheck]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md
  - topics/camera-health-monitoring/notes/syntheses/chm-enhanced-diagnostics-proposal.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase3-cross-camera-correlation.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase5-frame-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase6-smtp-ailink-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase7-historical-trending.md
  - topics/camera-health-monitoring/reading-list.md
incoming_updated: 2026-05-01
---

# CHM Diagnostics Architecture

The Camera Health Monitoring diagnostic system is a batch-oriented framework that runs periodic health checks across all cameras on a site, detects issues, creates incidents, and sends email alerts. This note documents the full architecture from source code analysis.

## DiagnosticRunner Dispatch Pattern

The `DiagnosticRunner` dispatches to per-integration `BaseDiagnostics` subclasses based on the site's `integration_type`, falling back to generic checks when no integration-specific class is registered. The dispatch follows a factory-like lookup mapping type strings (`"digital_watchdog"`, `"exacq"`, `"milestone"`, `"avigilon"`, `"rtsp"`) to diagnostics classes. Unregistered integrations -- [[salient-components|Salient]], [[luxriot-components|Luxriot]], [[hikcentral-components|HikCentral]], [[eagle-eye-components|Eagle Eye]], [[genetec-components|Genetec]], [[orchid-components|Orchid]], [[kvs-components|KVS]], and others -- receive only generic diagnostics.

## BaseDiagnostics Per-Integration Class

Each integration-specific diagnostics class extends `BaseDiagnostics` and implements some or all of the standard diagnostic methods:

- **`check_connectivity()`** -- Tests camera/VMS reachability. [[digital-watchdog-components|DW]] authenticates via REST API; [[exacq-components|Exacq]] obtains a session via `get_session_id()`; [[rtsp-components|RTSP]] does a basic HTTP GET; [[milestone-components|Milestone]] uses `try_server_connection()`.
- **`check_recording()`** -- Verifies active recording. Full for DW and Exacq; [[avigilon-components|Avigilon]] has a stub.
- **`check_motion()`** -- Validates motion detection. Only Avigilon has a stub.
- **`check_stream_quality()`** -- Assesses resolution, FPS, codec. Avigilon stub only.
- **`check_server()`** -- Tests VMS server health. Full for [[milestone-components|Milestone]] via `MilestoneService`; Avigilon stub.

## BaseHealthcheckRunner Abstract Methods

`BaseHealthcheckRunner` defines the abstract contract for the batch healthcheck lifecycle: enumerate cameras, allocate diagnostic slots, run checks with timeout management, collect results, and persist incidents. Key abstract methods: `run_diagnostics(camera)` and `process_results(results)`.

## BaseHealthcheckCamera Orchestration

`BaseHealthcheckCamera` is the camera-level orchestrator that runs health checks across all cameras on a site. It manages:

- **ThreadPool execution** -- Cameras are processed concurrently using a thread pool. The `batch_size` parameter (default 400) controls how many cameras are checked in a single batch. For large sites, cameras are partitioned into batches to avoid overwhelming the VMS or exhausting thread resources.
- **Per-camera timeout** -- Each camera check has a computed timeout based on the total budget divided by camera count. The [[vch-components|VCH]] variant uses a 25-minute target budget (`_VCH_TARGET_BUDGET_SECONDS`) with dynamic `retry_sleep_time` reduction for high-camera-count sites.
- **Result aggregation** -- Each camera check returns a structured result (connectivity status, recording status, image quality metrics, stream parameters). Failed checks are tagged with error codes (CONNECTION, LOW_FPS, LOW_RES, BLURRED_VIEW, VIDEO_LOSS, SCENE_CHANGE).

## Generic Checks (All Integrations)

Regardless of integration type, every camera receives these generic checks via the base camera implementation:

- **Blur detection** -- FFT-based via `actuate-blur`. Frequency-domain sharpness score; below threshold flags BLURRED_VIEW.
- **Scene change** -- SIFT matching via `actuate-suddenscenechange`. Compares current frame to stored reference; divergence triggers SCENE_CHANGE.
- **Stream quality** -- Resolution validation against configured minimums. Flags LOW_RES.
- **Connectivity** -- Puller connection test; pull at least one frame or trigger CONNECTION incident.
- **Motion status** -- Checks motion signal queues; stale queues indicate motion detector failure.

## Incident Lifecycle

Incidents follow a state machine: **create -> pending -> resolved**, with email retry logic for delivery failures.

1. **Create** -- Diagnostic failure creates a DynamoDB incident with status `pending`, capturing camera ID, diagnostic type, failure details, and site context.
2. **Pending** -- Subsequent runs detecting the same failure update `last_seen` without duplicating. An email alert is queued.
3. **Email retry** -- Failed SES delivery triggers retry with exponential backoff. Related: CS3-33 (restructure incident table).
4. **Resolved** -- Camera returning healthy transitions the incident to `resolved` with a resolution timestamp and optional resolution email.

## DynamoDB Schema

CHM uses two primary DynamoDB tables:

- **Healthcheck table** -- Stores per-camera health state. Partition key is the `custcam_id` (customer-camera composite). Attributes include connectivity status, recording status, last check timestamp, stream quality metrics, and blur/scene-change scores. This table is the source of truth for the current health state of every monitored camera.
- **SceneChange table** -- Stores reference images and SIFT comparison results. Used by `actuate-suddenscenechange` to persist baseline images and track scene change history over time. Related Jira: CS3-31 (auto-update reference images).

Incident records are stored with attributes for incident type, status (pending/resolved), creation time, last-seen time, resolution time, email delivery status, and retry count.

## HealthcheckConfig Fields

The `HealthcheckConfig` class centralizes all configuration for a healthcheck run:

- **Scheduling**: `schedule_id`, `cron_expression`, `timezone` -- defines when healthchecks execute.
- **Scope**: `customer_id`, `site_id`, `camera_ids` (optional subset) -- defines which cameras to check.
- **Thresholds**: Blur threshold, scene-change sensitivity, minimum resolution, FPS floor -- defines what constitutes a failure.
- **Alerting**: Email recipients, alert suppression windows, incident deduplication window -- controls notification behavior.
- **Execution**: `batch_size` (default 400), `timeout_seconds`, `retry_count` -- controls runtime behavior.

The config is loaded from DynamoDB at healthcheck start time and can be overridden per-camera via CS3-58 (configuration per camera, ready to deploy).
