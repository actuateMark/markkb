---
title: "Architecture Decision Records (ADRs)"
type: concept
topic: engineering-process
tags: [adr, architecture, decisions, documentation]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/architecture-decision-records.md
  - topics/engineering-process/_summary.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Architecture Decision Records

ADRs capture significant technical decisions with their context, alternatives, and rationale. They live in the repo's `docs/backend/architecture-decisions.md` and are synced to Confluence via CI.

## When to Write an ADR

- Choosing between deployment strategies (Lambda vs k8s vs ECS)
- Changing data storage patterns (DynamoDB vs PostgreSQL vs both)
- Adding significant dependencies (actuate-libraries, new SDKs)
- Altering the API contract in a way that affects partners
- Any decision where "why did we do this?" will be asked in 6 months

## ADR Format

```markdown
## ADR-NNN: Title

**Status:** Proposed | Accepted | Denied | Deferred
**Date:** YYYY-MM-DD
**Context:** Jira ticket / project reference

### Decision
One paragraph: what we decided.

### Context
Why this decision was needed. What constraints exist.

### Options Considered
#### Option A: Name
Description, pros, cons.

#### Option B: Name (Recommended)
Description, pros, cons.

### Decision Rationale
Why we picked what we picked.
```

## Status Workflow

```
Proposed → Accepted (team agreed)
         → Denied (rejected with reason)
         → Deferred (not deciding now, with conditions for revisiting)
```

**Critical: Document denied decisions too.** The v5 project originally planned a Lambda→k8s migration (ADR-001). When the team denied it, we updated the ADR to "Denied" with the reason. This prevents future engineers from re-proposing the same migration without the context of why it was rejected.

## Open Questions Pattern

Before ADRs are decided, capture open questions in a separate section at the top of the architecture-decisions doc. Each question should have:
- The question itself
- Who needs to answer it (engineering, product, legal)
- What it blocks (which phase, which design choice)
- Space for the answer to be written inline by the reviewer

This pattern was used in v5: the user answered 12 questions directly in the document, and many answers fundamentally changed the project scope. Getting these answers early saved weeks of wasted implementation.

## Relationship to KB

After ADRs are decided, write a synthesis note to the KB capturing the decision. The ADR lives in the repo; the KB synthesis provides cross-project context and links to related decisions in other repos.
