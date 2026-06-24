---
title: "Three-tier routine check pattern: script first, LLM as fallback"
type: synthesis
topic: engineering-process
tags: [scheduled-tasks, scripts, llm-fallback, firebat, dashboard, conversion-pattern]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - topics/engineering-process/notes/entities/automation-jira-sync.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-laptop/notes/syntheses/2026-04-30_firebat-script-conversion-candidates.md
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/engineering-process/notes/entities/automation-jira-sync.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-10-s3-sink-review-ux.md
  - topics/engineering-process/notes/syntheses/2026-06-22_actuate-footprint-handoff.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
  - topics/offboarding/notes/concepts/2026-06-23_firebat-dashboard-ownership-handoff.md
  - topics/offboarding/notes/concepts/2026-06-23_local-repo-audit.md
  - topics/operational-health/notes/syntheses/2026-05-21_overnight-check.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-laptop/notes/concepts/2026-06-22_firebat-operations-runbook.md
incoming_updated: 2026-06-24
---

# Three-tier routine check pattern: script first, LLM as fallback

## Context

Mark's morning routine fan-out (`/daily-scope` and the standing exec items in mark-todos's Morning Follow-Ups block) used to invoke a stack of LLM-driven skills (`/dashboard-check`, `/repo-scan`, `/autopatrol-overnight-check`, `/autopatrol-cleanup-lambda-check`, etc.) inline. Each invocation cost tokens, hit rate-limit ceilings during the fan-out, and surfaced unrelated failure modes (NR MCP detached, AWS SSO expired, GitHub API rate-limit). The 2026-04-30 attempt to run them headlessly on the Firebat (`mork-firebat`) made the fragility explicit: all three scheduled skills exited rc=0 but actually bailed early on permission gates because `--permission-mode acceptEdits` doesn't auto-approve bash, and NR MCP only exposed the OAuth bootstrap tool.

This note codifies the pattern that replaces the LLM-on-the-box approach.

## The three tiers

```
Tier 1 — Firebat script (canonical)
    ↓ (Firebat unreachable)
Tier 2 — Local laptop script (fallback)
    ↓ (script not installed / broken)
Tier 3 — LLM skill (last resort + diagnostic)
```

Walk down. Stop at the first that succeeds. Tier 3 also fixes Tiers 1-2 when it runs (closed-loop self-healing).

### Tier 1 — Firebat script

**Where:** `~/bin/<name>` on `mork-firebat`, deployed by phase-13-tasks.sh from `/home/mork/work/local_network_scripts/files/<name>.sh`. Driven by `~/.config/systemd/user/<name>.timer`.

**Outputs (canonical paths):**
- **stdout digest:** `~/.local/state/claude-jobs/<name>-<YYYY-MM-DD>.stdout` (markdown — same path as the LLM version's `claude-run-skill.sh` wrote, preserving daily-scope's cache contract)
- **structured JSON:** `~/.local/state/minipc-tasks/<topic>/<name>-<YYYY-MM-DD>.json` (machine-consumable)
- **dashboard sink:** appended observations in `~/Documents/worklog/dashboard/sink/observations.jsonl` with `component=<topic>`, `source_skill=<name>`, FACET-shaped values where applicable (per-repo, per-site, per-region)

**Auth pattern:**
- AWS via Roles Anywhere — `AWS_PROFILE=dashboard-check` (or sibling profile per workload)
- NR via direct nerdgraph using `~/.config/newrelic/key` + `~/.config/newrelic/account_id` (NOT NR MCP — that's OAuth-gated, doesn't survive headless)
- GitHub via PAT at `~/.config/gh/hosts.yml` (installed by phase-15-secrets)

**Caddy exposure:** `/logs/` serves `~/.local/state/claude-jobs/`. `/app/api/observations` serves the dashboard sink. So consumers GET via HTTP, no SSH needed.

**Sized for cron:** runtime measured in seconds (repo-scan: 4s for 7 repos, 188 issues). NR queries scoped tight — tight time windows, FACETs not raw rows. AWS calls scoped to one Region per workload.

### Tier 2 — Local laptop script

**Where:** `~/bin/<name>` on the laptop (same script source, same path).

**Why:**
- Firebat offline (laptop on plane, public WiFi blocking tailnet, etc.)
- Want fresher-than-cache data without waiting for Firebat's next cron tick
- Multi-machine resilience

**KB convergence:** the laptop's `~/Documents/worklog/knowledgebase/` is the same Obsidian vault as Firebat's. Both write to it; Obsidian Sync converges. Last writer for a given dated scan note wins, both writers carry the same content (deterministic from inputs).

### Tier 3 — LLM skill

**Where:** `~/.claude/skills/<name>/SKILL.md`, invoked via `/<name>`.

**When:** only when both scripts are unavailable. The skill's `## Procedure` MUST begin with a "Step 0 — prefer the script" preamble that walks Tiers 1 and 2 before running the LLM-orchestrated body.

**Diagnostic responsibility:** when LLM tier is running, both Tier 1 and Tier 2 failed. The LLM must:
1. Surface the error (`AccessDeniedException`, `cert expired`, `module not found`, `wrong path`)
2. Patch the script in-place where the fix is mechanical (file path, IAM action, missing dependency, broken regex). Edit `local_network_scripts/files/<name>.sh` and run phase-13 to redeploy, OR push a fix commit if it's a repo-tracked script.
3. Where the fix is environmental (SSO token expired, API key rotated, IAM policy needs human approval), surface remediation to the user with exact commands.
4. Log the failure in today's daily note `## Notes / Learnings` so it doesn't repeat silently.

This is the closed-loop self-healing part. Every LLM-fallback run leaves Tiers 1-2 stronger.

## Conversion criteria

When triaging an existing skill or designing a new routine, **convert / build as Tier 1 first** if:

- Mostly mechanical: `gh issue list`, `aws lambda get-...`, NRQL against fixed thresholds, file scans, regex matches
- Output consumed by another routine (digest fed to `/daily-scope`, signals fed to dashboard)
- Fired on a cron, not in response to a human request
- Token cost > $0.01/run × frequency justifies it (rough heuristic: > $5/year break-even at ~1-2h port effort)

**Stay in Tier 3 only** if:

- Output requires synthesis judgment ("is this a real incident or noise across these 4 weak signals?")
- Skill invoked rarely (< 1×/week) — token cost trivial, conversion overhead not paid back
- Each invocation has wildly different needs (investigation skills, debugging skills) — too much branching to script

## Anti-patterns

| Anti-pattern | Why it's wrong | What to do instead |
|---|---|---|
| Put `claude -p` on the Firebat | Permission-gate failures, NR MCP OAuth doesn't survive headless, token spend on a cron | Tier 1 pure script |
| Skip the laptop tier | "Just SSH to Firebat" fragile when traveling | Tier 2 mirror |
| Cache-stale silently used | Consumer thinks data is fresh, isn't | Surface staleness explicitly (`/daily-scope` Step 2ba does this) |
| LLM tier doesn't diagnose | Tiers 1-2 stay broken across runs, every morning quietly costs tokens | LLM-fallback patches the script before exiting |
| Convert a judgment-heavy skill | Lose the qualitative narration, brittle thresholds | Stay LLM, run on-demand only |
| Sink-write but no dashboard render | Data silently piles up, never surfaced | Add to `prebuild.js` `renderCodeHealth` `order` array (see `/repo-scan` 9-signal addition) |

## Reference implementations

Worked examples — read these before designing a new one:

| Routine | Tier 1 | Tier 2 | Tier 3 | Status |
|---|---|---|---|---|
| `/dashboard-check` | `~/bin/run-dashboard-check.sh` (hourly) | `/dashboard-check` skill (de-LLM) | n/a — already pure script | ✅ converted 2026-04-27 |
| `/repo-scan` | `~/bin/repo-scan` (in morning-prep) | `~/bin/repo-scan` on laptop | SKILL.md Step 0 fallback | ✅ converted 2026-04-30 |
| `/autopatrol-cleanup-lambda-check` | `~/bin/autopatrol-cleanup-check` | TBD (after Firebat IAM) | SKILL.md Step 0 fallback | 🔄 in progress 2026-04-30 |
| `/autopatrol-overnight-check` | TBD | TBD | SKILL.md Step 0 fallback | ⏳ next |
| `automation-jira-sync` | TBD | TBD | TBD | ⏳ pending investigation |
| `pr-review-digest` (new) | TBD | TBD | n/a — script-only, no skill | ⏳ planned |

## Why this pattern wins

1. **Cost** — for routine checks, tokens add up. `/repo-scan` ran 7×/week × ~$0.05 = ~$18/yr; converted, $0/yr. Across ~5 morning skills, ~$100/yr saved.
2. **Reliability** — scripts don't depend on MCP server health, OAuth refresh, prompt-cache state, model availability. They run or they fail with a clear stderr.
3. **Latency** — `/repo-scan` LLM version: ~90s. Script version: ~4s. Across the morning batch the cumulative gain is minutes.
4. **Cron-friendly** — pure scripts have honest exit codes and no permission gates. They survive headless invocation. Dashboard signals refresh hourly instead of daily.
5. **Self-healing** — Tier 3's diagnostic responsibility means every fallback run improves the scripts. Drift gets fixed automatically.

## Related

- [[2026-04-30_morning-prep-scripts-runbook]] — operational runbook for every Tier-1 script (per-script playbooks, common errors, cred rotation procedures)
- [[2026-04-30_firebat-script-conversion-candidates]] — per-skill conversion inventory + payback estimates
- [[2026-04-23_firebat-minipc-as-claude-dev-box]] — the Firebat as a deployment target architecturally
- [[2026-04-24_minipc-dashboard-static-gen-refactor]] — the static-render architecture sink signals plug into
- [[skill-dashboard-check]] — first conversion (proof-of-concept)
- [[skill-repo-scan]] — second conversion (scoring + dashboard signal integration)
- [[skill-daily-scope]] — primary consumer (Step 2b/2ba cache-first patterns)
- `~/.claude/CLAUDE.md` — section "Routine Checks: Three-Tier Pattern" — operational rules version of this synthesis
