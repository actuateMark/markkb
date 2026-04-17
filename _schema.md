# Knowledge Base Schema

This knowledge base follows the [kb-starter](https://github.com/sbuffkin/kb-starter) structure.

## Directory Layout

```
knowledgebase/
  _schema.md          # this file -- structural specification
  _rules.md           # behavioral rules for agents
  _index.md           # navigation index (auto-maintained)
  _log.md             # change log
  _checkpoint.md      # last-sync checkpoint
  _dive-queue.md      # sources queued for ingestion
  _todo.md            # pending KB tasks
  bases/                        # Obsidian Bases (.base files, YAML)
    All Notes.base              # every note, filterable
    Syntheses.base              # cross-topic analyses
    Topic Summaries.base        # all summaries
    Concepts.base               # architecture/design notes
    Entities.base               # services, repos, people
    Sources.base                # ingested source material
    Recent Changes.base         # recently modified
    People.base                 # team member entities
  readinglist/
    Links.md          # global URL inbox
  topics/
    {topic-slug}/               # standalone topics
      _summary.md               # topic overview (always read first)
      sources/                  # immutable source notes (one per source)
      notes/
        concepts/               # concept notes (ideas, patterns, techniques)
        entities/               # entity notes (people, services, tools, repos)
        syntheses/              # synthesis notes (cross-source analysis)
    {group}/                    # grouped topics (e.g., integrations/, models/)
      {subtopic-slug}/          # same internal structure as standalone topics
        _summary.md
        sources/
        notes/{concepts,entities,syntheses}/
```

## Frontmatter Convention

Every note file uses YAML frontmatter:

```yaml
---
title: Note Title
type: concept | entity | synthesis | source | summary
topic: topic-slug
tags: [tag1, tag2]
sources: [source-file.md]       # for concept/synthesis notes
confluence: "https://..."       # link to Confluence source-of-truth
jira: "PROJ-123"               # related Jira ticket
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---
```

## Bases Convention

Database views use **Obsidian's native Bases plugin** (`.base` files), NOT Dataview codeblocks.

```yaml
# .base file format (YAML) -- filters go INSIDE the view
views:
  - type: table
    name: "View Name"
    filters:
      and:
        - file.folder.contains("topics/my-topic")  # folder scoping
        - '!file.name.startsWith("_")'                # negation (single-quoted)
        - type = "concept"                            # frontmatter match (single =)
    order:
      - file.link     # clickable link to the note
      - type          # columns to show
      - title
      - tags
      - updated
```

- **Global bases** go in `bases/` directory
- **Per-topic bases** go as `_base.base` in the topic directory
- Reference example: `knowledgebase/basicbase.base`
- See `topics/actuate-platform/notes/concepts/obsidian-bases-format.md` for full docs

## Rules

- **Source immutability:** Source notes cannot be edited post-creation.
- **Authorship guard:** `author: kb-bot` marks machine-generated notes. Human notes omit this field or use the author's name.
- **Concept threshold:** Concept notes are stubs (one sentence) for 1 source; full articles (500-1500 words) for 2+ sources.
- **Deep linking:** Use `[[wikilink]]` syntax for internal references.
- **Confluence links:** Always include `confluence:` frontmatter when the note mirrors a Confluence page.
- **Bases format:** Always use `.base` files (YAML) for database views. Never use Dataview codeblocks.
