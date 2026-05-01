---
title: "Handoff — /app/repos/ architectural dashboard (mark-todos §12j)"
type: concept
topic: personal-laptop
tags: [handoff, dashboard, repos, code-health, minipc]
created: 2026-04-27
updated: 2026-04-28
author: kb-bot
status: phase-1-shipped
incoming:
  - topics/personal-laptop/notes/concepts/2026-04-28_handoff-repos-dashboard-phase-2-code-health.md
  - topics/personal-laptop/notes/concepts/2026-04-29_repos-dashboard-followups.md
  - topics/personal-laptop/notes/syntheses/2026-04-27_minipc-tooling-improvements.md
  - topics/personal-laptop/notes/syntheses/2026-04-28_long-lived-credentials-on-headless-boxes.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/2026-04-28.md
  - topics/personal-notes/notes/daily/2026-04-29.md
incoming_updated: 2026-05-01
---

> **Status update 2026-04-28 — Phase 1 SHIPPED** (toolkit commit `605f604`).
> The page at http://mork-firebat/app/repos/ now renders 7 repos × HEAD state + last 5 commits per branch + open PRs + conditional `/repo-scan` backlog link. Hourly `git-fetch-major-repos.timer` keeps it fresh; ~580 MB total disk on minipc with `--filter=blob:none`. Both auth gates closed in [[2026-04-28_long-lived-credentials-on-headless-boxes]]. **Phase 2 (code health overlays) section below remains the open work.**

# Handoff — /app/repos/ architectural dashboard (§12j)

A fresh session can pick up cold from this note. **Read this first**, then [[2026-04-27_minipc-tooling-improvements]] for the surrounding architecture, then the existing files mentioned below.

## What the user wants

Direct quote, 2026-04-27:

> I'd like to start on this repos page next. I have sketched out a general idea of where i want to take this (ideally this will grow into an architectural dashboard with all of the tooling we've mapped out). For now i'd just like to have the major repos hosted in a folder on the minipc ([[vms-connector|vms connector]], libraries, admin, deployer, etc) I think we may have copied them over already. I want to have a job that runs each day that pulls the latest changes on the default branch on each (and perhaps the stage branch on major ones like [[vms-connector|vms connector]]) and then displays that activity on this page. From there we will grow into the plans we have mapped out to track code health/cleanliness/etc.

URL: http://actuate-dev.local/app/repos/

## Two-phase scope

### Phase 1 — fetch + display recent activity (initial deliverable)

Replace what's there now (which renders a `collect-repos.sh` artifact) with a richer view backed by **bare clones on the minipc**. New flow:

1. **Bare clone the major repos** under `~/work/` on the minipc (or a dedicated `~/repos/`):
   - `vms-connector`, `actuate-libraries`, `actuate_admin`, `connector_deployer`, `actuate-inference-api`, `autopatrol-server`, `autopatrol_onboarder`
   - Initial set is in [[core-repo-suite]] (`topics/actuate-platform/notes/entities/core-repo-suite.md`) — confirm with user.
   - Verify which repos are already cloned during phase-07 (or the laptop's normal workflow) before re-cloning.
2. **Daily-fetch cron** — `git fetch && git pull --ff-only` on each repo's default branch + the stage branch on the majors (vms-connector, [[actuate_admin]] definitely; actuate-libraries probably).
3. **Render** at `/app/repos/`:
   - Per-repo last-pull timestamp + default-branch HEAD SHA + branch
   - Last 5 commits on default branch (subject + author + age)
   - Last 5 commits on stage branch (where applicable)
   - Contributor count (last 7d)
   - Branch count (informational)
   - Open PR count via `gh pr list --json` (requires `gh auth` re-do — see Gates below)
   - **Per-repo entry should link to the corresponding `repo-backlog/notes/concepts/<repo>.md`** which `/repo-scan` already maintains and curates issue clusters.

### Phase 2 — code health + cross-repo signals (architectural dashboard)

This is the "growth direction" the user mapped out. Defer until Phase 1 lands and we have the bare-clones + daily-fetch foundation. Then layer:

- **Code health metrics**:
  - Cyclomatic complexity (`radon cc`) — pattern already exists in §6 software-arch sketches; reuse the metrics collector
  - Type-checker issues (`pyright` / `mypy --reports`)
  - Test coverage delta
  - TODO/FIXME count over time (`rg "TODO|FIXME" --count` per file)
- **Cleanliness**:
  - Dead-code / unused-imports (`vulture`, `ruff F401`)
  - Duplicated-code estimates (`pylint --duplicate-code`)
- **Cross-repo signals**:
  - Library version drift — which connector/admin/etc. pin which `actuate-libraries`, `actuate-frames` versions. Surface drift between repos
  - CI flakiness rates per repo
  - Deployment frequency
  - Mean-time-to-merge per repo
- **Architectural overlays**:
  - [[dependency-graph|Dependency graph]] between repos (vms-connector → actuate-frames + [[actuate-daos]] + …)
  - Cross-repo refactor opportunities surfaced by `/repo-scan` ([[repo-backlog/_summary]])

These are *signals* — strong candidates to register as `dashboard-check` catalog entries via the `minipc_local` source type or a new `git_local` source. See [[2026-04-27_dashboard-signal-cookbook]] for the registration pattern.

## What already exists on the box

- **`/app/repos/`** route in 11ty — `minipc-blog/content/repos.md` is generated by `prebuild.js` `genRepos()` reading `~/.local/state/minipc-tasks/repos/latest.json`. That JSON is produced by `~/bin/collect-repos.sh` on a 30-min systemd timer.
- **`collect-repos.sh`** currently uses `gh` to query open PRs / issues across the user's actuate org repos. `gh auth` token is **expired** (see Gates).
- **`/repo-scan` skill** — already produces curated `topics/repo-backlog/notes/concepts/<repo>.md` files daily. Phase 1 should LINK to those, not duplicate them.

## Gates / dependencies

Before Phase 1 work starts:

1. ~~**gh auth on minipc** must be re-authed~~ **CLOSED 2026-04-28** — replaced with a per-host classic PAT installed by `phase-15-secrets.sh` from `~/.config/minipc-secrets/github-pat`. Decoupled from laptop reauths; doesn't expire. Architectural why in [[2026-04-28_long-lived-credentials-on-headless-boxes]]; how-to in [[2026-04-28_minting-github-pats-for-automation]]. Same batch dropped Tailscale `--ssh` so `ssh mork@mork-firebat` no longer requires browser reauth either.
2. **Confirm bare-clone set with user** — should the minipc clone the repos as bare or as full working trees? Bare clones save ~50% disk; working trees let you `git log` directly without --git-dir gymnastics. Recommendation: full working trees on the minipc since disk isn't tight (98G with 14G used) and tooling like `radon cc` needs the working-tree files.

## Concrete first session steps (recommended)

1. **Read this handoff + [[2026-04-27_minipc-tooling-improvements]]** for context.
2. **Audit current state**: `ssh mork@mork-firebat` and check `ls ~/work/` — what repos are already cloned there? (Phase-07 may have rsync'd a few; verify.) Check `gh auth status`. Read `~/bin/collect-repos.sh`.
3. **Re-auth `gh`** (interactive — user does it).
4. **Decide architecture**: bare clones in a dedicated dir, OR full clones in `~/work/` to mirror laptop layout? Mirror is cleaner for tooling reuse; clarify with user.
5. **Write `~/bin/git-fetch-major-repos.sh`** — iterates over a config list (defined in `~/.config/minipc-repo-cron/repos.json` or similar), runs `git fetch` + `git pull --ff-only` on default + stage branches, writes per-repo state JSON to `~/.local/state/minipc-tasks/repos-detailed/<repo>.json`.
6. **Write systemd user timer** — daily at e.g. 06:00 ET. Idempotent; logs to journal.
7. **Update `prebuild.js` `genRepos()`** to read the new per-repo JSON and render the richer view. Link each repo to `/app/kb/repo-backlog/notes/concepts/<repo>` (Quartz-published path of the repo-backlog curated note).
8. **Verify** http://mork-firebat/app/repos/ loads, links work, data is fresh.
9. **Add a task** for Phase 2 (code health metrics) once Phase 1 is stable.

## Open decisions to discuss with user

- Bare clones vs. full working trees on the minipc?
- Daily fetch is what user said; would hourly be too aggressive? (Rate-limit unlikely; gh API allows 5000 reqs/hr authenticated.)
- Should `/app/repos/` show ONLY tracked repos, or also surface "out-of-scope" repos that the user has cloned somewhere else? Probably tracked-only for now.
- For Phase 2 code health: which language ecosystems matter? Python is the bulk; node for `actuate_admin` frontend; Terraform for some repos. Prioritise Python first.

## Related

- [[2026-04-27_minipc-tooling-improvements]] — surrounding architecture this builds on
- [[2026-04-27_dashboard-signal-cookbook]] — how to register the eventual code-health signals
- [[2026-04-24_minipc-dashboard-static-gen-refactor]] — 11ty/Caddy/Quartz layout (where `/app/repos/` slots in)
- [[skill-repo-scan]] — already curates `repo-backlog/notes/concepts/<repo>.md` daily; Phase 1 should LINK to those
- [[core-repo-suite]] — canonical list of which repos are local vs. clone-on-need
- [[repo-backlog/_summary]] — top-level for the curated per-repo notes
- mark-todos §12j — task tracker entry (sub-section under §12 *Minipc dashboard app*)
- [[knowledgebase/topics/software-architecture/_summary|software architecture tooling]] this project will grow into a first pass/local dashboard for parts of this overall code health ecosystem, it should be made with an eye towards that.
