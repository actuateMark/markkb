---
title: "Hypothesis HealthCheck enum + suppression patterns"
type: concept
topic: hypothesis
tags: [hypothesis, healthcheck, debugging, performance, testing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-platform/notes/concepts/job-executor-architecture.md
  - topics/camera-health-monitoring/notes/concepts/2026-05-14_chm-multi-frame-quality-sampling-followup.md
  - topics/camera-health-monitoring/notes/concepts/chm-diagnostics-architecture.md
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
  - topics/hypothesis/_summary.md
  - topics/hypothesis/notes/concepts/given-and-settings.md
  - topics/hypothesis/notes/syntheses/2026-05-21_hypothesis-in-actuate.md
incoming_updated: 2026-06-02
---

# Hypothesis health checks

Hypothesis runs a set of self-diagnostic checks while testing. When one fires, it surfaces as `FailedHealthCheck` (separate from your assertion failures). They exist to catch test setups that *seem* to work but produce poor coverage or unreliable signal.

## The enum

```python
from hypothesis import HealthCheck
```

### Performance checks

| Member | What fires it | Why it matters |
|---|---|---|
| `HealthCheck.too_slow` | Generation + execution of each example averages too slow | Slow tests → fewer examples in the time budget → worse coverage |
| `HealthCheck.data_too_large` | Many examples exceed the internal size budget | Strategy is producing oversized values; coverage suffers |
| `HealthCheck.large_base_example` | Even the *smallest* example the strategy can produce is large | Bad [[shrinking]] behaviour; tests will fail with confusing minimums |
| `HealthCheck.filter_too_much` | `assume()` or `.filter()` rejects >50%-ish of examples | Effective example count is much smaller than `max_examples` |

### Correctness checks

| Member | What fires it | Why it matters |
|---|---|---|
| `HealthCheck.function_scoped_fixture` | A pytest function-scoped fixture is used inside a Hypothesis test | Fixture runs once total, not once per example — most callers want session/module/class scope |
| `HealthCheck.differing_executors` | The same test gets run by different executors in one session | Indicates pytest is confused about fixture scope or plugin interaction |
| `HealthCheck.nested_given` | `@given` decorator nested inside `@given` | Quadratic example count; usually a refactor mistake |

### Deprecated

`HealthCheck.return_value` and `HealthCheck.not_a_test_method` are deprecated; ignore.

## Suppression

```python
from hypothesis import HealthCheck, settings

@settings(suppress_health_check=[HealthCheck.too_slow])
@given(idp=idp_strategy())
def test_property(idp):
    expensive_check(idp)
```

Multiple suppressions:

```python
@settings(suppress_health_check=[
    HealthCheck.too_slow,
    HealthCheck.function_scoped_fixture,
])
```

All suppression (rarely correct):

```python
@settings(suppress_health_check=list(HealthCheck))
```

Suppress in a profile (preferred for fleet-wide settings):

```python
settings.register_profile(
    "ci",
    suppress_health_check=[HealthCheck.too_slow],
)
settings.load_profile("ci")
```

## When to suppress vs fix

| Health check | First try | If still firing |
|---|---|---|
| `too_slow` | Set `deadline=None`; reduce strategy complexity | Suppress |
| `filter_too_much` | Move the constraint into the strategy via `@composite` so it's never violated | Suppress only if the test deliberately needs the filter (rare) |
| `data_too_large` | Tighten `max_size` on collection [[strategies]], narrow numeric ranges | Suppress with caution — coverage IS hurt |
| `large_base_example` | Tighten `min_size`/`min_value` defaults; make [[strategies]] that admit small examples | Suppress only if there really is no smaller valid input |
| `function_scoped_fixture` | Promote the fixture to module/session scope | Suppress only if the fixture genuinely must reset per-example |
| `differing_executors` | Investigate pytest plugin interactions | Suppress as a last resort; ping for help |
| `nested_given` | Refactor; use a single `@given` with a composite strategy | Don't suppress — this is a real bug |

## Why "fix first, suppress second"

Health checks fire because the test produces less signal than the caller assumes. Suppressing without addressing the underlying issue means the test still runs but with degraded confidence — exactly the opposite of what property-based testing buys you.

Example from real code: a test that filtered out 80% of generated IDPs ran 100 examples but only had ~20 effective ones. Suppressing `filter_too_much` made the warning go away; the test still couldn't catch the bug it was supposed to.

## Cross-references

- [[given-and-settings]] — `settings(suppress_health_check=[...])`
- [[strategies]] — bounded ranges to avoid `data_too_large`
- [[composite-strategies]] — `@composite` to avoid `filter_too_much`
- [[../sources/hypothesis-healthchecks]] — upstream docs (partial)
