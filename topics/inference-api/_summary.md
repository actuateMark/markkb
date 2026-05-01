---
title: Actuate Inference API
type: summary
topic: inference-api
tags: [inference-api, fastapi, lambda, v5, detection]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496140289"
jira: "ED-32"
created: 2026-04-13
updated: 2026-04-15
author: kb-bot
---

# Actuate Inference API

FastAPI-based REST service that accepts JPEG images and returns object detection results. Deployed as AWS Lambda (container image via Mangum adapter) behind API Gateway with a Rust Lambda authorizer. **Lambda deployment is permanent** — there is no planned migration to Kubernetes.

## Architecture

```
Client (EBUS, partners) -> API Gateway -> Rust Lambda Authorizer (DynamoDB lookup)
    -> Lambda (FastAPI/Mangum) -> Model Servers (K8s, ds-model-prod)
    -> Post-processing filters -> Response
```

## API Versions

| Version | Endpoints | Status |
|---------|-----------|--------|
| v1 | `/v1/infer/frames` | Legacy |
| v2 | `/v2/{intruder,weapon}/detections` | Legacy |
| v3 | `/v3/{model}/detections` | Stable, in use |
| v4 | `/v4/{model}/detections` (7 models) | Stable, latest |
| v5 | `GET /v5/models`, `POST /v5/detect` | In development |

## v5 API (In Development)

Unified generic detection endpoint for [[external-api/_summary|External API Initiative]] partners such as [[integrations/ebus/_summary|EBUS]]. Key design:
- **Single POST endpoint** (`/v5/detect`) services all models
- Request body: `model_id`, `frame`, `data` (JSON object validated against model schema)
- `GET /v5/models` returns available models with their expected `data` schemas
- Model list is **static/dictated** (not dynamically discovered), extending how v4 configures models
- Same response format for all customers — no per-customer response shapes
- API key auth (no customer_group concept)

**Primary consumer:** [[integrations/ebus/_summary|EBUS]] (Accellence Technologies VMS)

## RBAC

8 roles managed via DynamoDB `InferenceAPIAuth-{stage}` table:
`full_access`, `intruder`, `weapon`, `intruder_plus`, `intruder_plus_with_vehicle`, `motion_plus`, `pet`, `sliced_intruder_plus_with_vehicle`

**v5 dynamic role checking:** The v5 detect endpoint does NOT use a single `v5_detect` role. Instead, it checks roles **per model** at runtime -- a user with `intruder` role can call `POST /v5/detect` with `model_id: "intruder"` but gets 403 for `model_id: "weapon"`. `GET /v5/models` filters the model list by the caller's roles. See [[sensitivity-to-confidence-mapping]] and [[deep-dive-rust-authorizer]] for the full auth chain.

## Deployment

- **Prod:** `https://api.actuateui.net` (us-west-2, eu-west-1)
- **Dev:** `https://dev-api.actuateui.net`
- **Dev Swagger:** `https://dev-api.actuateui.net/docs` (Basic Auth — username is the DynamoDB `name` field, password is the `api_key` value)
- **CI/CD:** GitHub Actions (develop -> dev, main -> prod)
- **IaC:** Terraform with workspaces

## Roadmap (Revised 2026-04-14)

| Phase | What | Status |
|-------|------|--------|
| 0 | Documentation (25 docs, Confluence sync) + basic dev test endpoint | Done |
| 1 | Filter consolidation with [[actuate-libraries]] | Can run in parallel |
| 2 | v5 unified endpoint (`POST /v5/detect`, `GET /v5/models`) | **Deployed to dev 2026-04-14. 104 tests, live regression passing.** |
| 3 | API key subkey generation endpoints | Future |
| 4 | Ignore zones (via `data` JSON extension), dependency trimming | Future |

**Cancelled from original plan:** Lambda-to-K8s migration (ADR-001 denied), dynamic K8s model discovery (ADR-003 postponed), per-customer response format (ADR-005 — everyone gets same format), metadata caching, actuate-admin auth complexity.

## Key People

- **Michael Aleksa** — Primary developer (219 commits)
- **Mark Barbera** — Assigned to ED-32 (v5 API)

## Related Repos

- `actuate-inference-api` (primary)
- `actuate-libraries` — `feature/ed-32-filter-annotations` (filter consolidation)

## Deep Dives

- [[deep-dive-v4-endpoints]] -- All v4 endpoint signatures, parameters, response shapes
- [[deep-dive-rust-authorizer]] -- Rust authorizer code-level, DynamoDB schema, role extraction
- [[deep-dive-filter-chain]] -- Filter chain composition, application points, FDMD
- [[deep-dive-terraform-infra]] -- Lambda, API Gateway, DynamoDB, multi-region Terraform
- [[inference-context-pattern]] -- Frame caching across multi-model calls
- [[sensitivity-to-confidence-mapping]] -- Sensitivity presets to per-label thresholds
- [[multi-model-inference]] -- Concurrent asyncio.gather() across models

## External References

- [EBUS UI Mapping (Integrations space)](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/493092870) -- Phase 1 API-to-EBUS mapping, updated 2026-04-13 by Laura Reno
