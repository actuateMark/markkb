---
title: "actuate_monitoring_api"
type: entity
topic: admin-api
tags: [repo, django, python, monitoring, camera-admin, rest-api]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate_monitoring_api

**Repository:** `aegissystems/actuate_monitoring_api`
**Description:** Camera Admin APIs for Monitoring UI
**Default branch:** `main`

## Purpose

Django REST Framework service that provides read-only APIs for the Monitoring UI. It was separated from the main Admin application to allow independent scaling under high read traffic from the monitoring dashboard. The service accesses the same database as the main Admin app using stripped-down copies of Admin models, but is explicitly **not intended for write operations** -- all updates must go through the main Admin application.

Authentication is simplified by running as an extension of the main Admin app (sharing session/auth infrastructure). The Swagger documentation is available at `/monitoring-api/swagger/` in each environment.

## Tech Stack

- **Framework:** Django 4.1 + Django REST Framework (<3.15)
- **Language:** Python
- **Database:** PostgreSQL (via `psycopg` 3.x)
- **Caching:** Redis (>=4.0, <8.0)
- **API docs:** drf-yasg (Swagger/OpenAPI)
- **Video processing:** FFmpeg (via `ffmpeg-python`), OpenCV (headless), NumPy
- **Testing:** Pytest + pytest-django, tox, coverage
- **Code quality:** SonarQube

## Key Files

| Path | Role |
|------|------|
| `monitoring/settings.py` | Django settings |
| `monitoring/urls.py` | URL routing |
| `monitoring/views/` | API views: alerts, alert routing, video maker, groups, filters |
| `monitoring/serializers/` | DRF serializers |
| `monitoring/auth/` | Authentication layer |
| `monitoring/integrations/` | External integrations: alert senders, text/webhook dispatchers |
| `monitoring/report_manager.py` | Report generation |
| `monitoring/monitoring_log_adapter.py` | Custom log adapter |
| `inframap/models.py` | Stripped-down copies of Admin DB models |
| `inframap/admin.py` | Django admin registration |
| `manage.py` | Django management entry point |
| `Dockerfile` | Container image |
| `docker-compose.yml` | Local development setup |
| `terraform/` | Infrastructure as code |
| `task-definition*.json` | ECS task definitions (dev, staging, prod) |

## Log Management

Logs default to WARNING level due to high call volume. Verbose logging can be temporarily activated per-section via `POST /config/log/` with a JSON body specifying `level` and `section` (e.g., `"video"`). This only activates on a single pod (in-memory config), and restarting the pod resets it.

## Deployment

Four GitHub Actions workflows: `main.yml`, `develop.yml`, `staging.yml`, `sonar.yml`. Deployed to **AWS ECS** with separate task definitions for dev, staging, and production. Infrastructure managed via Terraform.

## Dependencies

- **Actuate libraries** (from CodeArtifact): `actuate-secrets`, `actuate-event-listener`, `actuate-viz`, `actuate-inference-objects`
- Django ecosystem: allauth, cors-headers, environ, filter, mptt, simple-history
- `boto3`, `gunicorn`, `redis`, `pyjwt`

## Relationship to Other Services

- **Shared database:** Reads from the same PostgreSQL database as the main Admin application
- **Upstream consumers:** [[alert-ui|Alert UI]] and the Monitoring dashboard consume these APIs
- **Write path:** All mutations route through the main Admin app, not this service
- **[[actuate-external-api-repo|External API]]** depends on `actuate-admin-api` library which calls into Admin; this monitoring API is a parallel read-optimized surface
- **Shared libraries:** Uses [[actuate-libraries]] (`actuate-secrets`, `actuate-viz`, `actuate-event-listener`, `actuate-inference-objects`)
