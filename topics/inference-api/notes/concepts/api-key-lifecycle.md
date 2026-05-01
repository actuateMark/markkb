---
type: concept
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [dynamodb]
---

# API Key Lifecycle

API keys are the authentication mechanism for the [[inference-api/_summary|Actuate Inference API]] and the broader [[external-api/_summary|External API Initiative]] initiative. Their lifecycle spans three systems: the [[admin-api/_summary|Actuate Admin API]] (provisioning), DynamoDB (storage), and the [[rust-lambda-authorizer]] (validation).

## Key Creation

API keys are created through the [[admin-api/_summary|Actuate Admin API]]. When an administrator provisions a key for a customer or partner, the Admin API writes a record to the `InferenceAPIAuth-{stage}` DynamoDB table (where `{stage}` is `prod`, `dev`, etc.). Each record contains:

- **`api_key`** -- the key value itself, sent by clients in the `X-API-Key` header.
- **`name`** -- a human-readable identifier for the key holder.
- **`roles`** -- a DynamoDB String Set (`SS` type) containing the roles assigned to this key.

The `roles` field must be stored as type `SS` (String Set), not `S` (String). Using the wrong DynamoDB type causes the Rust authorizer to fail deserialization silently, returning an opaque "Unauthorized" error with no indication of the root cause.

## Roles

Eight base roles control access to detection models: `full_access`, `intruder`, `weapon`, `intruder_plus`, `intruder_plus_with_vehicle`, `motion_plus`, `pet`, `sliced_intruder_plus_with_vehicle`. There is no separate `v5_detect` role -- the v5 unified endpoint checks roles **per model** at runtime using the same roles as v4. A key can carry multiple roles -- for example, a partner might have both `intruder` and `weapon` access.

The `full_access` role is a wildcard that grants access to all endpoints and models.

## Request-Time Validation

On every inbound request, the AWS API Gateway invokes the [[rust-lambda-authorizer]] before the request reaches the FastAPI application:

```
Client -> API Gateway -> Rust Lambda Authorizer -> FastAPI (Lambda/Mangum)
```

The authorizer extracts the `X-API-Key` header, performs a DynamoDB lookup against `InferenceAPIAuth-{stage}`, and validates the key exists. If valid, it returns an IAM policy allowing the request to proceed, with the user's roles injected as a comma-separated string into the API Gateway authorizer context. API Gateway caches authorizer results (default TTL 3600 seconds) to avoid per-request DynamoDB lookups.

The authorizer is written in Rust for cold-start performance -- it executes on every request (or cache miss) and must respond within milliseconds.

## Per-Endpoint Access Control

The FastAPI application layer enforces fine-grained access via the `CheckRoles` class in `api/security/check_api_key.py`. Each endpoint declares a dependency on a role-checking function (e.g., `Depends(check_intruder_roles)`). When the endpoint is invoked:

1. `CheckRoles._extract_roles()` reads the roles string from `request.scope["aws.event"]["requestContext"]["authorizer"]["roles"]`.
2. The string is parsed into a set of role names.
3. The set is compared against the endpoint's `AcceptedRoles` enum value (e.g., `AcceptedRoles.Intruder = {"full_access", "intruder"}`).
4. If no matching role is found, a 403 is returned.

For **v1-v4 endpoints**, each path has a fixed role check. For **v5**, the unified `POST /v5/detect` endpoint checks roles dynamically based on the `model_id` in the request body -- a key with `intruder` can detect with `model_id: "intruder"` but receives a 403 for `model_id: "weapon"`. The `GET /v5/models` endpoint filters its response to show only models the caller's roles permit.

## Swagger UI Access

A separate Rust authorizer (`InferenceAPIBasicAuthRS`) protects the Swagger docs at `/docs` and `/openapi.json` using HTTP Basic Auth. The username is the `name` field from the DynamoDB record; the password is the `api_key` value. This uses the same DynamoDB table, providing docs access without a separate credential system.

For the operational runbook on issuing keys to partners and customers, see [[partner-api-credential-runbook]].
