---
title: "Open Questions Inbox — design sketch"
type: concept
topic: engineering-process
tags: [kb-flow, open-questions, inbox, dashboard, follow-ups, llm-shop]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
status: design-sketch
incoming:
  - topics/personal-notes/notes/daily/2026-05-05.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-06
---

# Open Questions Inbox — design sketch

Captured 2026-05-05 during the Phase 2F shipping session. Mark surfaced this as a recurring KB pain point that deserves a dedicated tool.

## The pattern

KB notes — especially syntheses, research-drafts from `kb-todo-research`, ADRs, and investigation writeups — accumulate `## Open questions` sections (or `## Decisions to lock`, `## Follow-ups`, etc.). These are real items requiring real answers, but **there's no consolidated view** of them across the vault. Each lives in its source note, easily forgotten, no answer-capture flow, no follow-up trigger when answered.

## What we have today

A grep would tell us:

```bash
grep -rn -A 10 '^## Open questions' ~/Documents/worklog/knowledgebase/topics/
```

…which is fine for a one-shot audit but loses the inbox feel: a single place to triage, an ergonomic answer surface, an automatic "you answered this; let me follow up" trigger.

## What we want

```
┌─ Open Questions Inbox ───────────────────────────────────────────────┐
│                                                                       │
│ 1. [llm-shop / 2026-05-05_first-real-tasks-experiments] (3 questions) │
│    • What is the codebase implementation of BlurHandler?              │
│    • Is high entropy correlated with blur or with blank frames?       │
│    • What's the perf impact at scale?                                 │
│      [answer here ___________________________ ] [delegate to LLM 🛍️]  │
│                                                                       │
│ 2. [autopatrol / 2026-04-23_immix-api-error-patterns] (5 questions)   │
│    • …                                                                │
│                                                                       │
│ 3. [camera-health-monitoring / chm-end-to-end-flow] (12 questions)    │
│    • …                                                                │
│                                                                       │
│ Total: 47 unanswered questions across 8 notes.                        │
└──────────────────────────────────────────────────────────────────────┘
```

User can:
- Type an answer inline
- Delegate to the local LLM ([[llm-shop/_summary]]) for a draft answer
- Mark "won't fix" / "deferred" without answering
- Click into the source note to answer in-place

When an answer lands:
- The bullet's status changes (e.g., `- [ ]` → `- [x]` or a child line gets indented under)
- The next scan picks up the answered state
- Triggers a follow-up: append the answer to the source note, optionally write a wikilink to a more substantial note that elaborates, optionally close any related dive-queue entries

## Implementation sketch

### Tier 1 — Scanner (the foundation)

Sister to `kb-todo-scan` and `kb-recap`. Pure Python, ~120 LOC.

```bash
~/bin/kb-questions-scan         # emit JSON of all open-question bullets
~/bin/kb-questions-scan --by-topic   # group by topic
~/bin/kb-questions-scan --status open   # default: only unanswered
```

Output schema:

```json
[
  {
    "source": "topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md",
    "section": "## Open questions",
    "questions": [
      {
        "line": 134,
        "text": "What is the codebase implementation of BlurHandler?",
        "status": "open",         // open | answered | deferred
        "answer": null,
        "answer_line": null
      }
    ]
  }
]
```

Detection rules (v1):
- Find sections matching `^##\s+(Open\s+questions?|Decisions\s+to\s+lock|Follow-ups?|Outstanding|TBD)`
- Extract bullet items underneath until the next `^#` heading
- For each bullet: parse status from `[ ]` / `[x]` / `[~]` / `[!]` markers if present
- Status `answered` if the bullet has a child line starting with `→` or `Answer:` or just an indented continuation that isn't a sub-bullet

### Tier 2 — Aggregator + answer-capture surface

Two flavors to consider:

**Flavor A — Dashboard page on the llm-shop site** (lightweight, integrates with what we just shipped):
- New page `/questions` on `http://npu-server.tail9b2a4e.ts.net:8080/`
- Reads the scanner JSON
- One section per source note
- Inline `<textarea>` per question
- "Save answer" button → POST to `/api/answer` → writes back to source note (appends an indented child line under the bullet) → marks as `answered`
- "Delegate to LLM" button → calls a new harness `/api/answer-draft` with the question + source-note context → returns a draft answer → user reviews + saves

**Flavor B — Aggregator file in the KB** (Obsidian-native):
- Auto-generated `topics/personal-notes/notes/concepts/_open-questions-inbox.md`
- Markdown file with one section per source note
- Each question linked back via wikilink (`[[source-note#L134]]` or similar)
- User edits in Obsidian directly; periodic sync script propagates answers back

Recommendation: **A for the live triage flow, B as a daily-scope-friendly snapshot**. A is the workspace; B is the morning-coffee read.

### Tier 3 — Follow-up triggers

When the scanner detects an answer landed:
1. Append a `## Answers` log entry to the source note
2. If the answer references a new concept worth promoting, add it to `_dive-queue.md`
3. Notify the relevant workstream in mark-todos if cross-linked
4. Optional: have the LLM shop generate a follow-up note if the answer is substantial

## Why this is a real win

- **Decision velocity**: open questions decay if not surfaced. Today they hide in their source notes.
- **LLM-shop integration**: the local 14B / 32B models are *good at* drafting answers given context. Free draft per question.
- **Cross-cutting awareness**: questions in distant topics (camera-health-monitoring, autopatrol, infrastructure) become visible together. Patterns emerge.
- **Reduces "open questions" anxiety**: the act of *seeing* the list reduces the dread of working through it.

## Connections

- Same shape as the [[kb-todo-scan]] → [[kb-todo-research]] pipeline shipped 2026-05-05 — could share infrastructure
- Sibling to the [[obsidian-clipper-evaluation]] direction (`kb-intake` for external sources; this is `kb-questions` for internal follow-ups)
- [[obsidian-cli|Obsidian CLI]] already exposes `obsidian search` which can locate questions textually — but the section-aware parsing needs Python
- [[harness-pattern]] applies — a `/answer-draft` harness fits the same mold as `/code-delegate`

## Status

**Idea captured 2026-05-05.** Not scheduled. Should land after Phase 2F polish + Phase 2C subagent. Track via §24 successor or a new §N when prioritized.

## Open questions

- Should the scanner detect *any* `##` section that "feels like" open questions, or only an allow-listed set of headings? Recommendation: allow-listed (`Open questions`, `Decisions to lock`, `Follow-ups`, `Outstanding`, `TBD`). Reduces false positives.
- How does this coexist with mark-todos workstream sub-items? Those are *also* open questions in some sense. Probably keep separate — mark-todos is action, this is information.
- What's the right answer-capture format in the source markdown? Options: `→ <answer>` indented under the bullet, or `**Answer:** <answer>` on the next line, or a separate `## Answers` section. Recommendation: indented `→` for compact + scannable.
- Should this work even for notes that DON'T have `author: kb-bot` frontmatter? Probably yes — but the script can't *write* answers there, only read. (Per kb-starter Rule 1.)
