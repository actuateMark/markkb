---
title: "Hypothesis shrinking — finding the minimal failing example"
type: concept
topic: hypothesis
tags: [hypothesis, shrinking, debugging, testing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/concepts/composite-strategies.md
  - topics/models/hypothesis/notes/concepts/example-database.md
  - topics/models/hypothesis/notes/concepts/given-and-settings.md
  - topics/models/hypothesis/notes/concepts/healthchecks.md
  - topics/models/hypothesis/notes/concepts/stateful-testing.md
incoming_updated: 2026-06-24
---

# Shrinking

When a Hypothesis test fails, the framework doesn't just print the first input that caused the failure — it **shrinks** the input to the smallest equivalent that still triggers the failure. Shrinking is what makes property-based testing actually debuggable.

## What "smaller" means

[[strategies|Strategies]] define a shrinking order:

| Strategy | Shrinks toward |
|---|---|
| `st.integers()` | 0 |
| `st.integers(min_value=0)` | 0 |
| `st.integers(min_value=-100, max_value=100)` | 0 |
| `st.floats()` | 0.0 |
| `st.text()` | empty string, then characters with lower codepoints |
| `st.binary()` | empty bytes |
| `st.lists(...)` | shorter lists, then shrink each element |
| `st.tuples(...)` | shrink each position independently |
| `st.sampled_from([a, b, c])` | earlier elements (a is "smaller" than c) |
| `st.one_of(s1, s2, s3)` | the earlier strategy in the list |
| `st.booleans()` | False |
| `st.dictionaries(...)` | fewer keys, then shrink each value |

Put **simpler / canonical [[strategies]] first** when using `st.one_of()` and `st.sampled_from()`. The order is the shrinking order.

## What you see in the output

```
Falsifying example: test_foo(
    n=0,
)
```

That `n=0` is the *shrunk* value, not the value first found. Hypothesis ran maybe hundreds of examples; the first failure might have been `n=8417`, and shrinking reduced it.

If you see a complex value in the falsifying-example output, it means the bug actually requires that complexity — Hypothesis couldn't reduce further while keeping the failure.

## When shrinking helps most

- **Round-trip bugs**: "the failing IDP had 12 motion boxes, products `{a, b, c}`, and a signal" usually shrinks to "the failing IDP just has product `a` with this one window" — telling you exactly which field is broken.
- **Boundary bugs**: an integer overflow that initially triggered at `2**30 + 1` shrinks to the actual boundary (e.g. `2**16 + 1` if there's an int16 conversion).
- **Empty-collection bugs**: `lst=[1, 2, 3]` shrinks to `lst=[]` if empty-list is what crashes.

## When shrinking is slow

Shrinking runs the test repeatedly with smaller candidates. If the test itself is slow, shrinking is slower. Symptoms:

- Test takes minutes to fail after the first crash.
- `HealthCheck.too_slow` fires.

Mitigations:
- Set `deadline=None` so individual examples don't get cut off by the deadline.
- Reduce `max_examples` for the first round of debugging — find the bug first, shrink it second.
- Skip shrinking entirely while debugging via `@settings(phases=[Phase.explicit, Phase.reuse, Phase.generate])`.

## Shrinking + `@composite`

[[composite-strategies|Composite strategies]] shrink the same way primitive ones do — Hypothesis tracks which `draw()` calls produced which values and reduces each independently:

```python
@st.composite
def packet(draw):
    name = draw(st.text())
    items = draw(st.lists(st.integers()))
    return Packet(name=name, items=items)
```

If `packet(name="abc", items=[1,2,3])` fails, Hypothesis tries `packet(name="", items=[])` first, then incrementally adds back complexity until it finds the boundary. The result is the *smallest packet that still fails*.

## When shrinking gives you a confusing minimum

Sometimes the shrunk example doesn't look obviously related to the bug. Two common causes:

1. **The bug only triggers on a *combination* of fields**, and the shrunk version is the smallest combination. The unintuitive shape is the actual signal — investigate the interactions.
2. **The test's failure mode is ambiguous** — multiple input shapes trigger different bugs under one umbrella assertion. Tighten the assertion to one specific behaviour and re-run; the new shrunk example will be cleaner.

## The shrinking contract callers rely on

Hypothesis guarantees:
- Shrinking is deterministic given a starting failure (modulo the [[example-database|example database]]).
- A shrunk example is *equivalent in failure mode* to the original — same exception class, same property violated.
- Shrinking will terminate (in finite time, sometimes long).

It does **not** guarantee:
- The shrunk example is *globally* minimal — it's the smallest *along the path Hypothesis explored*.
- That two runs produce identical shrunk values (cosmic-ray variance in scheduling can cause minor differences).
- That shrinking finds the "true" bug if the test is testing the wrong thing.

## Cross-references

- [[strategies]] — strategy-by-strategy shrink behavior
- [[composite-strategies]] — how shrinking interacts with `@composite`
- [[given-and-settings]] — `Phase.shrink` and how to skip it
- [[example-database]] — how shrunk examples persist for replay
