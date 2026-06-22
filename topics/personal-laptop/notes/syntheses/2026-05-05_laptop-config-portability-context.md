---
title: "Laptop-config portability + DR — workstream context (factored from mark-todos §10)"
type: synthesis
topic: personal-laptop
tags: [laptop-config, disaster-recovery, mark-todos-factored]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-06
---

Factored out of mark-todos §10 on 2026-05-05 to keep the live workstream tracker lean. See [[mark-todos]] §10 for active checkboxes.

## Trigger

2026-04-23 user directive: *"I do not want to lose this monitoring setup, the rules, skills, and other configurations for all of this if I need to do a reboot or get a new computer."*

## Goal

A one-command bootstrap that reconstitutes this laptop's Actuate-related configuration on a fresh machine (or after a wipe). Covers: Claude Code skills + agents + hooks + global rules + per-project memories, systemd user services, the KB itself, the dashboard output layout, secrets-refresh runbook for things that can't be stored.

## Inventory — what needs to survive

**Claude Code config** (`~/.claude/`):
- `CLAUDE.md` — global rules
- `skills/<name>/` — all custom skills
- `agents/<name>.md` — custom subagents
- `hooks/` — session-start + stop hooks
- `lib/` — shared libraries (`nr_query.py`, `atlassian_query.py`)
- `plans/<slug>.md` — approved plan files
- `projects/<project>/memory/` — per-project memory

**systemd --user services** (`~/.config/systemd/user/`):
- `dashboard-server.service`
- `jira-sync.service` + `.timer`
- `overnight-check.service` + `.timer`

**Knowledge base** (`~/Documents/worklog/knowledgebase/`):
- The Obsidian vault, version-controlled separately

**Dashboard data** (`~/Documents/worklog/dashboard/`):
- `sink/observations.jsonl` — operational-event sink
- Per-day snapshot dirs

**Cloned repos** (`/home/mork/work/`):
- `vms-connector`, `actuate-libraries`, `actuate-inference-api`, `actuate_admin`, `autopatrol_onboarder`, `autopatrol-server`, `camera-ui`, `software-arch-sketches`, `ds-terraform-eks-v2`, `local_network_scripts`

**System deps** (package-managed):
- `python3.12-venv`, `uv`, `gh`, `aws-cli`, `jq`, `curl`, `git`, `nodejs`

**Secrets / tokens (CANNOT store; runbook-only):**
- AWS SSO, CodeArtifact, GitHub, Anthropic API key, NR API key, Atlassian API token, Slack webhooks

## Approach options

1. **Dotfiles repo with `chezmoi`** — purpose-built (handles templates, secret-exclude, post-apply hooks)
2. **Dotfiles repo with GNU `stow`** — simpler, symlink-based
3. **Plain git repo + bootstrap script** — one repo at `~/.dotfiles/` + `bootstrap.sh`. Cheapest to build.
4. **Nix home-manager** — gold-standard reproducibility but huge learning curve

Likely: **option 3** for v1, upgrade to chezmoi only if v1 friction shows up.

## Relevant KB

- [[engineering-process/_summary|engineering-process]] — likely home for the secrets-refresh runbook
- [[core-repo-suite]] — repo clone list partially maintained there
- [[agents-catalog]] — subagent inventory

## Related workstreams

- §9 Operational Dashboard — the initiative that surfaced "I shouldn't lose this"
- §13 (archived [[2026-04-27]]) — secrets-refresh runbook example via NR/Atlassian REST wrappers
- [[skill-daily-scope]] — morning routine depends on the whole config being intact
