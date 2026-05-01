---
title: "Context-Efficient KB Retrieval Recipe"
type: synthesis
topic: obsidian
tags: [obsidian, cli, knowledge-base, retrieval, context-efficiency, kb-lookup, kb-ask]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
incoming:
  - topics/obsidian/_summary.md
incoming_updated: 2026-05-01
---

The KB is meant to be queried by LLMs without burning context. Every time a skill walks the vault recursively (`grep -r` over 1050 files, reading every frontmatter), the conversation pays in tokens. The Obsidian CLI plus a richer link/tag graph (post-2026-05-01 [[2026-04-30_kb-skill-cli-retrofit|retrofit]] + relink pass) lets us answer the same questions in 1-3 structured calls. This synthesis captures the canonical retrieval recipe and the design choices that support it.

## The retrieval cost ladder

Order operations cheapest-to-most-expensive. Stop as soon as the question is answered.

| Tier | Operation | Cost (rough tokens) | When to use |
|---|---|---|---|
| 0 | Read `_index.md` | ~3k once per session | Find which topic owns the question |
| 1 | Read a topic `_summary.md` | ~2-4k each | Get topic-level answer; lists entities/concepts |
| 2 | `obsidian tag name=#X` | ~50-200 (path list) | All notes tagged with a topic — single call |
| 3 | `obsidian backlinks file=<anchor>` | ~50-200 (path list) | All notes referencing a specific entity |
| 4 | `obsidian search:context query="<phrase>"` | ~500-2k (matched lines + context) | Free-form phrase when tags/backlinks don't fit |
| 5 | Read specific note(s) identified at tier 1-4 | ~2-5k each | Get the actual content |
| 6 | Recursive Grep over `topics/**/*.md` | ~50k+ | Last resort; CLI unavailable |

Tier 6 is the OLD way. The retrofit (2026-04-30) routes all KB skills to start at tier 0-2.

## The recipe (canonical)

For "What do we know about X?":

```
1. Read _index.md if not yet read this session.
2. Identify the topic (or topics) X belongs to from the index.
3. Read topics/<topic>/_summary.md for that topic.
4. If X is a known anchor:
     ~/.local/bin/obsidian backlinks file=<X>
   This returns all referrers in one call. Read 1-3 for cross-context.
5. If X has a tag form:
     ~/.local/bin/obsidian tag name=#<X>
   For aspect-level discovery (every note about X across topics).
6. Only if the above don't suffice:
     ~/.local/bin/obsidian search:context query="<distinctive phrase>"
   Picks up free-form mentions.
```

For "What's the architecture of Y?": same, but tier 1 + tier 5 (read entity + summary) is usually enough — the relink pass ensures entities cross-link to their cohort.

For "What's stale / broken in the KB?": single call, no traversal:

```
~/.local/bin/obsidian unresolved   # broken wikilinks
~/.local/bin/obsidian orphans      # files with no incoming links
~/.local/bin/obsidian deadends     # files with no outgoing links
```

## Why the link graph matters

Tier 3 (backlinks) only works when notes actually link to each other. Before the 2026-05-01 relink pass, prose mentioning "Evalink" rarely linked to `[[evalink-components]]`, so `obsidian backlinks file=evalink-components` returned almost nothing. After the pass:

| Anchor | Backlinks before | Backlinks after |
|---|---:|---:|
| evalink-components | (~3) | 20 |
| kvs-components | (~2) | 31 |
| vms-connector | (~30) | 89 |
| admin-api/_summary | 0 | 25 |
| autopatrol/_summary | 0 | 31 |

Tier 2 (tag query) works because tag-rules.yaml + threshold-gated tag enrichment populated frontmatter `tags:` arrays. `obsidian tag name=#autopatrol` returns 66 files — that's the LLM's "pre-filtered set" for autopatrol-relevant content.

Tier 4 (`search:context`) replaces what the OLD agent did with `Grep -rn -C 3` against the full vault.

## Skill-level integration status

As of 2026-05-01:

| Skill | Tier 0-2 | Tier 3 | Tier 4 | Notes |
|---|:---:|:---:|:---:|---|
| `/kb-lookup` | ✓ | ✓ | ✓ | Tag + backlinks first; search as fallback |
| `/kb-ask` | ✓ | ✓ | ✓ | Same pattern |
| `/kb-lint` | — | — | — | Uses unresolved/orphans/deadends instead |
| `/kb-relink` | ✓ | ✓ | — | Uses tags/backlinks for inventory build |
| `kb-scribe` agent | ✓ | ✓ | ✓ | Pre-write CLI lookup for canonical tags |
| `/kb-synthesise` | ✗ | ✗ | ✗ | **Not yet retrofitted** — recursive read of `sources/` |
| `/kb-recap` | ✗ | ✗ | ✗ | Uses `find -mtime`; minimal cost already |
| `/kb-ingest`, `/kb-sync`, `/kb-queue`, `/kb-auto` | n/a | n/a | n/a | Write-side / external (Atlassian MCP); CLI not applicable |

The unwired skills are mostly write-side. Highest-value retrofit candidate is `/kb-synthesise`.

## Structural choices that support LLM navigation

These are baked into the KB conventions and the [[skill-kb-relink|kb-relink driver]]:

1. **One canonical entity per service / library / tool** — slug-style filename (`evalink-components.md`, not `Evalink Components.md`). Lets `[[anchor]]` and `obsidian backlinks file=anchor` work uniformly.

2. **Topic summaries linked via path syntax** — `[[admin-api/_summary|Actuate Admin API]]` instead of bare `[[admin-api/_summary|Actuate Admin API]]`. The bare form was unresolved (no `admin-api.md` exists); path form resolves and is indexed by Obsidian.

3. **Aliases curated in `aliases.yaml`** — adds the prose forms ("Evalink", "KVS", "Watchman") that don't slug-derive from the anchor's filename. Lets the relinker fill in cross-topic references that would otherwise stay unlinked.

4. **Tags follow `<topic>` or `<service>` form** — `#vms-connector`, `#new-relic`, `#evalink`. Hyphenated, lowercase. Makes `obsidian tag name=#X` predictable.

5. **Threshold-gated tag enrichment** — a single phrase mention isn't enough to add a tag (PHRASE_TRIGGER_MIN=5). This keeps the tag set semantically meaningful — `obsidian tag name=#autopatrol` returns notes that ARE about autopatrol, not notes that just mention it once.

6. **Source notes excluded from edits** — `sources/*.md` are immutable (worklog exports, raw research). The relinker won't add wikilinks to them, so backlinks to source notes stay clean.

7. **`incoming:` snapshot in entity / concept / synthesis frontmatter** (added 2026-05-01) — the top-N backlinks are baked into frontmatter via `relink.py --refresh-incoming`. A query reading the note gets the referrer set for free, eliminating a tier-3 CLI call.

## Open structural improvements

Tracked in [[obsidian/_summary]] easy-win backlog. Two recently shipped:

- ✓ **Backlink-summary frontmatter field** — implemented as Pass 4 in `relink.py` (`--refresh-incoming` flag). Refresh weekly via cron.
- **`/kb-explore` skill** — given a starting term, walk the link graph N hops with bounded token cost, return a summary tree. Specifically for LLM-driven exploration.
- **"Quick lookup" sub-section in `_summary.md`** — hand-curated top-3 entities + top-3 syntheses for each topic. A query can read just this section and get a 200-token map of the topic without reading the full summary.
- **Token-budget declarations in skill metadata** — each `SKILL.md` declares expected token cost per invocation (e.g. `expected_tokens: 5000`). Helps Claude pick the cheapest skill that answers the question.
- **`/kb-synthesise` retrofit** — use `obsidian search` for cross-source concept frequency.

## Related

- [[obsidian-cli]] — CLI capability matrix
- [[obsidian/_summary|Obsidian topic]] — landing page
- [[2026-04-30_kb-skill-cli-retrofit|2026-04-30 retrofit]] — original CLI integration of the KB skills
- [[skill-kb-relink|kb-relink]], [[skill-kb-lookup|kb-lookup]], [[skill-kb-ask|kb-ask]], [[skill-kb-lint|kb-lint]] — the skills that implement this recipe
