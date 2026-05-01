---
title: "Plan: v5 Revised Architecture — Unified Detect Endpoint on Lambda"
type: synthesis
topic: inference-api
tags: [plan, v5, architecture, ebus, lambda]
jira: "ED-32"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# v5 Revised Architecture Plan

## What Changed (2026-04-13)

The original ED-32 plan had 4 phases culminating in a Lambda-to-K8s migration with dynamic model discovery. After team review of the [[architecture-decision-records|architecture decision records]], the scope was significantly narrowed:

### Cancelled
- **Lambda-to-K8s migration** (ADR-001 denied) — staying on Lambda permanently
- **Dynamic K8s model discovery** (ADR-003 postponed) — static model list instead
- **Per-customer response format** (ADR-005) — everyone gets the same endpoints
- **Customer group in authorizer** — API keys are sufficient, no customer_group concept
- **Metadata caching** — no camera/site lookups, each call is a singleton
- **Dockerfile dual-mode** — no uvicorn, Lambda + Mangum stays
- **actuate-admin runtime dependency** — not needed for v5

### Confirmed
- **Single unified POST endpoint** (`/v5/detect`) with `model_id`, `frame`, `data` JSON body
- **GET /v5/models** returns available models with expected `data` schemas
- **Static model registry** extending v4's approach (env vars + `InferenceClientType`)
- **Filter consolidation** with `actuate-libraries` can run in parallel
- **Gradual rollout** — v1-v4 untouched, v5 added alongside
- **API key subkey generation** — future endpoint for top-level keys to create subkeys

## Why

The team determined that v5 is a **reorganization of existing functionality**, not a migration. The core value is:
1. One endpoint for all models (vs v4's 9 endpoints)
2. Self-documenting via `GET /v5/models` which describes expected `data` schemas
3. Extensible — new models added to registry, not new endpoints
4. Clean for partners — EBÜS gets a simple, well-documented JSON API

## Architectural Choices

### Validated `data` Object
The `data` field in the POST body is a freeform JSON object whose schema is defined per-model. `GET /v5/models` returns the expected schema for each model, and the endpoint validates incoming `data` against it. This is the core innovation — it makes the API extensible without endpoint changes.

### Reuse of v4 Infrastructure
- Same `LoadBalancerInferenceClient` with `InferenceClientType` enum
- Same `InferenceContext` and `ModelContext` for frame processing
- Same filter pipeline (LabelFilter, LabelwiseConfidenceFilter, FdmdStationaryFilter, IoUFilter)
- Same API Gateway `{proxy+}` route catches `/v5/*` automatically
- Same [[rust-lambda-authorizer|Rust Lambda authorizer]] validates API keys

### Model Registry as Code
Models are defined statically — a registry data structure that maps `model_id` to: display name, description, detection classes, expected `data` schema, inference client type, and default parameters. This replaces v4's implicit "one endpoint per model" pattern with an explicit, queryable registry.

## Cross-Service Impacts

- **API Gateway:** No changes needed — existing `{proxy+}` proxy integration routes all paths to the Lambda
- **Rust authorizer:** No new role needed — v5 reuses the existing per-model roles dynamically (resolved: no `v5_detect` role)
- **DynamoDB auth table:** New API key for EBÜS dev testing needed by 2026-04-18
- **actuate-libraries:** Filter consolidation is independent and can proceed in parallel
- **Terraform:** No infrastructure changes for v5 itself
- **CI/CD:** Existing deploy-dev.yaml handles v5 automatically (same Lambda)

## Timeline Pressure

EBÜS needs a dev endpoint by end of week (2026-04-18). Minimum viable: basic `POST /v5/detect` working on dev with at least one model, plus an API key in the dev DynamoDB table.
