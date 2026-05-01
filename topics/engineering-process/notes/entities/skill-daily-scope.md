---
title: "Skill: /daily-scope"
type: entity
topic: engineering-process
tags: [skill, daily-ritual, planning, personal-workflow]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/aws-cost/notes/concepts/aws-cost-explorer-access-pattern.md
  - topics/engineering-process/notes/concepts/2026-04-27_headless-mcp-bypass.md
  - topics/engineering-process/notes/entities/skill-daily-wrap.md
  - topics/engineering-process/notes/entities/skill-repo-scan.md
  - topics/engineering-process/notes/entities/skill-todos-add.md
  - topics/engineering-process/notes/entities/skill-todos-audit.md
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-laptop/notes/syntheses/2026-04-30_firebat-script-conversion-candidates.md
  - topics/personal-notes/_summary.md
incoming_updated: 2026-05-01
---

# /daily-scope

Morning planning ritual for Mark. Surveys in-flight work, reads [[mark-todos]] workstreams + auto-synced Jira queue, interviews for today's scope (2-3 items), and tracks picks as `TaskCreate` entries.

**Installed at:** `/home/mork/.claude/skills/daily-scope/SKILL.md`

## When to trigger

- Start of a working day, especially after an off-day
- When resuming a long task and want to re-orient
- When the in-flight state feels fuzzy ("what was I doing?")

Trigger phrases: `/daily-scope`, "daily scope", "scope today", "plan my day", "what should I work on".

## What it does (high level)

0. **Carry-over check** — reads Today's Scope; surfaces unfinished items from prior session or prior day before anything else
1. **Survey in-flight work** — branches + open PRs across working repos (skip with `--quick`)
2. **Read workstreams + Jira queue** from [[mark-todos]] (in [[personal-notes/_summary|personal-notes]])
   - **2a** Recent KB syntheses not yet workstreamed
   - **2b** Optional GitHub cross-repo scan (via `--with-repo-scan` — invokes [[skill-repo-scan]])
3. **Light audit** — anomaly flags (untracked branches, stale sync, high-priority unscoped tickets, stale frontmatter, orphan syntheses)
4. **Present landscape** — concise, under ~300 words
5. **Interview** — `AskUserQuestion` with 4-option limit; chained questions or free-form notes for >4 candidates
6. **Persist to mark-todos** — edit between `<!-- BEGIN-TODAY-SCOPE -->` sentinels
7. **Persist to session Tasks** — `TaskCreate` per pick, with `addBlocks`/`addBlockedBy` where relevant
8. **Confirm** — 3-5 line summary; don't auto-start tasks

## Key constraint: AskUserQuestion 4-option limit

`AskUserQuestion` validates `options.length <= 4`. The skill handles >4 candidates via:

- **Notes-as-free-form-input:** user adds extras to any option's notes field; skill parses into TaskCreates
- **Chained questions:** second `AskUserQuestion` call for next batch (framed additively)

Do not try to pack >4 into one question — it errors out (`too_big: maximum 4`) and costs a round trip.

## Related

- [[mark-todos]] — the source of truth for workstreams (lives in [[personal-notes/_summary|personal-notes]])
- [[automation-jira-sync]] — the daily job that keeps the Jira queue fresh
- [[automation-overnight-check]] — another scheduled daily job; `/daily-scope` is manual and interactive by contrast
- [[personal-notes/_summary|personal-notes topic]]
- [[agents-catalog]] — the distinction between skills (user-invoked rituals) and agents (delegated search/analysis)

## Relation to other skills

| Skill | Timing | Interactive? | Writes tasks? |
|-------|--------|-------------|--------------|
| `/daily-scope` | morning, manual | yes | yes |
| [[skill-daily-wrap\|/daily-wrap]] | end-of-day, manual | yes | cosmetic (marks completed) |
| [[skill-todos-audit\|/todos-audit]] | weekly, manual | optional (`--fix`) | no |
| [[skill-todos-add\|/todos-add]] | on-demand | yes | no (writes workstream §) |
| [[skill-repo-scan\|/repo-scan]] | on-demand or via `--with-repo-scan` | optional drill | no |
| `/autopatrol-overnight-check` | scheduled nightly | no | no |
| `/validate-release` | pre-merge | no | no |
| `/stage-release` | during release | some | no |

Within the personal-workflow set, `/daily-scope` is the planning entry point; `/daily-wrap` closes the loop. `/todos-add`, `/todos-audit`, `/repo-scan` are supporting utilities.

## Origin

Created 2026-04-17 after the first manual run of the ritual. The chat pattern was:
1. Survey branches + PRs
2. Read mark-todos
3. Use AskUserQuestion to offer 4 most likely picks + multi-select
4. User selected options AND added free-form notes for sub-tasks (500 error on motion-plus, prod release strategy)
5. TaskCreate per picked item

The skill codifies this so future sessions don't have to rediscover the pattern.

## Future enhancements

- **Dynamic option generation** — skill could rank workstreams + tickets by recency, priority, and in-flight-branch correlation to pick the "top 4" intelligently rather than a fixed order.
- **Smarter carry-over prompt** — if the user consistently defers the same item day after day, surface it with a "is this still real?" prompt rather than auto-offering to re-add it.
- **Light auto-pick based on active branch** — if the user is mid-work on a feature branch, auto-mark the matching workstream item as "in progress" for today without asking.
