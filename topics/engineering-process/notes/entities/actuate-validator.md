---
title: "actuate-validator (golden-set integration testing)"
type: entity
topic: engineering-process
tags: [actuate-libraries, validation, golden-set, integration-testing, observers, pipeline, harness, motion-validator]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-22_ait-phase-12-sweep.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/models/hypothesis/_summary.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-06-24
---

# actuate-validator

Standalone library in `actuate-libraries` providing **golden-set integration testing** for Actuate observers and the connector filter pipeline. Surveyed 2026-05-21 from `feat/motion-validator` branch (PR not yet open as of survey). Primary driver: [[zack-schmidt|Zack Schmidt]] (17 of 21 commits on the branch); 4 are CI-generated bumps.

## Location

`actuate-libraries/actuate-validator/` (library); shares CodeArtifact dep graph with the rest of `actuate-libraries`. Current version pin on the branch: `0.1.1.dev1+feat.motion.validator`.

## Core idea — the Trinity

Every validation scenario is built from three components:

| Component | What | Where |
|---|---|---|
| **Intent manifest** | JSON file declaring test cases with params + expected outcomes | `src/actuate_validator/manifests/<suite>_manifest.json` |
| **Validation harness** | Adapter that translates manifest params into production config and runs production code | `src/actuate_validator/harness.py` (observer), `pipeline_harness.py` (filter pipeline), or user-supplied |
| **Golden set** | Immutable test data — videos + pre-computed detection files | S3 bucket `actuate-test-sets/<prefix>/v1/...` (and/or local repo for small ones like `stationary-filter`) |

Manifests reference observer/pipeline params + expected outcomes; harnesses wire real production classes (`PersonLineCrossingObserver`, `StationaryFilterStep`, etc.) into a test scaffold via mocked DAOs / ImageCache; golden sets supply the inputs.

## Test types today

Discovered via `HARNESS_REGISTRY` lookup keyed on the manifest's `test_type`:

| `test_type` | Harness | Tests |
|---|---|---|
| `observer` | `ObserverHarness` (`harness.py`) | `PersonLineCrossingObserver`, `VehicleLineCrossingObserver` — alert-generation logic against video + precomputed detections |
| `pipeline` | `PipelineHarness` (`pipeline_harness.py`) | The full filter chain: FDMD motion → detection load → [[ignore-zones|ignore zones]] → IOU dedup → stationary filter. Supports precomputed or live model inference. |
| Custom | User-supplied `BaseHarness` subclass | Any production component with known-good input/output pairs (the README example is CNN model inference) |

Adding a new test type: subclass `BaseHarness`, register in `HARNESS_REGISTRY`, create a manifest with the matching `test_type`. The pytest infrastructure and CLI runner dispatch automatically — zero framework changes required.

## CLI surface

```bash
# Interactive setup for a new project / observer / test type
python -m actuate_validator walkthrough

# Discover + run all manifests
just test-package actuate-validator
uv run pytest actuate-validator/ -v

# Direct run against a specific manifest
uv run python -m actuate_validator run --manifest path/to/manifest.json
```

The walkthrough is a six-step interactive flow (test type → suite name → data source → test cases → review → integration) that produces both the manifest JSON and an integration stub appended to the product's existing unit tests.

## Mocks + adapters

`mocks.py` provides `MockDaoManager` (mirrors all 17 DAO properties on the real DaoManager; intercepts `put_stream_alert` writes into a `self.alerts` list) and `MockImageCache` (in-memory frame store). Lets observers run end-to-end without DB or S3 connectivity.

Pipeline harness adds inline mock packet types (`_MockImageDataPacket`, `_MockProductDataPacket`, `_MockFeatureDeployment`) to wrap `StationaryFilterStep` without the full pipeline link infrastructure. **These overlap with the factory primitives in `actuate-pipeline-objects/testing/` that AIT Phase 11 introduced 2026-05-21** — there's a refactor opportunity (see [[2026-05-21_ait-validator-dovetail]]).

## Regression-detection model

`baselines.json` stores per-suite expected scores. `conftest.py` converts AssertionError failures to XFAIL and tracks per-suite scores. **Individual test failures don't block CI; the suite's aggregate score regressing below baseline does.** This is more lenient than typical pass/fail integration testing — designed to tolerate occasional flake while still catching real behavior shifts.

## Today's golden sets

| Suite | Where | Test type |
|---|---|---|
| `stationary-filter` | local repo (small detection files only) | observer |
| `vehicle-motion-filter` | mix of local labels + S3 video | pipeline |
| `customer-line-crossing-intake` | S3 | observer |
| `line-crossing` (manifests reference) | S3 `actuate-test-sets/line-crossing/v1/` | observer + pipeline |

## When this fires

Per the README's "When to Use" table:

- R&D-to-production handoff (validates the production build reproduces R&D results)
- Bug fixes (existing golden set confirms the fix doesn't break real scenarios)
- Parameter tuning (e.g. stationary vehicle overlap threshold)
- Feature enhancements (new test cases for the new behavior; existing tests confirm backward compatibility)
- Refactors / dependency upgrades (full golden set acts as behavioral regression suite)

## Overlap with AIT brain-in-jar

The libraries share substantial mechanics (mock IDPs, mock DAOs, fixture-driven test orchestration, explicit registries). The replay-vs-simulate-vs-validate landscape is now:

| | What it tests | Input | Where outputs live |
|---|---|---|---|
| AIT replay arc (Phases 5–10) | "Reproduce this specific captured failure" | Real captured pipeline state | S3 dump bucket |
| AIT simulate arc (Phase 11) | "Find failures across the input space" | Synthetic IDPs (factories + Hypothesis) | Local; optional dump for replay-puller |
| `actuate-validator` | "Verify production code matches expected behavior on real golden inputs" | Video + precomputed detections | S3 golden-set bucket; baselines.json scores |

All three share the same upstream packet types and pipeline infra; refactor opportunities + integration points detailed in [[2026-05-21_ait-validator-dovetail]].

## Cross-references

- [[2026-05-21_ait-validator-dovetail]] — overlap analysis + concrete integration plays
- [[actuate-integration-tools]] — sibling toolkit; replay + simulate arcs
- [[2026-05-20_ait-brain-in-jar-spec]] — AIT replay arc parent
- [[2026-05-21_ait-phase-11-simulate]] — AIT simulate arc parent
