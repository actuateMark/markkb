---
title: "actuate_ailink"
type: entity
topic: vms-connector
tags: [repo, websocket, python, ailink, vms-integration, clips, video-analysis]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/alert-ui.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase-review-findings.md
  - topics/infrastructure/notes/entities/reusable-github-actions.md
  - topics/watchman/notes/entities/watchman-repo.md
incoming_updated: 2026-05-01
---

# actuate_ailink

**Repository:** `aegissystems/actuate_ailink`
**Version:** 0.2.0
**Description:** Websocket for AILink integration
**Default branch:** `main`
**Python:** 3.12

## Purpose

WebSocket server that receives video frames from VMS (Video Management System) integrations, runs AI inference on them, and generates alert clips. Originally built for the AILink integration, it now supports multiple VMS connectors including **[[sentinel-components|Sentinel]]**, **Frontel**, and **Yousix** (Umbo). Each connected camera sends frames over a persistent WebSocket connection; the server processes them through YOLO-based object detection, applies postprocessing rules (noise reduction, movement tracking, line crossing), and dispatches alerts via the [[actuate-libraries|actuate-alarm-senders]] library.

The server also includes a FastAPI-based **AI Sync API** (`server.py`) for synchronous inference requests.

## Tech Stack

- **WebSocket server:** `websockets` library (legacy auth protocol), port 8766
- **Sync API:** FastAPI + Uvicorn (port 8765)
- **Language:** Python 3.12
- **Package manager:** `uv` (with `Makefile` task runner)
- **AI/CV:** [[opencv-entity|OpenCV]] (headless), NumPy, scikit-image, PyTurboJPEG, Shapely (geometry)
- **Monitoring:** [[new-relic|New Relic]] telemetry SDK, Prometheus client
- **Caching:** Redis
- **Storage:** AWS S3 (boto3) for clip storage
- **Testing:** Pytest + pytest-xdist (parallel), Watchdog for dev auto-reload
- **Code quality:** SonarQube, pylint

## Key Files

| Path | Role |
|------|------|
| `app.py` | WebSocket server entry point -- memory tuning, auth, handler loop, GC thread |
| `server.py` | FastAPI AI Sync API entry point |
| `src/message_processor.py` | Core message routing: consumer, analyzer, output, producer, postprocessing tasks |
| `src/frame_processor.py` | Frame analysis pipeline |
| `src/yolo_client.py` | YOLO inference client |
| `src/clip.py` | Clip creation and management |
| `src/alerts/clip_alert_sender.py` | Alert dispatch for completed clips |
| `src/websocket_adapter.py` | WebSocket abstraction layer |
| `src/connection_tracker.py` | Active connection monitoring |
| `src/redis_client.py` | Redis connection management |
| `src/frontel/` | Frontel VMS integration (TCP server + handlers) |
| `src/umbo/` | Umbo/Yousix VMS integration (media + schemas) |
| `src/event_library/` | Event library for AILink events |
| `src/delta_noise.py` | Noise reduction between frames |
| `src/image_manipulation.py` | Frame image processing utilities |
| `auth/basic_authentication.py` | WebSocket basic auth against Admin credentials |
| `kubernetes/` | K8s manifests (prod, slack) |
| `docker-compose.yml` | Local development with Docker |

## Architecture

The WebSocket handler spawns five concurrent async tasks per connection:

1. **Consumer** -- receives incoming frames
2. **Analyzer** -- runs YOLO inference
3. **Output** -- sends results back to client
4. **Producer** -- generates clips/alerts
5. **Postprocessing** -- noise reduction, movement analysis

A dedicated GC thread runs every 15 seconds to break cyclic references between Clip objects and callbacks, preventing memory accumulation from numpy frame arrays.

## Deployment

GitHub Actions workflows: `main.yml`, `develop.yml`, `build-only.yml`, `sonar.yml`. Pushing to `main` triggers build and deploy. Deployed to **Kubernetes** with Docker images built using CodeArtifact for private dependencies. Supports `STAGE` values: prod, staging, dev, local.

## Dependencies

Heavy reliance on [[actuate-libraries]] from CodeArtifact:
- `actuate-movement` (1.2.5), `actuate-log` (1.0.2), `actuate-admin_api` (1.2.0)
- `actuate-daos` (3.2.6), `actuate-event-listener` (1.1.2), `actuate-secrets` (1.0.1)
- `actuate-alarm-senders` (1.9.16), `actuate-config` (1.8.3)

## Relationship to Other Services

- **VMS connectors:** Receives frames from AILink, [[sentinel-components|Sentinel]], Frontel, and Yousix integrations (closely related to the [[vms-connector]] project)
- **Admin API:** Authenticates users and queries camera config via `actuate-admin-api`
- **[[actuate-monitoring-api|Monitoring API]]:** Generated alerts and clips are displayed through the monitoring dashboard
- **[[alert-ui|Alert UI]]:** End-user interface for viewing alerts/clips this service produces
- **S3:** Stores generated video clips in AWS S3
- **Redis:** Used for connection state and inter-process coordination
