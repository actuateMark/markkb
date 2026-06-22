---
title: "Hypothesis API reference (upstream)"
type: source
topic: hypothesis
source_url: "https://hypothesis.readthedocs.io/en/latest/reference/api.html"
ingested: 2026-05-21
author: mark
---

# Hypothesis API reference (source notes)

Source-note distillation of [https://hypothesis.readthedocs.io/en/latest/reference/api.html](https://hypothesis.readthedocs.io/en/latest/reference/api.html), captured 2026-05-21. See [[../notes/concepts/given-and-settings]] for our internal coverage.

## `@given(*args, **kwargs)`

Transforms a function into a Hypothesis test. Constraints:

- Positional or keyword args, not mixed.
- When fewer positional args than function params, unfilled args remain on the left.
- Supports `**kwargs` / `*args` only with the keyword form.
- Cannot be used on functions with default values.

Type inference via `hypothesis.infer` (alias for `...`):

```python
@given(...)
def test(a: int, b: str):
    pass
```

`builds()` infers required annotated parameters automatically.

## `@example(*args, **kwargs)`

Explicit cases run in `Phase.explicit`, before generated ones. They don't count toward `max_examples`, don't shrink, and fail immediately.

- `@example(x=1).xfail(reason="bug #N")` — expected-failure variant; can specify `raises=ExceptionType`.
- `@example(x=1).via("regression-test")` — machine-readable origin label.

## Control functions

| Function | Effect |
|---|---|
| `assume(condition)` | Reject example as invalid (not a failure). |
| `note(value)` | Record value; printed only on the minimal failing example. |
| `event(value, payload='')` | Tally event for stats (`--hypothesis-show-statistics`). |
| `target(observation, *, label='')` | Bias search toward maximizing the observation (int/float). Effective above `max_examples=1000`. |

## `@seed(seed)`

Deterministic generation. Accepts any hashable. Overrides `settings.derandomize`.

## `@reproduce_failure(version, blob)`

Re-runs a serialized failing case. Raises `DidNotReproduce` if the blob doesn't fail under the current code. Temporary; not stable across Hypothesis versions.

## `settings` class parameters

| Parameter | Default | Purpose |
|---|---|---|
| `max_examples` | 100 | Test count before success |
| `derandomize` | False (True in CI) | Hash-based deterministic generation |
| `database` | `DirectoryBasedExampleDatabase` | Stores/retrieves prior failures |
| `verbosity` | `Verbosity.normal` | Output detail |
| `phases` | all | Which phases to run |
| `stateful_step_count` | 50 | Max rule iterations per stateful example |
| `report_multiple_bugs` | True | Report all vs stop on first |
| `suppress_health_check` | `()` | Disable specific HealthCheck warnings |
| `deadline` | 200ms (None in CI) | Max per-example duration |
| `print_blob` | False (True in CI) | Print `@reproduce_failure` code |
| `backend` | `"hypothesis"` | Alternative generation backend |

### Profiles

```python
settings.register_profile(name, parent=None, **kwargs)
settings.load_profile(name)
settings.get_profile(name)
settings.get_current_profile_name()
```

Built-in: `default`, `ci` (auto-detected via `CI` env var).

## `Phase` enum

- `Phase.explicit` — run `@example` decorators
- `Phase.reuse` — replay saved failures from the example DB
- `Phase.generate` — create new random examples
- `Phase.target` — mutate for targeted PBT (requires `target()` in test)
- `Phase.shrink` — minimize the failing example
- `Phase.explain` — explain the failure (requires shrink)

## `Verbosity` enum

- `Verbosity.quiet` — no output
- `Verbosity.normal` — final falsifying example + notes (default)
- `Verbosity.verbose` — each case, notes per case, shrink attempts
- `Verbosity.debug` — internal counters

## `HealthCheck` enum

Performance:
- `data_too_large` — too many oversized examples
- `filter_too_much` — `assume()` / `.filter()` rejecting too many
- `too_slow` — slow generation/execution
- `large_base_example` — even the simplest input is large

Correctness:
- `function_scoped_fixture` — pytest function-scoped fixture (runs once, not per example)
- `differing_executors` — same test, different executors
- `nested_given` — `@given` inside `@given` (quadratic behaviour)

Deprecated: `return_value`, `not_a_test_method`.

Suppress all: `suppress_health_check=list(HealthCheck)`.

## Cross-references

- [[../notes/concepts/given-and-settings]]
- [[../notes/concepts/healthchecks]]
- [[../notes/concepts/example-database]]
- [[../notes/concepts/shrinking]]
