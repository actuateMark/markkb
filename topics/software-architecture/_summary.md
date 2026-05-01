---
title: Software Architecture Health & Governance
type: summary
topic: software-architecture
tags: [architecture, code-health, tech-debt, tooling, metrics, governance, automation]
created: 2026-04-16
updated: 2026-04-23
author: kb-bot
---

# Software Architecture Health & Governance

Processes, tooling, metrics, and automation for maintaining code quality, enforcing architectural boundaries, tracking tech debt, and keeping Actuate codebases clean and well-structured over time.

This topic is the strategic counterpart to [[engineering-process/_summary|Engineering Process]], which covers day-to-day development workflows. This topic covers the systems that **prevent drift** — the dashboards, gates, agents, and fitness functions that keep the codebase healthy as it grows.

## Core Documents

| Document | Type | Purpose |
|----------|------|---------|
| [[2026-04-16_code-health-dashboard]] | Synthesis | Extensible dashboard design consolidating all code health metrics |
| [[2026-04-16_tooling-landscape]] | Synthesis | Catalog of tools for analysis, enforcement, and monitoring — with reading list |
| [[2026-04-16_metrics-to-track]] | Synthesis | What to measure: complexity, coupling, coverage, debt ratio, architecture conformance |
| [[2026-04-16_architecture-enforcement]] | Synthesis | Enforcing boundaries, dependency rules, and style via CI gates and fitness functions |
| [[2026-04-16_tech-debt-agent]] | Synthesis | Design sketch for a headless AI agent that patrols the codebase for debt and drift |

## Key Principles

1. **Measure to manage** — you can't reduce tech debt you can't see; instrument everything, track trends
2. **Enforce at the boundary** — CI gates, pre-commit hooks, and import rules catch violations before they land
3. **Automate the boring** — dead code, unused imports, style drift, stale dependencies — let machines find them
4. **Fitness functions over code review heroics** — encode architectural intent as executable tests
5. **Dashboard as single pane** — one place to see the health of every repo, every metric, every trend

## Scope

- **In scope:** Static analysis, architecture testing, code health metrics, tech debt tracking, dependency governance, automated code patrol, dashboards
- **Out of scope:** Runtime observability (see [[new-relic]]), deployment pipelines (see [[infrastructure/_summary|Infrastructure & Security]]), day-to-day dev process (see [[engineering-process/_summary|Engineering Process]])
- **Adjacent (added 2026-04-23):** The [[2026-04-16_code-health-dashboard]] concept in this topic is *code-health* focused; the **operational-health dashboard initiative** in [[mark-todos]] §9 (born of the 2026-04-23 onboarder silent-failure post-mortem) is *behavioral/runtime* focused. Either they collapse into one cross-cutting dashboard platform, or they coexist with clearly-delineated scope. Each of the 5 sketches under [[2026-04-17_local-sketches-plan]] must demonstrate monitoring hooks from the start — "how do I know this is working in prod?" is a first-class design question.

## Current State (April 2026)

The Actuate codebase has basic linting (ruff) and testing (pytest) but lacks:
- Architecture conformance testing
- Code health trend tracking
- Consolidated quality dashboard
- Automated tech debt detection
- Dependency boundary enforcement across the monorepo

This topic captures the plan to close those gaps.

## Status

- 2026-04-16 — 5 synthesis documents drafted (dashboard, tooling, metrics, enforcement, agent)
- 2026-04-17 — **Local sketch phase planned** — see [[2026-04-17_local-sketches-plan]] for the minimal-fidelity prototypes of all 5 projects + integration-point contract
- 2026-04-17 — **Issue hygiene workstream added** — see [[2026-04-17_issue-hygiene-plan]]. Triggered by the [[2026-04-17_scan|first repo scan]] exposing that poor label/body hygiene blunts scan signal. Proposed automation: [[agent-issue-auditor]]. Tracked as §7 in [[mark-todos]].
- 2026-04-22 — **Substrate decision locked + sketch repo scaffolded** — single flat Python 3.12+ sandbox at `/home/mork/work/software-arch-sketches/` with all 5 sketches as sibling modules under `software_arch_sketches`; vms-connector as input repo; JSON-on-disk data; Flask + Chart.js dashboard. All 5 stubs run + emit envelopes; smoke tests pass. Per-sketch scaffolding status noted at the top of each of the 5 synthesis notes. See [[2026-04-17_local-sketches-plan]] "Shared substrate decisions (RESOLVED 2026-04-22)" + "Scaffolding complete (2026-04-22)".
- Next — flesh out each sketch's stub into a real collector (start with metrics or enforcement as warm-up), wire the dashboard to real data, capture per-sketch findings notes. Still tracked as §6 in [[mark-todos]]. In parallel: manual issue-hygiene pilot on vms-connector per §7.

## Reading List

- [[software-architecture/reading-list|Reading list]] — seeded 2026-04-22. 8 sections covering fitness functions, code-health metrics, tech-debt research, Python static-analysis tooling (candidates for the tooling sketch), dashboard patterns, monorepo governance, and industry benchmarks.

## Related Topics

- [[engineering-process/_summary|Engineering Process]] — day-to-day development workflows and checklists
- [[actuate-libraries]] — 41-package UV monorepo needing dependency governance
- [[vms-connector]] — largest service, most complex architecture
- [[infrastructure/_summary|Infrastructure & Security]] — CI/CD pipelines where enforcement gates will live
- [[fleet-architecture/_summary|Fleet Architecture Redesign]] — fleet-redesign initiative (candidate architectures, PoCs, selection) — this topic will produce the systems the fleet architecture eventually runs under
