---
title: "KB Skill / Agent Retrofit to Obsidian CLI (2026-04-30)"
type: synthesis
topic: obsidian
tags: [obsidian, cli, knowledge-base, kb-relink, kb-lint, kb-lookup, kb-ask, kb-scribe, retrofit]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - _index.md
  - topics/obsidian/_summary.md
  - topics/obsidian/notes/entities/obsidian-cli.md
  - topics/obsidian/notes/syntheses/2026-05-01_context-efficient-kb-retrieval.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/obsidian/_summary.md
  - topics/obsidian/notes/entities/obsidian-cli.md
  - topics/obsidian/notes/syntheses/2026-05-01_context-efficient-kb-retrieval.md
incoming_updated: 2026-06-25
---

On 2026-04-30, the user enabled CLI access on both Obsidian instances (laptop and firebat). The CLI exposes structured discovery primitives — tags, backlinks, orphans, search — that the KB skills had previously been emulating with recursive Glob/Grep over `~/Documents/worklog/knowledgebase/`. This synthesis captures the retrofit: which skills changed, what they now prefer, and what's still open.

## Core principle

When a KB question can be answered by a single `obsidian` CLI call, prefer it over recursive filesystem scan. Scanning ~1050 files for `[[wikilinks]]` or `tags:` consumes orders of magnitude more tokens than asking the running Obsidian instance, which already has the index in memory. This is the same "aggregate first, drill second" discipline that governs NRQL and Cost Explorer queries.

The CLI is at `~/.local/bin/obsidian` on both boxes. See [[obsidian-cli]] for the install paths and the firebat wrapper detail.

## Per-skill changes

### `/kb-relink` — extended to also enrich tags

Before: only filled in missing wikilinks. After: also fills in missing frontmatter tags using a curated `tag-rules.yaml` parallel to the existing `aliases.yaml`.

- New file: `~/.claude/skills/kb-relink/tag-rules.yaml` — maps a tag (`#vms-connector`, `#new-relic`, …) to the prose phrases or anchor slugs that authorize adding it.
- New steps in the procedure: 2.5 (build tag inventory using `obsidian tags counts`), 4.6 (scan files for tag triggers), 4.7 (anti-hallucination — never propose a tag absent from `tag-rules.yaml`).
- New flags: `--links-only`, `--tags-only` for scoping a sweep narrowly.
- Report includes both axes: wikilinks added, tags added, suggested rules to curate.

The wikilink and tag passes share the same anchor inventory, the same safe-zone parser, and the same anti-hallucination rule. Combining them in one skill avoids two stale-half-the-time sweeps.

### `/kb-lint` — uses `unresolved` / `orphans` / `deadends`

Before: each check did its own recursive scan of frontmatter and `[[wikilinks]]`. After: the link-graph checks call the CLI directly. Also added a new "dead-end pages" check (`obsidian deadends`) and a tag-hygiene check (`obsidian tags counts` flags single-use tags as likely typos).

### `/kb-lookup` — tag-driven discovery first

Before: read topic `_summary.md`, then recursive Grep for the search term. After: read `_summary.md` first, then `obsidian tag name=#<topic>` (full file list in one call) and `obsidian backlinks file=<topic-anchor>` (cross-topic referrers) before falling through to phrase search via `obsidian search:context`.

### `/kb-ask` — `search:context` over recursive Grep

Same shape as kb-lookup: tag/backlink lookups when the question maps to a topic; `obsidian search:context query=...` for free-form phrase questions instead of `Grep -rn`.

### `kb-scribe` agent — canonical tag lookup before write

Added Bash to the agent's toolset. New "Before Writing" step: `obsidian tags counts | grep -i <topic-fragment>` to see how a topic is canonically tagged in the wild, so the agent prefers existing tags over inventing new ones. Reduces tag fragmentation (the `#new-relic` vs `#newrelic` problem).

## Anti-hallucination rules carry forward

The wikilink anti-hallucination rule that guards `kb-relink` Step 4.5 (never link a phrase to an anchor unless the anchor explicitly claims that phrase in `aliases.yaml` or its frontmatter) extends to tags: never add a tag to a note unless the tag has an entry in `tag-rules.yaml`, and the trigger fires from THAT tag's rule (not a sibling's). The curated rule file is the single source of truth on both axes.

The same `Suggested rules to curate` block in the report surfaces high-frequency tags from `obsidian tags counts` that are absent from `tag-rules.yaml` — the curation backlog stays visible at the end of every run rather than getting lost.

## CLI availability check (shared pattern)

Every retrofitted skill begins its CLI-using step with the same probe:

```bash
~/.local/bin/obsidian vault 2>&1 | head -1
```

If it succeeds, use the CLI. If it fails (Obsidian not running, socket missing, CLI not on PATH), fall back to the Read/Glob/Grep procedure for that step and note "CLI unavailable — used filesystem fallback" in the skill's report. Both paths produce equivalent results; the CLI just makes them faster.

## What's still open

Tracked in the topic's [[obsidian/_summary|_summary]] under "Easy-win backlog":

- `/kb-synthesise` source-scan loop still uses Grep — could use `obsidian search query="<concept>"` to get concept frequency across sources in one call.
- Frontmatter schema audit — `obsidian properties` could feed `/kb-lint` Check 2 for cheaper validation.
- Daily-note tag analytics — `obsidian tags counts` differential vs. last week could surface workstream-tag drift.

These are non-blocking and lower-value than the four skills already retrofitted. Promote to first-class concept notes when one becomes worth doing.

## Related

- [[obsidian-cli]] — CLI capability matrix and the firebat wrapper
- [[obsidian/_summary|Obsidian topic]] — landing page and easy-win backlog
- [[skill-kb-relink]] — extended skill (links + tags)
- [[skill-kb-lint]], [[skill-kb-lookup]], [[skill-kb-ask]] — retrofitted to prefer CLI
- [[engineering-process/_summary|engineering-process]] — KB conventions and skill catalog
