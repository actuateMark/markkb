---
title: "actuate-admin-api"
type: entity
topic: actuate-libraries
tags: [library, config-data, rest-api, camera-admin, http-client]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
outgoing:
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/camera-health-monitoring/notes/entities/health-report.md
  - topics/external-api/notes/entities/actuate-external-api-repo.md
  - topics/integrations/ajax/_summary.md
  - topics/integrations/ajax/notes/entities/ajax-components.md
  - topics/integrations/evalink/evalink-integration/notes/concepts/alarm-push-pattern.md
  - topics/personal-notes/notes/daily/2026-04-24.md
  - topics/team-structure/notes/entities/clarissa-herman.md
  - topics/team-structure/notes/entities/paolo-zilioti.md
incoming:
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/autopatrol/notes/syntheses/2026-04-24_stale-schedule-cleanup-aar.md
  - topics/camera-health-monitoring/notes/entities/health-report.md
  - topics/external-api/notes/entities/actuate-external-api-repo.md
  - topics/integrations/ajax/_summary.md
  - topics/integrations/ajax/notes/entities/ajax-components.md
  - topics/integrations/evalink/evalink-integration/notes/concepts/alarm-push-pattern.md
  - topics/personal-notes/notes/daily/2026-04-24.md
  - topics/team-structure/notes/entities/clarissa-herman.md
incoming_updated: 2026-05-08
---

## Purpose

actuate-admin-api (v1.2.2) is a Python HTTP client for the Actuate Camera Admin REST API. It wraps all API endpoints into a single `AdminApi` class so that other libraries ([[actuate-daos]], [[actuate-config]], [[actuate-monitoring]]) can interact with Camera Admin without crafting raw HTTP requests.

## Key Class: AdminApi

`AdminApi` is initialised with an optional `admin_dao`, a `stage` (prod/dev/staging/local), and an `actuate_base_url` (defaults to `https://www.actuateui.net`). It resolves the base URL by stage (admin, dev, staging, or localhost) and retrieves the API token from AWS Secrets Manager via `actuate-secrets.SecretManager`.

### Core Method: `api_call`

All endpoint methods delegate to `api_call(path, params, data, method, return_response)`. It builds the full URL, adds `Authorization: Token {api_token}` headers, and uses `requests.request()`. By default it raises on non-2xx status codes and returns JSON; passing `return_response=True` returns the raw `requests.Response`.

### Endpoint Methods

| Method | Endpoint | Purpose |
|---|---|---|
| `get_camera(camera_id)` | `camera/{id}` | Single camera details |
| `list_cameras(**kwargs)` | `camera/` | Filter cameras |
| `list_camera_info(**kwargs)` | `camera/info/` | Camera info with type expansion |
| `list_options(**kwargs)` | `option/` | Product options |
| `list_ai_models(**kwargs)` | `ai_model/` | AI model connections |
| `list_configurations(**kwargs)` | `configuration/` | Named config values |
| `get_customer(id)` | `customer/{id}/` | Customer by PK |
| `get_customer_by_id(id)` | `customer/by_customer_id/{id}/` | Customer by deployment ID |
| `patch_customer(id, data)` | `customer/{id}/` | Update customer |
| `list_webhooks(**kwargs)` | `webhook/` | Webhook configs |
| `get_management_server_by_customer(id)` | `management_server/by_customer/{id}/` | VMS server info |
| `create_schedules(data)` | `auto_patrol_schedule/` | Autopatrol schedules |
| `create_sites(data)` | `auto_patrol/sync/` | Autopatrol site sync |
| `get_customer_armed(pk)` | `customer/{pk}/about/` | Armed/disarmed status |
| `list_streams(**kwargs)` | `stream/` | Stream list |
| `reboot(data)` | `customer/reboot/` | Trigger reboot |

## Dependencies

- **[[actuate-secrets]]** >=1.0.0 -- retrieves API token and Postgres secrets from AWS Secrets Manager.

## Consumers

[[actuate-daos]] (`AdminDAO` wraps most calls), [[actuate-config]] (`CustomerConfig` fetches AI models), [[actuate-monitoring]] (`NewRelicMonitor` for mute rule management). Any service that needs Camera Admin data uses this through AdminDAO.

## Notable Patterns

- **Stage-based URL resolution**: The base URL is transformed by replacing the subdomain (www -> admin/dev/staging) based on the deployment stage.
- **Token from Secrets Manager**: The API token comes from `prod/actuate/postgres` secret, keyed as `api-token-{stage}`.
- **Thin wrapper**: AdminApi methods are one-liners that build a path and call `api_call`. Business logic lives in the consuming AdminDAO, not here.
