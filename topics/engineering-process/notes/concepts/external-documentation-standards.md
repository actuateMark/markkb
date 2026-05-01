---
title: "External Documentation Standards"
type: concept
topic: engineering-process
tags: [documentation, external, api-docs, partners, security]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/entities/agent-actuate-pr-reviewer.md
  - topics/engineering-process/notes/entities/skill-api-endpoint-development.md
  - topics/engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle.md
incoming_updated: 2026-05-01
---

# External Documentation Standards

Rules for writing API documentation visible to integration partners. Derived from the v5 inference API docs review where internal details (role names, infrastructure, library references) were found in customer-facing pages.

## Core Principle

External docs answer: **what to call, what to send, what comes back, what can go wrong.** They never explain how it works internally.

## What Leaks and Why It Matters

| Leak Type | Example | Risk |
|-----------|---------|------|
| Role names | Internal role identifiers | Reveals [[rbac-model|RBAC model]]; aids privilege escalation probing |
| Infrastructure | Lambda, API Gateway, DynamoDB | Reveals attack surface |
| Libraries | Pydantic, PIL, SAHI | Reveals dependency versions for CVE targeting |
| File paths | Internal source file paths | Reveals project structure |
| Processing order | "RBAC before validation" | Reveals security architecture |
| Internal tooling | Test pages, dev endpoints | Reveals dev surface area |

## Dynamic Content for Role-Gated APIs

When docs list resources the user may not have access to (e.g., model lists), use placeholder tags that the serving layer replaces at runtime:

```markdown
## Available Models

<!-- MODEL_TABLE -->
```

The docs API replaces `<!-- MODEL_TABLE -->` with a role-filtered table before serving. This keeps the markdown files readable in GitHub while the served version respects permissions.

Pattern: `_build_model_table(user_roles, doc_path)` in the docs endpoint generates the table from the model registry, filtered by `has_role_access()`.

## Rewriting Internal Language

| Don't Say | Say Instead |
|-----------|------------|
| "SAHI sliced inference" | "analyzes images at multiple zoom levels" |
| "frame difference computation" | "detects moving objects, ignores static background" |
| "PIL image verification" | "validated as a valid image" |
| "Lambda payload limit of 6MB" | "maximum ~4.5 MB per base64-encoded frame" |
| "Pydantic schema validation" | "validated against the model's expected format" |
| "filtered by your API key's roles" | "available to your API key" |

## Skill

Use `/write-external-docs` to create or review external documentation. It enforces these standards automatically.

## Reference Implementation

See [[v5-implementation-patterns]] in the inference-api topic for the concrete translation table and file paths.
