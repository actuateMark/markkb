---
title: "Obsidian Bases Format"
type: concept
topic: actuate-platform
tags: [obsidian, bases, tooling, kb-infrastructure]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/obsidian/_summary.md
incoming_updated: 2026-05-01
---

# Obsidian Bases Format

Obsidian Bases is a **built-in core plugin** (not Dataview) that provides database-like views of vault notes. Base files use the `.base` extension and YAML format.

## File Format

`.base` files are YAML with this schema (from `obsidian.d.ts`):

```yaml
# BasesConfigFile
filters?: BasesConfigFileFilter    # global filters
properties?: Record<string, Record<string, any>>  # property display config
formulas?: Record<string, string>  # computed columns
summaries?: Record<string, string> # summary formulas
views?: BasesConfigFileView[]      # view definitions
```

### Views

```yaml
views:
  - type: table       # "table" is the primary view type
    name: "View Name"
    filters?: ...     # per-view filters (same format as global)
    groupBy?: {}      # grouping config
    order?: string[]  # sort order (e.g., "updated desc")
    summaries?: {}    # per-view summaries
```

### Filters

**Critical:** Filters go **inside the view**, not at the root level. Use method-style expressions.

```yaml
views:
  - type: table
    name: My View
    filters:
      and:
        - file.folder.startsWith("topics/my-topic")   # folder scoping
        - '!file.name.startsWith("_")'                 # negation (quote with '')
        - type = "concept"                             # frontmatter property match
    order:
      - updated          # columns to show, in order
      - type
      - title
      - tags
```

**File properties:** `file.folder`, `file.name`, `file.mtime`
**Methods:** `.startsWith("...")`, `.endsWith("...")`
**Negation:** prefix with `!`, wrap in single quotes: `'!file.name.startsWith("_")'`
**Frontmatter match:** `property = "value"` (single `=`, value in quotes)
**Logical operators:** `and: [...]`, `or: [...]`

### Order (columns)

The `order` array defines which columns appear and their default sort. Just list property names:

```yaml
order:
  - file.name     # file name column
  - type           # frontmatter: type
  - topic          # frontmatter: topic
  - tags           # frontmatter: tags
  - updated        # frontmatter: updated
  - file.mtime     # file modification time
```

## Rules for Creating Bases

1. **Always use `.base` extension** -- never use Dataview codeblocks
2. **Filters go inside the view**, not at root level
3. **Use `file.folder.startsWith("path")`** to scope to a folder
4. **Use `property = "value"`** for frontmatter filtering (single `=`)
5. **Quote negations** with single quotes: `'!expr'`
6. **Place global bases in `bases/`** directory
7. **Place per-topic bases as `_base.base`** in the topic directory

## Current Bases in This KB

**Global (in `bases/`):** All Notes, Syntheses, Topic Summaries, Concepts, Entities, Sources, Recent Changes, People

**Per-topic:** `_base.base` in each of the 18 core topics + integrations group + models group
