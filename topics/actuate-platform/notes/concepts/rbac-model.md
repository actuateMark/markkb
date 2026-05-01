---
type: concept
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [dynamodb]
incoming:
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
incoming_updated: 2026-05-01
---

# RBAC Model

The Actuate platform uses three distinct authentication and authorization systems across its surface areas. They evolved independently to serve different audiences and have no unified identity layer.

## 1. Cognito (Admin API and Web UIs)

The [[admin-api/_summary|Actuate Admin API]] and customer-facing web applications ([[alert-ui]], camera-ui) authenticate via **AWS Cognito**. In production, Cognito supports social login; in development, local username/password authentication is used. Cognito issues JWT tokens that the Django application validates on each request.

This is the primary auth system for Actuate's internal users and monitoring center operators. It controls access to camera configuration, customer management, schedule creation, integration setup, and all administrative operations.

A significant weakness is that **19+ applications share a single Cognito app client**. This means any client configuration change (scopes, callback URLs, token settings) affects all applications simultaneously. Cognito's update API is destructive -- it replaces the full client config rather than patching individual fields -- so a misconfigured update can break authentication platform-wide. See [[secrets-management]] for the planned per-app client provisioning remediation.

## 2. API Keys + Rust Lambda Authorizer (Inference API)

The [[inference-api/_summary|Actuate Inference API]] uses a custom **API key system** backed by DynamoDB and a [[rust-lambda-authorizer]]. This is the auth system for external partners (EBUS, AlarmWatch, Alarmquip, RuggedNetworks) and internal services that call the detection API.

The flow is: client sends `X-API-Key` header, API Gateway invokes the [[rust-lambda-authorizer|Rust Lambda authorizer]], the authorizer looks up the key in `InferenceAPIAuth-{stage}` DynamoDB table, and returns the user's roles in the authorizer context. FastAPI's `CheckRoles` dependency then enforces per-endpoint access.

Eight roles map to detection products: `full_access`, `intruder`, `weapon`, `intruder_plus`, `intruder_plus_with_vehicle`, `motion_plus`, `pet`, `sliced_intruder_plus_with_vehicle`. There is no separate `v5_detect` role -- the v5 unified endpoint checks roles **per model** at runtime using the same eight roles as v4. Each role implicitly includes `full_access` as an alternative -- any endpoint accepts either its specific role or `full_access`.

See [[api-key-lifecycle]] for the full provisioning and validation flow.

## 3. API Key Passthrough (External API)

The [[external-api/_summary|External API Initiative]] initiative is standardizing partner-facing endpoints on the same `API Gateway -> Rust Lambda Authorizer -> backend` pattern used by the inference API. This includes schedule management (ENG-123), image ingestion (ENG-124), and arm/disarm endpoints (ENG-125) that are served by the [[admin-api/_summary|Actuate Admin API]] backend but exposed through API Gateway.

Whether these endpoints share the same Rust authorizer instance as the inference API or use a separate deployment is still TBD. The key design question is whether the same DynamoDB table and role model can serve both detection and administrative operations, or whether a separate role namespace is needed for schedule/site management permissions.

## How They Interact

The three systems are **largely independent**. Cognito governs internal/operator access. API keys govern external/partner access. There is one critical bridge: the [[admin-api/_summary|Actuate Admin API]] is responsible for **creating API keys** that the inference authorizer validates. When an admin provisions an API key through the Cognito-authenticated Admin API, the key is written to DynamoDB, where the Rust authorizer reads it at request time. The authorizer has no runtime dependency on the Admin API or Cognito -- it only needs DynamoDB.

This decoupled design means a Cognito outage does not affect inference API authentication, and an inference authorizer issue does not affect Admin API access. The trade-off is operational complexity: three separate systems to monitor, three credential stores, and no single view of "who has access to what" across the platform.
