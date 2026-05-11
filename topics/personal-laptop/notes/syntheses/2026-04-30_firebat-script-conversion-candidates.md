---
title: "Firebat scheduled tasks — script-conversion candidates"
type: synthesis
topic: personal-laptop
tags: [firebat, scripts, token-spend, automation, scheduled-tasks]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_firebat-minipc-followups-context.md
incoming:
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_firebat-minipc-followups-context.md
  - topics/personal-laptop/notes/syntheses/2026-05-07_firebat-enhancements-batch.md
  - topics/personal-notes/notes/daily/2026-05-06.md
incoming_updated: 2026-05-08
---

# Firebat scheduled tasks — script-conversion candidates

The Firebat (`mork-firebat`) runs several pre-arrival cron tasks via `systemd --user` timers. Some are pure scripts (no LLM calls); some still go through `~/bin/claude-run-skill.sh` which spins up a Claude Code session per invocation. This note inventories all of them, marks conversion status, and ranks the un-converted ones by token-spend payback.

## Inventory

| Timer | Cadence | Implementation | Tokens/run | Conversion status |
|---|---|---|---|---|
| `run-dashboard-check.timer` | hourly + boot | **Pure Python** (`run.sh collect/render`) | 0 | ✅ converted 2026-04-27 (was daily LLM, now hourly de-LLM) |
| `git-fetch-major-repos.timer` | hourly | **Pure shell** + `gh` CLI | 0 | ✅ never used LLM |
| `rebuild-blog.timer` | every 5 min | **Pure JS** (11ty + `~/bin/kb-recap` Python inline) | 0 | ✅ `kb-recap` is pure Python, no Claude |
| `rebuild-quartz.timer` | every 5 min | **Pure JS** (Quartz build) | 0 | ✅ never used LLM |
| `status-page.timer` | every 30s | **Pure shell** (`gen-status-page.sh`) | 0 | ✅ never used LLM |
| `morning-prep.timer` | Mon-Fri 06:00 ET | **1 script + 2 Claude sessions** | ~$0.10-0.20/day | ⏳ 2 of 3 sub-skills still LLM |

After 2026-04-30 conversion sweep:
- ✅ **/repo-scan** → pure script (~/bin/repo-scan, Firebat + laptop)
- ✅ **automation-jira-sync** → pure script (was LLM-wrapped via claude -p; replaced inline at ~/bin/jira-sync.sh on both Firebat (Tier 1, 06:30 ET) and laptop (Tier 2, 10:37 ET); KB entity [[automation-jira-sync]] updated)
- ✅ **autopatrol-cleanup-check** → pure script (~/bin/autopatrol-cleanup-check on Firebat; IAM policy v2 applied 2026-04-30; 8/10 green, 1 informational, 1 yellow on Lambda duration_avg=1027ms which is at-baseline)
- ✅ **pr-review-digest** → new pure-script routine (no prior skill); ~/bin/pr-review-digest hourly on Firebat, integrated with dashboard
- ✅ **autopatrol-overnight-check** → pure script (~/bin/autopatrol-overnight-check on Firebat); NR-side only (k8s deferred); discovers sites dynamically via NRQL `capture()` since the SKILL.md's hardcoded site IDs went stale
- 🆕 **Three-tier pattern codified**: see [[2026-04-30_three-tier-routine-check-pattern]] + CLAUDE.md "Routine Checks: Three-Tier Pattern" — Firebat script → laptop script → LLM skill (which also self-heals scripts on fallback). All three autopatrol+repo-scan SKILL.md files updated with Step 0 preamble.

**Morning-prep is now fully script-driven** as of 2026-04-30. Total batch runtime: ~9 seconds (was ~10-15 minutes via LLM). Token cost: $0/day (was ~$0.10-0.25/day). The `claude-run-skill.sh` wrapper remains on Firebat as Tier 3 fallback only.

## Conversion priority — morning-prep skills

Ranked by `(token spend) × (convertibility)`. Highest value at the top.

### 1. `/repo-scan` — ✅ **CONVERTED 2026-04-30**

- **Token spend before:** ~$0.02-0.06 per run.
- **Token spend after:** **$0.** Runs in ~4 seconds end-to-end across 7 repos (188 open issues).
- **Implementation:** `~/bin/repo-scan` (Python) does fetch (parallel `gh issue list` ×7 for open + ×7 for closed-60d) + delegates scoring/KB to existing `curate.py` + writes 9 per-repo signals to the dashboard sink. Sibling to `~/bin/git-fetch-major-repos.sh`.
- **Deployed to:** Firebat (`~/bin/repo-scan`) + laptop (`~/bin/repo-scan`). The skill's SKILL.md (Step 0) now prefers the script and falls back to Firebat cache, only running the original LLM flow if both are absent.
- **Bonus:** added 9 issue-side dashboard signals (`repo_open_issues_count`, `*_high_impact_count`, `*_lhf_count`, `*_stale_count`, `*_oldest_age_days`, `*_p50_idle_days`, `repo_issue_churn_60d`, `*_p50_time_to_close_60d`, `*_close_rate_60d`) — these light up the per-repo cards and the code-health leaderboard at `/app/repos/`. Caught a real signal: vms-connector opens 29 issues / 60d, closes 0 = backlog growing fast.
- **morning-prep impact:** repo-scan step now runs in ~4s instead of ~90s (LLM); summary.json includes `"invoker": "script"` so daily-scope's Step 2b cache-check is unchanged.
- **Files:** `/home/mork/work/local_network_scripts/files/repo-scan.sh` (canonical), `~/.claude/skills/repo-scan/SKILL.md` (updated Step 0), `minipc-blog/scripts/prebuild.js` (new signal labels in renderCodeHealth + renderLeaderboard).

### 2. `/autopatrol-cleanup-lambda-check` — medium priority, medium effort

- **Token spend per run:** ~10K-25K input + 2K-5K output ≈ **~$0.05-0.10 per run** (~$13-26/yr).
- **What it does:** chain check across SQS / Lambda / DDB / Immix — confirms vms-connector emits → SQS delivers → Lambda consumes → DDB increments → threshold hits → would-disable / actual-disable rates.
- **LLM dependency:** mostly mechanical (NRQL queries + AWS CLI calls + threshold comparisons), with some judgment for the **interpretation** ("is this rate normal?").
- **Convertibility:** **MEDIUM.** Most checks are deterministic — pure Python could run all the queries and compare to thresholds. The interpretive layer ("is the queue depth elevated for time-of-day?") could be either:
  - Hard-coded thresholds (simplest, but stale fast)
  - A signal in `~/.claude/skills/dashboard-check/config/signals.json` so it integrates with the existing dashboard pipeline (best long-term — kills two birds)
- **Effort:** 4-8 hours. The "Onboarder Lambda liveness" check at the top is the trickiest — it currently relies on judgment about "log activity looks normal".
- **Recommendation:** **convert second.** The dashboard-pipeline integration would also let it become an hourly signal (much earlier detection).

### 3. `/autopatrol-overnight-check` — medium priority, higher effort

- **Token spend per run:** ~15K-30K input + 3K-7K output ≈ **~$0.07-0.15 per run** (~$18-39/yr).
- **What it does:** kubectl checks (cronjob health, pod state) + NR log queries + interpretation across 5 prod sites.
- **LLM dependency:** more judgment-heavy than cleanup-lambda — the skill walks through cronjob status, pod restart counts, recent NR errors, and synthesizes a per-site verdict.
- **Convertibility:** **MEDIUM.** Same pattern as cleanup-lambda — most checks are deterministic; some interpretation steps assume context. The per-site fan-out could become 5 dashboard signals (one per site).
- **Effort:** 8-16 hours. Most work in encoding the per-site judgment heuristics (what counts as "healthy" for site 41158 vs 45061 given different schedules).
- **Recommendation:** **convert third** (or skip and just live with the cost — the value of an LLM-narrated overnight summary on arrival may justify the spend).

## Suggested order of operations

If pursuing conversion:

1. **Now (this PR)**: morning-prep.sh wired up, all three running via Claude session — token spend acceptable in the short term.
2. **+1-2 weeks**: convert `/repo-scan` to a pure-Python `~/bin/repo-scan` script. Keeps the SKILL.md as documentation; the script becomes the cron-callable form. Updates `morning-prep.sh` to call the script directly when available, falling back to `claude-run-skill.sh` if not.
3. **+1 month**: extract `/autopatrol-cleanup-lambda-check`'s queries into dashboard signals — incremental, signal-by-signal, so partial conversion is fine.
4. **Later or never**: `/autopatrol-overnight-check` — the LLM-narrated form may be worth keeping for the daily morning summary even at $0.15/run.

## Cost ceiling — don't bother converting if

- Total spend stays under ~$50/yr (currently ~$25-65/yr for all three skills, weekday only).
- The conversion would lose the qualitative "judgment" layer that makes the morning summary actually useful (autopatrol-overnight in particular has this risk).
- A signal already exists in the dashboard pipeline that captures the same information at higher frequency (in which case retire the skill, don't convert it).

## Related

- [[2026-04-30_morning-prep-scripts-runbook]] — operational runbook for every Tier-1 script (per-script playbooks, common errors, cred rotation)
- [[2026-04-30_three-tier-routine-check-pattern]] — architectural rule the conversions follow
- [[2026-04-24_skills-audit-script-candidates]] — earlier audit when `/dashboard-check` and `/kb-recap` were converted
- [[2026-04-23_firebat-minipc-network-setup]] — Firebat provisioning history
- [[skill-daily-scope]] — primary consumer of the morning-prep cache (Step 2b cache-check, Step 2c autopatrol-cache language added 2026-04-30)
- `~/work/local_network_scripts/files/morning-prep.sh` — the orchestrator
- `~/bin/claude-run-skill.sh` — the headless wrapper (would be retired per skill as conversions complete)
