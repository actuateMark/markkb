---
title: Actuate Admin API
type: summary
topic: admin-api
tags: [admin, django, drf, ecs, crud]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Actuate Admin API (actuate_admin)

Django 6.0 + Django REST Framework application serving as the **operational backbone** of the Actuate platform. Manages cameras, customers, integrations, users, schedules, webhooks, and all configuration.

## Tech Stack

- **Framework:** Django 6.0 + DRF
- **Server:** Gunicorn behind Nginx
- **Deployment:** AWS ECS (Docker on Linux instances)
- **Database:** PostgreSQL on RDS (`actuateadminprodcluster`)
- **Auth:** AWS Cognito (prod), local username/password (dev)
- **Background jobs:** Django-Q (EKS, Redis broker)
- **Package manager:** uv (Python 3.12)

## API Scope

50+ resource types across:

- **Core:** camera, customer, group, user, auth, configuration
- **AI/ML:** ai_model, sensitivity
- **Integrations (29+):** immix, axis, mobotix, bold, patriot, lisa, evalink, sureview, sentinel, softguard, eagle_eye, yoursix, frontel, umbo, etc.
- **AutoPatrol:** auto_patrol, auto_patrol_schedule, auto_patrol_contract, auto_patrol_metric_healthcheck
- **Health:** healthcheck, healthcheck_result, metric_healthcheck
- **Scheduling:** schedule, schedule_location, calendar, calendar_event, flex_schedule
- **Webhooks:** webhook, webhook_customer, webhook_type
- **Infra:** storage, smtp, wireguard, wireguard_tunnel, remote_link
- **Advanced:** sqlexplorer, bulk_onboarding, site_status, camera_status, command_history

## Environments

- **Prod:** `admin.actuateui.net`
- **Staging:** `staging.actuateui.net`
- **Dev:** `dev.actuateui.net`

## Release flow

Release-train, **stage-first**: feature → `staging` → `main`. CI workflow `Protect Main Branch` rejects PRs to `main` from non-staging heads. **Always use `gh pr create --base staging`** for feature work — never `--base main`. See [[release-flow-stage-first]] for the full rules + gotchas.

## Docs

- Swagger UI: `/swagger/`
- ReDoc: `/redoc/`

## Key People

- **[[tatiana-hanazaki|Tatiana Hanazaki]]** -- Core maintainer (3,336 commits)
- **[[paolo-zilioti|Paolo Zilioti]]** -- (458 commits)
- **actuateMark / [[mark-barbera|Mark Barbera]]** -- (311 commits)
- **jacob-aegis / [[jacob-weiss|Jacob Weiss]]** -- (173 commits)
- **Angela Wang** -- (85 commits)

## Current Focus (April 2026)

- **AutoPatrol dev settings** (`feature/autopatrol-dev-settings`) -- endpoint_stage, queue_stage config on Customer model
- **Line crossing separation** (PROD-116) -- decoupling from intruder product
- **[[database-performance|Database performance]]** -- BACK-623 / BT-926: recursive CTE in `get_descendants()` causing Aurora CPU spikes (98.7%). Needs index on `inframap_group.parent_id` + caching.
- **Django upgrade** (BACK-604) -- in QA/QC
- **Monitoring API upgrade** (BACK-638) -- in progress

## Relationship to Other Services

- **Creates API keys** -> stored in DynamoDB -> validated by [[inference-api/_summary|Actuate Inference API]] Rust authorizer
- **Provides camera/customer/site metadata** -> consumed by [[vms-connector]] via config files and API calls
- **Manages integration configurations** -> alarm senders in vms-connector read these
- **Phase 4 of inference-api:** will call Admin API for camera_id -> site_id resolution
