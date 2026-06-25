---
title: "Skill: /todos-add"
type: entity
topic: engineering-process
tags: [skill, personal-workflow, workstreams]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/engineering-process/notes/entities/agent-issue-auditor.md
  - topics/engineering-process/notes/entities/skill-daily-wrap.md
  - topics/engineering-process/notes/entities/skill-repo-scan.md
  - topics/engineering-process/notes/entities/skill-todos-audit.md
  - topics/personal-notes/_summary.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/repo-backlog/_summary.md
  - topics/repo-backlog/notes/concepts/2026-04-27_scan.md
  - topics/repo-backlog/notes/scans/2026-04-17_scan.md
incoming_updated: 2026-06-25
---

# /todos-add

Interactive scaffold for adding a new workstream section (§N) to [[mark-todos]]. Keeps format, numbering, and cross-references consistent so the file's convention doesn't drift when a workstream is added mid-session.

**Installed at:** `/home/mork/.claude/skills/todos-add/SKILL.md`

## When to trigger

- New work arrives that deserves a high-level workstream (not just a Today's Scope item)
- A one-off ticket balloons into a multi-week initiative
- The user says "let's make X a workstream"

Trigger phrases: `/todos-add`, "add workstream", "new workstream", "add todo", "todos add".

## Interview fields

- **Title** (short, outcome-oriented)
- **Priority** — current focus / this-week / this-month / backlog
- **Status** — in progress / not started / blocked / design phase
- **Tickets** — comma-separated Jira keys, or "pre-ticket"
- **Gated on** — optional `§M` that blocks this

## Context pre-population

Before writing the section, the skill:
1. Greps working repos for branches matching the topic — if found, includes in a "Branch:" line
2. Greps the KB for related notes — auto-links in the Related section

This prevents orphaned workstreams with no KB context (a signal [[skill-todos-audit]] would flag otherwise).

## Insertion rules

Priority determines position:
- **current focus** → §1 (shift others down by 1 — requires explicit user confirmation)
- **this-week** → after current-focus block
- **this-month / backlog** → append to end

**Renumbering requires explicit user confirmation** because §N may be referenced externally (Jira, PRs, KB notes).

## Format template

Matches existing mark-todos section shape:

```markdown
## N. <Title>

**Priority:** …
**Tickets:** …
**Status:** …

### What's left / ### Design surface / ### Subtasks

- [ ] …

### Relevant KB

- [[…]]

### Related

- …
```

## Related

- [[skill-daily-scope]] — picks from workstreams added here
- [[skill-todos-audit]] — flags workstreams without tickets / without sub-tasks
- [[skill-daily-wrap]] — counterpart for removal
- [[mark-todos]] — the file this skill writes to
