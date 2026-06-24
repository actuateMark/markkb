---
title: "Hypothesis composite strategies (@composite)"
type: concept
topic: hypothesis
tags: [hypothesis, composite, strategies, python, testing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/concepts/given-and-settings.md
  - topics/models/hypothesis/notes/concepts/healthchecks.md
  - topics/models/hypothesis/notes/concepts/shrinking.md
  - topics/models/hypothesis/notes/concepts/strategies.md
  - topics/models/hypothesis/notes/syntheses/2026-05-21_hypothesis-in-actuate.md
  - topics/models/hypothesis/reading-list.md
  - topics/models/hypothesis/sources/hypothesis-quickstart.md
  - topics/models/hypothesis/sources/hypothesis-strategies-reference.md
incoming_updated: 2026-06-24
---

# Composite strategies (`@st.composite`)

When values depend on each other or you need to assemble a complex object from many drawn pieces, the `@st.composite` decorator turns a function into a strategy factory.

```python
from hypothesis import strategies as st

@st.composite
def ordered_pair(draw):
    a = draw(st.integers())
    b = draw(st.integers(min_value=a))   # b depends on a
    return (a, b)

@given(pair=ordered_pair())
def test_ordered(pair):
    a, b = pair
    assert a <= b
```

Mental model: **`@composite` turns its decorated function into a function that returns a strategy when called**. Always call it (`my_strategy()`) before passing to `@given`.

## `draw()` mechanics

- `draw(strategy)` is callable only inside a `@composite` function. Its first parameter (`draw`) is provided automatically.
- Each `draw()` call advances Hypothesis's example generator and is shrinkable.
- The order matters: later `draw()` calls can use earlier values to choose bounds, so dependent generation is natural.

## Parameters beyond `draw`

```python
@st.composite
def sized_list(draw, *, min_size=1, max_size=10):
    n = draw(st.integers(min_value=min_size, max_value=max_size))
    return draw(st.lists(st.integers(), min_size=n, max_size=n))

@given(lst=sized_list(min_size=5, max_size=20))
def test_has_at_least_5(lst):
    assert len(lst) >= 5
```

Pass kwargs when calling the strategy factory. Keyword-only args (`*,`) are recommended — positional gets confusing once [[strategies]] are passed through multiple layers.

## `@composite` vs `st.builds()`

| Need | Use |
|---|---|
| Constructor args are independent [[strategies]] | `st.builds(MyClass, x=st.integers(), y=st.text())` |
| One arg's range depends on another arg's drawn value | `@composite` |
| Object needs custom post-construction setup | `@composite` |
| The constructor itself takes a strategy / lazy callable | `@composite` (builds doesn't know what to do) |

`st.builds()` is the right call when the constructor's args are independent. `@composite` wins as soon as you need *dependent* draws or post-processing.

## `@composite` vs `data()`

`st.data()` is another mid-test draw mechanism:

```python
@given(data=st.data())
def test(data):
    n = data.draw(st.integers(min_value=0))
    lst = data.draw(st.lists(st.integers(), max_size=n))
    assert len(lst) <= n
```

Trade-offs: `data()` is incompatible with `@example`, and Hypothesis can't print a clean repr of the drawn values when a failure happens. Prefer `@composite` where possible.

## `assume()` inside `@composite`

```python
from hypothesis import assume

@st.composite
def nonzero_sum_list(draw):
    lst = draw(st.lists(st.floats(0, 1), min_size=1))
    assume(sum(lst) > 0)
    return [f / sum(lst) for f in lst]
```

`assume(condition)` rejects the example if condition is false. Over-rejection triggers `HealthCheck.filter_too_much` — restructure the strategy to avoid the constraint instead.

## When `.map()` beats `@composite`

For trivial post-processing, `.map()` is more readable:

```python
# @composite — verbose
@st.composite
def sorted_int_pair(draw):
    a = draw(st.integers())
    b = draw(st.integers())
    return sorted([a, b])

# .map() — equivalent, cleaner
sorted_int_pair = st.tuples(st.integers(), st.integers()).map(sorted)
```

Reserve `@composite` for *dependent* generation or *control flow*. Pure transformations: use `.map()`.

## Composing composites

`@composite` [[strategies]] are first-class — pass them to other [[strategies]], embed them in containers:

```python
@st.composite
def user(draw):
    name = draw(st.text(min_size=1))
    age = draw(st.integers(min_value=0, max_value=120))
    return User(name=name, age=age)

@given(roster=st.lists(user(), min_size=1, max_size=10))
def test_roster(roster):
    assert all(0 <= u.age <= 120 for u in roster)
```

This is the most common pattern in our codebase — see `actuate-pipeline-objects/testing/strategies.py` where `idp_strategy` composes `pdp_strategy` composes `wdp_strategy`.

## Cross-references

- [[strategies]] — primitive [[strategies]] that `draw()` consumes
- [[given-and-settings]] — the `@given` decorator that consumes composite [[strategies]]
- [[shrinking]] — composite [[strategies]] still shrink; Hypothesis tracks which `draw()` call produced which value
- [[2026-05-21_hypothesis-in-actuate]] — how we layer composites in Actuate code
- [[../sources/hypothesis-custom-strategies]] — upstream tutorial
