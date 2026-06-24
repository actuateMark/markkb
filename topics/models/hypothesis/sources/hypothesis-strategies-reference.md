---
title: "Hypothesis strategies reference (upstream)"
type: source
topic: hypothesis
source_url: "https://hypothesis.readthedocs.io/en/latest/reference/strategies.html"
ingested: 2026-05-21
author: mark
---

# Hypothesis strategies reference (source notes)

Source-note distillation of [https://hypothesis.readthedocs.io/en/latest/reference/strategies.html](https://hypothesis.readthedocs.io/en/latest/reference/strategies.html), captured 2026-05-21. See [[strategies]] for our internal cheat sheet.

## Categorized inventory

### Core primitives

- `st.none()` — only `None`; no shrinking (single value).
- `st.nothing()` — never produces a value; always rejects on draw.
- `st.just(value)` — always the given value; no shrinking.
- `st.booleans()` — bool, shrinks toward `False`.

### Numeric

- `st.integers(min_value=None, max_value=None)` — shrinks toward zero, then toward positives.
- `st.floats(min_value=None, max_value=None, *, allow_nan=None, allow_infinity=None, allow_subnormal=None, width=64, exclude_min=False, exclude_max=False)` — prefers finite + smaller magnitude.
- `st.complex_numbers(*, min_magnitude=0, max_magnitude=None, allow_infinity=None, allow_nan=None, allow_subnormal=True, width=128)`.
- `st.decimals(min_value=None, max_value=None, *, allow_nan=None, allow_infinity=None, places=None)`.
- `st.fractions(min_value=None, max_value=None, *, max_denominator=None)`.

### Text + binary

- `st.text(alphabet=characters(codec='utf-8'), *, min_size=0, max_size=None)` — shrinks toward shorter strings with lower codepoints.
- `st.characters(*, codec=None, min_codepoint=None, max_codepoint=None, categories=..., exclude_categories=..., exclude_characters=..., include_characters=...)`.
- `st.binary(*, min_size=0, max_size=None)`.
- `st.from_regex(regex, *, fullmatch=False, alphabet=None)` — supports compiled patterns + flags.
- `st.emails(*, domains=domains())` — RFC 5322 emails.
- `st.uuids(*, version=None, allow_nil=False)`.

### Collections

- `st.lists(elements, *, min_size=0, max_size=None, unique_by=None, unique=False)`.
- `st.tuples(*args)` — fixed-length; positional draws.
- `st.sets(elements, *, min_size=0, max_size=None)` — requires hashable elements.
- `st.frozensets(elements, *, min_size=0, max_size=None)`.
- `st.dictionaries(keys, values, *, dict_class=dict, min_size=0, max_size=None)`.
- `st.fixed_dictionaries(mapping, *, optional=None)` — predetermined keys + per-key strategies.
- `st.iterables(elements, *, min_size=0, max_size=None, unique_by=None, unique=False)` — non-indexable, non-fixed-length.

### Datetime

- `st.dates(min_value=date.min, max_value=date.max)` — shrinks toward 2000-01-01.
- `st.times(min_value=time.min, max_value=time.max, *, timezones=none())`.
- `st.datetimes(min_value=datetime.min, max_value=datetime.max, *, timezones=none(), allow_imaginary=True)`.
- `st.timezones(*, no_cache=False)` — ZoneInfo objects.
- `st.timedeltas(min_value=..., max_value=...)` — shrinks toward zero.

### Combinators

- `st.one_of(*args)` — pick any; **put simpler strategies first** for shrinking.
- `st.sampled_from(elements)` — pick from collection; shrinks toward earlier elements.
- `st.builds(target, /, *args, **kwargs)` — calls `target(...)` with drawn args; infers missing strategies from type annotations.
- `@st.composite` — decorator turning a function with a `draw` parameter into a strategy factory.
- `st.data()` — `@given(data=st.data())` then `data.draw(strategy)` mid-test. Avoid where `@composite` works — incompatible with `@example`, worse failure printing.
- `st.recursive(base, extend, *, min_leaves=None, max_leaves=100)` — for trees.
- `st.deferred(definition)` — for recursive / mutually-recursive strategy definitions.

### Chaining

- `strategy.map(callable)` — transform drawn value.
- `strategy.filter(predicate)` — reject draws that don't pass.
- `strategy.flatmap(expand)` — deprecated; use `@composite` instead.

### Type-based

- `st.from_type(thing)` — looks up strategy via default mappings + typing module + `register_type_strategy()`.
- `st.register_type_strategy(custom_type, strategy)` — register a global mapping.

### Shared values

- `st.shared(base, *, key=None)` — single value per test run; same key shares across draws.

### Control

- `assume(condition)` — reject example if False; excessive rejection triggers `HealthCheck.filter_too_much`.

## Cross-references

- [[strategies]] — internal cheat sheet
- [[composite-strategies]]
- [[shrinking]]
- [[hypothesis-custom-strategies]]
