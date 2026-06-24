---
title: Hypothesis (property-based testing)
type: summary
topic: hypothesis
tags: [python, testing, property-based-testing, fuzzing, hypothesis, ait, actuate-pipeline-objects, actuate-validator]
created: 2026-05-21
updated: 2026-05-21
author: mark
---

# Hypothesis

[Hypothesis](https://hypothesis.readthedocs.io/en/latest/) is the Python property-based testing library we use across Actuate. Instead of writing example-based tests ("for this input, expect this output"), Hypothesis generates inputs from declarative *[[strategies]]* and shrinks any failing case to its minimal form.

Imported into the codebase 2026-05-21 as part of AIT Phase 11 (simulate arc) — `actuate-pipeline-objects/testing/strategies.py` exposes Hypothesis [[strategies]] for the pipeline packet types.

## When to reach for Hypothesis

| Situation | Reach for it? |
|---|---|
| Round-tripping a serializer across the full field space | **Yes** — exactly what [[shrinking]] solves |
| Fuzzing a parser, validator, or step over its input distribution | **Yes** |
| Asserting a property holds across all valid inputs (commutativity, idempotence, monotonicity) | **Yes** |
| Reproducing a single known input | **No** — use a regular `def test_x()` |
| Testing UI / end-to-end flows | **No** — too slow; @given inflates run time by 100× |
| Testing code that talks to live AWS / DB | **No** — generation is fast but I/O on every example will kill you |

## Quick reference

| Topic | Concept note |
|---|---|
| Strategy primitives (integers, lists, text, dicts, etc.) | [[strategies]] |
| `@given` decorator + `settings()` options | [[given-and-settings]] |
| `@st.composite` for dependent generation | [[composite-strategies]] |
| What [[shrinking]] does + how to debug | [[shrinking]] |
| HealthCheck enum + suppression patterns | [[healthchecks]] |
| [[example-database|Example database]] (failing-case replay) | [[example-database]] |
| RuleBasedStateMachine for sequence testing | [[stateful-testing]] |
| How we use Hypothesis in actuate-pipeline-objects | [[2026-05-21_hypothesis-in-actuate]] |

## One-minute usage

```python
from hypothesis import given, settings, strategies as st

@given(n=st.integers(min_value=0, max_value=1000))
@settings(max_examples=100, deadline=None)
def test_no_crash(n):
    assert process(n) >= 0
```

If `process(0)` panics, Hypothesis shrinks any failing case down to `n=0` automatically.

## Composite for nested types

```python
@st.composite
def my_strategy(draw):
    name = draw(st.text(min_size=1, max_size=20))
    count = draw(st.integers(min_value=0, max_value=draw(st.integers(max_value=100))))
    return MyObject(name=name, count=count)
```

`draw()` is callable only inside a `@st.composite` function. The decorated function becomes a *strategy factory* — call it like `@given(obj=my_strategy())`.

## Common gotchas

- **`max_examples=100` is the default.** For round-trip tests across complex shapes, bump to 500 or 1000 — the search space is bigger than you think.
- **`deadline=200ms` is the default per-example deadline.** If your test is heavy, set `deadline=None` or it will fail randomly under load.
- **Function-scoped pytest fixtures only run once across all generated examples.** Hypothesis warns via `HealthCheck.function_scoped_fixture`. See [[healthchecks]].
- **`assume()` rejects examples; `.filter()` rejects at generation time.** Heavy filtering triggers `HealthCheck.filter_too_much`. Use `@composite` with constraints instead.
- **[[strategies|Strategies]] are values, not generators.** `st.integers()` returns a strategy; it doesn't generate anything until passed to `@given`.

## Sources

The KB sources/ dir mirrors the canonical Hypothesis docs by section. See [[knowledgebase/topics/models/hypothesis/reading-list]] for the full reading list across the upstream docs.

## Cross-references

- [[2026-05-21_ait-phase-11-simulate]] — AIT simulate arc; introduced Hypothesis to the Actuate codebase
- [[actuate-validator]] — sibling testing library; may adopt Hypothesis-driven fuzzing per [[2026-05-21_ait-validator-dovetail]] Play F
- [[actuate-pipeline-objects]] — library that hosts our [[strategies]]
