---
title: "Firebat enhancements batch — 2026-05-07"
type: synthesis
topic: personal-laptop
tags: [firebat, dashboard, signals, autopatrol-cleanup, code-health, sparklines, drilldowns, mark-todos-closure]
jira: null
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-05-07_handoff-cleanup-lambda-interpretive-checks.md
  - topics/personal-laptop/notes/concepts/2026-05-07_handoff-dashboard-threshold-calibration.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

# Firebat enhancements batch — 2026-05-07

Closes [[mark-todos]] §11c, §12i.b, §12j batch items, plus a KB frontmatter hygiene pass. Four substantive deliverables + one cleanup.

## §11c — Auto-start Claude in persistent tmux

**Status:** shipped.

Updated `local_network_scripts/files/claude-session.service` to invoke a new wrapper `~/bin/start-claude.sh` (also added at `local_network_scripts/files/start-claude.sh`). The wrapper runs `~/.local/bin/claude` in a `while true` loop so a `/exit` or crash respawns the prompt. systemd unit set to `Restart=always`. Removed old reference to non-existent `start-claude-rc.sh`.

**Verification:** `ssh -t mork@mork-firebat tmux attach -t main` lands in a live Claude prompt.

**Billing impact:** idle Claude prompts consume no tokens — billing is per input/output, not per process — so this is token-free even though Claude is "always running."

**Deployment:** `phase-10-sessions.sh` updated to push the new wrapper.

---

## §12i.b — kb-recap port

**Status:** confirmed shipped (no new work).

`~/bin/kb-recap` was already deployed (md5 matches `local_network_scripts/files/kb-recap.sh`), and `prebuild.js` already invokes it inline at every blog rebuild tick. No superseded `run-kb-recap.{service,timer}` units exist. This was a confirmation pass.

---

## §12j batch — dashboard code-health follow-ups

Four items from the ~2026-05-06 queue in [[2026-04-29_repos-dashboard-followups]]. All landed 2026-05-07.

### D1 — FACET classify in render.py

`~/.claude/skills/dashboard-check/render.py` `classify()` now walks each value in a FACET dict and returns the worst per-key status (via new `_classify_numeric()` helper). Added 5 new tests: green/yellow/red per-key classification, empty dicts, all-pin-string dicts, below-thresholds.

**Effect:** code-health regressions now elevate the dashboard summary (not just the leaderboard). Tests pass remotely on Firebat.

### D2 — Per-repo 7d deltas on /app/repos/ cards

Extended `prebuild.js` `loadCodeHealth()` to track the closest-to-7d-old observation per signal, compute per-(repo, signal) delta, and emit `↑ +N (7d)` / `↓ −N (7d)` annotations next to current values. Tinted via new `.delta-bad` (red) / `.delta-good` (green) CSS classes in `app.css`.

### D3 — Sparklines per metric on cards

Reused the existing `sparkline()` helper (90×18 inline SVG). Extended `loadCodeHealth()` to emit `seriesByRepo[repo][sigId] = number[]` (last 7d, ~168 hourly samples), and `renderCodeHealth()` appends one inline sparkline per row.

### D4 — Per-metric drilldown pages

New `genRepoHealthDrilldowns()` writes 20 pages at `/app/repos/health/<sid>/`, one per numeric metric. Each is a sortable table of (repo, current value, 7d delta, 7d sparkline). Linkified the metric labels in the leaderboard column to point at drilldowns.

**Routing gotcha:** 11ty `permalink:` must NOT include the `/app/` prefix because Caddy's `handle_path /app/*` strips it before file lookup. First attempt 404'd because content was at `_site/app/repos/health/...` but Caddy looked under `_site/repos/health/...`. The existing `repos.md` got this right by relying on default 11ty permalink (no `/app/` in frontmatter). Drilldowns now use `/repos/health/<sid>/`.

Refactored `main()` to flatten gen-functions returning arrays.

---

## E — Cleanup-lambda check signal conversion

**Status:** wired into dashboard pipeline.

Added Python dispatchers in `~/.claude/skills/dashboard-check/collect.py` for 5 existing `cleanup_lambda_*` signals plus 2 new ones:
- `cleanup_lambda_dlq_depth` (existing)
- `cleanup_lambda_errors` (existing)
- `cleanup_lambda_would_patch_rate` (existing)
- `cleanup_lambda_actual_disable_rate` (existing)
- `cleanup_lambda_anomaly_reset_rate` (existing)
- `cleanup_lambda_main_queue_depth` *(new)* — SQS main queue, pairs with DLQ
- `cleanup_lambda_event_source_mapping_state` *(new)* — Lambda ESM state (1=Enabled, 0=Disabled); "is this pipeline alive at all" signal

Flipped `enabled: true` for all 7. Flagged a CloudWatch filter-pattern gotcha: literal `:` requires double-quote wrapping (`"anomaly: bucket="`), otherwise `InvalidParameterException`.

**Tier-3 skill update:** Added a Tier-0 preamble to `~/.claude/skills/autopatrol-cleanup-lambda-check/SKILL.md` pointing at the dashboard signals as the new lowest-cost path. The LLM skill is now reserved for interpretive bits (DDB drift, onboarder hotfix grep, deploy workflow integrity). Moves this workstream further along the [[2026-04-30_three-tier-routine-check-pattern]].

Note: the 7d anomaly-repeat-offenders signal stays `enabled: false` (would need a 7d log scan, not implemented; could be added later).

---

## Bonus — KB frontmatter hygiene sweep

**Found and fixed:** `kb-bot` had introduced orphan list items (`- topics/...`) directly under `author: kb-bot` in 102 KB notes — invalid YAML (list items dangling with no parent key like `incoming:`). Wrote a Python sweep (regex: list line whose preceding key has an inline value) and fixed all 102 (66 simple-pattern + 36 with `status:` inline + 2 stragglers on Firebat that hadn't synced yet).

**Result:** Quartz now builds clean: 733 input files, 2662 emitted, 25s, 0 errors (previously failing).

**Defect note:** worth flagging this as a recurring `kb-bot` pattern — likely needs a fix on the kb-bot side or a `kb-lint` check that catches it pre-publish.

---

## Cross-references

- [[2026-05-05_firebat-minipc-followups-context]] — §11 factor-out
- [[2026-04-29_repos-dashboard-followups]] — the §12j queue this drains
- [[2026-04-30_firebat-script-conversion-candidates]] — three-tier inventory (E moves cleanup-lambda further along Tier 1)
- [[mark-todos]] — §11c, §12i.b, §12j tracking
