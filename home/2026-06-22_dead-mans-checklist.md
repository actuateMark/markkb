---
title: "Dead-man's checklist — if Mark's automation breaks after 2026-06-26"
type: synthesis
topic: engineering-process
tags: [offboarding, runbook, break-glass, firebat, troubleshooting, dead-mans-checklist]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
incoming:
  - _tooling/DEVBOX-BOOTSTRAP.md
  - index.md
  - topics/engineering-process/notes/syntheses/2026-06-22_actuate-footprint-handoff.md
  - topics/engineering-process/notes/syntheses/2026-06-22_offboarding-plan.md
  - topics/offboarding-overview.md
  - topics/offboarding/notes/concepts/2026-06-22_manual-action-checklist.md
  - topics/offboarding/notes/concepts/2026-06-23_firebat-dashboard-ownership-handoff.md
incoming_updated: 2026-06-25
---

# Dead-man's checklist

> **For the week(s) after Mark's last day (2026-06-26).** When something he ran stops working, find the symptom below → likely cause → fix. Most failures trace to one of the four **identities** that were re-homed off Mark in WS-A (Tailscale / GitHub / NR / Atlassian) — if his accounts were deactivated before those re-homes completed, that's almost always the cause.
>
> **First move, always:** run `~/bin/firebat-identity-verify.py` on firebat. It checks all 4 identities + 14 timers and tells you exactly what's red. Baseline (pre-re-home) is at `~/identity-baseline-pre-rehome.json`.
> **Detail for every system below:** [[2026-06-22_firebat-operations-runbook]] · map of everything: [[2026-06-22_actuate-footprint-handoff]].

## Symptom → cause → fix

| Symptom | Likely cause | Fix |
|---|---|---|
| **Can't reach firebat at all** (ssh/http both dead) | Tailscale node was user-owned by `mark@`; his deactivation removed it from the tailnet | Re-auth the node at the console with a **tagged** auth key: `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`. (WS-A) Tailnet itself is company-owned (`aegissystems.ai`). |
| **Dashboard `http://mork-firebat/app/` stale or 5xx** | `rebuild-blog` / `rebuild-quartz` / `minipc-app.service` stopped, or firebat unreachable (see above) | `systemctl --user status rebuild-quartz.timer minipc-app.service`; restart; check Caddy. Runbook §dashboard. |
| **Morning Jira queue (mark-todos) stopped updating** | `jira-sync` timer failing — Atlassian token (`~/.config/atlassian/api-token`) was Mark's `mark@actuate.ai`, now invalid | Re-issue an Atlassian API token under a **service account**, write to that path. (WS-A) Verify: `firebat-identity-verify.py`. |
| **Dashboard NR signals all `error` / missing** | NR key (`~/.config/newrelic/key`) was Mark's personal `NRAK-`, now revoked | Mint a replacement NR key (ideally team/service), write to that path. (WS-A) |
| **`repo-scan` / `git-fetch-major-repos` / `pr-review-digest` failing** | firebat `gh` authenticated as personal `actuateMark`, now lost org access | Authenticate `gh` as an org machine account / install a fine-grained org PAT. (WS-A) |
| **`billing-reconcile-check` / `ecr-lifecycle-audit` failing** | AWS — *should NOT break* (IAM Roles Anywhere host cert, team-owned) | If it does: check the cert at `~/.config/aws-rolesanywhere/mork-firebat.{crt,key}` + role `dashboard-check-rolesanywhere` / trust-anchor in account `388576304176` weren't revoked. |
| **`llm-shop-delegate` / local-LLM tasks failing** | npu-server unreachable (Tailscale, same as firebat) or its `systemctl --user` services down | Non-fatal — callers fall back to Claude. Fix: re-auth npu-server's Tailscale node; restart `llm-shop-*` units. [[2026-06-22_npu-server-llm-shop-runbook]]. |
| **KB / Quartz not updating with new notes** | `kb-org-sync` timer not pulling from the org (gh auth / network), or push side failing | firebat git-pulls `aegissystems/actuate-kb` every 30m via `kb-org-sync.timer`. Check `journalctl --user -u kb-org-sync` + `~/.local/state/claude-jobs/kb-org-sync-*`; a pull/rebase conflict needs a human (`git -C ~/Documents/worklog/work/knowledgebase status`). Obsidian Sync is OFF — git is the only path. |
| **A timer "succeeds" but `kb-lint` shows exit 2** | Normal — that's kb-lint's "issues found" signal, not a failure | No action (the verify harness treats it as PASS). |

## Standing facts that won't change
- **AWS is genuinely safe** — Roles Anywhere host identity, not Mark's. The one credential that needs *no* intervention.
- **Tailnet is company-owned** (`aegissystems.ai`); only the *device registrations* were under `mark@`.
- **Logs:** `~/.local/state/claude-jobs/` (timer stdout/stderr) and `journalctl --user -u <svc>`.
- **Source of truth for firebat scripts:** `aegissystems/actuate-dev-toolkit` (`files/`, phase scripts) — deployed by `phase-13`. Don't hand-edit `~/bin` without updating the repo.
- **Re-homing all happens in [ENG-376](https://actuate-team.atlassian.net/browse/ENG-376)** (WS-A) — if a symptom above appears, that ticket has the context.

## Related
- [[2026-06-22_actuate-footprint-handoff]] — the map · [[2026-06-22_offboarding-plan]] — the plan
- [[2026-06-22_firebat-operations-runbook]], [[2026-06-22_dashboard-signals-catalog]], [[2026-06-22_npu-server-llm-shop-runbook]]
