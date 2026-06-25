---
title: "Skill: /todos-audit"
type: entity
topic: engineering-process
tags: [skill, audit, personal-workflow, periodic]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/engineering-process/notes/entities/skill-daily-wrap.md
  - topics/engineering-process/notes/entities/skill-todos-add.md
  - topics/personal-notes/_summary.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-25
---

# /todos-audit

Weekly (or on-demand) health check for [[mark-todos]]. Catches drift: stale workstreams, orphaned Jira tickets, workstreams without tickets, untracked branches, priority drift, duplicate sections, missing sub-tasks, stale frontmatter, broken archive links, missed wraps.

**Installed at:** `/home/mork/.claude/skills/todos-audit/SKILL.md`

## When to trigger

- Start of week (Monday morning) for a weekly tune-up
- When mark-todos "feels off" — stale, duplicated, or out of sync with actual work
- After a long vacation or break before resuming

Trigger phrases: `/todos-audit`, "audit todos", "review todos", "check workstreams".

## Default: read-only

Produces a categorized report (Critical / Warning / Info). Does not mutate without `fix` argument and per-finding user confirmation.

## Checks

| # | Check | Severity |
|---|-------|----------|
| 1 | Stale workstream movement (>14 days) | Warning |
| 2 | Orphaned Jira tickets (in queue, not mapped) | Warning |
| 3 | Workstreams without tickets | Info |
| 4 | In-flight branches not mapped to any § | Warning |
| 5 | Priority drift (Highest in §4 vs Medium in §1) | Info |
| 6 | Duplicate / overlapping sections | Info |
| 7 | Missing sub-tasks in a workstream | Info |
| 8 | Stale frontmatter `updated:` | Info → Warning if >7d |
| 9 | Archive rows pointing to missing daily notes | Critical |
| 10 | Today's Scope date is older than today (missed wrap) | Critical |

## Fix mode

`/todos-audit fix` — for each finding, offers an interactive fix via `AskUserQuestion`. Common fixes:
- Map orphaned ticket → `AskUserQuestion` picks which § to map to
- Stale workstream → offer to archive (hands off to [[skill-daily-wrap|/daily-wrap]]) or refresh
- Missing sub-tasks → invite the user to add via free-form input

## Relation to other skills

| Skill | Overlap | Distinction |
|-------|---------|-------------|
| [[skill-daily-scope]] | runs a LIGHT audit inline (checks 2, 4, 8, 10) | /todos-audit covers all 10 checks |
| [[skill-daily-wrap]] | owns archive mutation | /todos-audit points at things to archive, doesn't do it |
| [[skill-todos-add]] | owns adding | /todos-audit identifies what's missing |

## Related

- [[skill-daily-scope]], [[skill-daily-wrap]], [[skill-todos-add]]
- [[mark-todos]] — the file this skill audits
- [[automation-jira-sync]] — source of the ticket queue used for cross-reference
