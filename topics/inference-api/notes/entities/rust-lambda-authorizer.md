---
title: "Rust Lambda Authorizer"
type: entity
topic: inference-api
tags: [rust, lambda, authorizer, dynamodb, rbac, api-gateway]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_local-repo-audit.md
  - topics/actuate-platform/notes/concepts/rbac-model.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/admin-api/notes/concepts/integration-architecture.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-vini-gateway.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/external-api/notes/concepts/partner-api-credential-runbook.md
  - topics/external-api/notes/concepts/shared-auth-pattern.md
  - topics/external-api/notes/entities/alarmwatch-customer.md
  - topics/inference-api/_summary.md
incoming_updated: 2026-06-25
---

# Rust Lambda Authorizer

The Rust Lambda Authorizer is a custom AWS API Gateway authorizer that sits in front of the [[inference-api/_summary|Actuate Inference API]] (and potentially other [[external-api/_summary|External API Initiative]] endpoints). It validates every inbound request before it reaches the FastAPI application layer.

## Request Flow

When a client (such as [[integrations/ebus/_summary|EBUS]] or another partner) sends a request to the Actuate API Gateway, the authorizer Lambda executes before the request is forwarded:

```
Client -> API Gateway -> Rust Lambda Authorizer -> Backend (Lambda or K8s pod)
```

The authorizer extracts the API key from the request and performs a lookup against a DynamoDB table to determine whether the key is valid and what permissions it carries.

## DynamoDB Lookup

API keys and their associated roles are stored in the `InferenceAPIAuth-{stage}` DynamoDB table (where stage is `prod`, `dev`, etc.). The [[admin-api/_summary|Actuate Admin API]] is responsible for creating and managing these API keys -- when a key is provisioned in the Admin API, it is written to DynamoDB, and the Rust authorizer reads from that same table at request time.

This decoupled design means the authorizer has no direct dependency on the Admin API at runtime; it only needs read access to DynamoDB.

## RBAC Model

The authorizer enforces role-based access control across 8+ roles:

- `full_access` -- unrestricted access to all models and endpoints
- `intruder` -- access to intruder detection only
- `weapon` -- access to weapon detection only
- `intruder_plus` -- intruder with additional object classes
- `intruder_plus_with_vehicle` -- intruder plus vehicle detection
- `motion_plus` -- motion detection with extended filters
- `pet` -- pet detection
- `sliced_intruder_plus_with_vehicle` -- sliced variant for high-resolution frames
The role attached to an API key determines which models and endpoints the caller can invoke.

**v1-v4**: Each endpoint has a fixed role check via FastAPI dependency injection (`Depends(check_intruder_roles)`). The authorizer returns roles, FastAPI checks them per-endpoint.

**v5**: There is no separate `v5_detect` role. The unified `POST /v5/detect` endpoint checks roles dynamically based on the `model_id` in the request body, using the same eight per-model roles. A key with `intruder` can call `/v5/detect` with `model_id: "intruder"` but gets 403 for `model_id: "weapon"`. The `GET /v5/models` endpoint filters its response to only show models the caller has access to.

## Shared Auth Pattern

The [[external-api/_summary|External API Initiative]] initiative is standardizing all public-facing services on this same `API Gateway -> Rust Lambda Authorizer -> backend` pattern. Whether the schedule management and image ingestion endpoints (served by [[admin-api/_summary|Actuate Admin API]]) will share this exact authorizer or use a separate instance is still TBD. See [[shared-auth-pattern]] for details.

## Docs Authorizer (Basic Auth)

A separate Rust authorizer (`InferenceAPIBasicAuthRS`) protects Swagger UI at `/docs` and `/openapi.json`. Uses HTTP Basic Auth:
- **Username:** the `name` field from the DynamoDB record
- **Password:** the `api_key` value itself

Same DynamoDB table as the inference authorizer.

## DynamoDB Field Type

The `roles` field **must** be DynamoDB type `SS` (String Set), not `S` (String). The Rust `DynamoDBItem` struct deserializes it as `HashSet<String>`. Using `S` type causes an opaque `"Unauthorized"` error. See [[2026-04-14_dev-deployment-issues]].

## Implementation

The authorizers are written in Rust for cold-start performance -- Lambda authorizers run on every request and must respond within milliseconds to avoid adding perceptible latency. Rust's compile-to-native model makes it well-suited for this use case.
