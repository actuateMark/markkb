---
title: "Agent: kb-scribe"
type: entity
topic: engineering-process
tags: [agent, knowledge-base, obsidian, documentation, write]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/automation-overnight-check.md
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
incoming_updated: 2026-05-01
---

# kb-scribe

Write-focused KB agent. Takes raw findings from the parent context and returns a properly-structured note in the Obsidian KB at `/home/mork/Documents/worklog/knowledgebase/`.

**File:** `/home/mork/.claude/agents/kb-scribe.md`
**Model:** haiku (fast, cheap — KB writes don't need deep reasoning)

## When to Use

- Writing a new concept / synthesis / entity note from session findings
- Updating an existing note with new information
- Converting a plan (from plan mode) into a synthesis note
- Batch creating related notes after an investigation

## When NOT to Use

- **Reading / searching the KB** — use Grep, Read, or `/kb-ask`. The scribe is write-focused.
- **Bulk ingestion from reading list** — use `/kb-queue` skill.
- **Writing to memory** — memories go to `/home/mork/.claude/projects/-home-mork/memory/`, not the KB. Don't route memory through the scribe.
- **Editing topic `_summary.md` files silently** — the scribe will suggest edits back, parent decides.

## What It Enforces

- Correct frontmatter (`type`, `topic`, `tags`, `created`, `updated`, `author: kb-bot`)
- Routing per the "After Work: Log to KB" table in global CLAUDE.md
- Length: 200-800 words
- Wikilinks for cross-references
- Check for existing notes before creating duplicates
- Flag topic-creation decisions back to parent rather than inventing topics

## Routing Logic

| Input type | Output location |
|-----------|-----------------|
| Bug fix findings | `{topic}/notes/concepts/{date}_bugfix-{slug}.md` |
| Design decision | `{topic}/notes/syntheses/{date}_adr-{slug}.md` |
| Plan record | `{topic}/notes/syntheses/{date}_{slug}.md` tagged `plan` |
| Skill or agent definition | `engineering-process/notes/entities/` |
| Service / repo entity | `{topic}/notes/entities/` |
| Investigation results | `{topic}/notes/syntheses/` |

## Reporting Format

Returns: full path of note written/edited + one-line description. Nothing else.

## Skill Callers

| Skill | Where in skill | Notes |
|-------|----------------|-------|
| `/kb-auto` | Steps 2d-2f (per-item source + concept + summary writes) | Biggest caller — 5 items per run |
| `/kb-ingest` | Steps 4-7 (source / concept / entity / summary / index writes) | Parent fetches; scribe writes |
| `/kb-sync` | Step 5 (entity/concept updates from refreshed Confluence/Jira data) | Combine with jira-landscape for Jira-sourced updates |
| `/kb-queue` | Per-approved-item writes | Interactive, so context benefit is smaller |
| `/kb-synthesise` | Step 6 (write approved notes after plan approval) | Plan stays in parent; writes delegate |
| `/api-endpoint-development` | Phase 8 KB synthesis note | Post-deploy ADR / feature note |
| `/autopatrol-overnight-check` | Post-run root-cause note (if issues found) | Bugfix concept note |

## Related

- [[agents-catalog]]
- [[feature-development-lifecycle]] — "After Work: Log to KB" step
