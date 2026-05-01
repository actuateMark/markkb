---
title: "Automation: overnight-check"
type: entity
topic: engineering-process
tags: [automation, systemd, overnight-check, operational-health, claude-headless]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Automation: overnight-check

A `systemd` user timer that runs a platform-wide operational health check every morning and writes the result to the KB. First of the automated-job family — later jobs follow this shape.

## When It Fires

- **Daily at 08:03 `America/New_York`** — timezone-aware, DST handled automatically
- `Persistent=true` — if the machine is off at fire time, runs on next boot
- `RandomizedDelaySec=60` — small jitter

## What It Produces

A dated synthesis note at `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/{YYYY-MM-DD}_overnight-check.md`. Contents cover:

1. AutoPatrol health (from `/autopatrol-overnight-check` skill)
2. Connector fleet error rates (last 12h, facet by container)
3. Alert delivery health (queue_immix_consumer, smtp-frame-receiver, webhook_listener, queue_consumer)
4. NR Issues opened overnight (count + severity + top entities)
5. Raw NRQL used (collapsible)

On failure, the wrapper still writes a note — with `title: FAILED: …`, `status: failed` frontmatter, and the stderr tail inline. The `FAILED:` prefix sorts it to the top of the directory and makes it unmissable in a morning KB scan.

## Files

| Path | Role |
|------|------|
| `/home/mork/bin/overnight-check.sh` | Wrapper; builds prompt, runs `claude -p`, guarantees KB artifact |
| `~/.config/systemd/user/overnight-check.service` | oneshot service unit |
| `~/.config/systemd/user/overnight-check.timer` | daily timer |
| `~/.local/state/overnight-check/{date}.stdout` | raw claude stdout |
| `~/.local/state/overnight-check/{date}.stderr` | raw claude stderr |

## Dependencies

- `claude` CLI at `/home/mork/.local/bin/claude` (v2.1.112+ supports `-p` headless mode)
- [[new-relic|New Relic]] MCP authenticated (token at whatever path `~/.claude` uses)
- `kubectl` with valid context for the `rearchitecture` namespace
- Skill: `/autopatrol-overnight-check`
- Agents: [[agent-nrql-investigator]], [[agent-kb-scribe]]
- Permission allowlist in `~/.claude/settings.json` — required for headless runs

## Permission Allowlist

Pre-approved tools in `~/.claude/settings.json` (under `permissions.allow`):

- `Bash(kubectl get *)`, `Bash(kubectl describe *)`, `Bash(kubectl logs *)`
- `mcp__newrelic__execute_nrql_query`
- `mcp__newrelic__list_available_new_relic_accounts`
- `mcp__newrelic__list_recent_issues`
- `mcp__newrelic__list_recent_logs`
- `mcp__newrelic__list_entity_error_groups`
- `Write(/home/mork/Documents/worklog/knowledgebase/**)`

Anything not on the list hits a permission prompt → fails in headless mode → `FAILED` note.

## Linger

`sudo loginctl enable-linger mork` runs once at setup time. Without it, user timers only fire while a session is active (logged in locally or via SSH). With linger, timers run independently of login state.

## How To Debug a Failure

1. Read the `FAILED:`-prefixed KB note at `topics/operational-health/notes/syntheses/{date}_overnight-check.md`
2. `journalctl --user -u overnight-check.service --since '24 hours ago'`
3. `cat ~/.local/state/overnight-check/{date}.stderr`
4. Manual rerun: `/home/mork/bin/overnight-check.sh`
5. Check: `systemctl --user list-timers overnight-check.timer` (when is it next due?)

## How To Disable / Re-Enable

```bash
# Pause
systemctl --user disable --now overnight-check.timer

# Resume
systemctl --user enable --now overnight-check.timer
```

## How To Edit The Prompt

Edit `/home/mork/bin/overnight-check.sh` — the `PROMPT=$(cat <<EOF …)` block. No restart needed; next fire uses the new prompt. Keep the "delegate to nrql-investigator" and "delegate to kb-scribe" steps — they're load-bearing.

## Reusable Pattern

This is the template for future automated jobs. See the plan at `/home/mork/.claude/plans/it-is-local-only-cozy-hoare.md` for the full pattern. Queued next:

- Morning Jira digest (via [[agent-jira-landscape]]) — ~08:06
- PR-state sweep (via [[agent-release-chain-watcher]]) — weekdays ~09:07
- KB staleness sweep (`/kb-lint` output) — Mondays ~07:31

## Related

- [[operational-health/_summary|Operational Health topic]] — where the output lives
- [[agents-catalog]] — agents it delegates to
- [[agent-nrql-investigator]], [[agent-kb-scribe]] — primary delegates
