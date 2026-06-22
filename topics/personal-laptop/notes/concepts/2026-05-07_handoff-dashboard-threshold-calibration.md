---
title: "Handoff — code-health threshold calibration against 7d distribution"
type: concept
topic: personal-laptop
tags: [handoff, dashboard, code-health, signals, calibration, dashboard-check]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
status: retired
incoming:
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming_updated: 2026-05-08
---

# Handoff — calibrate code-health thresholds against 7d empirical distribution

> **RETIRED 2026-05-07.** Calibration applied. Outcome: rejected pure p75/p95 statistical heuristic for *debt* signals (radon, ruff, stale_branches, todos, vulture) — instead dropped `red_above` entirely for those, since "unused imports" and "TODOs" have no alarm-grade quantity. Kept yellow/red split for *regression* signals (ci_failure 15/30, mtm 1/3, open_prs_age 15/60) where red means genuine alarm. Today's reds: ailink CI 35%, inference-api 714d PR, watchman 3.17d MTM — all legitimate. See [[2026-05-07]] § Notes/Learnings.

Queued in the §12j tail after the 2026-05-07 dashboard enhancements batch shipped per-repo deltas, sparklines, and per-metric drilldown pages ([[2026-05-07_firebat-enhancements-batch]]). This is the **analytical** follow-up that didn't fit in that session.

## Why

Current `yellow_above` / `red_above` thresholds in `~/.claude/skills/dashboard-check/config/signals.json` for code-health signals (`repo_vulture_dead_code`, `repo_radon_cc_hotspots`, `repo_ruff_unused_imports`, etc.) are anchored to **day-1 baselines** when the dashboard was first wired up. Two weeks of sink history later, the per-repo distributions are visible, and the thresholds either:

- Misclassify everything (e.g. a healthy Django repo always shows yellow because vulture's noise floor on it is genuinely higher than the threshold)
- Miss real regressions (a repo whose count crept past threshold weeks ago is now permanently yellow with no signal that it changed today)

The drilldown pages now show per-repo distributions live (`/app/repos/health/<sid>/`), so the human-loop verification is easier than before — eyeball a few drilldowns, decide, edit signals.json.

## Inputs

- **Sink:** `~/Documents/worklog/dashboard/sink/observations.jsonl` on Firebat (and laptop). Each line is one observation per signal. Filter by `component == "code-health"` for the relevant signals.
- **Signal catalog:** `~/.claude/skills/dashboard-check/config/signals.json` — the file you'll edit.
- **Drilldown pages:** http://mork-firebat/app/repos/health/`<sid>`/ — sortable per-repo view with current value, 7d delta, 7d sparkline. Reading these is the fastest way to gut-check a proposed threshold.
- **Cookbook:** [[2026-04-27_dashboard-signal-cookbook]] §"Calibration cookbook" is the canonical reference for the calibration ritual (it pre-dates this work; the recipe holds).

## Signals in scope

The followups note ([[2026-04-29_repos-dashboard-followups]]) called out vulture / radon / ruff specifically — those have the most room to be miscalibrated because they're noisy across language/framework boundaries. Full list of code-health metrics worth re-evaluating:

| Signal id | Current threshold (yellow_above / red_above) | Notes |
|---|---|---|
| `repo_vulture_dead_code` | check signals.json | Often false-positive-heavy on Django repos; consider per-repo allowlist file (`.vulture.toml`) before global tweak |
| `repo_radon_cc_hotspots` | " | "C+" complexity functions; baseline depends on codebase age |
| `repo_ruff_unused_imports` | " | F401; should be near-zero on actively maintained repos |
| `repo_todo_fixme_count` | " | Stable comparator across repos; less noise |
| `repo_stale_branches_count` | " | Distribution is *very* skewed (vms-connector at 229+) — mean is misleading, use median |
| `repo_open_prs_p50_age_days` | " | Days; threshold should reflect "what age is genuinely concerning" |
| `repo_mtm_days_p50` | " | Median time-to-merge; depends on team cadence |
| `repo_ci_failure_rate_pct` | " | Already collapses workflows into one number — threshold less meaningful until per-workflow split lands (separate followup) |
| `repo_open_issues_*` | " | Several variants; some already noisy at the high end |
| `repo_prs_pending_mark_review_count` | " | Personal queue depth — threshold should reflect realistic backlog tolerance |

## Procedure

1. **Compute distributions per signal.** One Python pass over the sink:
   ```python
   import json
   from collections import defaultdict
   from statistics import quantiles, median
   from pathlib import Path

   sink = Path.home() / "Documents/worklog/dashboard/sink/observations.jsonl"
   import datetime as dt
   cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=7)).isoformat()

   per_signal = defaultdict(lambda: defaultdict(list))  # sid -> repo -> [values]
   for line in sink.read_text().splitlines():
       if not line.strip(): continue
       obs = json.loads(line)
       if obs.get("component") != "code-health": continue
       if obs.get("timestamp", "") < cutoff: continue
       val = obs.get("value")
       if not isinstance(val, dict): continue
       sid = obs["signal_id"]
       for repo, v in val.items():
           if isinstance(v, (int, float)):
               per_signal[sid][repo].append(v)

   for sid, by_repo in per_signal.items():
       latest = sorted([(repo, vs[-1]) for repo, vs in by_repo.items()], key=lambda x: -x[1])
       print(f"=== {sid} ===")
       across_repo = [v for _, v in latest]
       try:
           q = quantiles(across_repo, n=4)
           print(f"  across-repo: p25={q[0]:.1f}  p50={q[1]:.1f}  p75={q[2]:.1f}  max={max(across_repo)}")
       except Exception:
           pass
       for repo, v in latest[:8]:
           vs = by_repo[repo]
           print(f"  {repo}: latest={v}  median={median(vs):.1f}  n={len(vs)}")
   ```

2. **Decide thresholds.** Heuristic starting point: `yellow_above ≈ across-repo p75`, `red_above ≈ across-repo p95`. Adjust by hand based on the drilldown view — the goal is "yellow flags top ~25% of repos as needing attention; red flags the genuine outliers."

3. **Sanity-check by counting flips.** Before saving, simulate: with proposed thresholds, how many (signal, repo) cells would change classification today? If >50% flip, the thresholds are probably too aggressive in one direction.

4. **Edit signals.json + sync to Firebat.**
   ```bash
   /home/mork/work/local_network_scripts/sync-claude-skills.sh --yes --skill dashboard-check
   ```
   The sync runs the test suite remotely; tests cover threshold-arithmetic correctness (post-2026-05-07 D1 changes also cover FACET-dict classification).

5. **Re-render dashboard and verify.** Trigger `~/bin/run-dashboard-check.sh render` on Firebat or just wait for the next hourly tick. Spot-check `/dashboard/` summary line — should now be more discriminating, not less.

## Edge cases / gotchas

- **Per-repo allowlists are sometimes the right answer, not threshold tuning.** vulture in particular has ~30 false positives per Django repo from `__init__.py` re-exports. A `.vulture.toml` allowlist on the noisier repos may make a global threshold workable; otherwise the threshold has to absorb the false-positive base rate, which dilutes the signal everywhere else.
- **Sparse repos.** Some signals only fire for repos with `actuate-*` pins or with active CI. Skip them in the distribution math (filter to repos with ≥3 observations in the 7d window).
- **Pin-string FACETs (`repo_actuate_frames_pin` etc.) have no thresholds and should not be touched.** They're informational-only.
- **Sink retention** is currently unlimited — a 7d window is conservative. If the sink ever gets pruned, this calibration becomes harder.

## When to retire this handoff

After thresholds are committed, drilldown pages should look "richer" — more variation in classification across repos. If everything is still uniformly green or uniformly yellow, the calibration is wrong, redo. Add a one-line entry to today's daily note `## Notes / Learnings` capturing what changed and why, and flip mark-todos §12j tail item.

## Related

- [[2026-04-29_repos-dashboard-followups]] — origin queue
- [[2026-04-27_dashboard-signal-cookbook]] §"Calibration cookbook" — canonical recipe
- [[2026-04-28_handoff-repos-dashboard-phase-2-code-health]] — Phase 2 design context
- [[2026-05-07_firebat-enhancements-batch]] — what shipped today (enables drilldown-driven calibration)
- `~/.claude/skills/dashboard-check/config/signals.json` — file to edit
- `~/Documents/worklog/dashboard/sink/observations.jsonl` — input data
