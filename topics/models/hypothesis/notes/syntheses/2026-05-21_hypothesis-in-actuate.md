---
title: "Hypothesis in the Actuate codebase"
type: synthesis
topic: hypothesis
tags: [hypothesis, actuate-pipeline-objects, actuate-integration-tools, actuate-validator, testing, strategies, fuzzing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/concepts/composite-strategies.md
  - topics/models/hypothesis/reading-list.md
  - topics/offboarding/notes/concepts/2026-06-23_local-repo-audit.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-06-24
---

# Hypothesis in the Actuate codebase

Hypothesis arrived in our codebase 2026-05-21 as part of [[2026-05-21_ait-phase-11-simulate|AIT Phase 11]]. This note captures where it lives, how we structure [[strategies]], and the conventions to follow when adding new ones.

## Today's footprint

| Where | What |
|---|---|
| `actuate-libraries/actuate-pipeline-objects/src/actuate_pipeline_objects/testing/strategies.py` | `wdp_strategy`, `pdp_strategy`, `idp_strategy`, `alerting_idp_strategy` — [[composite-strategies|composite strategies]] for the pipeline packet types |
| `actuate-libraries/actuate-pipeline-objects/tests/test_testing_strategies.py` | Property tests using the [[strategies]]; round-trips ~230 randomized packets through the Phase 4 serializer |
| `actuate-integration-tools/src/actuate_integration_tools/simulate/cli.py` | `ait simulate fuzz --iterations N` drives `idp_strategy` through the serializer round-trip in CLI form |

`hypothesis>=6.100` is:
- A dev dep in `actuate-pipeline-objects` (the [[strategies]] module imports it lazily — production code can pull `actuate_pipeline_objects.testing.factories` without pulling Hypothesis into the import graph)
- A runtime dep in `actuate-integration-tools` (because the fuzz CLI uses it)

## Convention: factories first, strategies on top

Two layers, separately useful:

1. **Factories** (`actuate_pipeline_objects.testing.factories`) — composable plain-Python builders with sensible defaults. No Hypothesis dep. `make_idp(...)`, `make_pdp(...)`, `make_wdp(...)`, `make_alerting_window(...)`.
2. **[[strategies|Strategies]]** (`actuate_pipeline_objects.testing.strategies`) — Hypothesis `SearchStrategy` instances that draw plausible values and forward them to the factories.

[[strategies|Strategies]] should not duplicate field-by-field assignment logic — they delegate to the factory:

```python
# strategies.py
@st.composite
def wdp_strategy(draw):
    denominator = draw(st.integers(min_value=1, max_value=10))
    hits = draw(st.integers(min_value=0, max_value=denominator))
    window_hits = [False] * (denominator - hits) + [True] * hits
    return make_wdp(
        denominator=denominator,
        thresh=draw(st.integers(min_value=1, max_value=denominator)),
        label=draw(_LABEL_STRATEGY),
        in_alert=draw(st.booleans()),
        window_hits=window_hits,
        # ...
    )
```

This keeps the [[strategies]] short, the factories the single source of truth for valid-packet construction, and changes propagate through cleanly when packet fields change.

## Bounded ranges for plausibility

Our [[strategies]] bound everything to "realistic + diverse" rather than "exhaustive." Examples:

- Timestamps are drawn from a 24-hour window around a fixed base — not the full float range. Stops Hypothesis from generating timestamps in year 4000 that don't tell us anything useful.
- Counter fields are bounded `0..1_000_000` — covers any conceivable production value but stops the strategy from drawing `2**63`.
- Collections (motion_boxes, products) cap at small sizes (3–5 elements). Tighter bounds = more example density in the realistic region of input space.

When extending: pick the smallest range that covers the production behaviour you care about. `data_too_large` is a sign you've overshot.

## Catalog of strategies

| Strategy | Returns | Typical use |
|---|---|---|
| `wdp_strategy()` | `WindowDataPacket` | Fuzz any code that consumes window state |
| `pdp_strategy()` | `ProductDataPacket` (with 0–3 nested WDPs) | Fuzz product-level processing |
| `idp_strategy()` | `ImageDataPacket` (with 0–3 products, 0–5 motion_boxes) | Fuzz pipeline steps, serializers, observers |
| `alerting_idp_strategy(product, label)` | `ImageDataPacket` *mid-alert* on the named product/label | Focused fuzz for alert-handling code paths |

## Conventions for adding a new strategy

1. Build the corresponding factory first (in `factories.py`) if one doesn't exist. The factory should accept all kwargs the strategy needs to vary.
2. Add the strategy as `@st.composite` in `strategies.py`. Compose existing [[strategies]] rather than re-implementing draws.
3. Add a property test in `tests/test_testing_strategies.py` that round-trips through any relevant serializer (proves the strategy doesn't generate invalid packets).
4. If the new strategy will appear in `ait simulate fuzz`, add an entrypoint in `actuate-integration-tools/src/actuate_integration_tools/simulate/cli.py`.
5. Document the strategy in [[strategies]] (the topic-level concept note).

## Recommended `@settings` for our test suite

```python
from hypothesis import given, settings

@given(idp=idp_strategy())
@settings(max_examples=50, deadline=None)
def test_property(idp):
    ...
```

- **`max_examples=50`** for cheap property tests (round-trip); **`max_examples=500-1000`** when fuzzing code paths whose bugs hide at boundaries.
- **`deadline=None`** because our tests aren't latency-sensitive at the property layer and we want [[shrinking]] to work without per-example deadline pressure.
- Avoid suppressing health checks broadly. If `filter_too_much` fires, refactor the strategy. See [[healthchecks]].

## Hypothesis vs the alternatives we considered

| Choice | What we picked | Why |
|---|---|---|
| Bespoke random loop vs Hypothesis | Hypothesis | [[shrinking|Shrinking]] is the killer feature. Without it, a 30-field IDP failure tells you nothing about the actual bug. |
| `st.builds()` vs `@st.composite` | `@st.composite` | Our IDP fields have inter-dependencies (e.g. `window_hits` length must equal `denominator`); `builds()` can't express that. |
| Hypothesis + factories vs Hypothesis-only | both layers | Factories are useful outside Hypothesis too (refactoring existing hand-built tests). Keeping the factory layer separate from [[strategies]] gives every test the choice. |

## Cross-references with Actuate KB

- [[2026-05-21_ait-phase-11-simulate]] — Phase 11 synthesis (Hypothesis adoption rationale)
- [[2026-05-21_ait-validator-dovetail]] — Play F: validator could adopt these [[strategies]] for fleet-validate fuzzing
- [[2026-05-21_ait-validator-integration-plan]] — Hypothesis adoption fits "AIT wins on factory/strategy organization"
- [[strategies]] — primitive strategy reference
- [[composite-strategies]] — `@composite` patterns
- [[given-and-settings]] — `@given` + `settings()` knobs
- [[shrinking]] — why [[shrinking]] is worth the dep cost
- [[healthchecks]] — what to fix vs suppress
- [[stateful-testing]] — likely next-step for window-state + alert-queue testing
