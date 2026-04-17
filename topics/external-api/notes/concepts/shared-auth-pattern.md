---
title: "Shared Auth Pattern"
type: concept
topic: external-api
tags: [auth, api-gateway, rust, authorizer, architecture, pattern]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Shared Auth Pattern

The [[external-api]] initiative is standardizing all public-facing Actuate services on a common authentication and routing architecture. This pattern ensures consistent security, key management, and infrastructure across every partner-facing endpoint.

## The Pattern

```
Client -> AWS API Gateway (REST) -> Rust Lambda Authorizer -> K8s pods (via VPC Link + ALB)
```

Each component has a distinct responsibility:

### AWS API Gateway (REST)

The entry point for all external traffic. API Gateway handles TLS termination, rate limiting, request validation, and routing. It is configured as a REST API (not HTTP API) to support Lambda authorizers and fine-grained request/response transformations.

### Rust Lambda Authorizer

The [[rust-lambda-authorizer]] executes on every request before it reaches the backend. It extracts the API key from the request, looks it up in a DynamoDB table (`InferenceAPIAuth-{stage}`), and returns an IAM policy that either allows or denies the request based on the key's associated role.

The authorizer was originally built for the [[inference-api]] but the [[external-api]] initiative aims to reuse this pattern across all partner-facing endpoints. Whether the schedule management, arm/disarm, and image ingestion endpoints share the exact same authorizer Lambda or deploy separate instances is still TBD as of April 2026.

### VPC Link + ALB

The API Gateway connects to Kubernetes pods running inside a VPC via a VPC Link. Traffic flows through an Application Load Balancer (ALB) to reach the appropriate K8s service. This allows the backend to run as standard Kubernetes deployments while remaining accessible through the public API Gateway.

### K8s Pods (Backend)

The actual application logic runs in Kubernetes. Different workstreams target different backends:

- **Detection (v5):** [[inference-api]] FastAPI pods (after [[lambda-to-k8s-migration]])
- **Schedule/Arm-Disarm:** [[admin-api]] Django pods
- **Image Ingestion:** Likely [[admin-api]] pods (TBD)

## Key Management

API keys are managed by the [[admin-api]] and stored in DynamoDB. The lifecycle is:

1. Admin API creates/rotates an API key for a customer
2. Key + role mapping is written to `InferenceAPIAuth-{stage}` DynamoDB table
3. Rust authorizer reads from DynamoDB at request time
4. No direct runtime dependency between Admin API and authorizer

Keys are issued **per-customer** (not per-integration-partner), so each customer using EBUS, AlarmWatch's schedule API, or Alarmquip's image endpoint gets their own key.

## Why Standardize

Before this initiative, the [[inference-api]] was the only service using the Rust authorizer pattern. Other external-facing endpoints either did not exist or used ad-hoc authentication. Standardizing on a single pattern provides:

- **Consistent security posture** across all partner-facing APIs
- **Single key management interface** in the Admin API
- **Reusable infrastructure** (Terraform modules, API Gateway configs)
- **Unified monitoring** -- all external traffic flows through the same API Gateway, enabling centralized logging and alerting

## Related

- [[rust-lambda-authorizer]] -- the authorizer implementation
- [[v5-api-design]] -- first consumer of this pattern (detection)
- [[alarmwatch-customer]] -- schedule/arm-disarm endpoints
- [[alarmquip-customer]] -- image ingestion endpoint
