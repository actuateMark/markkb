---
title: "Hypothesis quickstart (upstream)"
type: source
topic: hypothesis
source_url: "https://hypothesis.readthedocs.io/en/latest/quickstart.html"
ingested: 2026-05-21
author: mark
---

# Hypothesis quickstart (source notes)

Source-note distillation of [https://hypothesis.readthedocs.io/en/latest/quickstart.html](https://hypothesis.readthedocs.io/en/latest/quickstart.html), captured 2026-05-21.

## Core thesis

Hypothesis is property-based testing for Python. Instead of writing examples ("for input 5, expect 10"), you write *properties* ("for any positive integer, output ≥ input") and Hypothesis generates inputs that try to break the property.

## `@given` patterns

Positional:

```python
from hypothesis import given, strategies as st

@given(st.integers(), st.text())
def test_one(n, s):
    assert isinstance(n, int)
    assert isinstance(s, str)
```

Keyword (recommended for clarity once the test has >1 arg):

```python
@given(n=st.integers(), s=st.text())
def test_two(n, s):
    ...
```

## Falsifying examples + shrinking

On failure the docs show:

```
E       Falsifying example: test_integers(
E           n=50,
E       )
```

That `n=50` is the *shrunk* minimum, not the original failing case. Default is 100 random examples per run (`max_examples`).

## Strategy primitives introduced

- `st.integers(min_value, max_value)` — bounded integers
- `st.text()` — Unicode strings
- `st.lists(elements)` — homogeneous lists

## Filtering at strategy vs test level

Strategy:

```python
@given(st.integers().filter(lambda n: n % 2 == 0))
def test_even(n):
    assert n % 2 == 0
```

Test:

```python
from hypothesis import assume
@given(st.integers(), st.integers())
def test_different(n1, n2):
    assume(n1 != n2)
```

## `@composite` shown in quickstart

```python
@st.composite
def ordered_pairs(draw):
    n1 = draw(st.integers())
    n2 = draw(st.integers(min_value=n1))
    return (n1, n2)

@given(ordered_pairs())
def test_pairs_are_ordered(pair):
    n1, n2 = pair
    assert n1 <= n2
```

## Cross-references

- [[../notes/concepts/strategies]]
- [[../notes/concepts/given-and-settings]]
- [[../notes/concepts/composite-strategies]]
- [[../notes/concepts/shrinking]]
