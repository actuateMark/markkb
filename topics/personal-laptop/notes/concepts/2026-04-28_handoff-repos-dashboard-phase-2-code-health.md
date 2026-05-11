---
title: "Handoff — /app/repos Phase 2 (code-health signals)"
type: concept
topic: personal-laptop
tags: [handoff, dashboard, repos, code-health, dashboard-check, signals, minipc]
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
status: complete
outgoing:
  - topics/personal-laptop/notes/concepts/2026-04-29_minipc-api-surface.md
  - topics/personal-laptop/notes/concepts/2026-04-29_repos-dashboard-followups.md
  - topics/personal-notes/notes/daily/2026-04-28.md
  - topics/personal-notes/notes/daily/2026-04-29.md
incoming:
  - topics/personal-laptop/notes/concepts/2026-04-29_minipc-api-surface.md
  - topics/personal-laptop/notes/concepts/2026-04-29_repos-dashboard-followups.md
  - topics/personal-laptop/notes/concepts/2026-05-07_handoff-dashboard-threshold-calibration.md
  - topics/personal-notes/notes/daily/2026-04-28.md
  - topics/personal-notes/notes/daily/2026-04-29.md
incoming_updated: 2026-05-08
---

# Handoff — /app/repos Phase 2 (code-health signals)

A fresh session can pick up cold from this note. Phase 1 shipped 2026-04-28 in toolkit commit `605f604` — see [[2026-04-27_handoff-repos-architectural-dashboard]] for design and [[2026-04-28_long-lived-credentials-on-headless-boxes]] for the auth-gate work that unblocked it.

## Phase 2 progress (2026-04-28)

- ✅ **Source-class decision: Pattern A — new `git_local` source class** (per-repo metrics are semantically distinct from per-host `minipc_local`). Dispatcher in `~/.claude/skills/dashboard-check/collect.py` (`collect_git_local_signals`) reads repos.json once, iterates `~/work/<name>/`, returns FACET `{repo_name: value}`. Optional `repos: ["all"]` (default) or `repos: ["vms-connector", ...]` scopes per-signal. `render.py::merge_results` updated to pick up `git_results.json`.
- ✅ **Signal #1 — `repo_todo_fixme_count` shipped.** `rg --count-matches '\b(TODO|FIXME)\b'` per repo, .gitignore-respected, 30s timeout. Live on dashboard, `/app/api/observations`, sink JSONL. Initial values: actuate-libraries=59, vms-connector=42, [[actuate_admin]]=27, autopatrol-server=7, connector_deployer=1, others=0. Thresholds 500/1500 (conservative, recalibrate after 7d).
- ✅ **Signal #2 — three pin signals shipped** (claude-config commit `8213967`): `repo_actuate_frames_pin`, `repo_actuate_filters_pin`, `repo_actuate_pullers_pin`. FACET `{repo: pin_spec}`, only repos that pin the package show up. Parses pyproject.toml (PEP 621 list and Poetry/uv key=value forms) plus requirements.txt; workspace = `true` declarations skipped. Day-1 drift visible: vms-connector pins `actuate-filters==2.0.4` while [[actuate_admin]] pins `~=2.0.0`. Status is `informational` (string values can't classify); `new_pattern` regression rule flags day-over-day pin changes. Collector tweak: `None` returns drop from FACET dicts so unpinned repos don't render as `None` rows. Catalog grew 31 → 34 enabled.
- ✅ **Tooling deps installed on minipc** — `radon` 6.0.1, `ruff` 0.15.12, `vulture` 2.16 via `uv tool install`. `phase-06-base-tooling.sh` updated with the install snippet (uses `--default-index https://pypi.org/simple/` + env-clean to dodge the laptop's CodeArtifact-pinned env vars that leak in via rsync). Idempotent — re-runs are no-ops. Each tool ~7 MB venv at `~/.local/share/uv/tools/<name>/`; shim at `~/.local/bin/<name>`.
- ✅ **Signals #3, #4, #5 shipped together** (claude-config commits TBD-pending-push): `repo_radon_cc_hotspots` (CCN ≥ 11 grade-C+ functions), `repo_ruff_unused_imports` (F401 violations), `repo_vulture_dead_code` (likely-unused symbols). FACET `{repo: int}` per signal. Day-1 baselines (2026-04-29) anchor each signal's thresholds — see `signals.json` description. Collector tweak: prepend `~/.local/bin` to `PATH` at module import so subprocess calls find the tools regardless of invocation path (cron sets PATH; ad-hoc SSH doesn't).
- ✅ **Signal #6 shipped** — `repo_mtm_days_p50` — median days-to-merge across last 50 merged PRs per repo via `gh pr list --json mergedAt,createdAt`. Resolves the GitHub slug from each repo's `git config remote.origin.url`. 1 gh API call per repo per collect (7/h, well under 5000/h authenticated rate limit). Day-1: vms-connector p50 = 0.41 days (~10h); other repos near 0 because their merged PRs are mostly stage-bot autobumps. Catalog grew 34 → 39 enabled.
- ✅ **Phase 2 fully shipped end-to-end.** All 8 git_local signals live on `/dashboard/`, sink JSONL, and `/app/api/observations`. Cookbook updated with the source-class recipe + None-handling note. Total collect time ~1 minute; vulture is the long pole. KB pointer at [[2026-04-29_minipc-api-surface]] for cross-session discovery.

## What's already in place

After Phase 1 (live at http://mork-firebat/app/repos/):

- **`git-fetch-major-repos.sh`** (Python) on minipc, hourly via systemd timer. Maintains `~/work/<repo>/` partial clones (`--filter=blob:none`) for 7 repos. Per-repo state JSON at `~/.local/state/minipc-tasks/repos-detailed/<name>.json`, aggregate at `_index.json`.
- **`repos-config.json`** at `~/.config/minipc-repo-cron/repos.json` — editable on the box. Schema: `{name, slug, default_branch, extra_branches}`.
- **`genRepos()` in `minipc-blog/scripts/prebuild.js`** renders the cards.
- **PAT-authenticated git/gh** via `phase-15-secrets.sh` — clones use HTTPS + gh credential helper.

## What Phase 2 needs to do

Each "code health" metric becomes a [[2026-04-27_dashboard-signal-cookbook|`dashboard-check` signal]]. That gives us:
- Daily history + trend (sparklines) for free
- Drill-down detail rendering via existing `render/macros.j2`
- Surfacing on `/dashboard-check` *and* via the observations endpoint that `/daily-scope` reads
- Optional: render the latest value inline on each `/app/repos/` card by reading from the same observations cache

**Critical architectural note:** these are *per-repo* metrics. The existing dashboard-check source classes are `NR`, `AWS`, and `minipc_local` (system-level). We need a new source class **`git_local`** (or similar) that knows how to iterate over the repos in `~/.config/minipc-repo-cron/repos.json` and emit one observation per repo. Read the cookbook + existing `collect.py` before deciding the exact dispatcher shape — there may be a simpler way than a new source class (e.g. each metric is its own signal id with a per-signal dispatch function, like AWS already does).

## Concrete first steps for the new session

1. **Read the prerequisites (in order):**
   - This handoff (you're reading it).
   - [[2026-04-27_dashboard-signal-cookbook]] — the canonical signal-add pattern.
   - `~/.claude/skills/dashboard-check/collect.py` — current source-class dispatcher.
   - `~/.claude/skills/dashboard-check/config/signals.json` — example signal definitions.
   - `~/.claude/skills/dashboard-check/render.py` + `render/macros.j2` — how scalar/dict signals get rendered.
2. **Decide the source-class shape.** Two viable patterns:
   - **(A) New `git_local` source class.** Each signal has a `repos: ["vms-connector", ...]` list (or special "all"). The dispatcher reads `~/.config/minipc-repo-cron/repos.json` and runs the metric function over each repo, emitting a FACET dict with repo names as keys. Pros: signals are simple ("count_todos"); the dispatcher does the iteration. Cons: a new source class.
   - **(B) Reuse `minipc_local`, one signal id per metric.** Each function in `collect.py` opens `~/.config/minipc-repo-cron/repos.json`, iterates repos, emits a FACET. Pros: no new source class. Cons: signal-collector functions get more imperative.
   Pick whichever the cookbook's existing patterns lean toward.
3. **Ship signal #1 — TODO/FIXME counts** (the smallest viable first metric):
   - Use `rg "TODO|FIXME" --count` against each `~/work/<repo>/` directory.
   - One FACET dict signal: `repo_todo_fixme_count` with keys like `vms-connector`, `actuate-libraries`, etc.
   - Verify on `/dashboard-check`, on the observations endpoint, and (optional Phase-2.5) inline on the `/app/repos/` cards.
4. **Then signal #2 — library version drift.** Parse each repo's `pyproject.toml` (or `requirements.txt` for non-uv repos) for `actuate-libraries` and `actuate-frames` pins. Surface the highest version anyone's pinning vs the lowest. Two scalar signals (`max_actuate_libraries_version`, `min_actuate_libraries_version`) or one FACET dict keyed by repo.
5. **Then signals #3+ as per the handoff §Phase 2 ordering:** radon CC hotspots, ruff F401 unused-imports, vulture dead-code count, mean-time-to-merge per repo. Each is independent.

## Open decisions to surface to user

- **A vs B above** (new source class vs reuse minipc_local) — let the cookbook's existing patterns decide.
- **Signal cadence** — `dashboard-check` signals run on the dashboard-check timer (currently hourly per the 2026-04-27 batch). Code-health metrics rarely change hour-to-hour; daily would be sufficient. But aligning to existing cadence is simpler. Recommend: run them on the existing cadence; the trend lookback handles smoothing.
- **Inline render on `/app/repos/` cards.** Optional Phase-2.5: extend `genRepos()` to read latest values from `~/.local/state/minipc-tasks/observations/latest.json` (or wherever the observations cache lives — see cookbook) and add a "Code health" sub-section per card showing the latest value + sparkline. **Defer this until at least 2 signals are working** so we know what fits naturally.
- **Tooling installs.** `radon` and `vulture` need to be installed on the minipc — add to `phase-06-base-tooling.sh` or to the dashboard-check skill's `requirements.txt`. `ruff` is already widely available; check if it's there. **Plan deps before adding signals**, not as you go.

## Things that will trip the new session up

- **The minipc has partial clones (`--filter=blob:none`).** Most Python tooling reads files lazily from the working tree, so partial clone is transparent for `radon cc`, `ruff`, etc. — they just trigger lazy blob fetches the first time. Subsequent runs hit the local object cache. **If a tool needs the full history (e.g., MTM analysis via `git log -p`), partial clone may force per-blob downloads — slow.** Plan around this; for blame-based metrics, consider fetching the full history just for analysis runs.
- **Path conventions on minipc differ slightly from laptop.** `$HOME/work/<repo>` exists on both, but the minipc's clones aren't writable by the user's normal interactive flow (the timer owns them). If a metric needs to mutate state (`uv sync`, `pre-commit install`), do it in `/tmp/<repo>-analysis/` or with `git worktree add` — don't dirty the canonical clones.
- **`/repo-scan`-curated backlog notes are at `~/Documents/worklog/knowledgebase/topics/repo-backlog/notes/concepts/<name>.md`.** They contain prose-level analysis. Cross-link these from the dashboard-check signal drill-down where it makes sense (e.g., "TODO count is rising for X — open backlog cluster Y links 4 of these").
- **gh API rate limit is 5000/hr authenticated.** Most code-health metrics are local-only (no API calls), so this doesn't bite. But MTM-per-repo via `gh pr list --state merged` could rack up calls — batch and cache.

## Related

- [[2026-04-27_handoff-repos-architectural-dashboard]] — Phase 1 design + Phase 2 metric list (this handoff is the "let's actually do Phase 2" companion)
- [[2026-04-27_dashboard-signal-cookbook]] — signal-add pattern (canonical)
- [[2026-04-27_minipc-tooling-improvements]] — surrounding architecture (signals, observations cache, /daily-scope integration)
- [[repo-backlog/_summary]] — `/repo-scan`-curated per-repo issue clusters (cross-link target)
- mark-todos §12j — task tracker entry (sub-section under §12 *Minipc dashboard app*); flip the synthesis follow-up table from "Phase 1 SHIPPED, Phase 2 pending" to "fully closed" after Phase 2 ships
- Toolkit commits to date: `84109f6` (auth-gate fix), `605f604` (Phase 1 dashboard)
