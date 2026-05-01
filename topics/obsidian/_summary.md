---
title: "Obsidian"
type: summary
topic: obsidian
tags: [obsidian, knowledge-base, tooling, cli]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
---

Operating notes for the Obsidian app and its companion CLI — the tools that back this knowledge base. Where conventions about KB structure (topics, frontmatter, wikilinks) live in [[engineering-process/_summary|engineering-process]], this topic covers the **mechanics** of working with Obsidian: how to query the vault from a terminal, how the CLI integrates with Claude Code skills, how the laptop and firebat instances stay in sync.

## What lives here

- **[[obsidian-cli|Obsidian CLI]]** — the binary at `~/.local/bin/obsidian` on both laptop and firebat. Capabilities, install paths, environment quirks (especially the firebat container shim). See [[obsidian-cli]].
- **Bases** — the Obsidian Bases query language and view files. See [[obsidian-bases-format]] (currently parked under `actuate-platform/notes/concepts/`; will migrate when next touched).
- **Skill / agent integration** — how Claude Code's `kb-*` skills lean on the CLI to minimize context. See [[2026-04-30_kb-skill-cli-retrofit]].

## Two vault instances, one source of truth

| Host | Vault path (host-visible) | Vault name | CLI socket | How CLI invokes |
|---|---|---|---|---|
| laptop | `/home/mork/Documents/worklog` | `worklog` | `~/.obsidian-cli.sock` | Direct binary in `~/.local/bin/` |
| firebat | `/home/mork/.config/obsidian-remote/<vault-mount>` | `work` (in-container) | `~/.config/obsidian-remote/.obsidian-cli.sock` | Wrapper in `~/.local/bin/obsidian` sets `HOME` + unsets `XDG_RUNTIME_DIR` |

Vaults stay in sync via Obsidian Sync — same content, same tag set, same wikilink graph. CLI behavior is identical across the two boxes once the wrapper is in place.

## How to query the vault from a terminal

| Goal | Command | Notes |
|---|---|---|
| Sanity check | `obsidian vault` | Returns `name<TAB>path<TAB>files<TAB>folders<TAB>size` |
| All tags + counts | `obsidian tags counts` | TSV; pipe to `sort -t$'\t' -k2 -n -r` for hot tags |
| Files using a tag | `obsidian tag name=#vms-connector` | Returns one path per line |
| Backlinks to an anchor | `obsidian backlinks file=nrql-efficient-query-patterns` | One path per referrer |
| Outgoing links | `obsidian links file=<name>` | What does this note point at? |
| Broken wikilinks | `obsidian unresolved` | Replaces recursive grep for missing targets |
| Notes with no incoming links | `obsidian orphans` | Discovery-graph holes |
| Notes with no outgoing links | `obsidian deadends` | Connective-tissue holes |
| Phrase search | `obsidian search query="<phrase>"` | Vault-wide, single call |
| Phrase + context | `obsidian search:context query="<phrase>"` | Includes surrounding lines |

Full command list: `obsidian --help`. Output formats: most commands accept `format=tsv|csv|json` for downstream parsing.

## Why this matters for Claude Code

The KB has ~1050 notes across ~30 topics with ~1300 unique tags. Recursive Grep across that surface is expensive in tokens. The CLI exposes structured discovery primitives (tags, backlinks, search, unresolved/orphans/deadends) that return ranked answers in one call. The KB skills (`/kb-relink`, `/kb-lint`, `/kb-lookup`, `/kb-ask`, `kb-scribe` agent) all prefer the CLI over recursive Grep when the CLI is available — see [[2026-04-30_kb-skill-cli-retrofit]] for the per-skill mapping and the install/availability check pattern they share.

## Context-efficient retrieval recipe

The canonical pattern for querying the KB without burning context lives at [[2026-05-01_context-efficient-kb-retrieval]] — a cost-ordered ladder (read summary → tag query → backlinks → search → file read), the per-skill integration status, and the structural choices (slug-style anchors, path-form topic links, threshold-gated tag enrichment) that make tier-2/tier-3 queries actually return useful results.

Before reaching for a recursive grep, walk the ladder. The 2026-05-01 [[2026-04-30_kb-skill-cli-retrofit|CLI retrofit]] + relink pass built up the link/tag graph that makes tier 2-3 cheap and accurate.

## Easy-win backlog (track new ones here as they surface)

When discovering a new "this skill could use the CLI but doesn't yet" gap, list it here as a checkbox so it's reachable from this summary. Promote to a synthesis note when more than a couple are accumulating.

- [ ] `/kb-synthesise` — source-scan loop currently uses Grep; could use `obsidian search query="<concept>"` to get concept frequency across sources in one call
- [ ] `/kb-recap` — currently uses `find -mtime`; could pair with `obsidian files` for vault-wide listing (low value but consistent)
- [ ] Daily-note auto-tagging — when `/daily-wrap` writes the day's note, run `obsidian tags counts` to surface which `#workstream-NN` tags were used today vs last week (light analytics, no code change needed yet)
- [ ] `obsidian properties` to validate frontmatter schema across the vault — could feed `/kb-lint` Check 2
- [ ] **"Quick lookup" sub-section in topic `_summary.md`** — hand-curated top-3 entities + top-3 syntheses; cheapest entry for cross-topic queries
- [ ] **Backlink-summary frontmatter field** — periodic script populates `incoming: [...]` from `obsidian backlinks`; LLM reads frontmatter and sees referrer set without a separate CLI call
- [ ] **`/kb-explore` skill** — given a term, walk the link graph N hops with bounded token cost; designed for LLM-driven exploration
- [ ] **Token-budget declarations in skill metadata** — each SKILL.md declares `expected_tokens: N` so Claude can pick the cheapest skill that answers the question

## Related

- [[obsidian-cli]] — full entity note with capability matrix and the firebat wrapper
- [[2026-04-30_kb-skill-cli-retrofit]] — synthesis of the 2026-04-30 retrofit pass
- [[obsidian-bases-format]] — the Bases query language (filed under `actuate-platform`; future migration candidate)
- [[engineering-process/_summary|engineering-process]] — KB conventions (topic structure, frontmatter, wikilinks, skill catalog)
- [[personal-laptop/_summary|personal-laptop]] — laptop tooling (where the laptop CLI binary lives)
