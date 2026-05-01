---
title: "Skill: /daily-wrap"
type: entity
topic: engineering-process
tags: [skill, daily-ritual, archive, personal-workflow]
created: 2026-04-17
updated: 2026-04-20
author: kb-bot
---

# /daily-wrap

End-of-day counterpart to [[skill-daily-scope|/daily-scope]]. Closes out the day: interviews which items from `## Today's Scope` in [[mark-todos]] closed, writes the daily note with summaries, archives fully-completed workstream sections.

**Installed at:** `/home/mork/.claude/skills/daily-wrap/SKILL.md`

## When to trigger

- End of a working day, before stopping
- When catching up on a missed wrap (pass `YYYY-MM-DD` arg for the date to wrap)
- Before starting a new `/daily-scope` if the prior day wasn't wrapped (the daily-scope carry-over check will suggest this)

Trigger phrases: `/daily-wrap`, "daily wrap", "wrap up day", "end of day", "log today".

## Core guarantees

- **Never destructive.** Completed items move to the daily note before their mark-todos row is removed.
- **Atomic.** If the daily-note write fails, abort — don't leave mark-todos in a half-mutated state.
- **Sectional archive.** Closed line items → bullet in daily note. Closed whole workstreams (§N) → full section copied into daily note + pointer row in mark-todos's `## Archive` table.

## Interview shape

Per unchecked line item in Today's Scope:
1. Status — `AskUserQuestion` with Closed / Deferred / Blocked / De-scoped
2. If Closed → 1-2 sentence summary via notes
3. Did this close a whole §N? (follow-up)

## Broader-day scan (Step 1.5, added 2026-04-20)

Scope is a floor, not a ceiling. Before the interview, the skill scans for work that happened today but wasn't in Today's Scope:

- **KB-note delta** — `find` notes under `knowledgebase/` modified today (excluding the daily note + mark-todos itself), plus any files with today's date prefix. Each hit that's not already referenced in the daily note's Closed Line Items becomes a candidate bullet the user approves during the interview.
- **Active session claims** — each non-self row in the `## Active Session Claims` table describes another Claude's scope today. Ask the user whether that session produced closed work worth recording (their summary; we can't read another transcript).
- **Repo commits** — `git log --since="today" --author=$(git config user.name)` across `/home/mork/work/*`. Commits not already tied to a closed item become candidate bullets.

## Diagnosis / TODO completeness cross-check (Step 2.5, added 2026-04-20)

For each closed investigation/bug item with a KB concept note, verify:
- The daily-note summary reflects the **diagnosis / root cause**, not just the discovery headline
- Any follow-up TODOs from the KB concept note landed in either the relevant `§N` section or the Deferred-to-tomorrow list

Precipitating incident: on 2026-04-20, the `dev.powerplus.com` SSL diagnosis (Sectigo DV R36 intermediate missing; server misconfig; fix recipe) was captured in `[[2026-04-20_dev-powerplus-ssl-cert-verify-failure]]` after the daily-note stub was last appended. The mid-day Task Completion Ritual only captured the discovery headline. The EOD wrap missed the diagnosis and didn't roll the three `§2d` follow-up TODOs into the deferred list. The Step 1.5 + Step 2.5 additions prevent this recurrence.

## Daily note output — progressive write + reconcile

The daily note at `topics/personal-notes/notes/daily/YYYY-MM-DD.md` is built **progressively through the day**, not only at EOD:

- **Mid-day:** the global Task Completion Ritual (see `~/.claude/CLAUDE.md`) appends a `## Closed Line Items` bullet the moment any tracked item closes, creating the stub file on first close.
- **EOD:** `/daily-wrap` reconciles — detects whether the stub exists, fills in `## Summary`, handles deferred/blocked items, archives any whole workstream that closed, and updates mark-todos.

The split means `/daily-wrap` is never writing from scratch (a missed wrap still leaves a useful provenance record), and EOD reconciliation is an additive pass rather than a create-everything pass.

Sections in the final file: Summary, Closed Line Items, Closed Workstreams (if any), Notes / Learnings. See [daily/README.md](../../../personal-notes/notes/daily/README.md) for the template.

## Renumbering caveat

If archiving §N shifts subsequent workstream numbers, the skill **asks before renumbering**. §N numbers may be referenced externally (Jira comments, PR descriptions, KB notes), so default to keeping gaps rather than renumbering silently.

## Related

- [[skill-daily-scope]] — morning counterpart; its carry-over check detects a missed wrap
- [[skill-todos-audit]] — flags missed wraps via the "Today's Scope hygiene" check
- [[skill-todos-add]] — owns adding workstreams; /daily-wrap owns removing them
- [[mark-todos]] — the file this skill mutates
- `topics/personal-notes/notes/daily/README.md` — daily-note convention
