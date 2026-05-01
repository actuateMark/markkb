---
title: "v5 Implementation: Unified Detect Endpoint"
type: synthesis
topic: inference-api
tags: [v5, implementation, ebus, api-design, detection]
jira: "ED-32"
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# v5 Implementation Complete

## What Was Built

Two new endpoints added to the [[inference-api/_summary|Actuate Inference API]] on the existing Lambda + API Gateway stack:

| Endpoint | Purpose |
|----------|---------|
| `GET /v5/models` | Lists 7 available models with JSON Schema descriptions of their `data` parameters |
| `POST /v5/detect` | Unified inference endpoint — accepts `model_id`, `frames[]`, and a `data` JSON object validated per-model |

### Core Design: Schema-Validated `data` Object

The fundamental innovation is that `POST /v5/detect` validates the `data` field against the model's Pydantic schema at runtime. `GET /v5/models` exposes each model's schema via `model_json_schema()`, making the API self-documenting. Adding a model = adding a registry entry + Pydantic class, not a new endpoint.

### Static Model Registry

`api/v5/registry.py` defines `MODEL_REGISTRY`, a dict mapping `model_id` → `ModelRegistryEntry` dataclass. Each entry contains:
- `client_type` (maps to env var → model server URL)
- `data_schema` (Pydantic class for request validation)
- `accepted_roles` (RBAC from `AcceptedRoles` enum)
- `confidence_function` (sensitivity → threshold mapping)
- `frame_type`, `min_frames`, `capabilities`

7 models registered: intruder, intruder-plus, intruder-plus-with-vehicle, weapon, pet, sliced-intruder-plus-with-vehicle, motion-plus.

### Request Flow

```
POST /v5/detect { model_id, frames[], data }
  → Registry lookup (404 if unknown)
  → Pydantic validation of data against model schema (422 if invalid)
  → RBAC check via CheckRoles (403 if denied)
  → Frame count validation against model.min_frames (400 if insufficient)
  → Decode frames (base64 → bytes, or URL download)
  → Build confidence thresholds from sensitivity
  → Build filter chain via shared make_filters()
  → Route: standard models → _infer(), motion-plus → infer_multi_model()
  → Transform to dict-keyed response { "0": [...dets], "1": [...dets] }
```

### Shared Filter Builder

`make_filters()` extracted from v4.py into `filter_builder.py`. Both v4 and v5 import from there. No behavioral change.

## Files Created

| File | Purpose |
|------|---------|
| `api/v5/registry.py` | Model registry + per-model Pydantic data schemas |
| `api/endpoints/v5.py` | GET /v5/models, POST /v5/detect, GET /v5/test |
| `api/endpoints/filter_builder.py` | Shared make_filters() |
| `api/dependencies/validation/v5_frame_handler.py` | Base64/URL frame decoder |
| `models/v5.py` | V5DetectRequest, V5DetectResponse, V5Detection, V5ModelInfo |
| `test/test_v5.py` | 31 unit tests (functional, security, role-filtering, role-enforcement) |
| `tools/v5-test-page/index.html` | Interactive test page with image upload + bbox overlay |
| `tools/v5-test-page/regression.html` | Live regression suite for v1-v5 with JSON export |
| `tools/v5-test-page/run.sh` | One-command local dev startup (stale process cleanup + AWS SSO + kubefwd + FastAPI) |
| `tools/v5-docs/index.html` | Wiki-style API documentation viewer (role-filtered) |

## Files Modified

| File | Change |
|------|--------|
| `api/endpoints/v4.py` | Removed local make_filters(), imports from filter_builder |
| `api/endpoints/routers.py` | Added router_v5 |
| `api/endpoints/common.py` | Added v5 to Tags enum |
| `api/security/check_api_key.py` | Added V5Detect role, check_v5_detect_roles() |
| `api/security/__init__.py` | Exported new function |
| `api/docs/generator.py` | Added /v5/models and /v5/detect to ENDPOINT_ROLE_MAPPING |
| `models/__init__.py` | Exported v5 models |

## Security Integration

- **API Gateway**: Existing `{proxy+}` routes all `/v5/*` through the [[rust-lambda-authorizer|Rust Lambda authorizer]]. No terraform changes needed.
- **Per-model RBAC on POST /v5/detect**: `CheckRoles(entry.accepted_roles)` checks the model-specific role (same roles as v4). A `weapon` key gets 403 on `model_id: "intruder"`.
- **Role-filtered GET /v5/models**: Only returns models the caller's API key grants access to. `full_access` sees all 7; `intruder` sees only intruder. Local dev (no auth context) shows all.
- **Role-filtered 404 hints**: When `model_id` is not found, the error message only lists models the caller can access — prevents leaking model names to unauthorized users.
- **Docs filtering**: v5 endpoints mapped to `AcceptedRoles.V5Detect` in `ENDPOINT_ROLE_MAPPING` for Swagger UI visibility.
- **API key**: `check_api_key` dependency on both endpoints for OpenAPI spec generation.

## Test Results

101/101 unit tests pass including 31 v5 tests (11 functional, 6 input validation, 5 role-filtering, 4 role-enforcement, 4 models schema, 1 test page). No regressions in v1-v4.

Live regression suite (`/v5/test/regression`) confirmed all v1-v4 endpoints still return 200/204 with real images through kubefwd. Results exportable as JSON via "Copy Results JSON" button.

## Tracking ID Parameters

- **v4 (7 non-vs endpoints):** Optional `id` Form parameter echoed via `X-Request-Id` response header. Non-breaking.
- **v4 `/vs/` (2 endpoints):** Already had required `id` — no change.
- **v5:** Optional `camera_id` and `site_id` in request body, echoed in response JSON. Matches EBUS integration spec.
- **Inference timeout:** Now configurable via `INFERENCE_TIMEOUT_SECONDS` env var (default 3s, local dev 10s).

## What Was NOT Built (Deferred)

- Lambda-to-K8s migration (ADR-001 denied)
- Dynamic K8s model discovery (static registry instead)
- Per-customer response format (everyone gets same format)
- [[ignore-zones|Ignore zones]] (extensible later via data JSON)
- API key subkey generation endpoints
- actuate-libraries filter consolidation (can proceed independently)
