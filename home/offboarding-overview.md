---
title: "Offboarding — topic summary"
type: summary
topic: offboarding
tags: [offboarding, handoff, mark, index]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
---

# Offboarding

Consolidates Mark's departure handoff (last day **2026-06-26**): transferring his Actuate footprint — firebat minipc automation, the KB, dashboards, the npu-server LLM shop, and in-flight workstreams — to the team. Decisions (2026-06-22): hardware stays (company-owned) → re-home credentials, keep automation running; no single successor → self-serve docs + ticket reassignment; mirror personal repos to the org. Jira: epic **[ENG-375](https://actuate-team.atlassian.net/browse/ENG-375)** (children ENG-376…382).

## Start here
- ✅ **[[2026-06-22_manual-action-checklist]]** — the do-this-by-hand list (credential re-homes, admin actions, team decisions). **Work through this.**
- 🗺️ [[2026-06-22_actuate-footprint-handoff]] — the "what runs where" map (the future Confluence landing page).
- 📋 [[2026-06-22_offboarding-plan]] — the full plan, decisions, Jira reassignment ledger, in-office execution sequence.
- 🚨 [[2026-06-22_dead-mans-checklist]] — if something breaks after Friday: symptom → cause → fix.

## Successor handoffs
- [[2026-06-23_watchman-fleet-handoff-paolo-mike]] — [[watchman-repo|Watchman]] + fleet-arch (ENG-300/ENG-383) split to **Paolo** (deploy/connector) + **Mike** (fleet/k8s).
- [[2026-06-23_firebat-dashboard-ownership-handoff]] — the firebat automation + operational dashboard (§9/§12) ownership charter. **⚠ no owner named yet.**
- [[2026-06-23_autopatrol-handoff]] — cleanup Lambda (§3) + arm-miss race (§14) + alert-flow (§2) → **Brad** (cleanup-Lambda internals are Mark's; reading list is load-bearing).
- [[2026-06-23_local-repo-audit]] — CLAUDE.md / KB-port status across all 25 local repos; HIGH+MED repos being drafted as branch+PR per repo.

## Setup / rebuild runbooks (enshrined — clone-and-rebuild)
- [[DEVBOX-BOOTSTRAP]] — stand up the whole KB + Claude-Code workflow on a fresh machine.
- [[SETUP]] — KB-only self-host instance.
- [[2026-06-24_secrets-refresh-runbook]] — every credential + how to rotate it.
- `actuate-dev-toolkit/npu-server-provisioning.md` — rebuild npu-server from bare OS (skeleton; Stage-2 driver stack needs §D box-capture).
- `actuate-dev-toolkit/aws-rolesanywhere-rebuild.md` — reconstruct firebat's team-owned AWS identity.
- `actuate-dev-toolkit/CLAUDE.md` + `phase-00…16` — rebuild firebat. `files/llm-shop/CLAUDE.md` — rebuild the llm-shop app layer.

## Operating runbooks (for whoever inherits each system)
- [[2026-06-22_firebat-operations-runbook]] — the minipc: 14 timers, creds, dashboard, KB repo
- [[2026-06-22_dashboard-signals-catalog]] — the ~89-signal operational dashboard
- [[2026-06-22_npu-server-llm-shop-runbook]] — the local-LLM shop

## State (2026-06-22)
- **Done (automatable):** WS-0 (PRs all already merged), WS-B markkb secured + secret-purged + gitleaks-guarded, WS-C handoff comments on 13 tickets, WS-D all 3 runbooks, WS-E dead-man's checklist, WS-A verify harness + baseline, AWS confirmed already-team-owned.
- **Remaining (manual — see the checklist):** the team automation-identity decision; GitHub/NR/Atlassian re-homes; Tailscale re-tag (needs a tailnet admin); npu SSH; org mirror; Confluence publish; Jira assignees; Friday verification + decommission.
