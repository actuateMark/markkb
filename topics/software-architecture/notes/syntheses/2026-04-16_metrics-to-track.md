---
title: "Code Health Metrics to Track"
type: synthesis
topic: software-architecture
tags: [metrics, code-health, tech-debt, complexity, coverage, architecture]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Code Health Metrics to Track

What to measure, why it matters, and how to collect it. Organized by category from most actionable to most strategic. All metrics should be tracked as **trends over time** — a single snapshot is useless; the direction tells you whether you're winning or losing.

> **Sketch status (2026-04-22):** Scaffolded as the `software_arch_sketches.metrics` module in `/home/mork/work/software-arch-sketches/`. Emits a well-shaped `data/metrics.json` envelope (generated-at, input-repo, status=stub). Real complexity (`radon cc`) + coverage (`coverage.xml` parse) collection is the next step — `radon` is already a dep. Target input repo: `vms-connector`. See [[2026-04-17_local-sketches-plan]].

---

## 1. Code Complexity

Measures how hard code is to understand and maintain.

| Metric | What It Measures | Tool | Target |
|--------|-----------------|------|--------|
| **Cyclomatic complexity** | Number of independent paths through a function | radon, ruff (C901) | < 10 per function |
| **Cognitive complexity** | How hard a function is to *understand* (nesting, breaks in flow) | sonarqube, flake8-cognitive-complexity | < 15 per function |
| **Maintainability index** | Composite score (Halstead volume + cyclomatic + LOC) | radon | > 20 (A or B grade) |
| **Lines per function** | Raw size indicator | custom / wily | < 50 lines |
| **Lines per module** | File sprawl detection | custom | < 500 lines |

**Why:** Complexity is the strongest predictor of defect density. A function with cyclomatic complexity > 10 is statistically more likely to contain bugs.

**Actuate context:** The vms-connector chain-of-responsibility handlers and inference-api route handlers are the most likely hotspots. Track at module level to catch files that grow unbounded.

---

## 2. Test Health

Measures confidence that the code works and that changes are safe.

| Metric | What It Measures | Tool | Target |
|--------|-----------------|------|--------|
| **Line coverage** | % of lines executed by tests | pytest-cov, coverage.py | > 80% overall, > 90% for critical paths |
| **Branch coverage** | % of conditional branches tested | pytest-cov (--branch) | > 70% |
| **Mutation score** | % of injected bugs caught by tests | mutmut, cosmic-ray | > 60% (aspirational) |
| **Test execution time** | How long the full suite takes | pytest --durations | < 5 min for unit, < 15 min for integration |
| **Flaky test rate** | % of tests that pass/fail non-deterministically | pytest-randomly + CI tracking | 0% (flag and fix immediately) |
| **Test-to-code ratio** | Lines of test code vs production code | custom | > 1:1 for critical services |

**Why:** Coverage alone is a vanity metric — 90% coverage with no assertions is worthless. Mutation testing is the true measure of test quality: if you inject a bug and the tests still pass, the tests aren't actually testing anything.

**Actuate context:** vms-connector tests are currently **disabled** (broken imports). This is the single biggest gap. Libraries have coverage; inference-api has tox + coverage. Mutation testing is aspirational but worth piloting on actuate-libraries where tests are healthy.

---

## 3. Dependency Health

Measures coupling, freshness, and security of dependencies.

| Metric | What It Measures | Tool | Target |
|--------|-----------------|------|--------|
| **Dependency count** | Total direct dependencies | pip-audit, deptry | Track trend; flag unexpected growth |
| **Unused dependencies** | Declared but never imported | deptry | 0 |
| **Outdated dependencies** | How far behind latest | pip-audit, dependabot | < 2 minor versions behind |
| **Known vulnerabilities** | CVEs in dependency tree | pip-audit, safety, snyk | 0 critical/high |
| **Internal coupling** | Cross-package imports in monorepo | import-linter, custom | Must follow declared [[dependency-graph|dependency graph]] |
| **Circular dependencies** | A imports B imports A | pydeps, import-linter | 0 |

**Why:** Every dependency is an attack surface, a maintenance burden, and a coupling point. Unused deps are free to remove. Vulnerable deps are urgent. Circular deps create untestable tangles.

**Actuate context:** actuate-libraries has 41 packages — dependency governance is critical. The pre-commit hook validates actuate-* pins, but there's no automated check for circular dependencies or unused deps across the monorepo.

---

## 4. Architecture Conformance

Measures whether the code matches the intended design.

| Metric | What It Measures | Tool | Target |
|--------|-----------------|------|--------|
| **Import rule violations** | Forbidden cross-layer or cross-module imports | import-linter | 0 violations |
| **Layer leakage** | Infrastructure concerns in domain/service layers | import-linter, custom tests | 0 |
| **API surface drift** | Endpoints/schemas changed without doc updates | OpenAPI diff, custom | 0 undocumented changes |
| **Module cohesion** | How focused a module is on a single concern | LCOM4 (custom) | Qualitative; flag modules with > 3 unrelated responsibilities |
| **Afferent/efferent coupling** | How many modules depend on / are depended upon | pydeps, custom | Flag modules with both high afferent AND high efferent (instability) |

**Why:** Architecture erosion is invisible until it's catastrophic. Fitness functions (executable architecture tests) make violations fail the build, not the review.

**Actuate context:** No architecture conformance testing exists today. The vms-connector's chain-of-responsibility pattern and the inference-api's layered architecture are good candidates for import-linter rules.

---

## 5. Tech Debt Indicators

Measures accumulation of shortcuts and deferred work.

| Metric | What It Measures | Tool | Target |
|--------|-----------------|------|--------|
| **TODO/FIXME/HACK count** | Explicit debt markers in code | grep/ruff, sonarqube | Track trend; review quarterly |
| **Code churn** | Files changed frequently (hotspots) | git log analysis, wily | Investigate files with high churn + high complexity |
| **Dead code** | Unreachable functions, unused variables | vulture, ruff (F841) | 0 |
| **Duplicate code** | Copy-paste blocks | sonarqube, jscpd (polyglot) | < 3% duplication |
| **Type annotation coverage** | % of functions with type hints | mypy/pyright --stats | > 80% for public APIs |
| **Suppressed warnings** | `# noqa`, `# type: ignore` count | custom grep | Track trend; each should have a justification comment |

**Why:** Tech debt compounds. The TODO you leave today becomes the bug someone hits next quarter. Tracking these as trends lets you set thresholds and catch regressions.

**Actuate context:** No systematic dead code detection. Type annotation coverage is low (pyright barely configured). SonarQube catches some duplication but isn't on all repos.

---

## 6. Process Metrics

Measures the health of the development process itself.

| Metric | What It Measures | Tool | Target |
|--------|-----------------|------|--------|
| **PR review time** | Time from open to first review | GitHub API / gh CLI | < 24 hours |
| **CI pass rate** | % of CI runs that pass on first attempt | GitHub Actions analytics | > 90% |
| **Mean time to fix CI** | How long broken builds stay broken | GitHub Actions + custom | < 1 hour |
| **Deploy frequency** | How often code reaches production | GitHub releases / deploys | Track trend |
| **Rollback rate** | % of deploys that require rollback | manual tracking | < 5% |

**Why:** These are DORA metrics (or close to them). They measure the health of the delivery pipeline, not just the code.

---

## Aggregation: The Health Score

Individual metrics are useful for diagnosis but overwhelming for status. A **composite health score** per repo rolls them up:

```
Health Score = weighted average of:
  - Complexity grade     (25%) — radon maintainability index
  - Test coverage        (20%) — branch coverage %
  - Dependency health    (15%) — 0 vulns, 0 unused, 0 circular
  - Architecture fitness (20%) — import-linter pass rate
  - Debt indicators      (20%) — dead code, duplication, TODOs trend
```

This score powers the [[2026-04-16_code-health-dashboard|Code Health Dashboard]] and gives a single number to track over time.

---

## Collection Strategy

| Frequency | What | How |
|-----------|------|-----|
| **Every PR** | Complexity, coverage, import rules, dead code | CI checks (ruff, pytest-cov, import-linter, vulture) |
| **Nightly** | Full metrics sweep, dashboard update | Scheduled CI job or [[2026-04-16_tech-debt-agent|Tech Debt Agent]] |
| **Weekly** | Trend analysis, health score delta | Dashboard review / automated report |
| **Quarterly** | Tech debt budget review, metric threshold adjustment | Team meeting |

## Related

- [[2026-04-16_code-health-dashboard]] — where these metrics are visualized
- [[2026-04-16_tooling-landscape]] — tools that collect these metrics
- [[2026-04-16_architecture-enforcement]] — how to make violations fail the build
- [[2026-04-16_tech-debt-agent]] — automated collection and filing
