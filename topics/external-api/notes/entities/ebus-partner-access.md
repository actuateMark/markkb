---
title: "EBUS Partner Dev API Access"
type: entity
topic: external-api
tags: [ebus, api-key, dev, partner-access, inference-api, dynamodb]
jira: "ENG-126"
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# EBUS Partner Dev API Access

Single source of truth for EBUS partner credentials and API access configuration on the dev inference-api.

**Generated using:** [[partner-api-credential-runbook]] — refer to that note for the full operational process for minting keys.

## Account & Credentials

**Location (not value):**
- DynamoDB table: `InferenceAPIAuth-dev` (AWS account `388576304176`, region `us-west-2`)
- DynamoDB row: `name = "ebus-dev"` with `roles` Set-of-Strings attribute
- API Gateway key ID: `w9xqifo4o3` (Key name: `ebus-dev`)

**Roles (model access):**
```
docs, intruder, intruder_plus, intruder_plus_with_vehicle, weapon, pet, motion_plus, sliced_intruder_plus_with_vehicle
```

Note: explicit per-model roles (not `full_access`). Any new model role must be added by mutation — the set is not auto-expanded.

**API Gateway binding:**
- Usage Plan: `inference_api_apigw_usage_plan-dev` (ID: `y36ojh`)
- API: `fmllvq1vf4`, Stage: `dev`
- Throttle: 500 burst / 1000 rps, no quota
- Status: enabled

Created 2026-04-17 via `generate_api_key.py` script in actuate-inference-api repo.

## How EBUS Uses It

**Base URL:** `https://dev-api.actuateui.net`

**Detection requests:**
- `GET /v5/models` — returns 7 models visible to the role set
- `POST /v5/detect` — send the key in `X-API-Key` header; accepts any `model_id` the roles cover
- Response contains detections filtered by the model's default thresholds

**Swagger / OpenAPI docs:**
- Endpoint: `https://dev-api.actuateui.net/docs`
- Auth: HTTP Basic Auth
  - Username: `ebus-dev` (the DynamoDB `name` field)
  - Password: the API key value
- Reuses the same DynamoDB row; no second credential store. Confirmed working 2026-04-17.
- OpenAPI spec: `https://dev-api.actuateui.net/openapi.json` (same Basic Auth)

## Rotation & Revocation

**Disable (fastest):**
- Flip `enabled: false` on the API Gateway key — no DynamoDB mutation needed.
- Alternative: delete the DynamoDB row (fails closed with 403 on next cache miss, TTL up to 1h).

**Rotate:**
- Re-run `generate_api_key.py` with `--username ebus-dev`
- Option A: pass `--api_key <newvalue>` to set a specific value
- Option B: omit `--api_key` to let API Gateway mint a fresh random key
- Notify EBUS of the new key value

**Update roles:**
- Re-run `generate_api_key.py` with different role flags; it detects the existing `name` and updates the DDB `roles` set in place

## Known Gotchas

- **API Gateway propagation delay (3–10s):** New key-to-usage-plan bindings may briefly return `403 Forbidden` from CloudFront with `x-amzn-errortype: ForbiddenException`. Retry after a brief delay.

- **Script version dependency:** The `generate_api_key.py` script was missing flags for `motion_plus`, `pet`, and `sliced_intruder_plus_with_vehicle` until 2026-04-17. Running an older copy of the repo will silently omit those roles; EBUS would get 403s at the app layer for those models.

- **`docs` role is vestigial:** The app layer doesn't check it; Swagger access is gated by the HTTP Basic Auth Lambda checking DynamoDB. The script adds it for historical consistency.

## Cross-Links

- [[external-api/_summary|external-api initiative]] — parent umbrella (ENG-122)
- [[integrations/ebus/_summary|EBUS integration topic]] — partner-side context
- [[inference-api/_summary|inference-api topic]] — API implementation
- `api-key-lifecycle` — creation, storage, validation flow; DDB `SS` patterns; Basic Auth docs auth
- `rust-lambda-authorizer` — key validation on every request

## Status

**Live on dev as of 2026-04-17**, verified end-to-end:
- `GET /v5/models` returned 200 with 7 models
- `POST /v5/detect` with `model_id: "intruder"` and `"motion-plus"` both returned 200
- `/docs` Basic Auth returned Swagger HTML
