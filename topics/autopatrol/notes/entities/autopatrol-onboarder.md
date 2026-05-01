---
title: "Autopatrol Onboarder"
type: entity
topic: autopatrol
tags: [autopatrol, lambda, onboarding, sync, immix, admin-api]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Overview

The **Autopatrol Onboarder** is an AWS Lambda function that synchronizes contracts, sites, schedules, and devices from the AutoPatrol third-party platform (immix Connect) into the [[actuate-admin-api|Actuate Admin API]]. It runs on a cron schedule via EventBridge and serves as the bridge that keeps Actuate's internal representation of AutoPatrol customers in sync with the external immix system.

**Repository:** `aegissystems/autopatrol_onboarder`

## Tech Stack

- **Language:** Python 3.12+ (managed with `uv`)
- **Runtime:** AWS Lambda (triggered by EventBridge cron)
- **[[actuate-libraries|Actuate Libraries]]:** `actuate-admin-api` (Admin API client, `AdminApi` base class) and `actuate-integration-calls` (immix/AutoPatrol API client, `AutoPatrolAPI`), both pinned with `+autopatrol` local version tags and sourced from CodeArtifact
- **AWS Services:** Lambda, EventBridge (scheduler), Secrets Manager (API keys), S3 (deployment artifact)

## Deployment Model

Two production deployments exist: **US** (`us-west-2`) and **EU** (`eu-west-1`), both named `immix-autopatrol-onboarding`. The CI/CD pipeline (`.github/workflows/deploy.yml`) triggers on push to `master` and automatically deploys to both regions. The build process uses `uv sync` to install dependencies, packages everything into a zip (including site-packages), and uploads via `aws lambda update-function-code`.

Manual deploy scripts are also available: `deploy.sh` (dev), `deploy_prod.sh` (US prod), `deploy_prod_eu.sh` (EU prod).

## Key Files and Entry Points

- **`lambda_function.py`** -- The primary entry point. Contains `lambda_handler(event, context)` which calls `autopatrol_onboard_flow()`. This is the production code that runs in Lambda.
- **`main.py`** -- An older/alternative entry point with a `Poller`-based flow for local development and an experimental `autopatrol_connector_flow()` with WebSocket streaming. Not used in production.
- **`poller.py`** -- Simple polling loop (30s interval) used by `main.py` for local dev; not relevant to Lambda execution.
- **`admin_onboarder.py`** -- Empty/minimal file, not actively used.

## Core Flow (`autopatrol_onboard_flow`)

1. **Health check** the immix API to confirm connectivity
2. **Fetch all contracts** from immix (paginated, max 100 per page -- a warning is logged if 100 are returned, indicating possible truncation)
3. **Per contract**: fetch sites and devices with retry logic, track transient failures per tenant
4. **POST contracts** to Admin API (`auto_patrol_contract/`), then activate them in immix
5. **Sync sites** to Admin API via `auto_patrol/sync/` with a critical `allow_deletion` flag -- set to `false` whenever any immix fetch failed, preventing accidental site deletions from partial data
6. **Sync schedules** in three categories -- awaiting (activate in immix after syncing), active, and deactivated -- all posted to `auto_patrol_schedule/`

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| `AUTOPATROL_API_KEY` | immix API key | **required** |
| `AUTOPATROL_STAGE` | Controls both immix and Admin API endpoints (`prod` or `staging`) | `staging` |
| `AUTOPATROL_REGION` | `US` or `EU` | `US` |
| `DRY_RUN` | `true` = skip all writes, log only | not set |
| `ACTUATE_ADMIN_API_URL` | Override Admin API base URL (used for EU: `https://admin.actuateui.eu`) | -- |

## Dependencies on Other Actuate Services

- **Admin API** -- the primary write target; receives contracts, sites, and schedules via POST endpoints
- **AutoPatrol API (immix Connect)** -- the primary read source; provides contracts, sites, devices, schedules, and health checks
- **AWS Secrets Manager** -- Admin API token retrieval (via `actuate-admin-api` library)

## Architecture Patterns

- **Deletion safety**: The `allow_deletion` flag in the site sync payload defaults to `true` but is flipped to `false` whenever any immix fetch failed during the run. This prevents partial data from causing the Admin API to delete sites that were simply unreachable.
- **Retry with backoff**: Transient failures (5xx, timeouts) retry up to 3 times with a 2-second delay. Permanent failures (400/401/403/404) are skipped immediately -- this distinguishes deleted tenants from temporarily unavailable ones.
- **Per-contract isolation**: Exceptions in one contract's processing are caught and logged, allowing the rest to proceed.
- **Dry run mode**: All write operations check the `dry_run` flag, enabling safe production testing without side effects.
- **Multi-region support**: The `AdminApiHandler` constructor switches base URLs based on region (EU uses `admin.actuateui.eu`).
