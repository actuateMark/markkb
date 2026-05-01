---
title: "Runbook: Detecting jira-sync staleness"
type: concept
topic: runbooks
tags: [runbook, jira, automation, mark-todos, observability]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
---

# Detecting jira-sync staleness

## When this applies

The `automation-jira-sync` cron is supposed to rewrite the `## Current Jira Queue` section of [[mark-todos]] daily, plus drop a per-day `topics/operational-health/notes/syntheses/<YYYY-MM-DD>_jira-sync.md` provenance note. When that automation wedges, mark-todos's Jira queue silently drifts — Ready-to-Deploy / In-Progress / To-Do tickets no longer match Jira's actual state, and morning planning rituals make picks against stale data without noticing.

Self-recursive: this runbook would have caught the 2026-04-30 morning miss (last-synced 2026-04-29, no sync run today).

## Symptoms

- mark-todos Jira-queue section's `**Last synced:** YYYY-MM-DD` line is older than yesterday.
- The expected file `topics/operational-health/notes/syntheses/<TODAY>_jira-sync.md` is missing.
- Tickets you know moved (closed, transitioned, re-prioritized) still show their old state in mark-todos.
- The auto-sync block (between `<!-- BEGIN-AUTOSYNC-JIRA -->` and `<!-- END-AUTOSYNC-JIRA -->`) wasn't rewritten today.

## Diagnose

**1. Confirm the staleness (10s):**

```bash
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d 'yesterday' +%Y-%m-%d)

# What does mark-todos claim?
grep -E "Last synced:" /home/mork/Documents/worklog/knowledgebase/topics/personal-notes/notes/entities/mark-todos.md \
  | head -1

# Did today's provenance note land?
ls -1 /home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/${TODAY}_jira-sync.md 2>&1
ls -1 /home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/${YESTERDAY}_jira-sync.md 2>&1
```

If both yesterday's and today's notes are missing, the sync has been wedged for >24h — escalate the diagnosis.

**2. Check the systemd timer state on the box that runs it:**

The sync runs as a `systemd --user` timer. The historical home was the laptop; if the timer's been migrated to the minipc, check `mork-firebat` instead.

```bash
systemctl --user list-timers | grep -i jira
systemctl --user status jira-sync.timer
systemctl --user status jira-sync.service  # last invocation result
journalctl --user -u jira-sync.service -n 100 --no-pager | tail -50
```

Common failure modes the journal will show:
- `gh auth status` returned a 401 — GitHub or Atlassian token expired.
- `mcp__atlassian__searchJiraIssuesUsingJql` failed — Atlassian MCP server detached.
- Markdown parser error on mark-todos — someone's manual edit broke a sentinel comment.
- File permission error on writing to the KB path.

## Fix

**Quick recovery (run the sync once manually):**

```bash
# Manual invocation matches what the timer would have done
~/bin/jira-sync.sh
# OR (depending on which host owns the timer)
ssh mork-firebat ~/bin/jira-sync.sh
```

If the script fails interactively, the journal output above usually tells you which sub-command was the blocker. Most common remediations:

| Failure | Fix |
|---|---|
| Atlassian MCP detached | `/mcp` to reconnect; re-run sync |
| GitHub token expired | `gh auth login`; re-run |
| [[sentinel-components|Sentinel]] comments missing in mark-todos | Restore `<!-- BEGIN-AUTOSYNC-JIRA -->` and `<!-- END-AUTOSYNC-JIRA -->` around the section before re-running |
| Timer disabled / not enabled | `systemctl --user enable --now jira-sync.timer` |

After the manual run, confirm both the in-place mark-todos rewrite AND the per-day provenance file landed.

## Verify

```bash
TODAY=$(date +%Y-%m-%d)

grep -E "Last synced:" /home/mork/Documents/worklog/knowledgebase/topics/personal-notes/notes/entities/mark-todos.md \
  | head -1
# Expect: Last synced: <TODAY>

test -f /home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/${TODAY}_jira-sync.md \
  && echo "provenance note OK" || echo "FAIL: provenance note missing"
```

Spot-check 1–2 ticket transitions you know happened (e.g. AUTO-478 closed yesterday) — they should be reflected in the rewritten queue.

## Prevent

- **Promote a dashboard signal: `jira_sync_freshness_hours`.** Compute as `now() - mtime(<topics/operational-health/notes/syntheses/<TODAY>_jira-sync.md>)` (or fall back to the most recent `*_jira-sync.md`). Yellow above 30h, red above 48h. The `dashboard-check` cron would surface staleness before morning ritual depends on the data.
- **Step 3 audit in [[skill-daily-scope]]** already includes "Jira auto-sync `Last synced:` is not today or yesterday" as an anomaly flag — keep that as the human-loop fallback even after the dashboard signal lands.
- **Surface in `/dashboard-check`:** add the freshness check as an `informational`-tier signal first, promote to enabled once it's stable.

## Cross-refs

- [[automation-jira-sync]] — the cron entity description
- [[skill-daily-scope]] §"Step 3 — Light audit" — where staleness gets flagged today
- [[2026-04-29_credential-expiry-recovery]] — common cause of jira-sync failure (MCP / GitHub / Atlassian token expiry)
- `~/bin/jira-sync.sh` — the script invoked by the timer
- [[runbooks/_summary|Runbooks]]
