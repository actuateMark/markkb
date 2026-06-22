---
title: "Host: firebat (personal devbox)"
type: entity
topic: compute-fleet
tags: [compute-fleet, firebat, devbox, tailnet, personal, tier-1, dashboard]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: active
incoming:
  - topics/compute-fleet/_summary.md
  - topics/compute-fleet/notes/entities/host-laptop.md
incoming_updated: 2026-05-05
---

# Host: firebat (personal devbox)

Mark's personal always-on mini-PC, role: Tier-1 cron host + dashboard server + LAN-side workstation. The "always-on" half of [[../../engineering-process/_summary|the three-tier routine pattern]] — runs the scheduled jobs that the laptop is too sleep-prone to handle reliably.

## Hardware

(Fill in from `~/work/local_network_scripts/baselines/` next time on the box; not yet captured here.)

| Component | Spec |
|---|---|
| Form factor | Mini PC |
| CPU | Intel (model TBD — capture from `lscpu`) |
| RAM | TBD |
| Disk | TBD |
| OS | Ubuntu / Debian (TBD) |
| Network | Wired ethernet to home LAN; on personal tailnet |

## Role on the personal tailnet

- **Tier-1 cron host** — runs `~/bin/jira-sync.sh`, `repo-scan`, `morning-prep.sh`, `kb-recap`, `kb-relink`, `run-dashboard-check.sh`, `pr-review-digest`, etc. via systemd `--user` timers
- **Dashboard server** — local static-HTML operational dashboard at `~/Documents/worklog/dashboard/`; served via Caddy at `http://firebat/dashboard/` and `http://firebat/app/api/observations`
- **KB sync target** — Obsidian vault syncs here automatically; KB-side jobs (`kb-relink`, `kb-recap`, `kb-lint`) run against the local copy
- **Quartz / blog rebuild** — `rebuild-blog.sh`, `rebuild-quartz.sh` scheduled
- **Always-on signal** — laptop's `/daily-scope` reads cached digest stdouts from firebat at `~/.local/state/claude-jobs/<job>-<date>.stdout` (HTTP path `http://firebat/logs/...`)

## Access

- **SSH**: `ssh mork-firebat` (alias in `~/.ssh/config` on the laptop) — direct ethernet via IPv6 link-local on `enp0s31f6`, OR over tailnet
- **User**: `mork`
- **Tailnet identity**: TBD — capture next time on box
- **Tailnet name**: TBD (`mork-firebat.<personal-tailnet>.ts.net`)

## Cross-references

- [[compute-fleet/_summary|fleet topic]]
- [[engineering-process/_summary]] — three-tier pattern; firebat is the Tier-1 host
- `~/work/local_network_scripts/files/` — the actual scripts that run here
- `~/work/local_network_scripts/phase-13-tasks.sh` — provisioning script that pushed scripts + systemd units to this box

## Open work for this entity

- [ ] Fill in hardware specs (CPU model, RAM, disk) — `lscpu`, `free -h`, `df -h /` next time on box
- [ ] Capture personal-tailnet name + IP
- [ ] List all running systemd `--user` timers + their cadences
- [ ] Cross-link from [[../../personal-laptop/_summary|personal-laptop]] (legacy topic) — eventually migrate firebat-specific content here from there
