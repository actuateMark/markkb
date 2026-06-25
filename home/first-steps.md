---
title: "First steps — day one as an Actuate engineer"
type: concept
tags: [orientation, onboarding, getting-started, repos, home]
updated: 2026-06-25
author: kb-bot
incoming:
  - home/README.md
  - index.md
incoming_updated: 2026-06-25
---

# First steps — day one

You've read [[what-is-actuate]] and [[system-architecture]]. This page answers the practical day-one questions the rest of the packet assumes.

## Where's the code?
The platform is a suite of GitHub repos under the **`aegissystems`** org. The canonical, always-current list (with "clone-on-need" vs "local" status) is **[[core-repo-suite]]**. The ones you'll touch most:

| Repo | What it is | Topic |
|---|---|---|
| `vms-connector` | The per-customer pipeline (puller/filter/observer/sender). The most important repo. | [[vms-connector/_summary\|vms-connector]] |
| `actuate-libraries` | Shared packages the connector + services depend on (auto-publishes stable on merge to `main`). | [[actuate-libraries/_summary\|actuate-libraries]] |
| `actuate-inference-api` | Model serving (the v5 contract). | [[inference-api/_summary\|inference-api]] |
| `actuate_admin` | Admin / control-plane API. | [[admin-api/_summary\|admin-api]] |
| `autopatrol_onboarder`, `autopatrol-server` | The AutoPatrol product. | [[autopatrol/_summary\|autopatrol]] |
| `camera-ui` | Front-end (live view / streaming). | [[video-processing/_summary\|video-processing]] · [[webrtc-deep-dive/_summary\|webrtc]] |
| `actuate-dev-toolkit` | Provisions + operates the firebat automation host. | [[2026-06-22_firebat-operations-runbook\|firebat runbook]] · [[personal-laptop/_summary\|personal-laptop]] |
| `actuate-kb` | This knowledge base. | [[how-to-use-this-kb]] · [[obsidian/_summary\|obsidian]] |

Clone what you need: `cd ~/work && gh repo clone aegissystems/<repo>`.

## Set up your dev environment
- Full workflow (KB + Claude-Code + tooling) on a fresh machine → **[[DEVBOX-BOOTSTRAP]]**.
- Just this KB → **[[SETUP]]**.
- Python projects use **`uv`** (not pip/venv): `uv sync`, `uv run …`, `uv add <pkg>`.
- **Before coding** in any repo, pull context: run `/kb-lookup` or read the repo's topic `_summary` (see [[how-to-use-this-kb]]). Most repos also have a `CLAUDE.md`.

## How code ships
Branch flow **feature → stage → rearchitecture → prod**, deployed via GitHub Actions CI + [[argocd|ArgoCD]] onto EKS. `actuate-libraries` merging to `main` auto-publishes to CodeArtifact — update connector pins deliberately. Details + the pre-merge workflow: [[engineering-process/_summary]] and [[releases/_summary]].

## Who owns what
Team layout + assignments: **[[team-structure/_summary]]**. As of the mid-2026 handoff, ownership of the systems documented here:
- **[[watchman-repo|Watchman]] / fleet architecture** → Paolo + Mike — [[2026-06-23_watchman-fleet-handoff-paolo-mike]]
- **AutoPatrol** → Brad — [[2026-06-23_autopatrol-handoff]]
- **Firebat automation host + the operational dashboard** → [[2026-06-23_firebat-dashboard-ownership-handoff]]

## What to work on / where work is tracked
- **Jira** is the work tracker (project ENG); the KB's [[jira-organization/_summary]] explains conventions, and `mark-todos` / `/daily-scope` was the personal planning flow.
- **Product direction** → [[product-roadmap/_summary]].
- **Cross-repo opportunities / tech-debt backlog** → [[repo-backlog/_summary]].

## When production is unhealthy
The operational dashboard (firebat, `http://mork-firebat/`) aggregates fleet health; signals are catalogued in [[2026-06-22_dashboard-signals-catalog]]. For New-Relic triage use the `nrql-investigator` subagent and the rules in [[new-relic/_summary]]. If the *automation itself* breaks: [[2026-06-22_dead-mans-checklist]].

## Next
Back to [[README]] for the full reading order, or [[the-topic-landscape]] to dive into a specific area.
