---
title: "Hypothesis strategies — primitive reference"
type: concept
topic: hypothesis
tags: [hypothesis, strategies, python, testing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/data-science/notes/concepts/motion-detection-challenge.md
  - topics/engineering-process/notes/concepts/adr-writing-guide.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/concepts/composite-strategies.md
incoming_updated: 2026-06-24
---

# Hypothesis strategies

A *strategy* is a recipe for generating values. Every Hypothesis test is anchored on one or more strategies passed to `@given`. Strategies are first-class objects — you can pass them around, store them in registries, and combine them.

```python
from hypothesis import given, strategies as st

@given(st.integers())
def test_passes(n):
    assert isinstance(n, int)
```

## Primitive strategies

### Numeric

```python
st.integers(min_value=None, max_value=None)
st.floats(min_value=None, max_value=None, *, allow_nan=None, allow_infinity=None,
          allow_subnormal=None, width=64, exclude_min=False, exclude_max=False)
st.complex_numbers(*, min_magnitude=0, max_magnitude=None, allow_infinity=None,
                   allow_nan=None, width=128)
st.decimals(min_value=None, max_value=None, *, allow_nan=None, allow_infinity=None,
            places=None)
st.fractions(min_value=None, max_value=None, *, max_denominator=None)
```

Numerics shrink toward zero and toward simpler/finite values.

### Booleans + None

```python
st.booleans()       # shrinks toward False
st.none()           # only None — no shrinking
st.nothing()        # never produces a value (reject all draws)
st.just(value)      # always the given value, no shrinking
```

### Text + binary

```python
st.text(alphabet=..., *, min_size=0, max_size=None)
st.characters(*, codec=None, min_codepoint=None, max_codepoint=None,
              categories=None, exclude_categories=None,
              exclude_characters=None, include_characters=None)
st.binary(*, min_size=0, max_size=None)
st.from_regex(regex, *, fullmatch=False, alphabet=None)
st.emails(*, domains=...)
st.uuids(*, version=None, allow_nil=False)
```

Text shrinks toward shorter strings with lower codepoint values.

### Collections

```python
st.lists(elements, *, min_size=0, max_size=None,
         unique_by=None, unique=False)
st.tuples(*strategies)                       # fixed-length, positional
st.sets(elements, *, min_size=0, max_size=None)
st.frozensets(elements, *, min_size=0, max_size=None)
st.dictionaries(keys, values, *, dict_class=dict, min_size=0, max_size=None)
st.fixed_dictionaries(mapping, *, optional=None)  # specific keys with per-key strategies
st.iterables(elements, *, min_size=0, max_size=None,
             unique_by=None, unique=False)
```

`unique=True` requires hashable elements. `unique_by=callable` accepts a function to derive a uniqueness key.

### Datetime

```python
st.dates(min_value=date.min, max_value=date.max)
st.times(min_value=time.min, max_value=time.max, *, timezones=st.none())
st.datetimes(min_value=datetime.min, max_value=datetime.max,
             *, timezones=st.none(), allow_imaginary=True)
st.timedeltas(min_value=timedelta.min, max_value=timedelta.max)
st.timezones(*, no_cache=False)
```

Dates shrink toward 2000-01-01.

## Combinators

```python
st.one_of(strategy_a, strategy_b, strategy_c)
        # picks from any of the given strategies; put simpler ones first for shrinking

st.sampled_from(elements)
        # picks from an explicit collection; shrinks toward earlier elements

st.builds(target, *positional_strategies, **keyword_strategies)
        # calls target(*positional, **keyword) with drawn args;
        # if target has type annotations, missing strategies are inferred

st.recursive(base, extend, *, max_leaves=100, min_leaves=None)
        # builds nested structures via extend(base | recursive_result)

st.deferred(definition)
        # for recursive or mutually-recursive strategy definitions
```

## Chaining transformations

```python
st.integers().map(str)                                  # generate, then transform
st.integers().filter(lambda n: n % 2 == 0)              # generate, reject odd
st.lists(st.integers()).map(sorted)                     # post-process to sorted list
```

**Filtering rule of thumb**: anything more selective than 1-in-10 will trigger `HealthCheck.filter_too_much`. Use `@composite` with constraints instead.

## Type inference

```python
st.from_type(int)                                       # equivalent to st.integers()
st.from_type(list[int])                                 # st.lists(st.integers())
st.from_type(MyDataclass)                               # builds via st.builds + annotations
```

`hypothesis.infer` (alias for `...`) lets `@given` infer strategies from the test function's type hints:

```python
@given(...)
def test_one(n: int, s: str):
    pass
```

Register a strategy for a custom type globally:

```python
st.register_type_strategy(MyType, my_strategy())
```

## When to use which

| Need | Strategy |
|---|---|
| Single value from a fixed list | `st.sampled_from([...])` |
| Pick between strategies | `st.one_of(s1, s2, s3)` |
| Build an object from constructor args | `st.builds(MyClass, *strategies)` |
| Build an object with dependent fields | `@st.composite` (see [[composite-strategies]]) |
| Recursive trees | `st.recursive(leaf_strategy, extend_fn)` |
| Custom invariants | `.filter(predicate)` (sparingly) or `@composite` with `assume()` |

## Shared values

```python
st.shared(base_strategy, key="my-key")
```

All draws with the same `key` within one test run produce the same value. Useful for tests where two operations need to agree on a value.

## Cross-references

- [[given-and-settings]] — the `@given` decorator
- [[composite-strategies]] — building complex / dependent strategies
- [[shrinking]] — how [[shrinking]] works (the why behind shrink-toward-zero / shrink-toward-empty)
- [[../sources/hypothesis-strategies-reference]] — fuller reference from upstream docs
