# Knowledgebase Rules & Guidelines

## 🤖 **Agents**
- Use `[[wikilinks]]` for cross-linking between topics.
- Update `_index.md` when adding/removing topics.
- Maintain `_schema.md` for data model definitions.
- Tag all `kb-bot` notes with `author: kb-bot`.

## 👨‍💻 **Humans**
- Verify all `kb-bot` notes have `author: kb-bot` tagging.
- Run weekly stale note checks (see `_staleness_check.sh`).
- Update `_summary.md` when new context impacts a topic.
- Prioritize `_todo.md` tasks for maintenance and validation.

## 🔄 **Sync Rules**
- Synchronize with Confluence/Jira via `_checkpoint.md`.
- Verify notes older than 30 days for staleness.
- Ensure external system updates are reflected in `_schema.md`.

## 🗂️ **Key Files**
| File                  | Purpose                                      |
|----------------------|-----------------------------------------------|
| `_index.md`          | Main directory structure                      |
| `_checkpoint.md`     | Sync status with Confluence/Jira             |
| `_dive-queue.md`     | Agent research tasks                          |
| `_todo.md`           | Maintenance and validation tasks              |
| `_schema.md`         | Data model definitions                        |

> 📚 For deeper rules, see: [Knowledgebase Rules](#knowledgebase-rules)