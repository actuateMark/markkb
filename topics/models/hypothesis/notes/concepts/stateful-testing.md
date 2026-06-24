---
title: "Hypothesis stateful testing (RuleBasedStateMachine)"
type: concept
topic: hypothesis
tags: [hypothesis, stateful-testing, state-machine, testing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/models/hypothesis/_summary.md
  - topics/models/hypothesis/notes/concepts/given-and-settings.md
  - topics/models/hypothesis/notes/syntheses/2026-05-21_hypothesis-in-actuate.md
  - topics/models/hypothesis/reading-list.md
incoming_updated: 2026-06-24
---

# Stateful testing with `RuleBasedStateMachine`

Property-based tests (`@given`) generate independent inputs and check that a property holds. Stateful testing generates **sequences of operations** — exercise behaviour that depends on prior actions (database state, queue contents, accumulator math, etc.).

Reach for it when the bug you're trying to catch can only manifest after a specific sequence of operations.

## The shape

```python
from hypothesis import strategies as st
from hypothesis.stateful import (
    RuleBasedStateMachine, Bundle, rule, initialize, invariant, precondition,
)

class DatabaseModel(RuleBasedStateMachine):
    keys = Bundle("keys")
    values = Bundle("values")

    def __init__(self):
        super().__init__()
        self.model = {}

    @rule(target=keys, k=st.text(min_size=1))
    def add_key(self, k):
        return k                              # adds drawn k to the keys Bundle

    @rule(target=values, v=st.integers())
    def add_value(self, v):
        return v

    @rule(k=keys, v=values)
    def save(self, k, v):
        self.model[k] = v

    @rule(k=keys)
    def delete(self, k):
        self.model.pop(k, None)

    @invariant()
    def model_is_a_dict(self):
        assert isinstance(self.model, dict)

# Convert to a pytest TestCase
TestDatabase = DatabaseModel.TestCase
```

When a property fails, Hypothesis prints a **reproducible program** — the exact sequence of `add_key`, `add_value`, `save`, `delete` calls that triggered the failure. That's the killer feature.

## The pieces

### Rules

`@rule(...)` marks a method as an action the state machine can take. Each rule's keyword args are [[strategies]] or Bundle references. Hypothesis picks rules in random order until the step count is hit (`stateful_step_count`, default 50).

```python
@rule(target=folders, parent=folders, name=st.text(min_size=1))
def create_folder(self, parent, name):
    return f"{parent}/{name}"
```

Rules:
- A single function cannot define multiple rules.
- The state machine must define at least one rule.

### Bundles

`Bundle("name")` is a named collection of values that flows between rules:

- `target=my_bundle` on a `@rule` adds the rule's return value to the bundle.
- `param=my_bundle` on another rule draws a value from the bundle.
- `param=consumes(my_bundle)` draws and **removes** the value (one-shot).

Bundles let Hypothesis chain operations into coherent sequences instead of generating disjoint random inputs.

### `@initialize`

Runs once before any normal rule. Useful for setting up bundles or initial state:

```python
@initialize(target=root_folder)
def init_root(self):
    return "/"
```

If multiple `@initialize` methods exist, all run but **in any order, and that order can vary between runs**. Don't rely on cross-initialize ordering.

### `@invariant`

Runs after every step. Asserts a property that should hold *throughout* the run — not just at the end:

```python
@invariant()
def model_count_matches_real(self):
    assert len(self.model) == self.real_db.count()
```

Invariants fire frequently — keep them cheap.

### `@precondition`

Gates a rule on the state machine's current state. More efficient than `assume()` inside the rule:

```python
@precondition(lambda self: len(self.model) > 0)
@rule()
def pick_existing(self):
    key = random.choice(list(self.model))
    assert key in self.model
```

Hypothesis skips inapplicable rules during generation, so preconditions are essentially free (vs `assume()` which discards already-generated examples).

## Configuration

```python
from hypothesis import settings

TestDatabase.settings = settings(
    max_examples=50,
    stateful_step_count=100,
)
```

- `max_examples`: number of *programs* (each a sequence of rule calls) Hypothesis tries.
- `stateful_step_count`: max rule invocations per program.

A test running 50 programs × 100 steps = 5000 individual rule invocations. Adjust based on test time budget.

## When stateful is the right tool

| Symptom | Use stateful? |
|---|---|
| "After N consecutive saves, the index gets corrupted" | Yes |
| "Race between two queue operations leaks an item" | Yes (or move to threaded property testing) |
| "Window state diverges after specific frame sequences" | Yes — this is exactly the brain-in-jar / sliding-window class of bug |
| "This function on this input crashes" | No — use `@given` |
| "Round-trip serialization is broken" | No — use `@given` with a strategy |

## When stateful isn't worth it

- Sequence length matters more than randomization → just write a deterministic test.
- The state is small (one or two fields) → a `@given` test with a parameterized initial state often suffices.
- The slow part is per-step setup → consider whether the per-step overhead masks the bug.

## Stateful for the Actuate pipeline

Likely future use cases:
- **Sliding-window accumulators**: prove that across any sequence of frame deliveries, the window state stays consistent and alerts fire/reset at the right thresholds.
- **Alert deferred-fire queue**: prove that no SQS message gets lost no matter what order send/ack/retry events arrive.
- **Camera state machine**: prove the camera transitions cleanly between alert / cooldown / re-arm states across any input sequence.

None of these are wired yet — flagging as the natural next step beyond Phase 11's `@given`-style fuzz.

## Cross-references

- [[given-and-settings]] — the `settings.stateful_step_count` parameter
- [[strategies]] — Bundle accepts the same primitive [[strategies]] in its args
- [[shrinking]] — stateful failures shrink the *sequence* of rules to the minimum
- [[../sources/hypothesis-stateful]] — upstream tutorial
