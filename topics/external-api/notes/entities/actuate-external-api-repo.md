---
title: "actuate-external-api"
type: entity
topic: external-api
tags: [repo, fastapi, python, external-api, partner-api]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-external-api

**Repository:** `aegissystems/actuate-external-api`
**Version:** 0.2.1
**Default branch:** `main`
**Python:** 3.12

## Purpose

FastAPI service that exposes partner-facing HTTP endpoints and forwards calls to the **[[actuate-admin-api|Actuate Admin API]]** using the caller's `X-API-Key` as the outbound token. This is the public-facing API layer that partners and external integrations use to interact with the Actuate platform, abstracting the internal Admin API behind a controlled, rate-limited surface.

## Tech Stack

- **Framework:** FastAPI (ASGI) with Uvicorn
- **Language:** Python 3.12
- **Package manager:** `uv` (with `justfile` task runner)
- **Build system:** Hatchling
- **Linting/formatting:** Ruff, pre-commit
- **Testing:** Pytest with coverage
- **Code quality:** SonarQube (`sonar-project.properties`)
- **Containerization:** Docker (Python 3.12-slim, uv 0.6.14)

## Key Files

| Path | Role |
|------|------|
| `src/main.py` | ASGI app instance, `create_app()`, public routes (`/`, `/health`), customer router |
| `src/app.py` | Factory: middleware, exception handlers |
| `src/api/` | Auth (`X-API-Key` header) and route definitions |
| `src/services/` | Domain logic (e.g., customer service) |
| `src/integrations/` | Admin API client -- outbound calls to internal APIs |
| `src/models/` | Pydantic request/response models |
| `src/core/config.py` | Pydantic Settings configuration (loads `.env`) |
| `src/middleware/rate_limit_404.py` | 404 rate limiting by IP to prevent enumeration |
| `Dockerfile` | Production container image |
| `justfile` | Task runner (`just dev`, `just test`, `just lint`) |

## Configuration

Key environment variables:

- **`admin_base_url`** / `ADMIN_BASE_URL` -- base URL for the internal Admin API
- **`STAGE`**, **`VERSION`** -- deployment metadata
- **`MAX_404_ATTEMPTS`**, **`404_WINDOW_SECONDS`**, **`404_BLOCK_DURATION_SECONDS`** -- 404 rate-limit tuning

## Deployment

Four GitHub Actions workflows: `main.yml`, `dev.yml`, `unit_test.yml`, `sonar.yml`. Docker builds require `UV_INDEX` pointing to AWS CodeArtifact for private dependency resolution. The container exposes port 8000 and runs `uvicorn src.main:app`.

## Dependencies

- **`actuate-admin-api>=1.2.2`** -- the shared [[actuate-libraries|Admin API client library]] from CodeArtifact
- `boto3`, `fastapi[standard]`, `pydantic-settings`, `requests`

## Relationship to Other Services

- **Upstream:** Partners and external systems call this API
- **Downstream:** Proxies requests to the [[actuate-monitoring-api|Admin API]] using the caller's API key
- **Shared libraries:** Depends on [[actuate-libraries]] via AWS CodeArtifact
- **UI:** The [[alert-ui|Alert UI]] may consume some of the same backend APIs, but via different routes
