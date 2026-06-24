---
title: "AIT Phase 11 — `ait simulate` (synthetic IDPs + Hypothesis fuzzing)"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, simulator, hypothesis, fuzzing, property-testing, roadmap]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/entities/actuate-validator.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-22_ait-phase-12-sweep.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/models/hypothesis/_summary.md
incoming_updated: 2026-06-24
---

# AIT Phase 11 — `ait simulate`

A synthetic IDP generator that sits in front of any pipeline segment, sender, or camera and drives parameterized scenarios through it. Complements the replay-of-real-captured-data arc (Phases 5–10) — replay is best for post-mortems, simulate is best for pre-merge / dev-iteration / "I want to test a case I haven't captured yet."

## Why this is Phase 11

Phases 5–10 give us the ability to capture real production state and replay it. That handles "reproduce a specific failure deterministically" but does nothing for **finding failures that haven't been captured yet**. A simulator closes that gap, and turns out to also kill another paper cut at the same time: the giant blocks of manual field assignment in pipeline tests (~50 lines per realistic IDP construction in the Phase 4E smoke; same shape replicated across many existing tests).

Confirmed 2026-05-21 with Mark: land now (after Phase 4, in parallel with the rest of 5–10). Makes everything downstream more testable and saves the dev-iteration tax on every subsequent phase.

## Three-layer design

### Layer 1 — Primitive factories (in `actuate-pipeline-objects/testing/`)

Composable builders with sensible defaults. Tests override only what matters:

```python
from actuate_pipeline_objects.testing import make_idp, make_pdp, make_wdp

idp = make_idp(
    motion_boxes=[(10, 20, 100, 200)],
    products={"intruder": make_pdp(in_alert=True, confirmed_labels=["person"])},
    pipeline_signal="resume_motion",
)
```

**Why pipeline-objects** (not just AIT): the boilerplate-replacement value applies to existing connector + library tests too, not just simulator scenarios. Keeping factories with the types they construct is the standard pattern. AIT keeps the *scenarios* and *CLI* but reuses these primitives. Small footprint addition.

### Layer 2 — Hypothesis strategies (also in `actuate-pipeline-objects/testing/`)

Shrinking-friendly [[strategies]] for each packet type. Built on top of factories — [[strategies]] just draw from `factory(**hypothesis-drawn-values)`:

```python
from actuate_pipeline_objects.testing.strategies import idp_strategy

@given(idp=idp_strategy())
def test_step_doesnt_crash_on_random_idp(idp):
    step.process(idp)  # if this raises, Hypothesis shrinks to a minimal failing case
```

**Hypothesis over bespoke fuzzing**: [[shrinking]] is the killer feature. When a test fails on a 30-field IDP, Hypothesis automatically reduces it to the minimum set of fields that still trigger the failure. That's the difference between "step X crashes on this specific input, I don't know why" and "step X crashes when `motion_boxes` is empty AND `pipeline_signal` is `motion_off`, here's the minimal repro." Worth the extra dep.

Hypothesis is a single dev dep; the integration cost is modest because [[strategies]] layer cleanly on factories.

### Layer 3 — Scenarios + CLI (in `actuate-integration-tools/simulate/`)

Pre-baked sequences that exercise known interesting behaviors. Each scenario returns an iterable of IDPs and (where relevant) a set of *expected outcomes* the test can assert against.

| Scenario | Generates | Stresses |
|---|---|---|
| `alert_triggering(product, denominator, hits_needed)` | N frames with hits arranged to trip the threshold | Window logic, alert emission |
| `stationary_filter(box, duration_frames)` | Same box across N frames | Stationary filter activation |
| `branded_vehicle_only(brands)` | Frames with only branded keys | Tier mapping (catches the 2026-05-19 bug class) |
| `motion_signal_dance()` | `motion_off` → N idle frames → `resume_motion` | Signal handling in steps |
| `ignore_zone_overlap(zone, overlap_pct)` | Box overlapping configured zone | Ignore-zone filter |
| `window_overrun(denominator, frames)` | More frames than window can hold | Window buffer rollover |
| `tier_escalation()` | Frames going person → vehicle → intruder → crowd | Tier transitions |
| `confidence_threshold(scores)` | Detections at varying confidence | Low-confidence filter |
| `iou_filter(overlap_pct)` | Two boxes with configurable overlap | IoU filter activation |
| `clip_lifecycle()` | Start clip → N frames → end clip | Clip event sequencing |

CLI:

```bash
# Drive a scenario through a single step
ait simulate alert-triggering --product intruder --step sliding-window --frames 10

# Fuzz a step with Hypothesis-drawn IDPs (shrinking on failure)
ait simulate fuzz --step pre-inference --iterations 1000

# Export a scenario as a brain-in-jar dump (Phase 5's DumpReplayPuller can consume it)
ait simulate motion-signal-dance --frames 100 --output /tmp/sim-dump.zip

# List available scenarios
ait simulate --list
```

The `--output` flag bridges Phase 11 with Phase 5 — a simulator-generated dump is structurally identical to a brain-in-jar dump from production, so `DumpReplayPuller` (Phase 5) can drive it through the full pipeline without knowing it's synthetic.

## How this complements vs differs from Phases 5–10

| Replay (Phases 5–10) | Simulate (Phase 11) |
|---|---|
| Reproduce *this specific* crash | Find crashes I haven't hit yet |
| Validate fix on the captured input | Validate fix across the input space |
| Bound to what production captured | Unbound; can generate impossible / edge inputs |
| Best for post-mortems | Best for pre-merge / dev iteration |
| Real frames in IDPs | Synthetic or omitted frames |

They share the dump format (Phase 4) and the playback infrastructure (Phase 5 + 6). The only new code is generators + scenarios + the `simulate` subcommand.

## TODOs (Phase 11)

### 11A — Factories in `actuate-pipeline-objects/testing/`

- [ ] Create `actuate-pipeline-objects/src/actuate_pipeline_objects/testing/__init__.py` exporting `make_idp`, `make_pdp`, `make_wdp`, `make_detection_dict`.
- [ ] Each factory has all-defaults so `make_idp()` produces a valid empty IDP; every field overrideable via kwarg.
- [ ] Nested defaults: `make_idp(products={"intruder": make_pdp(...)})` chains cleanly.
- [ ] Convenience helpers: `make_alerting_window(label, hits=3, thresh=2)` returns a WDP that's mid-alert.
- [ ] Unit tests verifying defaults are sane + every override works.
- [ ] Refactor `test_brain_in_jar_serialization.py` (Phase 4) + `test_data_dump_link.py` to use the factories — proves the dogfooding works.

### 11B — Hypothesis strategies (also `actuate-pipeline-objects/testing/strategies.py`)

- [ ] Add `hypothesis` as an optional / dev dep in `actuate-pipeline-objects/pyproject.toml`.
- [ ] `wdp_strategy()`, `pdp_strategy()`, `idp_strategy()` returning Hypothesis `SearchStrategy` instances.
- [ ] Bounded numeric ranges so generated IDPs are plausible (timestamps within a sane window, counts non-negative and capped, etc.).
- [ ] Discriminated [[strategies]] for `pipeline_signal_strategy()`, `detection_strategy()`.
- [ ] Test: a property test that asserts `to_dict() → from_dict()` is value-preserving across 100 randomized IDPs — proves both the [[strategies]] AND the Phase 4 serializer in one shot.

### 11C — Scenario templates in AIT

- [ ] Create `actuate-integration-tools/src/actuate_integration_tools/simulate/` package.
- [ ] `scenarios.py` with at least 6 of the table scenarios (start with: alert_triggering, stationary_filter, branded_vehicle_only, motion_signal_dance, window_overrun, tier_escalation).
- [ ] Each scenario returns a generator of `(idp, expected_outcome | None)` tuples.
- [ ] Discoverable via a `SCENARIOS` registry dict (same pattern as the validator registry from Phase 2).

### 11D — `ait simulate` CLI

- [ ] Subcommands:
  - `ait simulate <scenario> --step <name> --frames N`
  - `ait simulate <scenario> --output <path>` (write as brain-in-jar dump)
  - `ait simulate --list`
  - `ait simulate fuzz --step <name> --iterations N` (Hypothesis loop)
- [ ] Renders results via `rich`: per-frame step output, expected-vs-actual assertion table, count of expected outcomes met / missed.
- [ ] On fuzz failure, prints the shrunk minimal failing IDP + suggests "save this as a regression test."

### 11E — Tests

- [ ] Test each scenario produces the right shape of IDPs.
- [ ] Test the Hypothesis property `to_dict → from_dict round-trip` across 100 random IDPs.
- [ ] Test `ait simulate fuzz` finds a deliberately-broken step (use a step that raises on `motion_boxes=[]` as the canary).
- [ ] Test `--output` produces a dump readable by `data_load` (cross-phase consistency).

### 11F — Documentation

- [ ] `actuate-pipeline-objects/testing/README.md` documenting factory API.
- [ ] `actuate-integration-tools/README.md` "Simulate" section.
- [ ] Cookbook entry: "I want to add a new pipeline step — how do I test it without real data?" → scenario + fuzz + replay.

## Estimate

- 11A — ~1.5h (factories + tests + refactor existing tests)
- 11B — ~1.5h ([[strategies]] + property test)
- 11C — ~2h (six scenarios + registry)
- 11D — ~1.5h (CLI + rendering)
- 11E — ~1h (tests across surfaces)
- 11F — ~30min (docs)

Total: ~8h. Spread across two sessions realistically.

## Risk

- **Hypothesis [[strategies]] are tricky for complex packet types.** [[watch-entity|Watch]] for: too-large search space → slow tests, contradictory constraints → no examples found, deep recursion → stack issues. Mitigation: keep ranges narrow, validate strategy output explicitly.
- **Scenario maintenance**: as the pipeline evolves, scenarios need to track behavior. Mitigation: a `scenarios/README.md` table mapping each scenario to the steps it stresses, so when a step changes the owner knows which scenarios to revisit.
- **Generated IDPs aren't *actually* realistic.** A scenario might be valid syntactically but never occur in production. Counter-argument: that's fine — the point is to *expand* test coverage past what production has seen.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent (Phase 11 added 2026-05-21)
- [[2026-05-20_ait-phase-4-idp-serializer]] — keystone; factories build on the same fields
- [[2026-05-20_ait-phase-5-dump-replay-puller]] — `--output` flag bridges to this
- [[2026-05-20_ait-phase-6-pipeline-replay]] — scenarios drive through the same `MockStepRunner` machinery
- [[actuate-validator]] — golden-set library that should adopt these factories ([[2026-05-21_ait-validator-dovetail]] Play A)
