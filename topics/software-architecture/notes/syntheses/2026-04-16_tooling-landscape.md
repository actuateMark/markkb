---
title: "Code Health Tooling Landscape & Reading List"
type: synthesis
topic: software-architecture
tags: [tooling, static-analysis, linting, architecture, testing, security, dashboard, reading-list, vms-connector]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/personal-notes/notes/concepts/2026-05-11_next-session-handoff.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/software-architecture/_summary.md
  - topics/software-architecture/notes/syntheses/2026-04-16_architecture-enforcement.md
  - topics/software-architecture/notes/syntheses/2026-04-16_code-health-dashboard.md
  - topics/software-architecture/notes/syntheses/2026-04-16_metrics-to-track.md
  - topics/software-architecture/notes/syntheses/2026-04-16_tech-debt-agent.md
  - topics/software-architecture/notes/syntheses/2026-04-17_local-sketches-plan.md
  - topics/software-architecture/reading-list.md
incoming_updated: 2026-06-25
---

# Code Health Tooling Landscape & Reading List

A catalog of tools for code quality, architecture enforcement, tech debt tracking, and automated review — organized by category with adoption recommendations for the Actuate Python/FastAPI/UV monorepo stack.

---

## Current Actuate Setup (April 2026)

| Tool | vms-connector | actuate-libraries | inference-api |
|------|:---:|:---:|:---:|
| **Ruff** (lint + format) | v0.9.3 | v0.9.3 | v0.9.3+ |
| **pytest** | disabled (broken imports) | active, pytest-xdist | active, tox runner |
| **pytest-cov** | configured, tests disabled | active, 90s timeout | active |
| **SonarQube** | configured | configured | not configured |
| **pyright** | none | minimal config | none |
| **pre-commit** | ruff + uv + custom | ruff + uv + pin check | ruff + uv |
| **Security scanning** | none | none | none |
| **Architecture enforcement** | none | none | none |
| **Dependency scanning** | none | pin validation only | none |

---

## Recommended Tool Stack

### Tier 1: Adopt Now (Low Effort, High Impact)

| Tool | Category | What It Does | URL |
|------|----------|-------------|-----|
| **import-linter** | Architecture | Enforces import boundaries between layers/packages via contracts (layers, independence, forbidden). The single most impactful tool for preventing architecture drift. | https://github.com/seddonym/import-linter |
| **deptry** | Dependencies | Detects unused, missing, and transitive deps. Written in Rust, very fast. Catches bloat and missing declarations. | https://github.com/fpgmaas/deptry |
| **pip-audit** | Security | Scans dependencies for known CVEs. Uses the OSV database. Exit code for CI gating. | https://github.com/pypa/pip-audit |
| **vulture** | Dead Code | Finds unreachable functions, unused variables, dead imports. Supports whitelists for intentional unused exports. | https://github.com/jendrikseipp/vulture |
| **radon** | Complexity | Computes cyclomatic complexity, maintainability index, Halstead metrics per function/module. JSON output for tracking. | https://github.com/rubik/radon |
| **xenon** | Complexity CI Gate | Wraps radon with thresholds — fails CI if complexity exceeds a grade (e.g., max absolute B). | https://github.com/rubik/xenon |

### Tier 2: Adopt Soon (Medium Effort, High Impact)

| Tool | Category | What It Does | URL |
|------|----------|-------------|-----|
| **pyright** (or basedpyright) | Type Checking | Static type checker, faster than mypy, native Pydantic support. basedpyright adds ~30 extra checks and better error messages. | https://github.com/microsoft/pyright / https://github.com/DetachHead/basedpyright |
| **wily** | Complexity Tracking | Tracks complexity metrics over git history. `wily diff` in CI prevents complexity creep on PRs. Produces HTML reports and graphs. | https://github.com/tonybaloney/wily |
| **Semgrep** | Custom Patterns | Write code-level rules that look like code. "Never call X from Y", "Always use Z pattern in this layer." Large community registry. SARIF output. | https://github.com/semgrep/semgrep |
| **pytestarch** | Architecture Tests | ArchUnit-style tests for Python. Write architecture rules as pytest tests. Good for rules that go beyond import boundaries. | https://github.com/zyskarch/pytestarch |
| **mutmut** | Mutation Testing | Injects bugs into source, re-runs tests, measures how many get caught. True test quality metric. Run weekly on critical modules. | https://github.com/boxed/mutmut |

### Tier 3: Evaluate (Higher Effort, Strategic)

| Tool | Category | What It Does | URL |
|------|----------|-------------|-----|
| **CodeRabbit** | AI Code Review | AI-powered PR review bot. Line-level comments, security review, style consistency. Best-in-class for automated review. | https://coderabbit.ai |
| **Sourcery** | AI Refactoring | Python-specific AI review. Suggests refactorings, finds dead code, simplifies conditionals. | https://sourcery.ai |
| **Qodo (formerly CodiumAI)** | AI Test Generation | Generates meaningful tests from code analysis. Qodo Merge does PR review. | https://www.qodo.ai |
| **Codecov** | Coverage Tracking | SaaS coverage tracking with "flags" for monorepo sub-project tracking. PR decoration. | https://codecov.io |
| **Qodana** | Code Quality Platform | JetBrains' platform — runs PyCharm-level inspections in CI. Strong for teams using JetBrains IDEs. | https://www.jetbrains.com/qodana |

### Already Have / Keep

| Tool | Status | Notes |
|------|--------|-------|
| **Ruff** | Keep | Fast, comprehensive, already configured. Consider expanding rule selection (currently minimal — just NPY201 and T201/T203). |
| **SonarQube** | Keep + Expand | Already on vms-connector and actuate-libraries. Add to inference-api. Use "New Code Period" for incremental improvement. |
| **pytest + pytest-cov** | Keep + Fix | Fix vms-connector tests (currently disabled). Add branch coverage. Add `--fail-under` gates. |
| **pre-commit** | Keep + Expand | Add import-linter, deptry, vulture hooks. |

---

## Tools NOT Recommended

| Tool | Why Skip |
|------|----------|
| **Pylint** (full) | Ruff covers most rules faster. Only use Pylint selectively for design-smell rules (R0801 duplicate-code, too-many-arguments) if needed. |
| **mypy** | Pyright is faster, has better inference, and native Pydantic support. Unless you need mypy plugins for specific frameworks. |
| **CodeClimate** | SonarQube covers the same space and is already partially deployed. |
| **Codacy** | Same — redundant with SonarQube. |
| **ArchGuard** | Focused on Java/.NET. Python support is limited. |
| **Pants/Bazel** | Powerful boundary enforcement but massive tooling commitment for 40 packages. Not worth it unless you hit 100+. |

---

## Visualization & Documentation Tools

| Tool | What It Does | URL |
|------|-------------|-----|
| **pydeps** | Generates module dependency graphs as SVG/PNG. Good for documentation. | https://github.com/thebjorn/pydeps |
| **pipdeptree** | Shows package dependency tree. Detects circular deps. | https://github.com/tox-dev/pipdeptree |
| **grimp** | Programmatic import graph analysis (used under the hood by import-linter). For custom scripts. | https://github.com/seddonym/grimp |

---

## Reading List

Sources for deeper evaluation. Queue these for `/kb-ingest` or manual reading.

### Books
- **Building Evolutionary Architectures** — Ford, Parsons, Kua (2nd edition, 2023). The canonical reference for fitness functions and architecture governance.
- **Software Architecture: The Hard Parts** — Ford, Richards, Sadalage, Dehghani. Covers coupling, contracts, and decomposition patterns.
- **Fundamentals of Software Architecture** — Richards, Ford. Architectural characteristics, fitness functions, architecture patterns.

### Articles & Talks
- import-linter docs & blog posts: https://import-linter.readthedocs.io/
- "Architecture fitness functions" — ThoughtWorks Tech Radar: https://www.thoughtworks.com/radar/techniques/architectural-fitness-function
- Semgrep rule writing guide: https://semgrep.dev/docs/writing-rules/overview
- SonarQube "Clean as You Code" methodology: https://docs.sonarsource.com/sonarqube/latest/
- Wily documentation (complexity tracking over time): https://wily.readthedocs.io/
- deptry documentation: https://deptry.com/
- "Fitness Functions for Architecture" (conference talk, Ford): search YouTube for "Neal Ford fitness functions"

### Tools to Evaluate Hands-On
- [ ] **import-linter** — install and write initial contracts for inference-api layer boundaries
- [ ] **deptry** — run against all 3 repos, assess findings
- [ ] **pip-audit** — run against all 3 repos, assess CVE exposure
- [ ] **vulture** — run against vms-connector, build initial whitelist
- [ ] **wily** — build history cache for vms-connector, generate first complexity report
- [ ] **basedpyright** — evaluate vs stock pyright on actuate-libraries
- [ ] **CodeRabbit** — trial on a PR to assess quality of automated review
- [ ] **Semgrep** — write 3 custom rules for Actuate-specific patterns (e.g., RBAC check before validation)
- [ ] **mutmut** — pilot on actuate-libraries (healthy test suite)

---

## Integration Map

How tools connect to the broader ecosystem:

```
Pre-commit              CI (per PR)              Nightly Sweep           Dashboard
─────────              ──────────              ─────────────           ─────────
ruff (lint+fmt)   →    ruff check              vulture (full)    →    SonarQube
import-linter     →    import-linter           radon (full)            ↕
deptry            →    deptry                  wily build        →    Grafana (custom)
                       pytest + coverage  →    mutmut (weekly)         ↕
                       pip-audit               dependency age    →    Health Score
                       xenon (complexity)      convention drift        ↕
                       pyright                 (LLM agent)       →    GitHub Issues
                       architecture tests
                       Semgrep
```

---

## Related

- [[2026-04-16_metrics-to-track]] — metrics these tools produce
- [[2026-04-16_architecture-enforcement]] — how to wire tools into CI gates
- [[2026-04-16_code-health-dashboard]] — consolidating tool output
- [[2026-04-16_tech-debt-agent]] — automated sweeps using these tools
