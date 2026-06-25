---
title: "How to use this knowledge base"
type: concept
tags: [orientation, kb, navigation, conventions, home]
updated: 2026-06-25
author: kb-bot
---

# How to use this knowledge base

This KB is an **Obsidian vault** (~1,070 notes across ~40 topics) capturing R&D, architecture, ops, and decisions for the [[what-is-actuate|Actuate platform]]. It's published as a static wiki via Quartz and synced to the firebat mini-PC. This page explains how it's organized and how to *find* things without reading 1,000 files.

## How notes are typed

Every note declares a `type:` in its frontmatter. The five types, in rough order of value:

| Type | What it is | Read it when |
|---|---|---|
| **`_summary`** | One per topic — the **map + entry point** for that area | Starting anywhere new |
| **`synthesis`** | Cross-cutting analysis, decisions, ADRs — **the highest-value notes** | You want the "why" and the trade-offs |
| **`concept`** | How one thing works (a mechanism, a bugfix, a feature) | You need a specific how/what |
| **`entity`** | A service / repo / tool / host / person | You need facts about one thing |
| **`source`** | Ingested external material (papers, docs) | Researching; treat as immutable |

Frontmatter convention: `title`, `type`, `topic`, `tags`, `updated:` (a date), `author:` (usually `kb-bot`). The schema lives in [[_schema]] and authoring rules in `rules/`.

## How to find things

**The retrieval ladder — cheapest first. Don't grep 1,000 files blind.**

1. **Start at a map.** The wiki home `[[index]]` lists every topic by domain. This `home/` folder is the orientation packet. Then open the relevant **topic `_summary`**.
2. **Structural queries (instant, no LLM):** the `obsidian` CLI talks to the running vault —
   - `obsidian backlinks file=X` — who links to X
   - `obsidian search:context query="…"` — full-text with surrounding context
   - `obsidian tag name=#X` / `obsidian tags counts` — by tag
   - `obsidian unresolved` / `obsidian orphans` — health
3. **Skills (LLM, when you need synthesis):**
   - **`/kb-lookup`** — pull the right context *before coding* in an Actuate repo.
   - **`/kb-ask`** — free-form "what does the KB say about X?"
   - Both walk the cost-ordered ladder internally (CLI first, file reads last).

**If you're a person:** open the vault in Obsidian → graph view + the **Bases dashboards** (`[[bases/Syntheses|Syntheses]]`, `[[bases/Topic Summaries]]`, `[[bases/Recent Changes]]`, `[[bases/Stale Notes]]`) + full-text search.

**If you're an agent:** read [[index]] → the topic `_summary` → use `/kb-ask` + `/kb-lookup`. The summaries and skills *are* the index — lean on them instead of scanning.

## Conventions worth knowing
- **Wikilinks** `[[note]]` resolve by **basename** (folder-independent) — so notes can move without breaking links, *as long as basenames stay unique*. Topic entry points are linked path-form, `[[topic/_summary]]`.
- **Dates are absolute** (`2026-06-25`), never "yesterday".
- Notes are **200–800 words**, cross-linked liberally with `[[wikilinks]]`.
- A `[[link]]` to a note that doesn't exist yet is a deliberate **stub marker** ("write this later"), surfaced by `kb-todo-scan` / `/kb-lint`.

## Maintenance (so it doesn't rot)
- **`/kb-lint`** — broken wikilinks, orphans, stale notes (exit 1/2 = *findings*, not failure).
- **`/kb-relink`** — enrich wikilinks/tags + regenerate each note's `incoming:` backlinks.
- **`kb-build-index.py`** — regenerates the topic-map block in `[[index]]` (a firebat timer keeps it live; new topics surface in an "Other — file me" bucket).
- **Sync:** the canonical remote is `aegissystems/actuate-kb`; firebat auto-pulls every ~30 min. See [[2026-06-24_firebat-kb-git-sync-task]].
- **Self-host your own instance:** [[SETUP]] (KB-only) or [[DEVBOX-BOOTSTRAP]] (full workflow).

## Next
- **[[the-topic-landscape]]** — what each topic/domain covers and *where to go to learn what*.
- **[[what-is-actuate]]** — the platform itself.
