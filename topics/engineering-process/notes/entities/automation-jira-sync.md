---
title: "Automation: jira-sync"
type: entity
topic: engineering-process
tags: [automation, systemd, jira-sync, mark-todos, claude-headless]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Automation: jira-sync

Daily `systemd` user timer that refreshes the "Current Jira Queue (auto-synced)" section in [[mark-todos]] with Mark's currently-assigned Jira tickets. Second of the automated-job family — follows the pattern set by [[automation-overnight-check]].

## When It Fires

- **Daily at 10:37 `America/New_York`** — off-minute, DST-aware
- `Persistent=true` — fires on next boot if the machine was off at 10:37
- `RandomizedDelaySec=60` jitter

## What It Produces

Replaces the content between the `<!-- BEGIN-AUTOSYNC-JIRA -->` and `<!-- END-AUTOSYNC-JIRA -->` sentinels inside `/home/mork/Documents/worklog/knowledgebase/topics/team-structure/notes/entities/mark-todos.md`.

The replacement groups tickets by status (Ready to Deploy / In Progress & In Review / To Do / Open / Other), with a per-ticket row of `Ticket | Priority | Type | Summary`. Tickets already referenced in the file's workstream sections (§1, §2, §3) get an inline `*(tracked in §N)*` marker.

The frontmatter `updated:` field is also updated to the sync date.

## Failure Behavior

**Fail-closed.** The wrapper backs up `mark-todos.md` before running. If `claude -p` exits non-zero, or the expected sentinels go missing, or the `Last synced:` line doesn't match today's date:

1. `mark-todos.md` is restored from the backup (no partial mutation).
2. A `FAILED: Jira Sync {date}` note is written to `topics/operational-health/notes/syntheses/{date}_jira-sync.md` with stderr inline.
3. journalctl logs the non-zero exit.

Same visibility principle as overnight-check — user sees failures in the morning KB scan.

## Files

| Path | Role |
|------|------|
| `/home/mork/bin/jira-sync.sh` | Wrapper; backs up, invokes `claude -p`, verifies outcome, restores on failure |
| `~/.config/systemd/user/jira-sync.service` | oneshot service unit |
| `~/.config/systemd/user/jira-sync.timer` | daily timer |
| `~/.local/state/jira-sync/{date}.stdout` | raw claude stdout |
| `~/.local/state/jira-sync/{date}.stderr` | raw claude stderr |
| `~/.local/state/jira-sync/mark-todos.{date}.bak` | pre-sync backup (7-day retention) |

## Dependencies

- `claude` CLI at `/home/mork/.local/bin/claude`
- Atlassian MCP authenticated (same account as the interactive session — `mark@actuate.ai` / cloudId `4776db4d-ed60-472d-91ac-28ea15902e45`)
- Permission allowlist in `~/.claude/settings.json` covering:
  - `mcp__atlassian__searchJiraIssuesUsingJql`
  - `mcp__atlassian__atlassianUserInfo`
  - `mcp__atlassian__getAccessibleAtlassianResources`
  - `Edit(/home/mork/Documents/worklog/knowledgebase/**)`
  - `Read(/home/mork/Documents/worklog/knowledgebase/**)`
- `--add-dir $KB_ROOT` on the `claude -p` invocation to satisfy the headless sandbox write check
- Linger enabled (`loginctl enable-linger mork`) for laptop-closed runs

## JQL

```
assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
```

`maxResults=50`. Response format `markdown`. If response exceeds context limit, the automation is expected to extract via jq/python from the saved tool-result file.

## Sentinel Markers (Contract)

The replacement target in `mark-todos.md` is identified by:

```
<!-- BEGIN-AUTOSYNC-JIRA -->
...content...
<!-- END-AUTOSYNC-JIRA -->
```

**Do not remove these markers manually.** If they go missing, the next sync will fail-closed and write a FAILED note. To reset, restore from `~/.local/state/jira-sync/mark-todos.*.bak`.

## How to Debug a Failure

1. Read the `FAILED:`-prefixed KB note at `topics/operational-health/notes/syntheses/{date}_jira-sync.md`
2. `journalctl --user -u jira-sync.service --since '24 hours ago'`
3. `cat ~/.local/state/jira-sync/{date}.stderr`
4. Manual rerun: `/home/mork/bin/jira-sync.sh`
5. If mark-todos.md is corrupted: `cp ~/.local/state/jira-sync/mark-todos.{date}.bak /home/mork/Documents/worklog/knowledgebase/topics/team-structure/notes/entities/mark-todos.md`

## How to Disable / Re-Enable

```bash
# Pause
systemctl --user disable --now jira-sync.timer

# Resume
systemctl --user enable --now jira-sync.timer
```

## How to Change the JQL

Edit `/home/mork/bin/jira-sync.sh` — the `PROMPT=$(cat <<'EOF' ... EOF)` block, specifically the `jql:` field. Consider updating this entity note's "JQL" section if the query changes materially.

## Related

- [[mark-todos]] — the file this automation mutates
- [[automation-overnight-check]] — sibling daily automation
- [[agent-jira-landscape]] — the agent this automation's prompt implicitly invokes when context fits
- [[agents-catalog]]
