---
title: "Minipc tooling improvements — 2026-04-27 batch"
type: synthesis
topic: personal-laptop
tags: [minipc, dashboard-check, obsidian, kb-lint, claude-usage, observability, automation]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Minipc tooling improvements — 2026-04-27 batch

A productive day of mostly-additive changes to the always-on Claude dev box. Each section below is a discrete piece of work; cross-link them when extending or debugging. Companion notes: [[2026-04-27_iam-rolesanywhere-minipc]] (auth setup), [[2026-04-27_dashboard-signal-cookbook]] (signal-add patterns).

## Patterns established (durable, reusable)

### 1. Two-repo DR split

Two private GitHub repos now mirror everything reproducible:

- `aegissystems/actuate-dev-toolkit` ← `~/work/local_network_scripts/` (provisioning + minipc app code + helper scripts)
- `actuateMark/claude-config` ← `~/.claude/` (skills + agents + hooks + global config)

Allowlist `.gitignore` on `claude-config` is **deny-by-default**: only `agents/`, `skills/`, `hooks/`, `CLAUDE.md`, `kb-config.md`, `policy-limits.json`, `settings.json` and the README are tracked. Everything else (projects/, history.jsonl, paste-cache, .credentials.json, etc.) is denied. **Pre-commit secret-scan is mandatory** — used `gitleaks` + a targeted-pattern script (`/tmp/scan-staged.sh`) to verify zero secrets in the staged set before pushing.

Disaster recovery procedure: clone both repos on a fresh laptop, recreate secrets per the listing in each README, run `provision-host.sh TARGET=user@new-firebat`. Minipc rebuilds itself from rsync.

### 2. De-LLM cron pattern (skill → script)

Pattern applied to `/dashboard-check`, `/kb-recap`, `/kb-lint`, `/recap`-eligible. Replaces `claude -p "/skill"` cron invocations with direct Python execution where the skill is mechanical (no reasoning, just data-fetch + classify + emit).

Architecture:
1. Skill keeps its `SKILL.md` (still useful for ad-hoc + drill-down)
2. Add a Python script in the skill dir that does the mechanical work — `collect.py`, `kb-lint.sh` (Python despite the .sh), etc.
3. Add a subcommand to the skill's `run.sh` (e.g. `run.sh collect --tempdir X`)
4. minipc cron wrapper invokes the run.sh subcommand, not `claude -p`
5. Output written to predictable filesystem paths; consumed by 11ty's `prebuild.js` or static HTML generators

Outcome: cron runs are ~25s instead of ~3-5 min, no MCP-allowlist flakiness, no `claude -p` token spend, all-Python error handling. Tracked in [[2026-04-24_skills-audit-script-candidates]].

### 3. Minipc as observability cache (kill the morning-routine NR-login pain)

`/dashboard-check` runs hourly on the minipc, writes per-signal observations to a sink JSONL, and the FastAPI app exposes `GET http://mork-firebat/app/api/observations` returning latest-per-signal as a single JSON. The laptop's `/daily-scope` morning routine reads this endpoint *first* via `~/bin/observations-snapshot --md` and only falls back to inline NRQL when the cache is stale (>65 min).

Result: morning routine that previously triggered ~21 separate NR-MCP queries now does **one HTTP GET**. NR query budget preserved. SKILL.md updated in `daily-scope/` with "Step 2ba — Read minipc observations cache" before the legacy preflight.

The pattern generalises: any operational signal we want to track can become a `dashboard-check` signal, get rendered, get cached at the endpoint, and surface in the morning routine without per-session re-querying.

## Specific ships

### Dashboard-check de-LLM + observability cache

- `~/.claude/skills/dashboard-check/collect.py` — NR via nerdgraph + AWS via Roles Anywhere boto3 + minipc-local via subprocess. 3 source-class dispatchers (NR, AWS, minipc_local), per-signal-id functions for AWS.
- `~/bin/run-dashboard-check.sh` rewritten — drops `claude -p`, calls `run.sh collect + render` directly. Treats render-exit 1 (yellow) and 2 (red) as success — only crash exits trigger systemd failure.
- Hourly cron (was daily). 28 enabled signals collect in ~25s.
- Observations endpoint at `/app/api/observations` (latest-per-signal) + `/app/api/observations/history?hours=N&signal_id=X` (raw history with optional filter).
- `~/bin/observations-snapshot` client — text/markdown/json output modes; exit 0/1/2/3 codes.

### minipc-local source type

New source class `minipc_local` for signals about the box itself. Signals: `minipc_failed_user_units`, `minipc_failed_system_units` (both FACET dicts so detail page lists which units), `minipc_unit_starts_24h`. collect.py shells out to `systemctl --user list-units --state=failed`, etc.

Surfaced one real signal: `systemd-networkd-wait-online.service` was chronic-failing post-NM-swap. Patched `phase-03-networkmanager.sh` to mask + reset-failed automatically on fresh provisions.

### Drill-down detail rendering

Signal drawer in `dashboard-check/render/macros.j2` extended with:
- `format_value` now shows top-3 facet preview inline (not just "15 items")
- `facet_breakdown` macro: full sortable table per FACET signal — every key with today/prior/Δ/new-or-gone flag
- `mini_sparkline` macro: tiny SVG plot for scalar+history signals
- `Prior-day comparison` drawer section for scalar signals

Gotcha: comparing today (dict) to prior (scalar — legacy from when the signal returned `count(*)` not FACET) requires gating `is_new`/`is_gone` on `has_prior_dict`, otherwise every row gets flagged "gone."

### kb-lint port

`local_network_scripts/files/kb-lint.sh` — pure-Python port of the `/kb-lint` skill. Walks vault, builds wikilink graph, emits broken-link / missing-frontmatter / orphan / stale findings. Json/md/text output modes.

Wikilink resolution handles:
- Exact rel-paths
- Topic-name refs (`[[ai-models/_summary|AI Models & Evaluation]]` → `topics/ai-models/_summary.md`)
- Sub-topic paths (`[[models/intruder-v5]]` → `topics/models/intruder-v5/_summary.md`)
- Date-prefixed shortlinks (`[[connector-library-deployment-lifecycle]]` → `2026-04-14_connector-library-deployment-lifecycle.md`)
- Strips fenced + inline code before parsing — avoids false positives on docs *about* wikilinks

Down from 740 false-positive errors to ~250 real broken links + ~150 missing-frontmatter.

### claude-usage indicator

`~/bin/claude-usage` walks `~/.claude/projects/*/*.jsonl`, sums today's + last-7d sessions/messages/tokens, checks `pgrep` for live claude + `tmux has-session -t main`. JSON / markdown / text modes. Wired into `prebuild.js` `genClaude()` so `/app/claude/` regenerates inline at every rebuild-blog tick. **Open follow-up**: % remaining vs subscription quota — Anthropic doesn't expose programmatic quota; needs a configurable limit file.

### /app/today linkification

`prebuild.js` `genToday()` now post-processes the kb-recap output: `` `topics/X/Y.md` `` becomes a `<a href="/app/kb/X/Y">` link to the Quartz-published page. One-click navigation from daily recap to rendered note.

### Obsidian Sync container fix (the big one)

Fixed a 4-day stale-sync incident that defeated the whole "minipc as live KB mirror" premise.

**Root cause:** sytone/obsidian-remote container had Obsidian's workspace-state pointed at `/config/work` (an empty container-internal volume) instead of `/vaults/work` (the host-mounted real vault). Sync was running fine, just pairing against an empty vault.

**Fix:**
1. Edited `/home/mork/.config/obsidian-remote/.config/obsidian/obsidian.json` to add a vault entry pointing at `/vaults/work` and close the old `/config/work` entry.
2. Patched `phase-08-obsidian.sh` to pre-seed the workspace state on first install, parameterise `VAULT_NAME`, and rsync the FULL vault (with `.obsidian/`) instead of just the `knowledgebase/` subfolder.

**Bonus secondary issue:** the bundled Oct-2022 Obsidian AppImage in the image is too old for current Obsidian Sync auth. Solved by:
1. Extracting Obsidian v1.12.7 AppImage into `/config/obsidian-1.12.7/` (idempotent in phase-08)
2. Bind-mounting `/home/mork/.config/obsidian-overrides/autostart` over `/defaults/autostart:ro` in the docker run command. The bind-mount supplies a launch command pointing at `/config/obsidian-1.12.7/obsidian` instead of the bundled binary. Works around an LSIO `cont-init.d` bug (`[[ ! -d <file> ]]` is always-true → overwrites our edits to `/config/.config/openbox/autostart` on every restart).

## Files inventory

**actuate-dev-toolkit** (commit `a9ac9b3` at handoff time):
- `files/kb-lint.sh` (NEW)
- `files/claude-usage.sh` (NEW)
- `files/run-dashboard-check.sh` (rewritten — de-LLM)
- `files/run-dashboard-check.timer` (hourly, was daily)
- `files/observations-snapshot.sh` (NEW)
- `phase-03-networkmanager.sh` (mask networkd-wait-online)
- `phase-08-obsidian.sh` (vault path fix + workspace pre-seed + AppImage extract + autostart override bind-mount)
- `phase-13-tasks.sh` (kb-recap deploy in lieu of run-kb-recap timer)
- `minipc-blog/scripts/prebuild.js` (genToday linkify, genClaude added)
- `minipc-blog/content/admin.md` (updated quick-ref)
- `minipc-app/main.py` + `routes/observations.py` (observations endpoint)
- `minipc-app/templates/kb_query.html` (loading-spinner UX fix from earlier)

**claude-config** (commit `d52d6a4` at handoff time):
- `skills/dashboard-check/collect.py` (NEW)
- `skills/dashboard-check/run.sh` (collect subcommand)
- `skills/dashboard-check/requirements.txt` (boto3 added)
- `skills/dashboard-check/config/signals.json` (5 k8s signals + 3 minipc_local + parser fixes)
- `skills/dashboard-check/render.py` (prior_value field + local_results.json merge)
- `skills/dashboard-check/render/macros.j2` (facet_breakdown + mini_sparkline + format_value preview)
- `skills/dashboard-check/css/dashboard.css` (drill-down styling)
- `skills/daily-scope/SKILL.md` (Step 2ba — observations cache)

## Known follow-ups (open at handoff)

| # | Title | Status |
|---|---|---|
| 69 | /app/repos/ → architectural dashboard | **Phase 1 SHIPPED 2026-04-28** (toolkit commit `605f604`). 7 repos cloned to `~/work/` on minipc; `git-fetch-major-repos.timer` hourly; rich render at http://mork-firebat/app/repos/. Phase 2 (code-health overlays) still pending — see [[2026-04-27_handoff-repos-architectural-dashboard]] §"Phase 2". |
| 70 | R&D auto-research surface | Pending; full design notes in [[2026-04-27_handoff-rd-autoresearch]] |
| (no #) | gh auth on minipc still expired | **CLOSED 2026-04-28** — replaced with per-host classic PAT via new `phase-15-secrets.sh` reading `~/.config/minipc-secrets/github-pat`. Decoupled from laptop reauths; no expiration. See [[2026-04-28_long-lived-credentials-on-headless-boxes]]. Same batch also dropped tailscale `--ssh` (was triggering daily browser-check reauth). Toolkit commit `84109f6`. |
| (no #) | claude-usage % remaining quota | Pending — Anthropic `/usage` returns prose, not parseable; needs configurable-limit file approach |

## Related

- [[2026-04-27_iam-rolesanywhere-minipc]] — AWS auth used by dashboard-check + future workloads
- [[2026-04-27_dashboard-signal-cookbook]] — how to add new signals (now includes minipc_local pattern)
- [[2026-04-24_skills-audit-script-candidates]] — the skill-to-script pivot decision tree
- [[2026-04-24_minipc-dashboard-static-gen-refactor]] — Quartz/11ty/FastAPI dashboard architecture
- [[2026-04-23_firebat-minipc-as-claude-dev-box]] — the box this all lives on
