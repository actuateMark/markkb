---
title: "Hypothesis reading list"
type: reading-list
topic: hypothesis
updated: 2026-05-21
---

# Hypothesis reading list

Canonical sources for the Hypothesis library, with KB notes mirroring the most-referenced pages. When a question comes up that isn't in the concept notes, go to the upstream docs *first* — the KB is a working subset, not a replacement.

## Upstream docs (canonical)

- [Hypothesis homepage](https://hypothesis.readthedocs.io/en/latest/) — entry point + nav
- [Quickstart](https://hypothesis.readthedocs.io/en/latest/quickstart.html) — `@given`, basic strategies
- [Strategies reference](https://hypothesis.readthedocs.io/en/latest/reference/strategies.html) — every primitive
- [API reference](https://hypothesis.readthedocs.io/en/latest/reference/api.html) — `@given`, `settings`, control functions
- [Custom strategies tutorial](https://hypothesis.readthedocs.io/en/latest/tutorial/custom-strategies.html) — `@composite` + `builds`
- [Stateful testing](https://hypothesis.readthedocs.io/en/latest/stateful.html) — `RuleBasedStateMachine`
- [How to suppress health checks](https://hypothesis.readthedocs.io/en/latest/how-to/suppress-healthchecks.html)
- [How to use a custom database](https://hypothesis.readthedocs.io/en/latest/how-to/custom-database.html)
- [Replaying failures](https://hypothesis.readthedocs.io/en/latest/tutorial/replaying-failures.html)
- [Settings + profiles](https://hypothesis.readthedocs.io/en/latest/tutorial/settings.html)
- [Extras (numpy, pandas, django)](https://hypothesis.readthedocs.io/en/latest/extras.html)
- [Changelog](https://hypothesis.readthedocs.io/en/latest/changelog.html)

## KB topic notes

| Note | What it covers |
|---|---|
| [[knowledgebase/topics/models/hypothesis/_summary]] | Topic overview + quick reference |
| [[strategies]] | Primitive strategy reference |
| [[given-and-settings]] | `@given` + `settings()` options |
| [[composite-strategies]] | `@composite`, `draw()`, when to use it |
| [[shrinking]] | Shrinking mechanics + debugging |
| [[healthchecks]] | HealthCheck enum + fix-vs-suppress |
| [[stateful-testing]] | `RuleBasedStateMachine` for sequence tests |
| [[example-database]] | Failing-case replay + custom DBs |
| [[2026-05-21_hypothesis-in-actuate]] | Synthesis: how we use Hypothesis here |

## External / supplementary

- [PROPER (Erlang property-based testing)](https://propertesting.com/) — the prior art Hypothesis draws from; the "model checking" framing is useful for understanding why shrinking matters.
- [PyCon 2018: Property-Based Testing for Beginners](https://www.youtube.com/watch?v=4R5cKDD8FdU) — Zac Hatfield-Dodds (Hypothesis maintainer); accessible intro.
- [HypothesisWorks blog](https://hypothesis.works/articles/) — patterns, case studies, deeper dives.

## When to refresh this list

- New major release of Hypothesis lands (currently 6.x; 7.x would warrant re-reading)
- Hypothesis docs site reorgs (the `/reference/` vs `/tutorial/` split is recent)
- A new external write-up captures a pattern we adopt internally
