---
title: Personal Notes
type: summary
topic: personal-notes
tags: [personal, workstream, todos]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# Personal Notes

Notes that are relevant only to [[mark-barbera|Mark Barbera]] — personal workstream tracking, priorities, and individual-scope planning. Shared team context lives in [[team-structure/_summary|team-structure]]; laptop/IT incidents live in [[personal-laptop/_summary|personal-laptop]].

## Contents

| Note | Purpose |
|------|---------|
| [[mark-todos]] | Active high-level workstreams and auto-synced Jira queue |

## Daily Ritual

- [[skill-daily-scope]] (`/daily-scope`) — morning: pick today's scope, persist to mark-todos + TaskCreate
- [[skill-daily-wrap]] (`/daily-wrap`) — evening: write daily note, archive closed workstreams
- [[skill-todos-audit]] (`/todos-audit`) — weekly: deeper audit for drift, stale, orphans
- [[skill-todos-add]] (`/todos-add`) — on-demand: scaffold a new workstream § with correct format
- [[skill-repo-scan]] (`/repo-scan`) — on-demand: GitHub cross-repo sweep for high-impact + low-hanging-fruit issues (also foldable into `/daily-scope --with-repo-scan`)

## Archive Layout

- `notes/daily/YYYY-MM-DD.md` — per-day archive written by `/daily-wrap`. Closed line items live here forever with short summaries; fully-completed workstream sections are moved here wholesale.
- [[mark-todos]] `## Archive` table — pointer rows to daily notes, sorted by date.
- Convention doc: `notes/daily/README.md`

## Related

- [[personal-laptop/_summary|personal-laptop]] — laptop-specific IT notes
- [[team-structure/_summary|team-structure]] — people-and-assignments reference
- [[automation-jira-sync]] — daily job that updates the Jira queue section in [[mark-todos]]
