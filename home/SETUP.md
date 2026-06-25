# KB system — set up your own instance

This repo is both **content** (the `topics/` Obsidian vault) and the **tooling** that operates it. This guide stands up the whole system on a fresh machine. Originally built by Mark; paths/credentials below assume his setup — **adjust for yours** (search for `/home/mork` and the vault path).

> **The system in one line:** an Obsidian vault of typed notes (`concept` / `synthesis` / `entity` / `source`), driven by Claude Code **skills + agents** for retrieval/ingestion/maintenance, with optional **cron automation** (relink/lint/recap/batch-intake) and an optional **local-LLM offload** (the npu-server "llm-shop") for token-free bulk work.

## What's in `_tooling/`
| Dir | What | Install to |
|---|---|---|
| `skills/` | 10 Claude Code skills (kb-ask, kb-lookup, kb-recap, kb-ingest, kb-synthesise, kb-queue, kb-auto, kb-sync, kb-lint, kb-relink) | `~/.claude/skills/` |
| `agents/` | 4 subagents (kb-scribe, source-reader, research-prospector, llm-shop-delegate) | `~/.claude/agents/` |
| `scripts/` | cron/automation scripts (kb-relink, kb-lint, kb-recap, kb-todo-scan, kb-batch-*, kb-job-runner/reap, rebuild-quartz + their `.service`/`.timer` units) | `~/bin/` (+ `~/.config/systemd/user/`) |
| `lib/` | shared `atlassian_query.py` / `nr_query.py` (used by kb-sync for Confluence/Jira/NR pulls) | `~/.claude/lib/` |
| `bin/` | the `obsidian` CLI (prebuilt **x86-64 Linux** binary — talks to a running Obsidian over a unix socket; gives cheap backlinks/tags/search/orphans). Provenance: `topics/obsidian/notes/entities/obsidian-cli.md`. Rebuild from source for other platforms. | `~/.local/bin/` |

## Prerequisites
- **Obsidian** (desktop) — open the repo root as a vault.
- **Claude Code** CLI.
- **Python 3.12 + uv** (`curl -LsSf https://astral.sh/uv/install.sh | sh`) — for the lib + some scripts.
- *(optional)* a always-on Linux host for the cron automation (Mark's was the "firebat" minipc — see `topics/personal-laptop/notes/concepts/2026-06-22_firebat-operations-runbook.md`).
- *(optional)* the npu-server local-LLM "shop" for token-free bulk intake (`topics/actuate-platform/notes/concepts/2026-06-22_npu-server-llm-shop-runbook.md`).

## Setup
1. **Clone + open the vault.** `git clone git@github.com:aegissystems/actuate-kb.git ~/Documents/worklog/knowledgebase` → open in Obsidian. Note conventions live in `rules/` (note types, frontmatter, topic layout).
2. **Install skills + agents + lib:**
   ```bash
   cp -r _tooling/skills/* ~/.claude/skills/
   cp _tooling/agents/* ~/.claude/agents/
   mkdir -p ~/.claude/lib && cp _tooling/lib/* ~/.claude/lib/
   ```
3. **Install the [[obsidian-cli|obsidian CLI]]** (Linux x86-64): `cp _tooling/bin/obsidian ~/.local/bin/ && chmod +x ~/.local/bin/obsidian`. Probe: `obsidian vault`.
4. **Adjust paths.** The skills/scripts assume the vault at `~/Documents/worklog/knowledgebase` and user `mork`. Grep and fix: `grep -rl '/home/mork' _tooling/` → update to your home/vault path.
5. **Credentials (only for the sync/ingest skills that pull external sources):**
   - Atlassian (kb-sync, kb-ingest of Confluence/Jira): `~/.config/atlassian/api-token` = `{"email","token","site"}`.
   - [[new-relic|New Relic]] (if you ingest NR data): `~/.config/newrelic/key`.
   - *(local KB use — kb-ask/kb-lookup/kb-lint/kb-relink — needs none of these.)*
6. **(Optional) cron automation:** copy `scripts/*` to `~/bin/`, the `.service`/`.timer` units to `~/.config/systemd/user/`, `systemctl --user enable --now <timer>`. This runs relink/lint/recap/batch-intake + the Quartz static-site rebuild on a schedule. See the firebat operations runbook for the full tier-1 pattern.
7. **(Optional) local-LLM offload:** stand up the npu-server llm-shop (see its runbook) and the `llm-shop-delegate` agent + `kb-intake`/`kb-batch-*` scripts will route bulk intake there instead of burning Claude tokens.

## How the pieces fit (workflow)
- **Retrieve before you act:** `/kb-lookup` (pre-coding context) and `/kb-ask` (free-form query) walk a cost-ordered ladder — `obsidian` CLI structural queries first, file reads only when needed.
- **Ingest sources:** `/kb-ingest <url|confluence|jira>` → `source-reader` agent reads → `kb-scribe` writes typed notes with frontmatter + wikilinks. `research-prospector` finds sources to read. Batch a reading list with `/kb-queue`; run headless from the `_dive-queue.md` with `/kb-auto`.
- **Synthesize:** `/kb-synthesise <topic>` cross-references accumulated source notes into a synthesis.
- **Maintain:** `/kb-lint` (broken wikilinks, orphans, missing frontmatter, staleness) and `/kb-relink` (enrich wikilinks/tags); `kb-todo-scan` surfaces broken-wikilink "write-this-stub" TODOs.
- **Recap:** `/kb-recap` summarizes what changed in a date range.
- **Publish:** `rebuild-quartz` renders the vault to a browsable static site.

## Caveats
- Skills/scripts carry **Mark-specific absolute paths** — step 4 is not optional if your layout differs.
- The `obsidian` CLI binary is **x86-64 Linux only**; rebuild from source elsewhere.
- Some scripts assume the **firebat cron host** layout (`~/.local/state/claude-jobs/`, a dashboard sink); they degrade gracefully but read best alongside the firebat runbook.
- This bundle is a **snapshot** (2026-06-23). The living sources are `actuateMark/claude-config` (skills/agents/lib) and `aegissystems/actuate-dev-toolkit` (scripts) — diverge over time.
