---
title: "Sketch findings: metrics collector (radon cyclomatic complexity)"
type: concept
topic: software-architecture
tags: [sketch, findings, metrics, complexity, radon, vms-connector]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
---

# Sketch findings: metrics collector

First of the 5 sketches called for in [[2026-04-17_local-sketches-plan]] landed as commit `263cd1a` on `main` of `/home/mork/work/software-arch-sketches/`. Module is `software_arch_sketches.metrics.collector`. Entry point: `make metrics` (or `uv run python -m software_arch_sketches.metrics.collector`).

## What it does

Walks every `.py` under `SKETCH_INPUT_REPO` (default `/home/mork/work/vms-connector`), skipping common noise dirs (`.git`, `.venv`, `__pycache__`, `build`, `dist`, `.tox`, `node_modules`, IDE dirs, lint caches). For each file, runs [radon's](https://radon.readthedocs.io/) `cc_visit` to extract per-function cyclomatic complexity, converts scores to letter ranks via `cc_rank`, and writes a per-file + summary envelope to `data/metrics.json`.

- Per-file entries: `path`, `function_count`, `max_complexity`, `mean_complexity`, `top_issues` (top-N highest-complexity functions, default N=10).
- Summary: `files_scanned`, `files_failed_to_parse`, total `functions`, `rank_distribution` (A–F count, computed across **every** function not just top-N), `mean_complexity`, `median_complexity`, `p95_complexity`, `max_complexity`.

## Concrete numbers (vms-connector, 2026-04-23)

| Metric | Value |
|---|---|
| Files scanned | 239 |
| Parse failures | 0 |
| Functions analyzed | 1,370 |
| Mean complexity | 3.62 |
| Median complexity | 2 |
| p95 complexity | 13 |
| Max complexity | 121 |
| Runtime | ~0.5s |
| LoC of collector | ~130 |

Rank distribution (A=1-5, B=6-10, C=11-20, D=21-30, E=31-40, F≥41):

| Rank | Count | % |
|---|---|---|
| A | 1146 | 83.6% |
| B | 128 | 9.3% |
| C | 67 | 4.9% |
| D | 22 | 1.6% |
| E | 4 | 0.3% |
| F | 3 | 0.2% |

Top-3 offenders:
- `site_manager/connector/analytics_site_manager.py` → `AnalyticsSiteManager._log_memory_breakdown` **cc=121** (F)
- `connector_factories/shared/factory.py` → `generate_site` cc=47 (F)
- `scripts/test_connection_timing.py` → `run_multi_bridge_test` cc=44 (F)

## What was surprisingly easy

- **radon API is clean.** `cc_visit(source)` returns `Function` objects with `.fullname`, `.complexity`, `.lineno`. `cc_rank(n)` maps score to letter. Integration was ~60 LoC of real logic.
- **Parse tolerance.** 0 parse failures across 239 files. No need to pre-filter generated code, tests with tricky conditional imports, or stub files. The `try/except (SyntaxError, ValueError)` guard is belt-and-braces but never fired.
- **Runtime.** Half a second for 239 files / 1,370 functions on an idle laptop. Viable for pre-commit / CI without dedicated caching. A full Actuate monorepo scan (if we ever merged them) would still be <30s.

## What was surprisingly hard

- **Designing the envelope shape.** First draft computed summary statistics (mean/median/p95/max + rank distribution) from `top_issues` — the display-capped subset. Bias toward higher complexity got baked into the stats silently (mean 4.35 vs real 3.62). Fix was a private `_all_complexities` field per file, aggregated repo-wide, then stripped before serialization. Worth remembering: "display sample" and "statistics sample" want to be separate data paths.
- **Bootstrap index config.** See [[2026-04-17_local-sketches-plan]] "First commit + uv migration (2026-04-23)" for the CodeArtifact-vs-PyPI story; not unique to metrics but surfaced during this sketch's setup.

## What it implies for a real implementation

**Complexity-only metrics collector: day-of-work.** The collector as-shipped is essentially production-shape (minus polish: incremental runs, per-commit baselines, a real output schema, JSON Schema validation). A day to harden; a week to integrate into CI with baselining + threshold alerts.

**Coverage integration: separate day.** The paper design's "1-2 key metrics (complexity + coverage)" is actually two integrations. Complexity is pure static analysis on source; coverage requires a `coverage.xml` / `.coverage` artifact from a test run, which means hooking into CI. Cleanest shape: a separate `coverage_collector.py` that reads `coverage.xml` and emits `data/coverage.json`; dashboard reads both.

**Open questions for the real version:**
- **Per-commit vs per-run.** Should metrics be run as a git pre-push hook, a CI job on main, or a nightly cron? Each implies different storage (versioned JSONs, a time-series DB, both?).
- **Baselining.** Flagging `max_complexity > 30` across the whole repo is useless when 47 functions already exceed it. Per-file or per-function baselines are needed for trend-detection to mean anything.
- **Aggregation boundaries.** Right now everything collapses to a single summary. Per-directory or per-Actuate-service (e.g., camera vs sender vs analytics) aggregation would probably be more actionable.

## Assumption check vs paper design

| Paper design ([[2026-04-16_metrics-to-track]]) | How it held up |
|---|---|
| "Complexity + coverage as the first two metrics" | Complexity alone is already substantive; coverage is a separate day. Design still sound — the sketch just scopes down. |
| "JSON on disk, no database" | Held up. `metrics.json` is 200KB-ish, human-readable, dashboard-ready. |
| "Per-file + summary" envelope shape | Mostly right; refined to add `_all_complexities` private field for stats, `top_issues` for display. |
| "Minimal collector script" | 130 LoC total. Feels right — any more and it starts wanting to be a framework. |

## Related

- [[2026-04-17_local-sketches-plan]] — parent plan (§Next concrete steps step 1)
- [[2026-04-16_metrics-to-track]] — original paper design this sketch implements
- [[2026-04-16_code-health-dashboard]] — next integration target (dashboard reads this JSON)
- [[mark-todos]] §6 — workstream tracking
