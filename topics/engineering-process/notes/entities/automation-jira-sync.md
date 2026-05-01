---
title: "Automation: jira-sync"
type: entity
topic: engineering-process
tags: [automation, systemd, jira-sync, mark-todos, three-tier-pattern, pure-script]
created: 2026-04-16
updated: 2026-04-30
author: kb-bot
incoming:
  - topics/engineering-process/notes/concepts/2026-04-27_headless-mcp-bypass.md
  - topics/engineering-process/notes/entities/skill-daily-scope.md
  - topics/engineering-process/notes/entities/skill-repo-scan.md
  - topics/engineering-process/notes/entities/skill-todos-audit.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-laptop/notes/syntheses/2026-04-30_firebat-script-conversion-candidates.md
  - topics/personal-notes/_summary.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Automation: jira-sync

Daily refresh of the "Current Jira Queue (auto-synced)" section in [[mark-todos]] with Mark's currently-assigned Jira tickets. **Pure-Python (no Claude tokens) as of 2026-04-30** — converted from the LLM-driven wrapper per the [[2026-04-30_three-tier-routine-check-pattern|three-tier routine check pattern]].

## Tier model

| Tier | Where | Cadence | Notes |
|------|-------|---------|-------|
| **Tier 1 (canonical)** | Firebat: `~/bin/jira-sync.sh` + `jira-sync.timer` | daily 06:30 ET | Always-on box runs first; idempotency guard makes later runs no-ops |
| **Tier 2 (fallback)** | Laptop: `~/bin/jira-sync.sh` + `jira-sync.timer` | daily 10:37 ET | Skips if Tier 1 already synced today |
| Tier 3 | n/a — no `/jira-sync` skill exists | — | Failure surfaces in `topics/operational-health/notes/syntheses/{date}_jira-sync.md` |

Both tiers run the same Python source from `/home/mork/work/local_network_scripts/files/jira-sync.sh`. Source-of-truth deployment via `phase-13-tasks.sh`.

## When It Fires

- **Firebat — 06:30 `America/New_York` daily** (Tier 1 canonical)
- **Laptop — 10:37 `America/New_York` daily** (Tier 2 fallback)
- `Persistent=true` on both — fires on next boot if machine was off at the scheduled time
- `RandomizedDelaySec` jitter (60-120s) on both

## What It Produces

Replaces the content between the `<!-- BEGIN-AUTOSYNC-JIRA -->` and `<!-- END-AUTOSYNC-JIRA -->` sentinels inside `/home/mork/Documents/worklog/knowledgebase/topics/personal-notes/notes/entities/mark-todos.md`.

The replacement groups tickets by status (Ready to Deploy / In Progress & In Review / To Do / Open / Other), with a per-ticket row of `Ticket | Priority | Type | Summary`. Tickets already referenced in the file's workstream sections (§1, §2, §3) get an inline `*(tracked in §N)*` marker.

The frontmatter `updated:` field is also updated to the sync date.

## Failure Behavior

**Fail-closed.** The script keeps an in-memory backup of `mark-todos.md` before any mutation. On any error (Atlassian API failure, splice failure, sentinel-missing):

1. `mark-todos.md` is restored from the in-memory backup (atomic `os.replace` on the splice — no torn writes possible).
2. A `FAILED: Jira Sync {date}` note is written to `topics/operational-health/notes/syntheses/{date}_jira-sync.md` with the Python traceback inline.
3. journalctl logs the non-zero exit.

The 7-day-retention backups also exist at `~/.local/state/jira-sync/mark-todos.{date}.bak` for manual restoration if needed.

## Files

| Path | Role |
|------|------|
| `~/bin/jira-sync.sh` | Pure-Python script; fetches via Atlassian REST, splices into mark-todos.md atomically |
| `~/.config/systemd/user/jira-sync.service` | oneshot service unit |
| `~/.config/systemd/user/jira-sync.timer` | daily timer (06:30 ET on Firebat, 10:37 ET on laptop) |
| `~/.local/state/jira-sync/{date}.stdout` | rendered section (for diagnostic) |
| `~/.local/state/jira-sync/{date}.stderr` | run log + tracebacks |
| `~/.local/state/jira-sync/mark-todos.{date}.bak` | pre-sync backup (7-day retention) |
| `~/bin/jira-sync.sh.llm-version-bak` | prior LLM wrapper, kept on laptop for reference |

## Dependencies

- Python 3 stdlib only (`urllib`, `json`, `re`, `tempfile`)
- `~/.config/atlassian/api-token` — Basic auth `{email, token, site}` JSON. Same credential the previous wrapper used via `atlassian_query.py`.
- Linger enabled (`loginctl enable-linger mork`) for runs while machine is sleeping (laptop) or closed.
- **No** Claude CLI required. **No** MCP server required. **No** allowlists or sandbox tweaks.

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
5. If mark-todos.md is corrupted: `cp ~/.local/state/jira-sync/mark-todos.{date}.bak /home/mork/Documents/worklog/knowledgebase/topics/personal-notes/notes/entities/mark-todos.md`

## How to Disable / Re-Enable

```bash
# Pause
systemctl --user disable --now jira-sync.timer

# Resume
systemctl --user enable --now jira-sync.timer
```

## How to Change the JQL

Edit `/home/mork/work/local_network_scripts/files/jira-sync.sh` — the JQL string inside `main()` near the `jira_search(...)` call. Re-deploy via `phase-13-tasks.sh` (or scp to both Firebat + laptop manually). Update the JQL section above if the query changes materially.

## Conversion notes (2026-04-30)

The previous version wrapped `claude -p` with a prompt instructing it to call `python3 ~/.claude/lib/atlassian_query.py search "<JQL>"`, parse JSON, format markdown between sentinels, and emit to stdout. Wrapper then spliced.

Replaced with deterministic Python that does the same work without the LLM round-trip:
- Calls Atlassian REST directly (urllib + basic-auth from `~/.config/atlassian/api-token`); no module dependencies beyond stdlib.
- Buckets tickets by status name into Ready to Deploy / In Progress & In Review / To Do / Open / Other.
- Computes `*(tracked in §N)*` annotation by scanning mark-todos.md once for `## N. ...` headings + `[A-Z]+-\d+` ticket keys, **stopping at the BEGIN-AUTOSYNC-JIRA sentinel** so the previous sync's annotations don't poison the mapping (this was a quiet bug in the LLM version — it tended to attribute every open ticket to whatever § appeared just before the autosync block).
- Idempotency guard: skips if `**Last synced:** TODAY` already present and section is well-formed. `--force` bypasses.
- Token cost: $0/run (was ~$0.02-0.04). Runtime: ~2s (was ~30-60s).

## Related

- [[mark-todos]] — the file this automation mutates
- [[automation-overnight-check]] — sibling daily automation
- [[agent-jira-landscape]] — the agent this automation's prompt implicitly invokes when context fits
- [[agents-catalog]]
