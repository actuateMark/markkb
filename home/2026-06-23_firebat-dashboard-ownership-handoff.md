---
title: "Firebat automation + operational dashboard — ownership handoff"
type: concept
topic: offboarding
tags: [offboarding, handoff, firebat, dashboard, ownership, monitoring, ops]
created: 2026-06-23
updated: 2026-06-23
author: kb-bot
incoming:
  - topics/offboarding-overview.md
incoming_updated: 2026-06-24
---

# Firebat automation + dashboard — ownership handoff

> The §9/§12 monitoring/tooling layer — the most uniquely-Mark part of the footprint. **It keeps *running* without an owner** (the §A credential re-homes in [[2026-06-22_manual-action-checklist]] handle survival), **but it won't be *maintained or extended* without one.** This is the ownership charter: what taking it on means. The operating *detail* is already in the two runbooks below.
>
> **⚠ Key open decision: no owner named yet.** Naming one is the action — see "Owner profile." Until then it's nobody's, and signal drift / a dead timer goes unnoticed.

## What the layer is
- **Firebat minipc** (`mork-firebat`): ~14 `systemd --user` timers — morning-prep, jira-sync, dashboard-check, billing-reconcile, ecr-audit, repo-scan, KB lint/relink/incoming, blog/quartz rebuilds. Runbook: [[2026-06-22_firebat-operations-runbook]].
- **Operational dashboard**: ~89 silent-regression signals across 15 components, rendered at `http://mork-firebat/app/`. Catalog: [[2026-06-22_dashboard-signals-catalog]]. Context: [[2026-05-05_operational-dashboard-context]].
- **Backed by**: the `actuate-dev-toolkit` repo (`local_network_scripts`) — phase scripts + `files/` deployed to firebat by `phase-13`.

## What owning it means (recurring duties)
- **[[watch-entity|Watch]] the morning signal** — `~/bin/observations-snapshot` / the dashboard; triage RED. Most are chronic (billing-unbilled, OOM offenders) — know which are noise vs. new.
- **Keep timers green** — `~/bin/firebat-identity-verify.py` is the one-shot health check (identities + all timers). Run it if the morning cache looks stale.
- **Rotate credentials** when they expire (NR key, Atlassian token, GitHub PAT, AWS cert) — the firebat runbook has the credential map + paths.
- **Standing discipline (inherited):** every new inference-api E2M rule ships with a matching dashboard signal in `signals.json` (mark-todos §9). Don't let metric series exist without a regression-aware view.
- **Three-tier routine-check pattern** — firebat script → laptop script → LLM skill. Don't run `claude -p` on firebat cron (autopatrol regression). [[2026-04-30_three-tier-routine-check-pattern]].

## Extension points (the "evolve it" part)
- **Add a signal:** edit `~/.claude/skills/dashboard-check/config/signals.json` (fields + source query); see the catalog's how-to.
- **Add/remove a timer:** edit the unit in `actuate-dev-toolkit/files/`, redeploy via `phase-13`, `systemctl --user` enable. Don't hand-edit `~/bin` without updating the repo.
- **Open Phase-1b/2 backlog** (mark-todos §9): replay-tests for historical incidents, baseline-drift regression rules, sparklines, coverage expansion. A new owner can pick these up or park them.

## Reading list (for the new owner)
[[2026-06-22_firebat-operations-runbook]] → [[2026-06-22_dashboard-signals-catalog]] → [[2026-05-05_operational-dashboard-context]] → [[2026-04-30_three-tier-routine-check-pattern]] → [[2026-04-30_morning-prep-scripts-runbook]]. Break-glass: [[2026-06-22_dead-mans-checklist]].

## Owner profile + recommendation
Best fit: someone **ops/devops/SRE-leaning** comfortable with systemd, AWS (Roles Anywhere), [[new-relic|New Relic]]/NRQL, and the KB. It's a *light but real* ongoing load — minutes/day to [[watch-entity|watch]] signals + occasional maintenance — not a full workstream. Options:
- **A single named owner** (cleanest — they get the morning signal + maintenance).
- **Fold into an existing on-call/infra rotation** (the dashboard becomes a rotation surface).
- **Minimum viable:** at least assign the **credential-rotation + timer-health** duty to someone, even if signal-watching stays informal — otherwise a dead timer is invisible.

**Jira:** §9/§12 are pre-ticket (ENG-179 R&D). Suggest opening an ownership/maintenance ticket once the owner is named, or folding it into their plate.

## Related
- [[2026-06-22_offboarding-plan]] · [[2026-06-22_manual-action-checklist]] · [[2026-06-22_actuate-footprint-handoff]]
- [[2026-06-22_firebat-operations-runbook]] · [[2026-06-22_dashboard-signals-catalog]] · [[2026-06-22_dead-mans-checklist]]
