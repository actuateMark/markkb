---
title: "Hypothesis @given decorator + settings() options"
type: concept
topic: hypothesis
tags: [hypothesis, given, settings, python, testing, profiles]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/concepts/composite-strategies.md
  - topics/models/hypothesis/notes/concepts/example-database.md
  - topics/models/hypothesis/notes/concepts/healthchecks.md
  - topics/models/hypothesis/notes/concepts/shrinking.md
  - topics/models/hypothesis/notes/concepts/stateful-testing.md
  - topics/models/hypothesis/notes/concepts/strategies.md
  - topics/models/hypothesis/notes/syntheses/2026-05-21_hypothesis-in-actuate.md
  - topics/models/hypothesis/reading-list.md
  - topics/models/hypothesis/sources/hypothesis-api-reference.md
incoming_updated: 2026-06-24
---

# `@given` and `settings()`

`@given` is the primary entry point — it transforms a regular test function into a Hypothesis-driven one. `settings()` controls *how* Hypothesis runs.

## `@given`

```python
from hypothesis import given, strategies as st

@given(st.integers(), st.text())                      # positional
def test_a(n, s):
    pass

@given(n=st.integers(), s=st.text())                  # keyword (recommended)
def test_b(n, s):
    pass
```

Mixing positional and keyword in the same `@given` is **not allowed**. Pick one form per test.

### Type-inference shortcut

```python
@given(...)                                           # infer all args from annotations
def test_c(n: int, s: str):
    pass

@given(n=..., s=st.from_regex(r"[A-Z]+"))             # infer some, specify others
def test_d(n: int, s):
    pass
```

`...` (Ellipsis, also accessible as `hypothesis.infer`) tells `@given` to call `st.from_type()` on the annotation.

### Explicit examples

```python
from hypothesis import example

@example(0, "")                                       # always run first
@example(1, "a", reason="known-good baseline")
@example(-1, "x").xfail(reason="known bug #1234")
@given(n=st.integers(), s=st.text())
def test_e(n, s):
    pass
```

Explicit examples run in `Phase.explicit` and don't count toward `max_examples`. They don't shrink; failures stop the test immediately.

### Determinism

```python
from hypothesis import seed

@seed(42)                                             # forces a deterministic example stream
@given(n=st.integers())
def test_seeded(n):
    pass
```

Overrides `settings.derandomize`. Mostly useful for chasing a specific failure.

## `settings()`

Wraps a `@given`-decorated test to override Hypothesis's run behaviour.

```python
from hypothesis import settings

@settings(max_examples=500, deadline=None)
@given(idp=idp_strategy())
def test_property(idp):
    ...
```

### Common options

| Option | Default | When to set |
|---|---|---|
| `max_examples` | 100 | Bump for complex search spaces (~500–1000 for nested-object round-trip tests) |
| `deadline` | 200ms (None in CI) | Set `None` for tests doing real work per example, otherwise random failures under load |
| `suppress_health_check` | `()` | List of `HealthCheck` members to silence; see [[healthchecks]] |
| `derandomize` | `False` (`True` in CI) | True → hash-based deterministic generation across runs |
| `database` | `DirectoryBasedExampleDatabase(...)` | Replace if shared CI / distributed tests need a shared DB; see [[example-database]] |
| `verbosity` | `Verbosity.normal` | `Verbosity.verbose` prints every example; useful for debugging |
| `phases` | all phases | Skip `Phase.shrink` to debug a fast failure path; skip `Phase.reuse` to ignore the example DB |
| `stateful_step_count` | 50 | Rules per stateful example run; see [[stateful-testing]] |
| `report_multiple_bugs` | `True` | Set False to stop on first bug |
| `print_blob` | `False` (`True` in CI) | Print `@reproduce_failure(...)` block for any failure — paste it into a test to reproduce |

### Phases

```python
from hypothesis import Phase

@settings(phases=[Phase.explicit, Phase.generate])    # skip shrinking + database
```

| Phase | What it does |
|---|---|
| `Phase.explicit` | Run `@example` decorators |
| `Phase.reuse` | Replay saved failures from the [[example-database|example database]] |
| `Phase.generate` | Create new random examples |
| `Phase.target` | Mutate for targeted PBT (requires `target()` calls in the test) |
| `Phase.shrink` | Minimize the failing example |
| `Phase.explain` | Add a human-readable explanation of why it failed (requires shrink) |

### Verbosity

```python
@settings(verbosity=Verbosity.verbose)
```

- `quiet` — no output, even on success
- `normal` — falsifying example + any `note()` values on failure
- `verbose` — each generated case + shrink progress
- `debug` — internal counters / draw sequences

## Profiles

Save commonly-used settings combinations as named profiles:

```python
from hypothesis import HealthCheck, settings

settings.register_profile(
    "soak",
    max_examples=10_000,
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow],
)

settings.register_profile(
    "fast",
    max_examples=20,
)

# Load explicitly:
settings.load_profile("soak")

# Or set via env var: HYPOTHESIS_PROFILE=soak pytest
```

Hypothesis auto-loads two built-in profiles:
- `default` — applied if nothing else is loaded.
- `ci` — applied when the `CI` env var is set (so CI runs more deterministically).

## `assume()`, `event()`, `note()`, `target()`

Control-flow primitives inside a test body:

```python
from hypothesis import assume, event, note, target, given, strategies as st

@given(n=st.integers())
def test_x(n):
    assume(n != 0)                       # reject example if False; doesn't count as failure
    note(f"computed: {process(n)}")      # only printed if test FAILS
    event(f"sign: {'pos' if n > 0 else 'neg'}")  # tally events; show via pytest --hypothesis-show-statistics
    target(abs(n), label="magnitude")    # tell Hypothesis to search toward higher magnitudes
    assert process(n) == expected
```

- `assume()`: reject silently if the precondition fails. Over-use triggers `HealthCheck.filter_too_much`.
- `note()`: attach a value to the failure report. Only printed if the test fails.
- `event()`: collect a label per example for the statistics report (`pytest --hypothesis-show-statistics`).
- `target()`: bias the search toward maximizing the observed value. Most useful with `max_examples >= 1000`.

## Reproducing a failure

When a test fails with `print_blob=True` (or in CI), Hypothesis prints something like:

```
@reproduce_failure("6.152.9", b"AXicY2BgZGJgZGJgZGJgZGJgZG...")
```

Paste this decorator onto the test (above `@given`) and re-run — the exact failing case re-runs. Discard after the bug is fixed; the blob is not stable across Hypothesis versions.

## Cross-references

- [[strategies]] — what `@given` consumes
- [[composite-strategies]] — `@composite` for dependent draws
- [[healthchecks]] — what `suppress_health_check` accepts
- [[example-database]] — what `database` controls
- [[shrinking]] — what `Phase.shrink` does
- [[../sources/hypothesis-api-reference]] — upstream API reference
