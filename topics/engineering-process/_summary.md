---
title: Engineering Process
type: summary
topic: engineering-process
tags: [process, development, lifecycle, methodology, standards]
created: 2026-04-14
updated: 2026-04-16
author: kb-bot
---

# Engineering Process

Standards, lifecycle patterns, and operational rules for Actuate engineering work. These are derived from actual project execution and codified as repeatable process.

## Core Documents

| Document | Type | Purpose |
|----------|------|---------|
| [[feature-development-lifecycle]] | Synthesis | End-to-end lifecycle for building a new feature — from planning through deployment |
| [[connector-library-deployment-lifecycle]] | Synthesis | Multi-repo deployment lifecycle for vms-connector + actuate-libraries — library stabilization, stage merge, ECR builds, NR monitoring |
| [[code-review-checklist]] | Concept | What to check during review — security, correctness, test coverage, documentation |
| [[security-hardening-checklist]] | Concept | Input validation, error handling, RBAC integration standards |
| [[adr-writing-guide]] | Concept | Architecture Decision Record format, status workflow, open questions pattern |
| [[dev-test-tooling-pattern]] | Entity | Test page + run script pattern for local API testing |
| [[pydantic-schema-as-contract]] | Concept | Using Pydantic models for validation, documentation, and UI generation simultaneously |
| [[async-concurrency-patterns]] | Concept | `asyncio.to_thread` and `asyncio.gather` patterns for FastAPI — CPU-bound and IO-bound work |
| [[external-documentation-standards]] | Concept | Rules for writing partner-facing API docs — what to include, what leaks, dynamic role-filtered content |
| [[api-endpoint-development]] | Skill | Full cycle: Pydantic models with Swagger examples, schema-as-contract, RBAC, validation, external docs, testing |
| [[agents-catalog]] | Entity | Custom Claude Code subagents installed at `~/.claude/agents/` — when to invoke each, scope, anti-patterns |

## Key Principles

1. **Plan before code** — architecture decisions and design review happen before implementation
2. **KB-driven context** — always check the KB before starting; always update it after finishing
3. **Security at every boundary** — validate all inputs, check RBAC before validation, never leak internal state
4. **Test what you build** — unit tests + local integration test + full regression before merge
5. **Document what you ship** — API docs, backend docs, KB synthesis notes, all updated before deploy
6. **Review intensely** — lint, security audit, code review, then review again

## Related Topics

- [[actuate-platform]] — overall architecture
- [[inference-api]] — primary project where this process was developed
- [[infrastructure]] — deployment and IaC patterns
