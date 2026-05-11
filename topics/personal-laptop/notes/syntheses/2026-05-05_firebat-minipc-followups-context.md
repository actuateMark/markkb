---
title: "Firebat minipc — workstream context (factored from mark-todos §11)"
type: synthesis
topic: personal-laptop
tags: [firebat, minipc, mark-todos-factored]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
outgoing:
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-laptop/notes/syntheses/2026-05-07_firebat-enhancements-batch.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

Factored out of mark-todos §11 on 2026-05-05 to keep the live workstream tracker lean. See [[mark-todos]] §11 for active checkboxes.

## Origin

§11 was seeded 2026-04-23 as the follow-up bucket from the "always-on Claude dev box" setup that turned the spare Firebat mini PC into a tailnet-reachable, linger-enabled, headless workstation. Core setup was complete and verified by 2026-04-23; this workstream tracks the enhancements layered on top (scheduled jobs, dashboard wiring, persistent tmux + Claude session).

## Hardware / network context

- **Box:** Firebat mini PC (`mork-firebat`), running as an always-on dev companion to the laptop.
- **Access paths:**
  - Tailscale (preferred): `ssh mork@mork-firebat`
  - Direct cable fallback: `ssh mork@fe80::8647:9ff:fe34:b4f2%enp0s31f6` (IPv6 link-local on `enp0s31f6`)
- **User-mode systemd with linger:** phase-02 of the toolkit enables `loginctl enable-linger mork`, so user timers fire without an active SSH session.
- **Toolkit:** `/home/mork/work/local_network_scripts/` — 12-phase install, reusable for future boxes via `TARGET=user@host` env var.
- **Source notes:** [[2026-04-23_firebat-minipc-as-claude-dev-box]] · [[2026-04-23_firebat-minipc-network-setup]]
- **Memory pointer (creds + URLs):** `~/.claude/projects/-home-mork-work-local-network-scripts/memory/firebat-minipc-access.md`

## Sub-workstream history and rationale

### 11a — Wire a specific scheduled Claude job

The `~/bin/claude-run-skill.sh` wrapper on the minipc is the scaffold for headless skill invocation. End-to-end smoke-tested 2026-04-23. Candidate skills for cron slots: `/overnight-check`, `/kb-auto`, `/dashboard-check`. Implementation pattern: systemd `.service` + `.timer` pair under `~/.config/systemd/user/`, enabled with `systemctl --user enable --now`. Linger from phase-02 is what makes this work without a login session. KB record-keeping: extend [[automation-overnight-check]] or seed a new `automation-minipc-timers` entity so we don't lose track of what's scheduled where.

Note: the three-tier routine-check pattern (see CLAUDE.md "Routine Checks") has since superseded the LLM-on-the-box approach. The Firebat now runs **pure-script** (Python/bash) cron jobs, not `claude -p`. Anything left under §11a should be re-cast as Tier 1 script work, not Claude invocations.

### 11b — Laptop-side dashboard sync → minipc *(superseded)*

Subsumed 2026-04-24 by §12e shipping a minipc-side daily `/dashboard-check` cron. Only the laptop-asleep continuous-poll case remains as a possible revisit.

### 11c — Auto-start Claude Code inside the persistent tmux session

Goal: on `tmux attach`, land directly in a ready Claude prompt. Two implementation options on the table:

- **Option A — modify the systemd ExecStart:** `tmux new-session -d -s main -c %h "claude"`. One-line change, auto-starts at boot. Downside: if `claude` exits, the tmux window closes with it.
- **Option B — watchdog timer:** poll for a `claude` process in the `main` session and spawn one if missing. More resilient, more moving parts.

Implementation lands as a patch to `files/claude-session.service` and/or a new `files/claude-watchdog.{service,timer}` in `~/work/local_network_scripts/`, then `phase-10-sessions.sh` is updated to push the chosen variant. Verification: reboot, wait 90s, `ssh -t mork@mork-firebat tmux attach -t main` should land in a live Claude prompt. *(2026-04-27 morning probe noted it was still down.)*

### 11d — Push-based dashboard ingest on minipc *(re-scope needed)*

Originally seeded 2026-04-24. §12e since shipped a minipc-side daily `/dashboard-check`, making the minipc the primary host. Open question: does the laptop also need to push (for travel / minipc-offline cases), or is the minipc's own daily run sufficient? Revisit once §12i closes.

Design sketch retained:
- Extend the minipc dashboard app (§12) with `POST /api/dashboard/snapshot`, `POST /api/dashboard/sink`, `GET /api/dashboard/latest`. Auth: Tailscale-mesh only.
- Laptop hook: after each `/dashboard-check` run, POST to the minipc.
- Store-and-forward outbox at `~/Documents/worklog/dashboard/.outbox/` with retry on push failure.
- Caddy routing: `http://actuate-dev.local/dashboard/` serves the latest snapshot regardless of source host.
- KB writeup: `topics/operational-health/notes/syntheses/<date>_dashboard-push-arch.md`.

### 11e — Cronify-friendly refactor of `/dashboard-check` *(largely overtaken)*

Partially superseded by §12e + §12i. Keep as design sketch; collapse or delete once §12i closes.

- Factor collector logic into `~/.claude/skills/dashboard-check/collect.sh` per source type.
- NR REST wrapper — **shipped 2026-04-27 as `~/.claude/lib/nr_query.py` via §13**. Reuse from there.
- `run-headless.sh` wrapper composing `collect.sh → render.py → push.sh`.
- systemd timer every 15–30 min on the minipc (and laptop as belt-and-braces).
- Interactive `/dashboard-check` stays as-is for human invocation.
- Verification target: after a week of cron, sink gains ~100+ rows/day organically.

## Related workstreams

- §9 Operational Dashboard — source of the dashboard artifact this work feeds
- §10 Laptop-config portability — sibling workstream on the laptop side
- §12 Minipc dashboard app — the target for §11d's push API
- §13 (archived [[2026-04-27]]) — REST wrappers reusable here
- Scripts + README: `/home/mork/work/local_network_scripts/README.md`
- [[2026-04-30_firebat-script-conversion-candidates]] — overarching inventory of which routine checks should run as Tier 1 scripts on the Firebat
- [[2026-04-30_three-tier-routine-check-pattern]] — architectural rationale for "no LLM on the box"
