---
title: "/app/repos dashboard — follow-up backlog (post Phase 2)"
type: concept
topic: personal-laptop
tags: [handoff, dashboard, repos, code-health, dashboard-check, signals, minipc, followups]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
status: queued
incoming:
  - topics/personal-laptop/notes/concepts/2026-04-29_minipc-api-surface.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# /app/repos dashboard — follow-up backlog

End-of-session capture of every deferred item for the `/app/repos/` + `dashboard-check` code-health stack. Ordered by *when this should be picked up* (not by raw value).

## Context

As of 2026-04-29 the dashboard tracks **16 repos** (Actuate ecosystem on `mork-firebat`) with **43 signals** in the catalog (10 code-health + 1 infra-health + AWS / NR / minipc-local). Phase 2 of [[2026-04-27_handoff-repos-architectural-dashboard]] is closed; per-repo cards on `http://mork-firebat/app/repos/` carry a Code health table, the page header has a leaderboard. Source-of-truth for endpoint discovery is `/app/endpoints/` ([[2026-04-29_minipc-api-surface]]).

## Queued for ~2026-05-06 (after 7d of sink history)

The signal sink at `~/Documents/worklog/dashboard/sink/observations.jsonl` accrues one observation per signal per hourly cron. Several follow-ups need a stable history before they're meaningful — picking them up earlier means coding against thin data.

- [ ] **Per-repo deltas vs prior week** — render `↑ +12 (last 7d)` or `↓ −3` next to each value on `/app/repos/` cards. Implementation: `prebuild.js` `loadCodeHealth()` already reads the sink; extend it to walk back 7d for each (signal, repo) pair, compute delta, and pass to `renderCodeHealth()`. Treat `↑` on count signals as red-tinted.
- [ ] **Sparkline per metric on each card** — tiny SVG, 7d×24h = 168 datapoints. Reuse the existing `sparkline()` helper at `prebuild.js:282`. Renders inline next to the metric value column.
- [ ] **Drilldown detail page per metric** — sortable table across all repos, sparklines, regression annotations. URL like `/app/repos/health/<metric>/`. Use 11ty data files driven from the sink. Pairs with the existing dashboard-check `components/<component>.html` drilldown convention.
- [ ] **Calibrate vulture / radon / ruff thresholds against 7d distribution** — current thresholds anchored to day-1 baselines. Pull p75/p95 across the week per repo, retune `yellow_above` / `red_above`. Cookbook §"Calibration cookbook" is the reference.
- [ ] **Recalibrate FACET-classify behavior** — currently FACET dict signals classify as `informational` regardless of per-key thresholds. `render.py::classify()` could check `max(values) > yellow_above` etc. Worth doing once we know empirically that thresholds are right. Without this, `/dashboard/` doesn't surface code-health regressions in its summary line — only the leaderboard does.

## Backlog (no time gate)

Sorted highest-leverage first.

- [ ] **Per-workflow CI failure rate** — current `repo_ci_failure_rate_pct` collapses all workflows into one number. A repo with one chronically-broken workflow + 3 healthy ones reads as ~25% even though 3 of 4 are fine. Split: emit one signal per `(repo, workflow)` pair, or extend the existing signal to a nested FACET `{repo:workflow: pct}`. Either way, catalog gets noisier — keep current single signal as the at-a-glance health, add per-workflow as drilldown only.
- [ ] **Repo-config drift detection** — does each repo have CLAUDE.md? `.pre-commit-config.yaml`? `.github/workflows/ci.yml`? An expected `pyproject.toml` section? Boolean checks per repo, FACET dict `{repo: 1}` for missing-this-thing signals. Captures process-debt — the org has standards that need enforcement.
- [ ] **Last-release age per repo** — `gh release list --json createdAt`. Useful for repos that tag releases (libraries especially); less useful for trunk-deploy services. Threshold yellow_above=60, red_above=180 days. Minor cost (1 API call/repo).
- [ ] **Open-issue count + p50 age** — pairs with PR signals. `gh issue list --state open --json createdAt`. Captures *bug-debt* the way open-PR-age captures review-debt.
- [ ] **Branch-protection drift** — does `main` (or default) have `required_status_checks` configured? `gh api repos/<slug>/branches/<default>/protection`. Boolean per repo, surfaces governance gaps.
- [ ] **uv-lock / package-lock freshness** — `git log -1 --format=%cs <lockfile>` per repo; days since last bump. Correlates with stale-deps risk.
- [ ] **Coverage signal** — only meaningful if repos publish coverage to a known location (Codecov, S3, in-repo report). Requires per-repo wiring; defer until a customer needs it.

## Operational gaps observed during build

- [ ] **`repo_actuate_pullers_pin` only sees vms-connector** — could fold into a single pin-drift signal that emits `{<repo>:<pkg>: pin_str}` with composite keys, reducing 3 thin signals to 1 informative one. Tradeoff: drilldown loses per-package focus. Decide after watching usage.
- [ ] **Vulture threshold revisit on Django repos** — even at `--min-confidence 80`, `actuate_admin` and `actuate_monitoring_api` mid-cluster could absorb a per-repo allowlist file (`.vulture.toml` or `whitelist.py`). Better than a global threshold tweak. Not urgent.
- [ ] **`signal.actuate.ai` and `test.actuate.ai` failed TLS probes** during the SSL signal seed. Possibly internal-only or a different port. If they're customer-facing, add to `ssl_cert_days_until_expiry` `hosts:` list once routing is confirmed.
- [ ] **vms-connector's 229 stale branches and actuate-inference-api's 724-day-old open PR** — flagged by the new signals 2026-04-29; both worth a separate cleanup pass. Surfaced via the dashboard, not yet actioned.

## Architecture / hygiene

- [ ] **dashboard-check tests** — only the original 28-signal classification fixtures exist. Each `git_local` signal should have a replay test against a known fixture-repo (synthetic git tree on disk?). Cookbook §"Add a test fixture" is the model.
- [ ] **Collect runtime profiling** — collect time grew 25s → ~80s as code-health scaled. Vulture is the long pole at `--min-confidence 80`; could parallelize the per-repo dispatcher (current loop is serial). Trivial speedup if it bites.
- [ ] **gh API rate-limit watcher** — at 16 repos × 3 gh-using signals = 48 calls/hour. Comfortably under 5000/hr. But a 16 → 32 repo expansion + a new gh-based signal would push it. Add a meta-signal that surfaces `gh api rate_limit` headers if it ever crosses 50%/hr.

## Related notes

- [[2026-04-27_handoff-repos-architectural-dashboard]] — original Phase 1 design + Phase 2 scope
- [[2026-04-28_handoff-repos-dashboard-phase-2-code-health]] — Phase 2 source-class decision, status `complete`
- [[2026-04-27_dashboard-signal-cookbook]] — canonical signal-add pattern (now includes git_local + tls_cert recipes)
- [[2026-04-29_minipc-api-surface]] — endpoint discovery (cross-session)
- mark-todos §12j — workstream entry, currently `[x]` (re-flip if any of the above grows past a one-line edit)
