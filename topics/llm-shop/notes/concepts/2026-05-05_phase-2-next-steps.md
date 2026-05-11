---
title: "LLM Shop — Phase 2 next steps menu (2026-05-05)"
type: concept
topic: llm-shop
tags: [llm-shop, phase-2, planning, kb-todo-scan, code-delegate, kb-intake, subagent]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
outgoing:
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
  - topics/llm-shop/notes/syntheses/2026-05-07_overnight-batch-pattern.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

# LLM Shop — Phase 2 next steps menu

End-of-session 2026-05-05: Phase 1 + 2A + 2B done. Five plausible next moves laid out below. **Picked: A first** (with C as a likely sibling once needed). Order locked is **C → A → D → B → E** but A is being prototyped solo first to prove the shop-as-coding-tool loop.

> **Update 2026-05-06**: separate workstream landed off this menu — model-routed proxy + first source-control checkpoint of `~/llm-shop/`. Was triggered by the SYCL 14B going live on `:8200` and being unreachable from the playground (whose proxy only knew about `ollama` and `npu`). See [[2026-05-06_model-routed-proxy]]. The original A/B/C/D/E lineup is still the next-pick menu after that.

## The menu

| ID | Title | Scope | Why |
|---|---|---|---|
| **A** | Build Phase 2F: `kb-todo-scan` + `kb-todo-researcher` agent (broken-wikilink → reading queue → drafts) | ~150 LOC scanner + ~250 LOC subagent | Highest leverage. Closes real KB-curation pain. Uses shop for exactly what it's good at. Designed in [[2026-05-05_first-real-tasks-experiments]]. |
| **B** | Build Phase 2D `code-delegate` and `kb-intake` harnesses | ~300 LOC each | Proving harnesses on top of 14B + 8B. `kb-intake` closes §23 obsidian-clipper-evaluation. |
| **C** | Build Phase 2C Claude Code subagent `~/.claude/agents/llm-shop-delegate.md` | ~80 LOC of YAML+prose | Minimal glue. Any skill can delegate to the shop. Likely prerequisite for A. |
| **D** | Apply the `/api/warm-up` endpoint to `server.py` + test interactively | ~25 LOC | 5-min thing. Verifies experiment-to-codebase loop. The endpoint code from Qwen-14B is in [[2026-05-05_first-real-tasks-experiments]] (needs `httpx.NetworkError` → `httpx.RequestError` fix). |
| **E** | User-side test of Pi against the shop | 5 min | Drop the config block from `/catalog` into `~/.pi/agent/models.json`, run `pi -p "..."`. End-to-end smoke test of the IDE-tool loop. |

## Locked order

1. **C** — Claude Code subagent definition (unblocks A's "researcher" piece)
2. **A** — kb-todo-scan + researcher (the leverage play)
3. **D** — apply warm-up endpoint (quick checkpoint, verifies loop)
4. **B** — code-delegate + kb-intake harnesses (broader productization)
5. **E** — Pi smoke test (user-side, can happen anytime)

**Currently in flight:** A — building it solo first to prove the "use the shop as the main coding tool" pattern. C will be added once needed.

## Cross-references

- [[2026-05-04_phase-2-day-to-day-usage]] — Phase 2 design ADR
- [[2026-05-04_phase-1-installed]] — what's running
- [[2026-05-05_first-real-tasks-experiments]] — Qwen-14B warm-up experiment + Phase 2F design (broken-wikilink research)
- [[harness-pattern]] — harness vs subagent rubric
- [[mark-todos]] — §24 workstream
