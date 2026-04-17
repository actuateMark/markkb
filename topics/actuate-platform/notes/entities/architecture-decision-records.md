---
title: "architecture-decision-records"
type: entity
topic: actuate-platform
tags: [adr, architecture, decisions, documentation, ai-agents]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# architecture-decision-records

A centralized repository for Architecture Decision Records (ADRs) that captures cross-cutting technical and architectural decisions affecting multiple Actuate repos or workstreams. Designed to be referenced by both human engineers and AI agents during development.

**Repo:** `aegissystems/architecture-decision-records` (GitHub, private)
**Description:** Centralized ADR repo for AI agents and developers
**Last updated:** 2026-03-05

## Purpose

As the Actuate platform grows across dozens of repositories, it becomes difficult to remember why certain architectural choices were made. This repo provides a written record that serves three audiences:

1. **New contributors** onboarding who need to understand existing constraints.
2. **AI agents** assisting with development who need grounded context about prior decisions.
3. **Teams revisiting past choices** to evaluate whether circumstances have changed.

Decisions scoped to a single repo should live in that repo's own `adr/` folder instead. This repo is reserved for decisions that span multiple services or workstreams.

## Process

The workflow is intentionally lightweight with no formal RFC lifecycle:

1. **Branch** from `main` using the naming convention `ADR-NNN/JIRA-123-short-title` (Jira ticket optional).
2. **Author** an ADR using the template at `adr/000-template.md`.
3. **Open a PR** where all debate, alternatives, and trade-offs are discussed.
4. **Merge** when accepted. The merged ADR is the final decision. Reversals or superseding changes are captured in new ADRs that reference the original.

## Structure

```
adr/
  000-template.md                            # Template for new ADRs
  001-use-adrs-for-cross-repo-decisions.md   # First ADR (bootstrapping)
  NNN-short-title.md                         # Subsequent ADRs
```

ADRs are numbered sequentially with lowercase kebab-case filenames.

## AI Agent Integration

AI agents operating across Actuate projects should read relevant ADRs before proposing changes to areas covered by an existing decision, cite ADRs when explaining rationale, and propose new ADRs via pull request when a cross-repo decision needs to be made. This makes the repo a key input for the [[actuate-claude-agents|Claude agent]] workflows used across the organization.

## Relationship to Other Repos

This repo is informational and does not deploy any services. It is referenced by any Actuate repository whose CLAUDE.md or development docs point agents to read ADRs before making architectural changes.
