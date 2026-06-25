---
title: "Mark's Actuate footprint — team handoff index (START HERE)"
type: synthesis
topic: engineering-process
tags: [offboarding, handoff, footprint, index, firebat, kb, runbook, autopatrol]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
incoming:
  - home/2026-06-22_dead-mans-checklist.md
  - home/2026-06-22_manual-action-checklist.md
  - home/2026-06-23_firebat-dashboard-ownership-handoff.md
  - home/2026-06-23_local-repo-audit.md
  - home/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - home/2026-06-24_offboarding-asks.md
  - home/DEVBOX-BOOTSTRAP.md
  - home/README.md
  - home/offboarding-overview.md
  - home/the-topic-landscape.md
incoming_updated: 2026-06-25
---

# Mark's Actuate footprint — handoff index

> **Purpose.** A single map of everything Mark ran, built, or knew, for the team inheriting it after his last day **Fri 2026-06-26**. This is the navigation hub — each section points to the runbook/note that has the detail. Tracked in Jira epic **[ENG-375](https://actuate-team.atlassian.net/browse/ENG-375)**; full plan: [[2026-06-22_offboarding-plan]].
>
> **No single successor** — work disperses across the team. Everything here is built to be self-serve: pick the thread you need, follow its runbook.

## 1. Infrastructure that keeps running (company-owned, stays)

| System | What it does | Where | Runbook |
|---|---|---|---|
| **firebat minipc** (`actuate-dev` / `mork-firebat`) | ~14 systemd timers: morning-prep, jira-sync, dashboard-check, billing-reconcile, ecr-audit, repo-scan, KB lint/relink, blog/quartz rebuilds | LAN + Tailscale `aegissystems.ai` | [[2026-06-22_firebat-operations-runbook]] |
| **Operational dashboard** | Silent-regression detection, ~89 signals across 15 components; web UI | `http://mork-firebat/app/` + `~/Documents/worklog/dashboard/` | [[2026-06-22_dashboard-signals-catalog]] |
| **npu-server LLM shop** (§24) | Local LLMs (TinyLlama/Qwen) for token-saving KB + code tasks | `npu-server.tail9b2a4e.ts.net` | [[2026-06-22_npu-server-llm-shop-runbook]] |
| **Knowledge base** (this vault) | ~1000+ notes of Actuate R&D, runbooks, ADRs, investigations | org mirror (see §3) + firebat bare repo | §3 below |
| **Minipc provisioning** | Reproducible firebat setup (`phase-00`…`phase-13`) | `aegissystems/actuate-dev-toolkit` | repo README |

## 2. Credentials & access (WS-A re-home — finish at the office Wed/Thu)

The firebat timers authenticate as Mark today. Status per identity (detail + the verify harness `~/bin/firebat-identity-verify.py` in [[2026-06-22_firebat-operations-runbook]]):

- ✅ **AWS** — already team-owned (IAM Roles Anywhere host cert → `dashboard-check-rolesanywhere`). Survives departure.
- 🔧 **Tailscale** — firebat + npu-server nodes are user-owned by `mark@`; re-auth with a `tag:server` auth key to make them tailnet-owned. ⚠ do at the box (can drop SSH).
- 🔧 **GitHub** — firebat `gh` is personal `actuateMark`; replace with an org machine account / fine-grained PAT.
- ⏳ **[[new-relic|New Relic]]** (`~/.config/newrelic/key`) + **Atlassian** (`~/.config/atlassian/api-token`) — personal `mark@`; rotate/re-issue under a team/service identity. *(A leaked NR key was found + purged from KB history 2026-06-22 — see plan §incident.)*

Baseline captured pre-re-home: `~/identity-baseline-pre-rehome.json` (0 FAIL / 3 WARN = the 3 targets).

## 3. Knowledge base — where it is & how to use it

- **Content:** this Obsidian vault (`~/Documents/worklog/knowledgebase/`), one topic per directory, notes typed concept/synthesis/entity/source.
- **Remotes:** ✅ **`aegissystems/actuate-kb`** (private, org-owned — the durable team home, pushed 2026-06-23) + firebat bare repo + `actuateMark/markkb` (personal). Scrubbed before mirroring (gitleaks-clean; a colleague IP + incident naming purged). gitleaks pre-commit hook enforced.
- **How to query:** Obsidian app + the `obsidian` CLI (backlinks/tags/search/orphans). Health probe: `~/.local/bin/obsidian vault`.
- **Self-host:** the repo bundles **`_tooling/`** (10 kb-* skills, 4 agents, ~19 automation scripts, the [[obsidian-cli|obsidian CLI]], shared lib) + **`_tooling/SETUP.md`** — clone `aegissystems/actuate-kb` and stand up your own KB instance (content + tooling).
- **firebat auto-syncs:** as of 2026-06-24 firebat git-pulls the KB from the org every 30 min (`kb-org-sync` timer) and pushes its relink enrichment back; **Obsidian Sync (Mark's account) is disabled** — no personal-account dependency. See [[2026-06-24_firebat-kb-git-sync-task]].
- **High-value entry points:** each workstream below links its load-bearing notes.

## 4. Workstreams — status & where each lives

| § | Workstream | Status | Load-bearing notes / tickets |
|---|---|---|---|
| §3 | AutoPatrol stale-schedule cleanup Lambda | live; verify-only | [[2026-04-17_stale-schedule-cleanup-design]]; check `/autopatrol-cleanup-lambda-check` |
| §5 | Fleet architecture / **[[watchman-repo|Watchman]]** | design; PoC pending | [[2026-06-02_watchman-phase0-fleet-fit]], [[2026-06-16_watchman-pipeline-backend-meeting]]; **ENG-300** |
| §9 | Operational dashboard | live; Phase 1b | [[2026-05-05_operational-dashboard-context]] + [[2026-06-22_dashboard-signals-catalog]] |
| §14 | AutoPatrol midnight arm-miss race | scoped, unimpl | [[actuate_admin]]#2310 |
| §18 | Memory-limit / VPA-floor drift | handed to Paolo/Mike | [[2026-04-23_oom-surge-connector-limit-drift]]; ENG-214 |
| §24 | Internal LLM shop | live | [[2026-06-22_npu-server-llm-shop-runbook]] |
| §28 | Customer billing pipeline | live | `billing-reconcile-check` timer |
| §29 | Custom-branch deploy lifecycle | in progress | ENG-269 / ENG-282 |
| §30 | Profiling & optimization | in progress | ENG-246 |
| §33 | RDS extended-support upgrades | runbook ready | [[2026-06-02_rds-extended-support-upgrade-runbook]]; BACK-673 |
| §10 | Laptop-config portability / DR | scoping | [[2026-05-05_laptop-config-portability-context]] |
| §12 | Minipc dashboard app | shipped | [[2026-04-24_minipc-dashboard-static-gen-refactor]] |

## 5. Jira handoff

- **Epic:** [ENG-375](https://actuate-team.atlassian.net/browse/ENG-375) (offboarding) → children ENG-376…382 (WS-A…E).
- **17 open assigned tickets** to reassign — full ledger (suggested owners) in [[2026-06-22_offboarding-plan]] § "Jira reassignment ledger." Don't-drop: CS3-31 (Highest), ENG-136/CS3-323/CS3-537 (High).

## 6. The automation layer (Claude Code config)

- **Repo:** ✅ **`aegissystems/claude-config`** (org-mirrored 2026-06-24) + personal `actuateMark/claude-config`. Holds skills (`~/.claude/skills/`), subagents (`~/.claude/agents/`), hooks, global rules (`CLAUDE.md`).
- **Daily rituals:** `/daily-scope` (morning), `/daily-wrap` (EOD), `/dashboard-check`, `/repo-scan`, the autopatrol checks. The morning automation depends on the firebat cron cache (`morning-prep.sh`) — see firebat runbook.
- **Subagent catalog:** [[agents-catalog]].

## 7. If something breaks after Mark leaves

- Run `~/bin/firebat-identity-verify.py` — pinpoints which identity/timer failed.
- **[[2026-06-22_dead-mans-checklist]]** — the symptom→cause→fix table ("if X breaks → check Y").
- Secret hygiene: a `gitleaks` pre-commit hook now guards both KB + claude-config (`.githooks/`); both scanned clean (0 leaks in history).
- Three-tier routine-check pattern: [[2026-04-30_three-tier-routine-check-pattern]] — firebat script → laptop script → LLM skill.

## Related
- [[2026-06-22_offboarding-plan]] — the execution plan + decisions + Jira ledger
- [[2026-06-22_firebat-operations-runbook]], [[2026-06-22_dashboard-signals-catalog]], [[2026-06-22_npu-server-llm-shop-runbook]]
