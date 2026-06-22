---
title: "Host: laptop (Mark's ThinkPad)"
type: entity
topic: compute-fleet
tags: [compute-fleet, laptop, thinkpad, tailnet, personal, primary-workstation]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: active
incoming:
  - topics/compute-fleet/_summary.md
  - topics/compute-fleet/notes/entities/host-actuate-dev.md
incoming_updated: 2026-05-05
---

# Host: laptop (Mark's ThinkPad)

Mark's primary day-to-day workstation. Where Claude Code runs, where Obsidian is the canonical KB editor, where IDEs and browsers live. **Not a Tier-1 host** (laptop sleeps too often for cron); the always-on duties run on [[host-firebat]].

## Hardware

| Component | Spec |
|---|---|
| Model | Lenovo ThinkPad P14s Gen 5 |
| Hostname | `mork-thinkpad-p14s-gen-5` |
| OS | Linux (TBD — capture from `/etc/os-release` next time) |
| RAM | TBD |
| Disk | TBD |

## Tailnet identity

| Field | Value |
|---|---|
| Tailnet | `tail9b2a4e.ts.net` (company) |
| Tailnet IP | `100.90.146.35` |
| Tailnet hostname | `mork-thinkpad-p14s-gen-5.tail9b2a4e.ts.net` |
| Tailnet user | `mark@` |
| Admin role | Non-admin (cannot generate auth keys, edit ACLs, enable HTTPS, etc.) |

## Role

- **Primary Claude Code surface** — `~/.claude/` lives here with skills, hooks, agents, MEMORY
- **Primary Obsidian editor** — vault at `~/Documents/worklog/`; the KB at `~/Documents/worklog/knowledgebase/` syncs to firebat via Obsidian Sync
- **IDE / browser / terminal host** — actual code-editing happens here
- **Tier-3 LLM tier** (per [[../../engineering-process/_summary|three-tier pattern]]) — when a routine check's Tier-1 script and Tier-2 fallback both fail, the laptop's Claude Code runs the LLM-driven equivalent
- **First consumer of `npu-server`'s LLM shop** (Phase 1+) — `ssh npu-server` from here works since 2026-05-04 ([[host-npu-server]])

## SSH config (for outbound to other hosts)

`~/.ssh/config` has aliases for:
- `npu-server` → `npu-server.tail9b2a4e.ts.net:22` (key: `~/.ssh/npu-server`)
- `mork-firebat` → personal tailnet / direct ethernet
- (others as needed)

## Cross-references

- [[host-firebat]] — the always-on counterpart that runs Tier-1 cron jobs
- [[host-npu-server]] — the company NPU box; reachable from here via tailnet
- [[../../personal-laptop/_summary|personal-laptop topic]] — legacy topic with pre-2026-05-04 detail; will eventually migrate here

## Open work

- [ ] Capture full hardware specs (`lscpu`, `free -h`, `df -h`) — fill in the placeholders above
- [ ] Migrate or cross-link content from the legacy `personal-laptop/` topic
