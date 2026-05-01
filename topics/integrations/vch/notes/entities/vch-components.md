---
title: "VCH Integration Components"
type: entity
topic: integrations/vch
tags: [integration, vch, components, autopatrol]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/camera-health-monitoring/notes/concepts/chm-rd-opportunities.md
  - topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md
incoming_updated: 2026-05-01
---

# VCH Integration Components

VCH (Virtual Camera Healthcheck) is a specialized integration type that runs camera health diagnostics instead of continuous AI detection. While standard integrations pull video frames and run inference to detect threats, VCH connects to cameras, evaluates stream health (connectivity, FPS, resolution, blur, entropy, scene changes), and reports results through the AutoPatrol API. It is fundamentally a healthcheck-only integration.

## How VCH Differs from Standard Connectors

In [[vms-connector]] `factory.py`, VCH is force-routed to the healthcheck path regardless of command-line flags:

```python
if integration_type == "vch" and not healthcheck:
    healthcheck = True
```

Standard connectors follow: Factory -> Camera -> `run()` -> continuous puller loop -> inference pipeline. VCH follows: Factory -> `VCHCamera` -> `run()` -> batch healthcheck across all cameras -> send results -> exit. VCH pods are designed to run as one-shot jobs (triggered by AutoPatrol patrols), not long-running deployments.

## VCHConnectorFactory

Defined at `connector_factories/autopatrol/vch_factory.py`. Uses `AutoPatrolConnectorConfig` from [[actuate-config]] (the same config class as AutoPatrol). The factory:

1. Retrieves the AutoPatrol API key from secrets.
2. Calls `autopatrol_api.get_patrols` to find scheduled patrols (with 3 retries).
3. Sleeps until patrol execution time if needed.
4. Creates a `VCHCamera` instance.

## VCHCamera

Defined at `camera/autopatrol/vch_camera.py`. Extends `BaseHealthcheckCamera` (not `BaseCamera` or `BaseStreamCamera`). Key behaviors:

- **Run timing budget**: `_compute_run_timings` calculates per-camera timeouts to ensure all cameras complete within a 25-minute target budget (`_VCH_TARGET_BUDGET_SECONDS`). It dynamically reduces `retry_sleep_time` (default 90s) when camera count is high. `healthcheck_duration` is capped at 360s for small sites.
- **Puller**: Uses `AutopatrolWebSocketStreamPuller` (not the standard URL pullers) for each camera.
- **Patrol lifecycle**: Calls `autopatrol_api.start_patrol` before running, `autopatrol_api.end_patrol` after.
- **Graceful shutdown**: Registers SIGTERM/SIGINT handlers to stop accepting new cameras while letting in-flight healthchecks finish.

## VCHAlertSender

Defined at `healthcheck/alerts/senders/vch_alert_sender.py`. Sends healthcheck results to the AutoPatrol API as patrol alerts. Supports two patrol types:

- **VisualCameraHealth** (`send_chm_alert`): Full diagnostic with detection codes for CONNECTION, LOW_FPS, LOW_RES, BLURRED_VIEW, VIDEO_LOSS, and SCENE_CHANGE. Includes reference and current image URLs from S3.
- **AutoPatrol CHM** (`send_ap_chm_alert`): Simpler version focused on connectivity checks. Stream quality and image quality checks are currently commented out.

Each alert is both raised via the API (`autopatrol_api.raise_patrol_alert`) and persisted via `autopatrol_dao.save_chm_issue`.

## VCHSiteManager

Defined at `site_manager/connector/integrations/vch_site_manager.py`. A thin subclass of `ChmSiteManager` with no overrides -- the VCH-specific behavior lives in `VCHCamera` and `VCHAlertSender`.

## Config

VCH uses `AutoPatrolConnectorConfig` from [[actuate-config]] (`actuate_config/connector/immix/immix_config.py`), which includes `AutoPatrolConfig` with fields like `tenant_id`, `site_id`, `schedule_id`, `patrol_id`, `batch_size`, and `patrol_type`. VCH sets `patrol_type` to `"VisualCameraHealth"`.

## Sharding

VCH is excluded from the standard [[sharding]] logic in `factory.py` -- `get_sharding_strategy` returns 2000 for `vch`, meaning all cameras run in a single process.
