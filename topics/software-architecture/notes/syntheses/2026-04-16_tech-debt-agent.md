---
title: "Automated Tech Debt Agent — Design Sketch"
type: synthesis
topic: software-architecture
tags: [automation, tech-debt, agent, claude-code, scheduled, dead-code, drift]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Automated Tech Debt Agent — Design Sketch

A headless AI agent that periodically patrols Actuate codebases for tech debt, style drift, architecture violations, and stale artifacts. It files findings as GitHub issues — never auto-commits or auto-merges.

> **Sketch status (2026-04-22):** Scaffolded as the `software_arch_sketches.debt` module in `/home/mork/work/software-arch-sketches/`. Emits `data/debt-report.md` (human-readable) + `data/debt-metrics.json` (structured). Real patrol heuristics (TODO/FIXME/HACK/XXX grep + count, large-function detection via radon, git-log-based stale-file detection) are the next step. **The headless-Claude variant from this synthesis's design is v2**; v1 is heuristic-only. See [[2026-04-17_local-sketches-plan]].

---

## Philosophy

**Deterministic tools for deterministic checks. LLM agents for pattern recognition. Humans gate all changes.**

The agent combines conventional static analysis tools (vulture, radon, deptry, import-linter) with LLM-powered pattern recognition (Claude Code) to catch both machine-detectable and judgment-requiring issues. All findings flow through a human review gate.

---

## Architecture

```
┌────────────────────────────────────────────┐
│              Scheduled Trigger             │
│   (cron via Claude Code /schedule or GHA)  │
└──────────────────┬─────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────┐
│           Deterministic Sweep              │
│  vulture · radon · deptry · import-linter  │
│  pip-audit · coverage diff · TODO count    │
└──────────────────┬─────────────────────────┘
                   │ raw findings
                   ▼
┌────────────────────────────────────────────┐
│            LLM Analysis Layer              │
│  Claude Code (headless) reviews findings:  │
│  - Filters false positives                 │
│  - Classifies severity                     │
│  - Groups related findings                 │
│  - Detects convention drift                │
│  - Checks for patterns tools can't catch   │
└──────────────────┬─────────────────────────┘
                   │ curated report
                   ▼
┌────────────────────────────────────────────┐
│             Output Actions                 │
│  - GitHub issue (weekly digest)            │
│  - Dashboard metric update                 │
│  - KB note update (if architecture drift)  │
│  - Slack notification (critical findings)  │
└────────────────────────────────────────────┘
```

---

## Sweep Categories

### 1. Dead Code Detection

**Tool:** vulture (--min-confidence 80)
**What:** Functions, classes, variables, and imports that are never referenced.
**False positive handling:** Maintain a `vulture_whitelist.py` per repo for intentional unused exports (e.g., FastAPI dependency injection, Celery tasks, __all__ exports). The LLM layer reviews new findings against common false positive patterns before filing.

```bash
vulture app/ vulture_whitelist.py --min-confidence 80
```

### 2. Complexity Regression

**Tool:** radon cc + radon mi
**What:** Functions whose cyclomatic complexity exceeds threshold (>10) or maintainability index drops below B grade.
**Tracking:** Compare against last sweep's baseline. Only file issues for *new* regressions, not pre-existing debt (avoid noise).

```bash
radon cc app/ -a -nc --json > complexity_current.json
# diff against complexity_baseline.json
```

### 3. Dependency Hygiene

**Tool:** deptry + pip-audit
**What:**
- Packages declared but never imported (unnecessary bloat)
- Packages imported but not declared (missing from deps)
- Known CVEs in dependency tree
- Circular dependencies in monorepo packages

```bash
deptry app/
pip-audit --fix --dry-run
```

### 4. Architecture Drift

**Tool:** import-linter + custom fitness tests
**What:** Import rule violations, layer leakage, forbidden cross-package coupling.
**LLM enhancement:** The agent reads the import-linter output and also scans for *emerging* patterns that suggest a new rule is needed (e.g., "3 services now import directly from infrastructure.config — should this be a shared concern?").

### 5. Convention Drift (LLM-Only)

**No deterministic tool — this is where the LLM shines.**
**What the agent checks:**
- Naming conventions: Are new files following the `routes_*.py`, `schemas_*.py` patterns?
- Error handling patterns: Are new endpoints using the standard error response format?
- Logging patterns: Are new modules using structured logging consistently?
- Test patterns: Do new tests follow the existing fixture/factory patterns?
- RBAC patterns: Are new endpoints checking permissions before validation?

**Prompt template:**
```
Review the files changed in the last 7 days (git log --since="7 days ago" --name-only).
For each changed file, check:
1. Does it follow the naming conventions in CLAUDE.md?
2. Does it use the same patterns as sibling files in its directory?
3. Are there any style inconsistencies with the surrounding code?
4. Are there security patterns that should be present but aren't?

Report only findings with HIGH confidence. Do not report subjective style preferences.
```

### 6. Stale Artifacts

**What:**
- TODO/FIXME/HACK comments older than 90 days (cross-reference with git blame)
- Commented-out code blocks
- Test files that don't test anything (empty test functions, only `pass`)
- Configuration for removed features (env vars, feature flags)
- Unused migration files

### 7. Documentation Staleness

**What:**
- Docstrings that contradict function signatures (LLM comparison)
- README sections that reference removed files/features
- API docs that don't match current OpenAPI spec
- KB notes with `updated:` > 30 days that reference changed code

---

## Scheduling & Cadence

| Sweep | Frequency | Duration | Resource |
|-------|-----------|----------|----------|
| Dead code + complexity | Weekly (Monday 6am) | ~5 min per repo | CI runner or Claude Code scheduled agent |
| Dependency hygiene | Weekly (Monday 6am) | ~2 min per repo | CI runner |
| Architecture drift | Every PR (blocking) + weekly full sweep | ~1 min per repo | CI runner |
| Convention drift | Weekly (Monday 6am) | ~10 min per repo | Claude Code scheduled agent |
| Stale artifacts | Bi-weekly | ~10 min per repo | Claude Code scheduled agent |
| Doc staleness | Monthly | ~15 min | Claude Code scheduled agent |

### Implementation Options

**Option A: Claude Code Scheduled Agents (preferred for LLM sweeps)**

```bash
# Create the weekly sweep schedule
claude schedule create \
  --name "tech-debt-sweep" \
  --cron "0 6 * * 1" \
  --prompt "Run the tech debt sweep: execute vulture, radon, deptry, and import-linter on vms-connector, actuate-libraries, and inference-api. Compare results against the baseline in .health/baseline.json. File a single GitHub issue per repo with only NEW findings. Tag issues with 'tech-debt' and 'automated'. Update .health/baseline.json with current results."
```

**Option B: GitHub Actions (preferred for deterministic sweeps)**

```yaml
name: Tech Debt Sweep
on:
  schedule:
    - cron: '0 6 * * 1'

jobs:
  sweep:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        repo: [vms-connector, actuate-libraries, inference-api]
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v4
      - run: uv sync --dev

      - name: Dead code scan
        run: uv run vulture app/ vulture_whitelist.py --min-confidence 80 > reports/vulture.txt
        continue-on-error: true

      - name: Complexity scan
        run: uv run radon cc app/ -a -nc --json > reports/complexity.json
        continue-on-error: true

      - name: Dependency scan
        run: uv run deptry app/ > reports/deptry.txt 2>&1
        continue-on-error: true

      - name: Security scan
        run: uv run pip-audit --format json > reports/audit.json
        continue-on-error: true

      - name: File issue if findings
        uses: actions/github-script@v7
        with:
          script: |
            // Aggregate reports, compare against baseline, file issue
```

**Option C: Hybrid (recommended)**

Use GitHub Actions for the deterministic tools (reliable, fast, no LLM cost), and Claude Code scheduled agents for the pattern-recognition sweeps (convention drift, doc staleness). Both write to the same dashboard.

---

## Output: The Weekly Digest

Rather than filing 20 individual issues, the agent produces a **single weekly digest issue** per repo:

```markdown
## Tech Debt Sweep — vms-connector — 2026-04-21

### New Findings (since last sweep)

#### Dead Code (vulture, 3 new)
- `app/handlers/legacy_rtsp.py:45` — `convert_frame_legacy()` unused (confidence: 95%)
- `app/utils/retry.py:12` — `RetryConfig.max_backoff` unused (confidence: 82%)
- `app/integrations/adpro/client.py:89` — `AdproLegacyAuth` class unused (confidence: 90%)

#### Complexity Regression (radon, 1 new)
- `app/handlers/frame_processor.py:process_batch` — cyclomatic complexity 14 → 17 (threshold: 10)

#### Convention Drift (LLM, 2 findings)
- `app/api/camera_routes.py` — does not follow `routes_*.py` naming convention
- `app/services/alert_service.py:send_alert` — missing structured logging (all sibling methods use `logger.info(event=...)`)

### Resolved Since Last Sweep
- ~~`app/utils/deprecated_helpers.py` — entire file was dead code~~ (deleted in PR #342)

### Metrics
| Metric | Last Week | This Week | Trend |
|--------|-----------|-----------|-------|
| Dead code items | 12 | 14 | ↑ |
| Functions > complexity 10 | 8 | 9 | ↑ |
| Unused dependencies | 2 | 2 | → |
| Known CVEs | 0 | 0 | → |
| Overall health score | 72/100 | 70/100 | ↓ |
```

---

## Baseline Management

To avoid drowning in pre-existing debt, the agent maintains a **baseline file** (`.health/baseline.json`) in each repo:

```json
{
  "generated": "2026-04-16T06:00:00Z",
  "vulture": {
    "known_items": ["app/legacy/old_handler.py:23:convert_v1"],
    "count": 12
  },
  "complexity": {
    "known_hotspots": ["app/handlers/frame_processor.py:process_batch"],
    "max_cc": 14,
    "avg_mi": "B"
  },
  "deptry": {
    "known_unused": ["deprecated-lib"],
    "count": 2
  }
}
```

**Rule:** Only file issues for findings *not* in the baseline. Update the baseline when a finding is deliberately accepted (via PR that updates the baseline file with a justification comment).

---

## Safety Rails

1. **Never auto-commit.** The agent files issues and draft PRs. Humans merge.
2. **Never touch protected branches.** Agent creates branches from `develop`, never pushes to `main` or `rearchitecture`.
3. **Confidence thresholds.** vulture: 80%+. LLM convention checks: only report HIGH confidence findings.
4. **Rate limiting.** Maximum 1 issue per repo per sweep. Aggregate findings into digests.
5. **Kill switch.** The schedule can be paused via `claude schedule pause tech-debt-sweep` or by disabling the GitHub Actions workflow.
6. **Audit trail.** Every sweep logs its findings to `.health/sweep-log.jsonl` for trend analysis.
7. **Cost cap.** LLM-powered sweeps are capped at ~10 minutes per repo (token budget). Deterministic sweeps have no meaningful cost.

---

## Phased Rollout

### Phase 1: Deterministic Only (Week 1)
- Add vulture, radon, deptry, pip-audit to a weekly GitHub Actions workflow
- Create `.health/baseline.json` from current state
- File first digest issue manually to validate the format

### Phase 2: LLM Convention Checks (Week 3)
- Create Claude Code scheduled agent for convention drift detection
- Start with vms-connector only (most active repo)
- Review findings for 2 weeks before expanding

### Phase 3: Full Fleet (Month 2)
- Expand to all repos
- Add doc staleness checks
- Connect output to [[2026-04-16_code-health-dashboard|Code Health Dashboard]]

### Phase 4: Proactive (Month 3+)
- Agent creates draft PRs for simple fixes (dead code removal, unused import cleanup)
- Agent suggests architecture rule updates when new patterns emerge
- Weekly trend reports posted to Slack

---

## Related

- [[2026-04-16_metrics-to-track]] — metrics the agent collects
- [[2026-04-16_code-health-dashboard]] — where findings are visualized
- [[2026-04-16_architecture-enforcement]] — CI gates the agent complements
- [[2026-04-16_tooling-landscape]] — tools the agent runs
