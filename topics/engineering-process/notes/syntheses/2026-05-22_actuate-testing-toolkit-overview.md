---
title: "Actuate testing toolkit — unified overview + cross-tool workflows"
type: synthesis
topic: engineering-process
tags: [actuate-integration-tools, actuate-validator, hypothesis, brain-in-jar, testing, qa, workflows, master-synthesis]
created: 2026-05-22
updated: 2026-05-22
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-22_ait-phase-12-sweep.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/infrastructure/_summary.md
  - topics/infrastructure/notes/syntheses/2026-06-02_dynamodb-fit-assessment-ait-phase-10.md
  - topics/personal-notes/notes/daily/2026-05-22.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
  - topics/vms-connector/notes/syntheses/2026-05-26_pyav17-local-validation.md
incoming_updated: 2026-06-19
---

# Actuate testing toolkit — unified overview

Top-level map of how the testing infrastructure being built across 2026-05 fits together. Until now each piece had its own synthesis; this is the **single document** that answers "which tool do I reach for, and how do they hand off to each other?"

Written 2026-05-22, after Phase 1–4 + Phase 6a + Phase 11 (AIT) shipped and `actuate-validator` (Zack) surveyed. Reflects the integration plan locked in 2026-05-21.

## The vision in one paragraph

Five tools, four different "what are you testing?" questions, one shared substrate (the `ImageDataPacket` serializer + factories from Phase 4 + 11). Engineers, QA, and SRE all reach for different tools but they share data formats, mocks, and conventions so a finding in one shows up usefully in the others. Captured production state (brain-in-jar) feeds the validator's golden set automatically; simulated state from `ait simulate` is structurally identical so the same replay machinery drives both; validator's manifests + golden sets curate the "should still work" surface; AIT's `validate`/`replay`/`simulate` answer the diagnostic and dev-iteration questions; Hypothesis fuzzes around any of them.

## The five tools

| Tool | Question it answers | Lives in | Audience |
|---|---|---|---|
| **`ait validate`** (Phase 2) | "Does this deployment's config still hold the semantic invariants?" | `actuate-integration-tools` | engineers, SRE pre-deploy |
| **`ait simulate`** + factories/[[strategies]] (Phase 11) | "How does code behave across the input distribution?" | AIT + `actuate-pipeline-objects/testing/` | engineers, dev-iteration |
| **`ait replay`** + brain-in-jar dumps (Phase 4 + 6 + 9) | "What did the pipeline do on this specific captured frame?" | AIT (+ crash-hook in connector) | engineers, SRE post-mortem |
| **`actuate-validator`** | "Does production code still produce the expected behavior on this curated case?" | `actuate-libraries/actuate-validator` | QA, pre-merge gate |
| **`ait diff`** (Phase 1) | "What changed between two configs / sites / library versions?" | AIT | engineers, library-bump triage |

These are **complementary, not redundant.** Replay is bounded by what production captured; simulate is unbounded but synthetic; validator is curated + scored; diff is structural-only. All four feed the same downstream replay/inspect machinery.

## Data flows + handoffs

```
┌──────────────────────────────────────────────────────────────────────┐
│                   Shared substrate (Phase 4 + 11)                     │
│  ─ ImageDataPacket.to_dict / from_dict (serializer keystone)         │
│  ─ actuate_instrumentation.data_dump / data_load (+ sidecars)        │
│  ─ actuate_pipeline_objects.testing.factories (make_idp/pdp/wdp)      │
│  ─ actuate_pipeline_objects.testing.strategies (Hypothesis)           │
└──────────────────────────────────────────────────────────────────────┘
        ▲              ▲              ▲                ▲              ▲
        │              │              │                │              │
  ┌─────┴─────┐  ┌────┴─────┐  ┌─────┴──────┐  ┌─────┴───────┐  ┌──┴──┐
  │ait validate│  │ait diff │  │ait simulate│  │ ait replay  │  │valid│
  │ (Phase 2)  │  │(Phase 1)│  │(Phase 11) │  │(Phase 6 + 9)│  │ ator│
  └─────┬─────┘  └────┬────┘  └─────┬──────┘  └──────┬──────┘  └──┬──┘
        │             │              │                │             │
        ▼             ▼              ▼                ▼             ▼
    ┌────────────────────────────────────────────────────────────────┐
    │           Outputs feed into each other:                         │
    │  ─ simulate --output writes brain-in-jar dumps                  │
    │  ─ Phase 9 prod crash dumps → ait replay (next morning)         │
    │  ─ Phase 10 sink (S3) → ait dumps fetch                         │
    │  ─ Validator golden sets can adopt brain-in-jar dumps (Play E)  │
    │  ─ Validator pipeline harness adopts AIT factories (Play A)     │
    └────────────────────────────────────────────────────────────────┘
```

Concrete handoffs:

1. **Phase 11 `simulate --output` → Phase 6a `ait replay`**: simulator-generated dumps are structurally identical to production crash dumps. Replay machinery works on both with no special-casing.
2. **Phase 9 crash dump → Phase 10 S3 → next-morning `ait dumps fetch`**: production state survives the pod and lands as a replayable artifact.
3. **Validator's `MockImageDataPacket` → AIT factories (Play A)**: validator drops its inline mocks for `make_idp`/`make_pdp`; single source of truth for packet shape.
4. **Validator's `MockDaoManager` / `MockImageCache` → `actuate-daos/testing/` / `actuate-image-cache/testing/` (Plays B + C)**: lift to upstream libs so AIT Phase 8 reuses without reinventing.
5. **Brain-in-jar dumps as validator golden-set inputs (Play E)**: every interesting production crash becomes a permanent regression test.

## Workflows by question

The map most-likely-asked → which tool(s).

### "I want to verify this customer's deployment is configured correctly before promoting" (engineer / SRE)

```bash
uv run ait validate connector-35831-autopatrol-259
```

Runs the 9-invariant battery from Phase 2. Errors block promotion; warnings surface for review. Catches the 2026-05-19-class bugs (branded-vehicle pairing, dev pins, healthcheck flag types).

### "Library bump landed — did it change how any real customer's config parses?" (engineer)

```bash
uv run ait diff connector-35831-autopatrol-259 \
    --library actuate-config --from 1.10.0 --to 1.10.1
```

Mode B from Phase 1 — same settings, two library versions, structural diff. Highest-leverage diagnostic for library-induced regressions.

### "I'm adding a new pipeline step. How do I test it without real frames?" (engineer)

Three layers:

1. **Factories** for hand-built unit tests: `make_idp(motion_boxes=[...], products={...})` — replaces 50-line manual setup blocks.
2. **Scenarios** for sequence-level tests: pick from the `ait simulate --list` catalog (alert-triggering, stationary-filter, branded-vehicle-only, etc.) and drive your step against the produced IDPs.
3. **Hypothesis property tests** for boundary fuzzing: `@given(idp=idp_strategy())` and assert a property holds across ~500 random IDPs. [[shrinking|Shrinking]] finds the minimal failing case.

### "There was a crash overnight. What was the pipeline state?" (SRE)

When Phase 9 + 10 land:

```bash
uv run ait dumps overnight                                       # what crashed
uv run ait dumps fetch connector-XXX 2026-05-22T03:15-exception-RuntimeError
uv run ait replay list /tmp/fetched-dump/                        # inspect IDPs
uv run ait replay show /tmp/fetched-dump/ --idp 0                # one frame
uv run ait replay diff /tmp/fetched-dump/ /tmp/known-good/ --idp 0  # vs reference
```

Today (post-Phase 6a) the local-replay loop works; the production-capture half waits on Phases 9 + 10.

### "Verifier test for a known-good case — does production still alert?" (QA)

```bash
just test-package actuate-validator              # full golden-set suite
# or for one suite:
uv run pytest actuate-validator/ -v -k stationary
```

Manifest-driven. Each test case is a video + precomputed detections + expected behavior. `baselines.json` tracks per-suite scores; only suite-aggregate regressions fail CI.

### "Given a video where I expect a specific alert (e.g., gun) — what config produces it?" (QA — current gap)

**No tool today.** This is the QA workflow gap captured below in the Phase 12 section. The closest existing fit is `actuate-validator`, but it answers the symmetric question ("given config + video + expectation, does it pass?") not the inverse ("given video + expectation, find the config").

## QA workflow gap — Phase 12 proposal

Direct quote from QA (2026-05-22):

> "I created the verifier tests, but I'm not sure about the correct model/raw metrics/other configs for that. I need to review all this. [...] we can improve the tests if we think more isolated, from the AI side. The issue with the V8 was luck, we can improve it much more"

> "given a video -> where I know what I expect, like a gun alert example:
> - how can I generate an alert on it?
> - which model can I use? or which is best for this?
> - what confidence level would be good?"

This is a **parameter-search workflow**: fix the input (video + expected outcome) and the model architecture, vary the controllable parameters (which model, confidence threshold, raw metric keys, ignore-zone polygons, etc.) until you find a configuration that produces the expected behavior. Repeatable, auditable, and the answer feeds straight back into a validator manifest.

### Sketch

```bash
# Define what we're searching for
ait sweep --video data/gun-scene.mp4 \
          --expect "alert_label=gun_drawn" \
          --param "model_name=v9_general,v9_threat,v8_gun" \
          --param "confidence=0.3,0.5,0.7,0.9" \
          --param "raw_metric_keys=['gun'],['gun','weapon']"
```

Cartesian sweep over the listed params. Each combination runs through the same harness `actuate-validator` uses; outputs a results table:

| Model | Confidence | Metrics | Alerts fired | Expected? | Notes |
|---|---|---|---|---|---|
| v8_gun | 0.5 | `[gun]` | 0 | ❌ | Below threshold |
| v8_gun | 0.3 | `[gun]` | 3 | ✅ | First positive |
| v9_threat | 0.5 | `[gun]` | 1 | ✅ | Highest-conf hit at frame 47 |
| ... | ... | ... | ... | ... | ... |

Then optionally: `ait sweep ... --emit-validator-manifest gun-validation.json` writes the winning configuration directly as a validator manifest entry. **QA's workflow becomes**: pick a video, write the expectation, run the sweep, commit the resulting manifest.

### Where it lives

Two options:

**Option A — in actuate-validator** as a new harness type `sweep`. Pros: reuses existing config_factory, harness execution, baselines.json scoring. Cons: actuate-validator becomes both a runner and a search tool; mission creep.

**Option B — in AIT** as `ait sweep`. Pros: keeps actuate-validator focused on regression-gating; AIT is the natural home for engineer/QA-facing diagnostics. Cons: needs to import actuate-validator's harness (extra dep).

**Recommendation**: Option B. AIT already imports `actuate-pipeline-objects` and depends on more of the library graph than validator does. `ait sweep` calls into validator's `ObserverHarness` / `PipelineHarness` per parameter combination. Validator stays a gate; AIT stays an exploration toolkit. The dep direction (AIT → validator) is correct since validator is the more stable / earlier-landing library.

### Phase 12 sketch (per-component)

This is a separate KB note to write: `2026-05-22_ait-phase-12-sweep.md`. High-level shape:

- **CLI**: `ait sweep --video X --expect Y --param k=v1,v2,v3`
- **Param parsing**: comma-separated values per `--param`; supports nested JSON for list-typed params.
- **Execution**: cartesian product of params; one harness invocation per combination.
- **Output formats**: rich table (default), JSON, validator-manifest stub.
- **Performance**: parallelize over a process pool; cap concurrency for inference-API rate limits.
- **Coordination**: needs Plays A + B from the integration plan to land first so AIT can drive validator's harnesses without import gymnastics.

Estimate: ~4-6h after Plays A + B land.

## Cross-tool integration status (2026-05-22)

| Integration | Status | Where |
|---|---|---|
| Shared substrate (factories, serializer, data_dump) | ✅ shipped (Phase 4 + 11) | actuate-libraries `feat/idp-serializer-brain-in-jar-phase-4` |
| simulate → replay round-trip | ✅ shipped (Phase 6a) | actuate-integration-tools `main` |
| Library publish + AIT switches to version-pins | ⏳ blocked on lib PR merge | feature branch awaiting review |
| Validator adopts AIT factories (Play A) | ⏳ pending coordination with Zack | feat/motion-validator |
| Lift `MockDaoManager` / `MockImageCache` to upstream libs (Plays B + C) | 📝 specced; needs coordination | integration plan §2 |
| Shared Terraform bucket module (Play D) | 📝 specced | AIT Phase 10 trigger |
| Brain-in-jar dumps as validator inputs (Play E) | 📝 specced | AIT Phase 9 + 10 trigger |
| Validator gets Hypothesis fuzz mode (Play F) | 📝 specced | post-Phase-11 publish |
| `ait sweep` for QA workflow (Phase 12) | 📝 specced (this doc) | post-Plays A + B |

## Per-persona quick reference

### Engineers

| Need | Tool |
|---|---|
| "Test my new step with synthetic data" | `ait simulate run <scenario> --output ./dump/` + your step |
| "Fuzz it against random IDPs" | `@given(idp=idp_strategy())` in pytest |
| "Reuse a real production crash" | `ait dumps fetch` + `ait replay show` (Phase 10 dependent) |
| "Compare two configs / library versions" | `ait diff` |
| "Pre-promote check" | `ait validate <deployment_id>` |

### QA

| Need | Tool |
|---|---|
| "Add a regression case to the golden set" | `python -m actuate_validator walkthrough` |
| "Run the full golden set" | `just test-package actuate-validator` |
| "Find a config for an expected outcome" | `ait sweep ...` (Phase 12 — not yet) |
| "Verify a specific observer / pipeline change didn't break the baseline" | `just test-package actuate-validator -k <suite>` |

### SRE

| Need | Tool |
|---|---|
| "What crashed overnight?" | `ait dumps overnight` (Phase 10 — not yet) |
| "Diff this site's config vs another" | `ait diff <a> <b>` |
| "Replay the failure on my laptop" | `ait dumps fetch` + `ait replay diff` |
| "Sanity-check the deployment" | `ait validate <deployment_id>` |
| "Was this caused by a recent library bump?" | `ait diff <deployment_id> --library <name> --from X --to Y` |

### Library authors (Zack et al)

| Need | Tool |
|---|---|
| "Did my [[actuate-config]] change break any customer's parse?" | `ait diff <deployment_id> --library actuate-config --from X --to Y` |
| "Run the validator's golden set against my branch" | `just test-package actuate-validator` |
| "Add a regression case for the fix I'm shipping" | validator walkthrough |
| "Property-test my new types" | factories + Hypothesis [[strategies]] in `actuate-pipeline-objects/testing/` |

## What we're deliberately NOT building

To anchor the scope:

- **Not an interactive debugger.** No `pdb`-style step-through. The replay / inspect surface is one-shot — load a dump, inspect, replay one step.
- **Not a frame-by-frame visual diff.** Detections might overlay differently; tools exist ([[ds-analysis-microservice]]). AIT/validator stop at structural / metric comparison.
- **Not a model-training harness.** AI model training lives elsewhere. We test what the *production code* does with whichever model is configured.
- **Not a load-test platform.** `ait simulate --output` can produce N IDPs but isn't designed for thousands-per-second throughput tests.
- **Not a CI workflow runner.** GitHub Actions / pytest / `just` continue to own that layer; our tools are libraries those workflows call.

## Cross-references

### Tool-level entities
- [[actuate-integration-tools]] — the AIT toolkit
- [[actuate-validator]] — Zack's golden-set framework
- [[hypothesis/_summary|Hypothesis (property-based testing)]] — property-based testing reference

### Master roadmap syntheses
- [[2026-05-19_ait-extensions-spec]] — Phases 1-3 (inspect arc)
- [[2026-05-20_ait-brain-in-jar-spec]] — Phases 4-10 (replay arc)
- [[2026-05-21_ait-phase-11-simulate]] — Phase 11 (simulate arc)
- [[2026-05-21_ait-validator-dovetail]] — overlap analysis (six plays)
- [[2026-05-21_ait-validator-integration-plan]] — gating doc for further AIT dev
- *to write*: `2026-05-22_ait-phase-12-sweep.md` — Phase 12 parameter sweep

### Convention notes
- [[2026-05-21_hypothesis-in-actuate]] — factories-first / strategies-on-top
- [[project_actuate_instrumentation_intent]] — memory: [[actuate-instrumentation]] = home for cross-cutting test infra
