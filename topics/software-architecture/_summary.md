---
title: Software Architecture Health & Governance
type: summary
topic: software-architecture
tags: [architecture, code-health, tech-debt, tooling, metrics, governance, automation]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Software Architecture Health & Governance

Processes, tooling, metrics, and automation for maintaining code quality, enforcing architectural boundaries, tracking tech debt, and keeping Actuate codebases clean and well-structured over time.

This topic is the strategic counterpart to [[engineering-process]], which covers day-to-day development workflows. This topic covers the systems that **prevent drift** — the dashboards, gates, agents, and fitness functions that keep the codebase healthy as it grows.

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
- **Out of scope:** Runtime observability (see [[new-relic]]), deployment pipelines (see [[infrastructure]]), day-to-day dev process (see [[engineering-process]])

## Current State (April 2026)

The Actuate codebase has basic linting (ruff) and testing (pytest) but lacks:
- Architecture conformance testing
- Code health trend tracking
- Consolidated quality dashboard
- Automated tech debt detection
- Dependency boundary enforcement across the monorepo

This topic captures the plan to close those gaps.

## Related Topics

- [[engineering-process]] — day-to-day development workflows and checklists
- [[actuate-libraries]] — 41-package UV monorepo needing dependency governance
- [[vms-connector]] — largest service, most complex architecture
- [[infrastructure]] — CI/CD pipelines where enforcement gates will live
- [[fleet-architecture]] — fleet-redesign initiative (candidate architectures, PoCs, selection) — this topic will produce the systems the fleet architecture eventually runs under
