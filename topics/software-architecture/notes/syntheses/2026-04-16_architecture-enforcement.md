---
title: "Architecture Enforcement & Fitness Functions"
type: synthesis
topic: software-architecture
tags: [architecture, enforcement, fitness-functions, import-linter, ci-gates, boundaries]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Architecture Enforcement & Fitness Functions

How to encode architectural intent as executable tests so violations fail the build, not the review. Based on the "fitness function" concept from *Building Evolutionary Architectures* (Ford, Parsons, Kua) — adapted for Python/FastAPI/UV monorepo stacks.

> **Sketch status (2026-04-22):** Scaffolded as the `software_arch_sketches.enforcement` module in `/home/mork/work/software-arch-sketches/`. Emits `data/violations.json` envelope. Real fitness-function logic (AST-based layer-import checks — e.g. `camera/` must not import from `sender/` in vms-connector) is the next step. Target input repo: `vms-connector` — has clear camera/pipeline/observer/sender layering with obvious violation targets. See [[2026-04-17_local-sketches-plan]].

---

## The Problem

Architecture erodes silently. A developer imports a repository class directly from a controller. Another adds a cross-package dependency that creates a cycle. A third puts business logic in an API route handler. Each change is small and passes review. Over months, the intended layered architecture becomes a ball of mud.

**Code review doesn't scale as an enforcement mechanism.** Reviewers miss structural violations because they're focused on correctness. The solution: make the architecture machine-checkable.

---

## Fitness Functions

A **fitness function** is an automated check that evaluates how well the system conforms to an architectural goal. They come in several flavors:

| Dimension | Options | Examples |
|-----------|---------|----------|
| **Scope** | Atomic (single check) / Holistic (system-wide) | "No circular imports" vs "Overall coupling score < threshold" |
| **Trigger** | Triggered (on event) / Continuous (scheduled) | PR check vs nightly dashboard scan |
| **Metric type** | Binary (pass/fail) / Continuous (score) | Import rule violation vs maintainability index |

### Categories for Actuate

1. **Dependency direction** — layers can only import downward (controller → service → repository → model)
2. **Package boundaries** — monorepo packages declare their public API; internal modules are off-limits
3. **No circular dependencies** — at module level and package level
4. **Naming conventions** — files, classes, and functions follow consistent patterns
5. **API contract stability** — schema changes are intentional and documented
6. **Security boundaries** — RBAC checks happen before validation; error messages don't leak internals

---

## Implementation: Import Linting

The most impactful enforcement tool for Python is **import-linter** — it defines allowed/forbidden import relationships and fails CI when violated.

### Example: Layered Architecture (inference-api)

```ini
# .importlinter config in pyproject.toml or setup.cfg

[importlinter]
root_packages = app

[importlinter:contract:layers]
name = Enforce layered architecture
type = layers
layers =
    app.api          # controllers / route handlers
    app.services     # business logic
    app.repositories # data access
    app.models       # domain models / schemas
    app.core         # shared config, exceptions, auth

[importlinter:contract:no-orm-in-api]
name = API layer must not import ORM directly
type = forbidden
source_modules =
    app.api
forbidden_modules =
    sqlalchemy
    app.db
```

### Example: Monorepo Boundaries (actuate-libraries)

```ini
[importlinter]
root_packages =
    actuate_aegis_client
    actuate_auth
    actuate_camera_data
    # ... all 41 packages

[importlinter:contract:aegis-client-isolation]
name = aegis-client has no internal dependencies
type = forbidden
source_modules = actuate_aegis_client
forbidden_modules =
    actuate_auth
    actuate_connector_core
    # ... everything except declared deps

[importlinter:contract:no-circular]
name = No circular package dependencies
type = independence
modules =
    actuate_aegis_client
    actuate_auth
    actuate_camera_data
```

### Running It

```bash
# In CI
lint-imports  # exits non-zero on violation

# In pre-commit
- repo: local
  hooks:
    - id: import-linter
      name: Check import rules
      entry: lint-imports
      language: system
      pass_filenames: false
```

---

## Implementation: Architecture Tests (pytest)

For checks that go beyond import rules — use pytest with custom fixtures.

### Example: Layer Compliance via AST

```python
# tests/architecture/test_layers.py
import ast
import pathlib

API_DIR = pathlib.Path("app/api")
FORBIDDEN_IN_API = {"sqlalchemy", "app.db", "app.repositories"}

def test_api_layer_does_not_import_infrastructure():
    """API handlers must go through services, never touch DB directly."""
    violations = []
    for py_file in API_DIR.rglob("*.py"):
        tree = ast.parse(py_file.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if any(alias.name.startswith(f) for f in FORBIDDEN_IN_API):
                        violations.append(f"{py_file}:{node.lineno} imports {alias.name}")
            elif isinstance(node, ast.ImportFrom) and node.module:
                if any(node.module.startswith(f) for f in FORBIDDEN_IN_API):
                    violations.append(f"{py_file}:{node.lineno} imports {node.module}")
    assert not violations, f"API layer violations:\n" + "\n".join(violations)
```

### Example: Naming Convention Enforcement

```python
# tests/architecture/test_naming.py
import pathlib

def test_route_files_are_prefixed():
    """All route modules must start with 'routes_' prefix."""
    api_dir = pathlib.Path("app/api")
    bad = [f for f in api_dir.glob("*.py")
           if not f.name.startswith(("routes_", "__", "deps"))]
    assert not bad, f"Route files without 'routes_' prefix: {bad}"

def test_schema_files_match_route_files():
    """Every routes_X.py should have a matching schemas_X.py."""
    routes = {f.stem.replace("routes_", "") for f in pathlib.Path("app/api").glob("routes_*.py")}
    schemas = {f.stem.replace("schemas_", "") for f in pathlib.Path("app/schemas").glob("schemas_*.py")}
    missing = routes - schemas
    assert not missing, f"Routes without matching schemas: {missing}"
```

---

## Implementation: CI Gates

Architecture checks should be **blocking** in CI — not advisory.

### Gate Hierarchy (ordered by priority)

| Gate | Tool | When | Blocking? |
|------|------|------|-----------|
| **Security scan** | bandit, semgrep, pip-audit | Every PR | Yes |
| **Import rules** | import-linter | Every PR | Yes |
| **Architecture tests** | pytest tests/architecture/ | Every PR | Yes |
| **Type checking** | pyright --strict (incremental) | Every PR | Warning → blocking (phased rollout) |
| **Complexity threshold** | radon + custom check | Every PR | Warning (alert if regression) |
| **Coverage threshold** | pytest-cov --fail-under | Every PR | Yes (per-repo threshold) |
| **Dependency audit** | pip-audit, deptry | Every PR | Yes for vulnerabilities, warning for unused |
| **Dead code scan** | vulture | Nightly | Advisory (filed as issues) |
| **Full health score** | Composite metric | Nightly | Dashboard only |

### GitHub Actions Example

```yaml
# .github/workflows/architecture.yml
name: Architecture Checks
on: [pull_request]

jobs:
  architecture:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4
      - run: uv sync --frozen

      - name: Import rules
        run: uv run lint-imports

      - name: Architecture tests
        run: uv run pytest tests/architecture/ -v

      - name: Dependency audit
        run: uv run pip-audit

      - name: Dead code check
        run: uv run vulture app/ --min-confidence 80
        continue-on-error: true  # advisory for now
```

---

## Phased Rollout Plan

Don't boil the ocean. Roll out enforcement incrementally:

### Phase 1: Foundation (Week 1-2)
- Add import-linter to all 3 repos with current-state rules (document what exists, don't break anything)
- Add `tests/architecture/` directory to each repo
- Run import-linter in CI as **warning** (continue-on-error)

### Phase 2: Tighten (Week 3-4)
- Convert import-linter to **blocking** after fixing any violations
- Add basic architecture tests (layer compliance, naming conventions)
- Add pip-audit to CI for vulnerability scanning

### Phase 3: Expand (Month 2)
- Add complexity thresholds (block PRs that increase max complexity)
- Add coverage thresholds (fail-under per repo)
- Type checking as CI warning

### Phase 4: Govern (Month 3+)
- Full health score dashboard
- Nightly sweeps by [[2026-04-16_tech-debt-agent|Tech Debt Agent]]
- Architecture tests for monorepo package boundaries
- Type checking blocking in CI

---

## Handling Violations

When an architect test fails, the developer should:

1. **Read the violation message** — it should explain the rule and why it exists
2. **Fix the violation** — restructure the import, move the code, add the missing schema
3. **If the rule is wrong** — open a PR to update the rule with justification (architecture tests are code too)
4. **Never `# noqa` an architecture violation** — if the rule doesn't apply, fix the rule

---

## Related

- [[2026-04-16_metrics-to-track]] — metrics these gates enforce
- [[2026-04-16_tooling-landscape]] — tools referenced here
- [[2026-04-16_code-health-dashboard]] — where gate results are visualized
- [[engineering-process/_summary|Engineering Process]] — development lifecycle where these gates fit
- [[code-review-checklist]] — human review complements automated checks
