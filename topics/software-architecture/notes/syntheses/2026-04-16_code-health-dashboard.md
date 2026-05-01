---
title: "Code Health Dashboard — Design"
type: synthesis
topic: software-architecture
tags: [dashboard, metrics, code-health, sonarqube, grafana, visualization, extensible]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - _index.md
  - topics/engineering-process/notes/entities/agent-issue-auditor.md
  - topics/fleet-architecture/notes/concepts/observability-and-tracing.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/operational-health/notes/syntheses/2026-04-23_dashboard-sketch.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/software-architecture/_summary.md
  - topics/software-architecture/notes/concepts/2026-04-23_sketch-findings-metrics.md
  - topics/software-architecture/notes/syntheses/2026-04-16_architecture-enforcement.md
incoming_updated: 2026-05-01
---

# Code Health Dashboard — Design

A single-pane-of-glass for code health across all Actuate repositories. Consolidates static analysis, test coverage, architecture conformance, dependency health, and tech debt trends into one extensible view.

> **Sketch status (2026-04-22):** Scaffolded as the `software_arch_sketches.dashboard` module in `/home/mork/work/software-arch-sketches/` (repo root). Flask app with Chart.js-from-CDN shell; reads `/api/data` JSON aggregated from the other 4 sketches. `make serve` on `localhost:8000`. **Stub only** — no real data wired yet. See [[2026-04-17_local-sketches-plan]] "Shared substrate decisions (RESOLVED 2026-04-22)" for the substrate choices.

---

## Design Goals

1. **One URL, all repos** — vms-connector, actuate-libraries (41 packages), inference-api, admin-api at a glance
2. **Trends, not snapshots** — every metric has a time axis; the direction matters more than the absolute value
3. **Drill-down** — from repo health score → category → individual findings
4. **Actionable** — every red indicator links to a fix path (GitHub issue, PR, doc)
5. **Extensible** — new metrics and repos can be added without redesigning the dashboard
6. **Low maintenance** — data flows automatically from CI; no manual data entry

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Data Sources                       │
│                                                      │
│  CI Pipelines     Nightly Sweeps     SonarQube API  │
│  (per-PR metrics) (full scans)       (quality gates) │
│  ruff, pytest,    vulture, radon,    code smells,    │
│  import-linter,   wily, deptry,      duplication,    │
│  coverage, etc.   pip-audit          coverage, debt  │
└──────────┬────────────┬───────────────┬──────────────┘
           │            │               │
           ▼            ▼               ▼
┌─────────────────────────────────────────────────────┐
│              Metrics Store                           │
│                                                      │
│  Option A: SonarQube (already deployed, has API)     │
│  Option B: PostgreSQL + custom schema                │
│  Option C: JSON artifacts in GitHub (simple start)   │
│  Option D: InfluxDB/Prometheus (for Grafana)         │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│              Visualization Layer                     │
│                                                      │
│  Option A: SonarQube dashboards (built-in)           │
│  Option B: Grafana (custom, extensible)              │
│  Option C: GitHub Pages static site (lightweight)    │
│  Option D: Obsidian canvas + bases (local-first)     │
└─────────────────────────────────────────────────────┘
```

---

## Recommended Approach: Layered Strategy

Rather than building everything custom, leverage what's already deployed and layer on top.

### Layer 1: SonarQube (Already Deployed)

SonarQube is already running for vms-connector and actuate-libraries. It provides:
- Code smells, bugs, vulnerabilities with severity
- Coverage tracking
- Duplication detection
- Cognitive complexity
- Quality Gates (pass/fail per PR)
- "New Code Period" — only enforce quality on new/changed code (the "ratchet" pattern)
- Built-in trending dashboards

**Action items:**
- Add inference-api to SonarQube (currently missing)
- Configure Quality Gates per repo (coverage threshold, 0 critical issues, 0 new bugs)
- Enable the "New Code Period" focus to avoid drowning in legacy findings

**SonarQube API** (`/api/measures/component`, `/api/measures/search_history`) exposes all metrics as JSON — this feeds the next layers.

### Layer 2: CI Metric Export

For metrics SonarQube doesn't track (architecture conformance, dependency health, dead code), export from CI as JSON artifacts.

```yaml
# .github/workflows/metrics.yml (runs on merge to develop)
name: Export Health Metrics
on:
  push:
    branches: [develop, rearchitecture]

jobs:
  export-metrics:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4
      - run: uv sync --dev

      - name: Collect metrics
        run: |
          mkdir -p .health/reports
          
          # Architecture conformance
          uv run lint-imports --json > .health/reports/import-linter.json 2>&1 || true
          
          # Dead code
          uv run vulture app/ vulture_whitelist.py --min-confidence 80 \
            > .health/reports/vulture.txt 2>&1 || true
          
          # Complexity
          uv run radon cc app/ -a --json > .health/reports/complexity.json
          uv run radon mi app/ --json > .health/reports/maintainability.json
          
          # Dependency health
          uv run deptry app/ --json-output .health/reports/deptry.json 2>&1 || true
          uv run pip-audit --format json > .health/reports/audit.json 2>&1 || true
          
          # TODO/FIXME count
          grep -rn "TODO\|FIXME\|HACK\|XXX" app/ --include="*.py" | wc -l \
            > .health/reports/todo-count.txt
          
          # Aggregate into health score
          python tools/compute_health_score.py \
            --complexity .health/reports/complexity.json \
            --coverage .health/reports/coverage.xml \
            --vulture .health/reports/vulture.txt \
            --deptry .health/reports/deptry.json \
            --imports .health/reports/import-linter.json \
            --output .health/reports/health-score.json

      - name: Upload metrics artifact
        uses: actions/upload-artifact@v4
        with:
          name: health-metrics-${{ github.sha }}
          path: .health/reports/
          retention-days: 90
```

### Layer 3: Grafana Dashboard (Extensible View)

For a unified cross-repo view with custom panels, Grafana is the most extensible option. It can pull from:
- SonarQube API (via JSON API datasource or Infinity plugin)
- GitHub Actions artifacts (via a small bridge service or stored in a DB)
- Custom metrics pushed to InfluxDB/Prometheus

**Dashboard panels:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Code Health Dashboard                         │
├────────────────┬────────────────┬────────────────┬──────────────┤
│ vms-connector  │ actuate-libs   │ inference-api  │ admin-api    │
│ Score: 68/100  │ Score: 74/100  │ Score: 81/100  │ Score: 77/100│
│ ↓ from 72      │ ↑ from 71      │ → (stable)     │ → (stable)   │
│ [WARN]         │ [OK]           │ [OK]           │ [OK]          │
├────────────────┴────────────────┴────────────────┴──────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │ Health Score Trend (90 days)                             │     │
│  │ ───── vms-connector    ───── actuate-libs                │     │
│  │ ───── inference-api    ───── admin-api                   │     │
│  │                                                          │     │
│  │ 100 ┤                                                    │     │
│  │  80 ┤──────────────────────────────────                  │     │
│  │  60 ┤      ╲                                             │     │
│  │  40 ┤                                                    │     │
│  │     └─────────────────────────────────────────────       │     │
│  │     Jan   Feb   Mar   Apr                                │     │
│  └─────────────────────────────────────────────────────────┘     │
│                                                                  │
├──────────────────────────┬───────────────────────────────────────┤
│ Complexity Hotspots      │ Architecture Conformance              │
│                          │                                       │
│ frame_processor.py  CC17 │ import-linter: 3 repos passing ✓     │
│ alert_dispatcher.py CC14 │ Layer violations: 0                   │
│ rtsp_handler.py     CC12 │ Circular deps: 0                     │
│ ...                      │ Forbidden imports: 0                  │
├──────────────────────────┼───────────────────────────────────────┤
│ Dependency Health        │ Test Health                           │
│                          │                                       │
│ Known CVEs: 0 ✓          │ vms-connector: DISABLED ⚠             │
│ Unused deps: 3 ⚠        │ actuate-libs: 84% coverage            │
│ Outdated (>90d): 5       │ inference-api: 78% coverage           │
│ Circular: 0 ✓            │ Flaky tests: 0 ✓                     │
├──────────────────────────┼───────────────────────────────────────┤
│ Tech Debt Indicators     │ Recent Activity                      │
│                          │                                       │
│ Dead code items: 14 ↑    │ Last sweep: 2026-04-14               │
│ TODOs: 87 →              │ Issues filed: 2                      │
│ Duplication: 2.1%        │ Issues resolved: 4                   │
│ Type coverage: 42% ⚠    │ Next sweep: 2026-04-21               │
└──────────────────────────┴───────────────────────────────────────┘
```

### Layer 4: Health Score Computation

A Python script (`tools/compute_health_score.py`) computes a composite score per repo:

```python
"""Compute a composite code health score from individual metrics."""

import json
import sys

WEIGHTS = {
    "complexity":    0.25,  # radon maintainability index (A=100, B=80, C=60)
    "coverage":      0.20,  # branch coverage %
    "dependencies":  0.15,  # 100 - (vulns * 20 + unused * 5 + circular * 30)
    "architecture":  0.20,  # 100 if import-linter passes, 0 per violation
    "debt":          0.20,  # 100 - (dead_code_pct * 2 + duplication_pct * 3 + todo_density)
}

def compute(complexity_json, coverage_xml, vulture_txt, deptry_json, imports_json):
    scores = {}
    
    # Complexity: average maintainability index normalized to 0-100
    with open(complexity_json) as f:
        mi_data = json.load(f)
    # ... parse and normalize
    scores["complexity"] = normalized_mi
    
    # Coverage: branch coverage %
    # ... parse coverage XML
    scores["coverage"] = branch_coverage_pct
    
    # Dependencies: start at 100, subtract for issues
    with open(deptry_json) as f:
        deptry = json.load(f)
    dep_score = 100
    dep_score -= len([v for v in deptry if v["type"] == "CVE"]) * 20
    dep_score -= len([v for v in deptry if v["type"] == "unused"]) * 5
    scores["dependencies"] = max(0, dep_score)
    
    # Architecture: binary pass/fail (100 or 0)
    # ... parse import-linter output
    scores["architecture"] = 100 if no_violations else max(0, 100 - violation_count * 10)
    
    # Debt: composite of dead code, duplication, TODOs
    # ... compute from vulture + SonarQube API
    scores["debt"] = debt_score
    
    # Weighted total
    total = sum(scores[k] * WEIGHTS[k] for k in WEIGHTS)
    
    return {
        "total": round(total, 1),
        "breakdown": scores,
        "timestamp": datetime.utcnow().isoformat(),
        "grade": "A" if total >= 90 else "B" if total >= 75 else "C" if total >= 60 else "D"
    }
```

---

## Simpler Starting Point: GitHub + Obsidian

If standing up Grafana is too much infrastructure initially, a lightweight alternative:

### Option A: GitHub Wiki/Pages Dashboard

Generate a static Markdown report in CI and push to GitHub Pages or the repo wiki:

```bash
# In CI after metric collection
python tools/generate_health_report.py > docs/health-report.md
# Push to GitHub Pages
```

### Option B: Obsidian Dashboard (Local-First)

Use an Obsidian `.base` file to create a live dashboard from KB notes:

```yaml
# topics/software-architecture/health-dashboard.base
views:
  - type: table
    name: "Code Health by Repo"
    filters:
      and:
        - file.folder.contains("topics/software-architecture")
        - type = "entity"
        - tags.includes("health-score")
    order:
      - title
      - health_score
      - coverage
      - complexity_grade
      - last_sweep
      - updated
```

Create entity notes per repo that get updated by the [[2026-04-16_tech-debt-agent|Tech Debt Agent]] after each sweep.

---

## Phased Rollout

### Phase 1: SonarQube Standardization (Week 1)
- Add inference-api to SonarQube
- Configure Quality Gates across all repos
- Enable "New Code Period" focus
- Bookmark SonarQube as the primary dashboard

### Phase 2: CI Metric Export (Week 2-3)
- Add the metrics export workflow to all repos
- Write `compute_health_score.py` 
- Store results as CI artifacts
- Create a simple Markdown [[health-report|health report]] generated per merge

### Phase 3: Unified Dashboard (Month 2)
- Choose visualization layer (Grafana vs GitHub Pages vs Obsidian)
- Wire up SonarQube API + CI artifacts as data sources
- Build the panels described above
- Add alerting for health score regressions

### Phase 4: Full Observability (Month 3+)
- Correlate code health with deployment success rate (DORA metrics)
- Add wily trend graphs for complexity over time
- Integrate [[2026-04-16_tech-debt-agent|Tech Debt Agent]] output as a data feed
- Add per-team/per-package breakdowns for actuate-libraries

---

## Data Retention

| Data | Retention | Rationale |
|------|-----------|-----------|
| CI metric artifacts | 90 days | Enough for quarterly trends |
| SonarQube history | Indefinite | Built-in, free |
| Health score history | Indefinite | Small JSON, append-only |
| Sweep reports | 180 days | Reference for trend analysis |

---

## Extensibility Design

The dashboard is built on a **metric registry** pattern. Each metric is:

```json
{
  "id": "cyclomatic_complexity_max",
  "name": "Max Cyclomatic Complexity",
  "category": "complexity",
  "source": "radon",
  "type": "continuous",
  "unit": "CC score",
  "threshold": {"warning": 10, "critical": 15},
  "higher_is_worse": true,
  "repos": ["vms-connector", "actuate-libraries", "inference-api"]
}
```

Adding a new metric means:
1. Add a collection step to the CI workflow
2. Register it in the metric registry
3. The dashboard auto-discovers and renders it

This prevents the dashboard from becoming a bespoke one-off that breaks when you add a repo or metric.

---

## Related

- [[2026-04-16_metrics-to-track]] — what metrics feed the dashboard
- [[2026-04-16_tooling-landscape]] — tools that produce the data
- [[2026-04-16_architecture-enforcement]] — CI gates shown in the conformance panel
- [[2026-04-16_tech-debt-agent]] — automated sweep that feeds the dashboard
