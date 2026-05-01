---
title: External API Initiative
type: summary
topic: external-api
tags: [external-api, v5, ebus, alarmwatch, alarmquip, partner-api]
jira: "ENG-122"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# External API Initiative

A strategic initiative (ENG-122) to expose **generic, partner-facing APIs** beyond the existing internal platform. Multiple workstreams, each driven by a specific customer need.

## Workstreams

| Ticket | Endpoint Type | Customer | Assignee | Status |
|--------|--------------|----------|----------|--------|
| **ENG-126** | Detection (v5 API) | [[integrations/ebus/_summary|EBUS]] | [[mark-barbera|Mark Barbera]] | To Do — [[ebus-partner-access|dev key live]] |
| **ENG-123** | Schedule Management | [[alarmwatch-customer|AlarmWatch / Crosbies (NZ)]] | [[vinicius-flores|Vinicius Flores]] | In Progress (PR #4 merged) |
| **ENG-124** | Image Ingestion (SMTP alt) | [[alarmquip-customer|Alarmquip (AU)]] | Unassigned | To Do |
| **ENG-125** | Arm/Disarm Per Site | AlarmWatch | [[vinicius-flores|Vinicius Flores]] | To Do |
| **ENG-132** | Harden Admin API + alarm clip fetch | -- | Unassigned | To Do |
| **ENG-133** | Add ID field for v4 endpoints | RuggedNetworks | Unassigned | To Do |

## Architecture Pattern

The team is standardizing all public-facing services on:

```
Client -> AWS API Gateway (REST) -> Rust Lambda Authorizer -> K8s pods (via VPC Link + ALB)
```

This pattern applies to both the [[inference-api/_summary|Actuate Inference API]] and the Admin-based external endpoints. Whether they share the same Rust authorizer is TBD.

## Key Design Decisions (from ENG-126)

- **Unified endpoint with body-based model routing:** `POST /v5/detect` with `model_id` in request body (not path-based)
- **detection_classes** exposed per-model in `GET /v5/models` response
- **Per-customer API keys** (not per-integration-partner)
- **motion-plus** treated as a separate model type (requires 2+ frames, uses frame differences, no stationary filter)

## Active Development

**Schedule Management (ENG-123)** is the most progressed workstream:
- PR #4 merged Apr 10 (DynamoDB mapping layer)
- Kubernetes deployment merged (k8s #328)
- Currently in test
- Open question: should `/schedule` and `/flex-schedule` be AlarmWatch-only?

**Arm/Disarm (ENG-34 / ENG-125):**
- [[vinicius-flores|Vinicius Flores]] working on this in parallel
- For [[alarmwatch-customer|AlarmWatch customer]]

## Not a Single Project

"External API" is **not a separate codebase** -- it's an umbrella initiative spanning:
- [[inference-api/_summary|Actuate Inference API]] (v5 detection endpoints)
- [[admin-api/_summary|Actuate Admin API]] (schedule, arm/disarm, image ingestion endpoints)
- Shared auth infrastructure (Rust authorizers, DynamoDB)

The term `actuate-external-api` appears in architecture docs as a reference to this pattern, but there is no standalone repo by that name.
