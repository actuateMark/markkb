---
title: "actuate-validator ↔ AIT brain-in-jar — overlap analysis + dovetail plays"
type: synthesis
topic: engineering-process
tags: [actuate-validator, actuate-integration-tools, ait, brain-in-jar, integration-testing, factories, hypothesis, golden-set]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-validator.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/syntheses/2026-05-21_hypothesis-in-actuate.md
  - topics/personal-notes/notes/daily/2026-05-21.md
incoming_updated: 2026-06-24
---

# actuate-validator ↔ AIT brain-in-jar — overlap + dovetail

Surveyed 2026-05-21 from the `feat/motion-validator` branch. Zack's library and our AIT work converged independently on a similar problem space — testing production pipeline code without standing up the full connector. The mechanics overlap enough that **active integration is the right move, not parallel tracks.**

> **Status update 2026-05-21:** Fault-line analysis + alignment decisions captured in **[[2026-05-21_ait-validator-integration-plan]]**. This synthesis remains the high-level six-play catalog; the integration plan is the gating doc for further AIT dev. Plays A + B + D below are operationalized in the integration plan with concrete sequencing.

## The landscape after Phase 11

Three complementary capabilities now exist or are landing:

| Capability | Library | What it answers | Inputs | Outputs |
|---|---|---|---|---|
| **AIT replay** (Phases 5–10) | `actuate-integration-tools` | "Reproduce *this specific* captured failure" | Real production state captured on crash | S3 dump bucket → developer laptop replay |
| **AIT simulate** (Phase 11) | `actuate-integration-tools` + `actuate-pipeline-objects.testing` | "Find failures I haven't hit yet across the input space" | Synthetic IDPs (factories + Hypothesis) | Local terminal output; optional dump |
| **actuate-validator** | `actuate-libraries/actuate-validator` | "Does production code still match expected behavior on this curated set of real cases?" | Curated golden-set videos + precomputed detections | Per-suite score vs baseline; pytest CI integration |

Each fills a hole the others don't. **Replay** is a forensic tool — bounded by what production captured. **Simulate** is a fuzzer — unbounded but synthetic. **Validate** is a regression gate — curated, real, deterministic, pre-merge.

## Where they overlap (and how each can enhance the other)

### 1. Mock packet types — refactor opportunity

`actuate-validator/src/actuate_validator/pipeline_harness.py` inlines its own packet stubs:

```python
class _MockProductDataPacket:
    def __init__(self, raw_model_response: list):
        self.raw_model_response = raw_model_response


class _MockImageDataPacket:
    def __init__(self, motion_boxes: MultiPolygon, products: dict):
        self.motion_boxes = motion_boxes
        self.skip_stationary_filter = False
        self.is_high_motion_sensitivity = False
        self.products = products
```

These reimplement what `actuate-pipeline-objects/testing/factories.py` (AIT Phase 11, 2026-05-21) now produces faithfully:

```python
from actuate_pipeline_objects.testing import make_idp, make_pdp
idp = make_idp(motion_boxes=multipoly, products={"intruder": make_pdp(...)})
```

**Play A — validator adopts our factories.** Switch the pipeline harness to use `make_idp` / `make_pdp` for its mock packets. Shrinks the validator code, removes a "second source of truth" for what a packet looks like, and means future fields added to the real packets propagate automatically. Probably a 30-minute change for Zack once Phase 11 lands on `main`.

### 2. DAO + ImageCache mocks — borrow direction

Validator's `mocks.py` exposes `MockDaoManager` (17 DAO properties, alert-capture interception) and `MockImageCache`. These don't exist in AIT today but **AIT Phase 8 (camera `from_dump` constructor) will need exactly this surface** to reconstitute a camera in a non-production environment.

**Play B — AIT borrows validator's mocks.** When Phase 8 lands, import `MockDaoManager` / `MockImageCache` from `actuate-validator` rather than reimplementing. Avoids drift. Trade-off: it makes `actuate-validator` an upstream dep of AIT. Acceptable since both live in CodeArtifact.

Alternative: lift those mocks into `actuate-daos/testing/` and `actuate-image-cache/testing/` so each lives next to the type it mocks (mirroring the pattern Phase 11 established for `actuate-pipeline-objects/testing/`). Cleanest long-term home; needs Zack's buy-in.

### 3. Test-type / scenario registries — converge on one pattern

Both libraries chose the same registry pattern:

| Library | Registry | Discovery |
|---|---|---|
| validator | `HARNESS_REGISTRY[test_type]` | Module import populates |
| AIT validate | `VALIDATORS[name]` | Explicit table in `__init__.py` |
| AIT simulate | `SCENARIOS[name]` | Explicit table in `__init__.py` |

Encouraging — the conventions match. **Play C — extract a shared registry helper.** A tiny `actuate_instrumentation.registry` module (or similar) that both libraries import keeps the pattern consistent and self-documenting. Minor; not urgent.

### 4. Golden-set storage vs crash-dump storage — same S3 lifecycle questions

Validator stores immutable test data in `s3://actuate-test-sets/<prefix>/v1/`. AIT Phase 10 plans `s3://actuate-crash-dumps/raw/<deployment_id>/` with 3-day TTL + 90-day Lambda-compacted summary.

These are **different buckets by design** (one is curated immutable test data, the other is ephemeral production captures), but the lifecycle / RBAC / Terraform patterns are nearly identical.

**Play D — share Terraform bucket modules.** When Phase 10 lands the `actuate-crash-dumps` bucket, factor a `ds-terraform-eks-v2/modules/test-data-bucket/` module that both buckets use. Saves duplication; encodes the "PII-bearing bucket" RBAC pattern once.

### 5. Brain-in-jar dumps as validator inputs

A brain-in-jar dump from Phase 9 contains: video frames (sidecars), IDPs (Phase 4 serialized state), captured alert payloads (Phase 7), camera state (Phase 8). That's roughly the same shape as a validator golden-set entry: video + precomputed detections + expected behavior.

**Play E — brain-in-jar dumps as a validator test-type.** Add a `dump_replay` harness to validator that takes a captured production dump and re-runs the relevant production code (observer / pipeline step) against it, asserting outcomes against the originally-captured outputs. This makes the validator's "golden set" expand organically with every interesting production crash, no manual curation required.

Conceptual chain:

```
prod crash → brain-in-jar dump (Phase 9 + 10)
            → ait dumps fetch <id>
            → validator/manifests/auto-from-dump.json (auto-generated)
            → just test-package actuate-validator
              → asserts the captured-state replay still produces captured-output
```

If we ship Play E, the brain-in-jar arc essentially becomes a *test-corpus generator* for the validator. The two libraries cooperate end-to-end.

### 6. Hypothesis strategies → validator fuzz

Validator's golden-set baselines are static. Adding Hypothesis fuzzing on top of the golden set (perturbing existing test cases within bounded ranges) would catch boundary-condition regressions that a single fixed example doesn't. Phase 11's `actuate-pipeline-objects/testing/strategies.py` is the foundation.

**Play F — validator gets a fuzz mode.** `just test-package actuate-validator --fuzz` runs each golden-set test case N times with Hypothesis-perturbed inputs; reports any divergence from the original outcome. Reuses our existing [[strategies]]; minimal new code in validator.

## Sequencing — what to do when

| Play | When | Effort | Owner |
|---|---|---|---|
| A — validator adopts factories | After `[minor:actuate-pipeline-objects]` from Phase 11 publishes | ~30min validator-side | Zack (with our PR if helpful) |
| B — AIT borrows validator mocks | Phase 8 (camera `from_dump`) | ~1h | Mark / AIT |
| C — shared registry helper | Anytime; low priority | ~1h | Either |
| D — shared Terraform module | Phase 10 (S3 sink) | ~2h | Mark / AIT |
| E — brain-in-jar dumps as validator inputs | Phase 9 + 10 land | ~2–4h | Joint |
| F — validator fuzz mode | Phase 11 ships; validator wants it | ~2h | Zack |

## What this means for the AIT roadmap

Two adjustments:

1. **Phase 8's mock surface** should explicitly plan to use validator's `MockDaoManager` / `MockImageCache` (or jointly-owned versions in `actuate-daos/testing/`), not reinvent them. Updated Phase 8 KB note accordingly.

2. **Phase 11's factories** become a cross-library asset, not AIT-only. Worth a heads-up to Zack so the validator-side adoption (Play A) happens once Phase 11 lands on libraries `main`.

No phase changes; no scope changes. Just integration discipline.

## Open questions

- Should `actuate-validator` live in `actuate-libraries` long-term, or get pulled out into its own repo like `actuate-integration-tools` did? The "testing library that pulls in 13 production deps" footprint is unusual for a library; cleaner as a top-level repo. Worth asking Zack.

- Do we want to coordinate the naming convention — e.g. `*-testing/` subpackages across libraries that need test factories? Phase 11 set a precedent in `actuate-pipeline-objects/testing/`; validator's `mocks.py` doesn't follow it.

- Should brain-in-jar dumps and validator golden sets converge on a single S3 layout / lifecycle, even if the buckets differ? Probably yes — saves operational complexity.

## Cross-references

- [[actuate-validator]] — entity overview
- [[actuate-integration-tools]] — sibling toolkit
- [[2026-05-20_ait-brain-in-jar-spec]] — AIT replay arc parent
- [[2026-05-21_ait-phase-11-simulate]] — AIT simulate arc parent (the factories Play A would adopt)
- [[2026-05-20_ait-phase-8-camera-from-dump]] — needs validator's DAO + cache mocks (Play B)
- [[2026-05-20_ait-phase-10-s3-sink-review-ux]] — shares bucket-lifecycle patterns with validator (Play D)
