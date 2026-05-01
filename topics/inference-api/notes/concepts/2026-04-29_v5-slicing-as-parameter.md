---
title: "v5 slicing as a parameter (registry dispatch override pattern)"
type: concept
topic: inference-api
tags: [v5, external-api, model-registry, refactor]
jira: "ENG-126"
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
---

# v5 Slicing as a Parameter

The v5 public model registry consolidates sliced variants into a single model with an optional `max_slices` parameter. This captures the reusable registry dispatch override pattern and the decision rationale.

## Model Registry Consolidation

**Before:** 7 models exposed in v5 public registry: `intruder`, `intruder-plus`, `intruder-plus-with-vehicle`, `sliced-intruder-plus-with-vehicle`, `weapon`, `pet`, `motion-plus`. SAHI slicing was a separate model endpoint.

**After:** 4 models: `intruder`, `weapon`, `pet`, `motion-plus`. The `intruder` model accepts an optional `max_slices` parameter (1–9, default 1) on the `data` payload. When `max_slices > 1`, the request routes to the SAHI-enabled backend (`SLICED_INTRUDER_PLUS_WITH_VEHICLE_ENDPOINT_URL`) and requires the `SlicedIntruderPlusWithVehicle` role. When == 1, it uses the regular intruder backend (`INTRUDER_PLUS_WITH_VEHICLE_ENDPOINT_URL`) and the `Intruder` role. Display name changed to "Intruder w/ Vehicle Detection"; detection classes now include `machinery`.

**Benefits:** Cleaner public API surface (partners see 4 models, not 7). Slicing is a tuning knob, not a separate product. Future models can adopt slicing without expanding the registry.

## The Pattern: Optional Slicing Fields on ModelRegistryEntry

Three new optional fields on `ModelRegistryEntry` encode a slicing override: `sliced_client_type`, `sliced_accepted_roles`, `sliced_confidence_function`. 

When all three conditions are met:
1. `max_slices > 1` in the incoming `data` payload
2. `"slicing"` is in the model's `capabilities` array
3. All three override fields are populated on the registry entry

…the v5 detect endpoint dispatches to the sliced backend instead of the default client. The registry pattern remains uniform — slicing is just a capability and its routing properties, not a separate model.

**File locations:**
- Registry definition: `inference_api/api/v5/registry.py` (ModelRegistryEntry fields)
- Dispatch logic: `inference_api/api/endpoints/v5.py` (start of detect handler, before RBAC enforcement)

## RBAC Ordering: Validate, Dispatch, Check Role

RBAC must be checked **after** the dispatch decision. The v5 detect endpoint now:
1. Validates `data` against the resolved model schema
2. Decides the backend based on `max_slices` value
3. Checks the resolved role against the request context
4. Proceeds or returns 403

A key with only the `intruder` role gets 403 if it requests slicing — intentional, because the sliced backend is a distinct model server with its own access policy.

## Confidence Threshold Semantics Differ

Unsliced intruder uses **per-label thresholds** (via `get_confidence_thresholds`); the sliced variant uses a **single threshold** (via `get_slice_intruder_plus_with_vehicle_confidence_threshold`). Partners selecting sensitivity get different actual thresholds depending on their slicing choice.

**Sensitivity mapping table** (documented in [[sensitivity-to-confidence-mapping]]):
- Per-label thresholds: intruder (max_slices=1), weapon, pet
- Single threshold: motion-plus, intruder (max_slices > 1)

This is a contract change partners should be aware of when tuning sensitivity.

## ENG-126 Scope vs. Implementation

**ENG-126 specifies** (but today's PR does NOT implement):
- Per-model paths `/v5/{model}/detections` (v5 currently uses single `/v5/detect` endpoint)
- `detection_classes` allow-list parameter
- Vehicle label roll-up
- Boolean `stationary_filter` parameter
- `confidence_threshold` parameter (global override)

**Today's PR (2026-04-29)** implements only:
- Model-list consolidation (7 → 4)
- `max_slices` parameter on intruder

Remaining ENG-126 items are deferred. Future work should reference ENG-126 and coordinate with [[v5-api-design]] when adopting them.

## PR Reference

[aegissystems/actuate-inference-api#59](https://github.com/aegissystems/actuate-inference-api/pull/59) — merged 2026-04-29 20:31 UTC. Three bundled commits:
- Registry consolidation (`fb38828`)
- Gitignore cleanup (`fd6d8f9`)
- Terraform 1.11.4 pin to fix pre-existing CI regression (`ad0dc2a`)

Deployed to dev cleanly; contract verified live via Swagger + EBUS integration tests.

## Cross-Links

- [[v5-api-design]] — should reflect that max_slices dispatch decision is no longer deferred
- [[sensitivity-to-confidence-mapping]] — documents threshold differences by model and slicing choice
- [[ebus-partner-access]] — EBUS retains both `intruder` and `sliced_intruder_plus_with_vehicle` roles; both still work
- [[multi-model-inference]] — related v5 dispatch and async patterns
