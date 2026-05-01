---
title: "v5 API Design (Revised)"
type: concept
topic: inference-api
tags: [v5, api-design, detection, ebus, external-api]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# v5 Unified Detection API Design

The v5 API is a unified detection endpoint for the [[inference-api/_summary|Actuate Inference API]], designed to serve all models through a single interface. It replaces v4's per-model endpoint pattern with a single `POST /v5/detect` that accepts a `model_id` and a validated `data` JSON object.

## Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v5/models` | GET | Lists available models with their expected `data` schemas |
| `/v5/detect` | POST | Single inference endpoint for all models |

## Core Design: Validated `data` Object

The fundamental v5 innovation is a single endpoint that validates its `data` payload against the model's schema:

```json
{
  "model_id": "intruder-plus-with-vehicle",
  "frame": "<JPEG bytes or URL>",
  "data": {
    "sensitivity": "medium",
    "max_slices": 4
  }
}
```

- `model_id` — identifies which model to run inference against
- `frame` — the image data (JPEG bytes or downloadable URL)
- `data` — JSON object whose schema is defined by the model; validated against the schema returned by `GET /v5/models`

The `GET /v5/models` endpoint returns the list of available models along with their expected `data` schemas, so clients know exactly what to send. This makes the API self-documenting and extensible — adding a new model means adding its schema to the model list, not creating a new endpoint.

## Key Design Decisions (2026-04-13)

### Single Unified Endpoint (Not Per-Model Paths)

Unlike v4 which has `/v4/intruder/detections`, `/v4/weapon/detections`, etc., v5 routes everything through `POST /v5/detect` with `model_id` in the body. This simplifies the API surface and means new models don't require new endpoints.

### Static Model Registry (Not Dynamic Discovery)

Models are **dictated statically** in code/config, extending how v4 already defines its models via `InferenceClientType` enum and environment variables. There is no dynamic Kubernetes service discovery. The model list includes: name, what the model returns, what it does, and what parameters it accepts.

### No Per-Customer Response Format

All customers receive the same response schema. No `customer_group` concept, no response transformers, no per-customer config in the authorizer.

### No Lambda-to-K8s Migration

The inference API stays on Lambda (ADR-001 denied). v5 is an extension of the existing API Gateway + Lambda setup, not a migration.

### No Metadata Caching

Each API call is a singleton. No camera/site lookups, no caching, no actuate-admin dependency at runtime.

### Ignore Zones — Future Extension via `data`

Not needed now, but because `data` is a freeform JSON object validated per-model, [[ignore-zones|ignore zones]] can be added later as a field in the model's `data` schema without changing the endpoint contract.

## Relationship to v4

v5 is a reorganization of what v4 already does. The same model servers, inference clients, filters, and processing pipeline are reused. The difference is the API surface:

| Aspect | v4 | v5 |
|--------|----|----|
| Endpoints | 9 separate POST endpoints | 1 POST + 1 GET |
| Model selection | URL path | `model_id` in body |
| Parameters | Form fields per endpoint | `data` JSON per model schema |
| Input format | multipart/form-data | JSON body with frame |
| Adding models | New endpoint + code | Add to model registry |

## Implementation Notes

- Reuse existing `LoadBalancerInferenceClient` and `InferenceClientType` from v4
- Reuse `InferenceContext` and `ModelContext` for frame processing
- Reuse existing filter pipeline (`LabelFilter`, `LabelwiseConfidenceFilter`, `FdmdStationaryFilter`, `IoUFilter`)
- `max_slices` included as a `data` parameter, decision on whether to keep it as a real param deferred to pre-launch

## Jira References

- **ED-32** — Phase 1 API integration (parent EBUS ticket)
- **ENG-126** — v5 API spec
