---
title: "vms-connector Repository"
type: entity
topic: vms-connector
tags: [connector, repo, architecture, development]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# vms-connector Repository

The `vms-connector` is the core frame processing service in the Actuate platform. It connects to customer Video Management Systems (VMS), pulls video frames, runs AI inference via a remote YOLO server, and dispatches alerts based on detections.

**Repo**: `aegissystems/vms-connector` (GitHub)
**Language**: Python 3.12+
**Package manager**: `uv` (with CodeArtifact for internal `actuate-*` libraries)
**Entry point**: `connector.py`

## Directory Structure

| Directory | Purpose |
|---|---|
| `camera/` | Camera implementations per VMS type. `camera/shared/` has base classes (`BaseCamera`, `BaseStreamCamera`, `BaseCameraState`). Integration dirs: `rtsp/`, `avigilon/`, `milestone/`, `exacq/`, `eagle_eye/`, `hikcentral/`, `autopatrol/`, etc. |
| `connector_factories/` | Factory pattern per integration. `shared/` has `BaseConnectorFactory`, `factory.py` (dispatch hub), `dao_factory.py`. Integration dirs mirror `camera/`. |
| `site_manager/connector/` | Site managers that orchestrate camera threads. `AnalyticsSiteManager` (single process), `ChunkedSiteManager` (multi-process sharding), `ChmSiteManager` (healthcheck). `integrations/` has per-VMS subclasses. |
| `pipeline/` | `ImagePipeline` and `HealthcheckPipeline`. Thin wrappers around `actuate_pipeline` library. |
| `inference/` | `AsyncInferencePool` -- shared async HTTP pool with AIMD congestion control. |
| `config/` | `app_config` (environment-level config from pydantic-settings). Per-integration configs live in `actuate-config` library. |
| `event_library/` | `VMSEventLibrary` for alarm/event lifecycle (site_armed, site_product_ended, etc.). |
| `motion/` | SQS-based motion signal receivers per integration type. |
| `healthcheck/` | Camera health monitoring runners and alert senders. |
| `docs/` | Operational docs: `CONNECTOR-OPERATIONS.md`, `PRODUCTS.md`, `ECOSYSTEM.md`, `OPTIMIZED-CONNECTOR.md`. |
| `test_vms/` | Pytest tests. Key files: `test_async_inference_pool.py`, `test_healthcheck.py`, `test_optimizations.py`, `test_deferred_alerts.py`. |
| `scripts/` | Utility scripts: connection timing benchmarks, Avigilon login tests, high-density simulation. |
| `docker_files/` | Four Dockerfile variants: ARM CPU, ARM GPU, x86 CPU, x86 GPU. |

## Entry Point Flow

```
connector.py -> generate_site() -> Factory -> SiteManager -> Camera threads -> Pipeline
```

1. `connector.py` -- Parses args, loads settings (S3 or local JSON), configures logging (async queue-based), pins thread counts for OpenCV/BLAS, tunes memory allocator (`MALLOC_MMAP_THRESHOLD_`).
2. `generate_site()` -- Selects factory by `integration_type`, creates cameras, selects site manager, applies sharding if needed.
3. `SiteManager.run()` -- Starts camera threads, creates shared `AsyncInferencePool`, starts GC thread, observer pool, and monitoring threads. Enters main loop checking camera health.
4. Each camera thread runs `BaseStreamCamera.pull()` -- alternates between pulling frames from the puller and collecting pipeline results.

## Branches and Deployment

- **`rearchitecture`** (aka `main`) -- Production. PRs target here. Triggers ECR build and fleet deployment.
- **`stage`** -- Release candidate. Dev library pins allowed here for validation.
- **Feature branches** -- Deployed via `connector_deployer` to specific sites.

Merge strategy: **squash merge** from stage to rearchitecture for clean history.

## Dependencies

The connector depends on 30+ internal `actuate-*` libraries published to AWS CodeArtifact. Key ones:

- `actuate-pipeline` -- Pipeline step framework and `PipelineFactory`
- `actuate-classic-inference-client` -- `YoloClient` for inference HTTP calls
- `actuate-pullers` -- Stream decoders (RTSP via PyAV, HTTP snapshot, SQS/SMTP)
- `actuate-connector-observers` -- Loitering, line crossing, blacklist observers
- `actuate-config` -- Settings JSON parsing into typed config objects
- `actuate-daos` -- DynamoDB/Admin API data access
- `actuate-alarm-senders` -- Alert dispatch (Immix, email, SQS, etc.)

## Dev Workflow

```bash
uv sync                              # Install dependencies
cp test_settings/VMS_CONNECTOR_LOCAL_RTSP.setting.json settings.json
python connector.py -l               # Run locally (mock inference)
python connector.py -l --live-inference  # Real inference via kubefwd
uv run pytest test_vms/              # Run tests
uv run pre-commit run --all-files    # Lint (ruff)
```

Docker builds via `./run-container-local.sh`. GPU variants require NVIDIA runtime. RTSP camera simulator available via `just play-camera-simulator`.

## Key Performance Tuning

- **Shard size**: `customer.shard_size` (default 24) -- cameras per Python process.
- **TurboJPEG**: GIL-releasing JPEG encoding; 10-20% throughput gain at scale.
- **Thread pinning**: OpenCV/BLAS threads capped at 1-2 to prevent CPU scaling with node capacity.
- **Frame deletion**: Proactive cache eviction after `pre_alarm/FPS + buffer` seconds; ~80% memory reduction.
- **Memory allocator**: `MALLOC_MMAP_THRESHOLD_=131072` forces large allocs through `mmap()` for immediate OS release.
- **Memory budget**: ~270 MB/camera steady-state RSS.
