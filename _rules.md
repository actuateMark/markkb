# Knowledge Base Rules

## For Agents (Claude Code)

1. **Read order:** `_index.md` -> topic `_summary.md` -> individual notes. Load only what is needed.
2. **Never edit source notes.** Sources are immutable records of what was found at ingestion time.
3. **Always set `author: kb-bot`** on machine-generated notes.
4. **Update `_index.md`** after creating or deleting any topic or note.
5. **Update `_checkpoint.md`** after any sync operation with Confluence/Jira.
6. **Prefer updating over creating.** Check if a note already exists before writing a new one.
7. **Cross-link aggressively.** Use `[[wikilinks]]` to connect related notes across topics.
8. **Include Confluence/Jira links** in frontmatter so humans can navigate to the source of truth.
9. **Date all updates.** Always set `updated:` in frontmatter when modifying a note.
10. **Keep summaries current.** When adding notes to a topic, update its `_summary.md` if the new information changes the big picture.

## For Humans

1. **Don't edit `author: kb-bot` notes directly.** If the content is wrong, update the source or add a new note -- the next sync will pick it up.
2. **Your notes are safe.** Agents will never modify notes without `author: kb-bot`.
3. **Use `_dive-queue.md`** to queue URLs or topics for the agent to research.
4. **Use `_todo.md`** for KB maintenance tasks.
5. **Tag freely.** Tags are the primary discovery mechanism in Obsidian.

## Sync Rules

- **Confluence -> KB:** Summaries and key facts are distilled into notes. Full page content stays in Confluence.
- **Jira -> KB:** Active tickets are tracked in entity notes for people and projects. Closed tickets are not tracked.
- **Staleness:** Notes older than 30 days should be verified before acting on them.
- **Conflicts:** If a KB note contradicts current Confluence/Jira state, trust the external system and update the note.
