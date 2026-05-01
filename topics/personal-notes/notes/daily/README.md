---
title: Daily Notes
type: concept
topic: personal-notes
tags: [daily, convention, archive]
created: 2026-04-17
updated: 2026-04-27
author: kb-bot
---

# Daily Notes — Convention

One file per working day, named `YYYY-MM-DD.md`. Each file is the archival record of what closed that day.

Daily notes are built **progressively** through the day: the global Task Completion Ritual (see `~/.claude/CLAUDE.md`) appends a `## Closed Line Items` bullet the moment a tracked item closes, creating the stub file on first close. At EOD, [[skill-daily-wrap|/daily-wrap]] reconciles — fills in `## Summary`, sweeps closed `[x]` sub-items out of mark-todos into `## Closed Sub-items`, handles deferred/blocked items, archives any whole workstream that closed, and updates mark-todos.

## Archival roles (three distinct headings)

1. **`## Closed Line Items`** — Today's-Scope picks that closed today. One narrative bullet per item with PR/ticket links, what changed, and what was learned. The Task Completion Ritual stubs these; `/daily-wrap` reconciles.
2. **`## Closed Sub-items`** — granular `[x]` checklist items swept from mark-todos `§N` workstreams. **Verbatim copies** of the bullet text so the workstream's checkbox history stays queryable. Grouped by `**§N — title:**` sub-heading. Added by `/daily-wrap` Step 2.7 (or by the close-time Task Completion Ritual when same-day distribution is feasible). New 2026-04-27 — this heading didn't exist before; without it, `[x]` accumulated forever in mark-todos.
3. **`## Closed Workstreams`** — full text of a `§N` section that closed today (the whole workstream, not just sub-items). Copied verbatim from mark-todos; the corresponding row gets removed from mark-todos and a pointer added to mark-todos's `## Archive` table.

**Never delete.** If something is wrong, correct via editing — the history is the point.

## Frontmatter (required)

```yaml
---
title: "Daily: YYYY-MM-DD"
type: concept
topic: personal-notes
tags: [daily, wrap]
topics: [autopatrol, vms-connector, infrastructure]   # KB topics touched today
workstreams: ["§3", "§9"]                             # workstream IDs touched today
created: YYYY-MM-DD
updated: YYYY-MM-DD
author: kb-bot
---
```

`topics:` and `workstreams:` are the **cross-reference primary keys**. Without them, you can't answer "when did I last work on autopatrol?" without reading every daily note. With them:

```bash
# All days that touched the autopatrol topic
grep -l "topic: autopatrol" topics/personal-notes/notes/daily/*.md

# All days that touched §3
grep -l "workstreams:.*§3" topics/personal-notes/notes/daily/*.md
```

Tag rigorously. When in doubt, over-tag.

## File template

```markdown
---
title: "Daily: YYYY-MM-DD"
type: concept
topic: personal-notes
tags: [daily, wrap]
topics: [<topic1>, <topic2>]
workstreams: ["§N", "§M"]
created: YYYY-MM-DD
updated: YYYY-MM-DD
author: kb-bot
---

# Daily: YYYY-MM-DD

## Summary

One paragraph: what the day's shape looked like, what shipped, what hit blockers.

## Closed Line Items

- **§1 fix 500 error on motion-plus model** — root cause was X; fixed by Y; PR #123 merged to stage.
- **§3 scope cleanup Lambda SQS** — decided on FIFO with site_id+schedule_id dedup key; design doc: [[2026-04-17_cleanup-lambda-design]].

## Closed Sub-items

*Granular `[x]` checklist items closed today, swept from mark-todos.*

**§3 — New Lambda — AutoPatrol stale-schedule cleanup:**

- [x] Step E.2 — `CLEANUP_ENABLED=true` flipped on cleanup Lambda us-west-2 at 17:59:26Z. Pre-flip acceptance state: 0 actual disables, 0 DLQ, dashboard GREEN.

**§9 — Operational Dashboard (Phase 1b):**

- [x] CPU/memory per deployment subset: cluster avg + vms + inference — shipped today.

## Closed Workstreams

*(full content of completed §N sections goes here, if any closed today)*

## Notes / Learnings

Freeform — anything surprising, any new KB notes written today.

## Related

- [[mark-todos]] — scope picked from
- [[skill-daily-scope]], [[skill-daily-wrap]]
```

## Retrieval

Search patterns:
- "When did I last work on X?" → `grep -rn "X" topics/personal-notes/notes/daily/`
- "What did I do last Tuesday?" → `Read: topics/personal-notes/notes/daily/YYYY-MM-DD.md`
- "When did §N close?" → row in mark-todos's `## Archive` table points to the daily note
- "When did §N have sub-item X close?" → grep daily notes for the sub-item text or `workstreams: ".*§N"` frontmatter
- "Show me every day touching the autopatrol topic" → `grep -l "topic: autopatrol" daily/*.md`

## Archive snapshots

If a structural cleanup of mark-todos happens (as on 2026-04-27), the pre-cleanup version is preserved verbatim under `_archive-snapshots/YYYY-MM-DD_mark-todos-pre-cleanup.md`. These snapshots are the safety net — distribution to per-day daily notes is best-effort, but the snapshot guarantees nothing is lost.

## Related

- [[mark-todos]] — the rolling-forward task tracker
- [[skill-daily-scope]] — morning ritual that picks scope
- [[skill-daily-wrap]] — end-of-day ritual that closes items + sweeps `[x]` sub-items into `## Closed Sub-items`
