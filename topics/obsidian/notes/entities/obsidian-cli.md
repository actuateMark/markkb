---
title: "Obsidian CLI"
type: entity
topic: obsidian
tags: [obsidian, cli, knowledge-base, tooling]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - _index.md
  - topics/obsidian/_summary.md
  - topics/obsidian/notes/syntheses/2026-04-30_kb-skill-cli-retrofit.md
  - topics/obsidian/notes/syntheses/2026-05-01_context-efficient-kb-retrieval.md
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - _index.md
  - topics/engineering-process/notes/concepts/2026-05-05_open-questions-inbox-idea.md
  - topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md
  - topics/obsidian/_summary.md
  - topics/obsidian/notes/syntheses/2026-04-30_kb-skill-cli-retrofit.md
  - topics/obsidian/notes/syntheses/2026-05-01_context-efficient-kb-retrieval.md
  - topics/personal-notes/notes/daily/2026-05-01.md
incoming_updated: 2026-05-08
---

Stripped ELF binary that talks to a running Obsidian instance over a unix socket and exposes the vault's data model (files, tags, links, search) as a structured CLI. Shipped with recent Obsidian builds when the user enables CLI access in Settings → Tools. Once enabled, Obsidian writes the binary to `~/.local/bin/obsidian` and the socket to `~/.obsidian-cli.sock`.

## Install paths

| Host | Binary | Socket | PATH source |
|---|---|---|---|
| laptop (`actuate-dev`) | `/home/mork/.local/bin/obsidian` | `/home/mork/.obsidian-cli.sock` | `.profile` adds `~/.local/bin` if it exists |
| firebat (`mork-firebat`) | wrapper at `/home/mork/.local/bin/obsidian` → in-container binary at `/home/mork/.config/obsidian-remote/.local/bin/obsidian` | `/home/mork/.config/obsidian-remote/.obsidian-cli.sock` | `.bashrc` line 121 sources `~/.local/bin/env`, which prepends `~/.local/bin` |

### The firebat wrapper

Obsidian on the firebat runs in an `obsidian-remote` Docker container that mounts `/home/mork/.config/obsidian-remote/` into `/config/` inside the container. The Obsidian app's own user-data-dir is `/config/.config/obsidian`, so the CLI socket lands at `/config/.obsidian-cli.sock` inside the container, which is `/home/mork/.config/obsidian-remote/.obsidian-cli.sock` on the host.

Two environment quirks matter when invoking the binary from the host:
1. The CLI checks `XDG_RUNTIME_DIR` first for the socket. On the host this points at `/run/user/<uid>/` which doesn't have the socket. **Unset `XDG_RUNTIME_DIR`** so it falls through to `HOME`.
2. The CLI then looks at `$HOME/.obsidian-cli.sock`. **Set `HOME=/home/mork/.config/obsidian-remote`** so it resolves the path correctly.

The wrapper at `/home/mork/.local/bin/obsidian` on firebat:

```bash
#!/bin/bash
exec env -u XDG_RUNTIME_DIR HOME=/home/mork/.config/obsidian-remote \
  /home/mork/.config/obsidian-remote/.local/bin/obsidian "$@"
```

## Capability matrix

The CLI ships ~70 commands. The ones useful for KB skills:

### Discovery (one-call structured queries)

| Command | Output | Use for |
|---|---|---|
| `obsidian vault` | name + path + counts | Health probe |
| `obsidian files` | one path per line | Vault file listing |
| `obsidian folders` | one folder per line | Topic / subdirectory enumeration |
| `obsidian tags` (`counts`, `total`) | TSV `#tag<TAB>count` | Canonical tag inventory |
| `obsidian tag name=#X` | files using a tag | Topic discovery via tags |
| `obsidian aliases` (`verbose`, `total`) | aliases or aliases+paths | Anchor discovery |
| `obsidian properties` | frontmatter property listing | Frontmatter schema audit |

### Link graph

| Command | Use for |
|---|---|
| `obsidian backlinks file=<name>` | What links to this anchor? |
| `obsidian links file=<name>` | What does this anchor link to? |
| `obsidian unresolved` | Broken wikilinks (target missing) |
| `obsidian orphans` | Notes with no incoming links |
| `obsidian deadends` | Notes with no outgoing links |

### Search

| Command | Use for |
|---|---|
| `obsidian search query="<text>"` | Vault-wide phrase search |
| `obsidian search:context query="<text>"` | Search with surrounding line context |
| `obsidian search:open query="<text>"` | Open the search view in the GUI |

### Read / write

| Command | Notes |
|---|---|
| `obsidian read file=<name>` | Read by name (resolves like a wikilink) |
| `obsidian read path=<folder/note.md>` | Read by exact path |
| `obsidian append file=<name> content="..."` | Append content (use `\n` for newlines, `inline` flag to skip the leading newline) |
| `obsidian prepend file=<name> content="..."` | Prepend content |
| `obsidian create name=<name> content="..."` | Create a new file (use `path=` for nested) |
| `obsidian move src=<old> dest=<new>` | Move/rename |
| `obsidian delete file=<name>` | Delete |

### Daily notes

`obsidian daily`, `daily:append`, `daily:prepend`, `daily:read`, `daily:path` — all the operations a hook needs to write into today's daily note without computing the path.

### Output formats

Most commands accept `format=tsv|csv|json|md|paths`. Default is `tsv` for list outputs. `format=json` gives structured records — useful when piping to `jq`.

## Common patterns

```bash
# Most-used tags (top 20)
obsidian tags counts | sort -t$'\t' -k2 -n -r | head -20

# Find broken wikilinks and which files reference them
for target in $(obsidian unresolved); do
  echo "=== $target ==="
  obsidian backlinks file="$target"
done

# Token-cheap "who references X?" — replaces grep -rn '\[\[X\]\]'
obsidian backlinks file=actuate-config

# Tag-driven topic walk — replaces recursive grep on frontmatter
obsidian tag name=#new-relic | head -20

# Frontmatter property audit
obsidian properties

# Output as JSON for downstream tooling
obsidian backlinks file=actuate-config format=json | jq '.[]'
```

## Failure modes

- **"The CLI is unable to find Obsidian"** — Obsidian app isn't running, OR socket is at a different path, OR `HOME`/`XDG_RUNTIME_DIR` point at the wrong place. On the firebat, this usually means the wrapper isn't being used (PATH issue) or the obsidian-remote container is down.
- **Empty output** — vault might be configured with a different default; pass `vault=<name>` to target a specific vault.
- **Stale data** — the CLI reflects the running Obsidian's current vault state. If a sync hasn't completed yet, queries against the laptop and firebat may return different results until convergence.

## Related

- [[obsidian/_summary|Obsidian topic]] — overview and easy-win backlog
- [[2026-04-30_kb-skill-cli-retrofit]] — the 2026-04-30 retrofit of the KB skills to use the CLI
- [[skill-kb-relink]] — uses `obsidian tags counts` for the tag-enrichment pass
- [[skill-kb-lint]] — uses `unresolved`, `orphans`, `deadends`
- [[skill-kb-lookup]] — prefers `tag name=` and `backlinks` over Grep
- [[skill-kb-ask]] — uses `search:context` for phrase queries
