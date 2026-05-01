---
title: "Agents Catalog"
type: entity
topic: engineering-process
tags: [agents, subagents, claude-code, workflow, routing, new-relic]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Agents Catalog

Custom Claude Code subagents installed at `/home/mork/.claude/agents/`. Invoke via the Agent tool with `subagent_type: <name>`. Each agent protects the main context from a specific high-volume task by narrowing its tool set and baking in team conventions.

## Catalog

| Agent | Model | When to invoke | Scope / Tools |
|-------|-------|---------------|---------------|
| [[agent-nrql-investigator]] | sonnet | Any NR investigation — connector log triage, deploy verification, error patterns, metric trends | NR MCP only; read KB query cookbook |
| [[agent-actuate-pr-reviewer]] | opus | Reviewing a PR in any Actuate repo under `/home/mork/work/` | gh + Read/Grep; applies KB security & code-review checklists |
| [[agent-kb-scribe]] | haiku | Writing or updating a KB note with proper frontmatter + routing | Write/Edit on `/knowledgebase/` only |
| [[agent-connector-pipeline-expert]] | opus | Architecture/implementation questions about the [[vms-connector|VMS connector]] pipeline | Read-only on `vms-connector` + `actuate-libraries` |
| [[agent-release-chain-watcher]] | sonnet | Monitoring a release from PR → merge → [[argocd|ArgoCD]] → post-deploy NR health | gh + NR MCP; ideal for background runs |
| [[agent-jira-landscape]] | haiku | Mapping Jira initiatives, workstreams, assignees, blockers | Atlassian MCP (read-only) |

## Proposed / Not Yet Built

Agents designed but not implemented. Build decisions tracked in [[mark-todos]].

| Agent | When it would be built | Scope |
|-------|----------------------|-------|
| [[agent-issue-auditor]] | After 1-2 manual issue-hygiene sweeps stabilize the standard (see [[2026-04-17_issue-hygiene-plan]]) | Audit GitHub issues against the issue-creation standard; propose normalization edits; read-only default |

## Routing Rules

Use these to decide when to delegate vs. work in-context. If a task matches, prefer the agent.

### Observability

- **NR query or log check** → `nrql-investigator`. Do not call `mcp__newrelic__*` from the parent except for one-off trivial lookups.
- **Post-deploy health window** → `release-chain-watcher` (background).

### Code Review & Security

- **PR review requested** (`/validate-release`, gh PR URL, "review this") → `actuate-pr-reviewer`.
- **Security audit of specific endpoint/module** → `actuate-pr-reviewer` scoped to the file paths.

### Codebase Exploration

- **"Where does X happen in the connector?"** → `connector-pipeline-expert`.
- **"Which library implements Y?"** → `connector-pipeline-expert`.
- **Admin API / inference API / other services** → NOT this agent; use `general-purpose` or `Explore` until dedicated agents exist.

### Release Management

- **Merging a PR and waiting for deploy** → `release-chain-watcher` with `run_in_background: true`.
- **Library publish verification** → `release-chain-watcher` (knows the GITHUB_TOKEN risk).

### KB Operations

- **Write new concept/synthesis/entity note** → `kb-scribe`. Give it the raw findings; it handles frontmatter, routing, wikilinks.
- **Read/search the KB** → use `/kb-ask` or direct Grep, NOT `kb-scribe` (it's write-only).
- **Bulk ingestion from reading list** → use `/kb-queue` skill, NOT `kb-scribe`.

### Project Management

- **"What's the state of ENG-122 / H1.3 / autopatrol workstreams?"** → `jira-landscape`.
- **Per-person work mapping** → `jira-landscape`.
- **Creating or editing tickets** → NOT this agent (read-only); parent handles writes.

## Anti-Patterns

- Don't invoke `nrql-investigator` for a single `get_entity` lookup — the overhead isn't worth it.
- Don't invoke `kb-scribe` to write a memory file — memories go to `/home/mork/.claude/projects/-home-mork/memory/`, not the KB.
- Don't invoke `actuate-pr-reviewer` for non-Actuate repos or for trivial one-line PRs.
- Don't spawn `connector-pipeline-expert` and then also Grep from the parent — pick one.

## Skill ↔ Agent Matrix

Which agents each skill should delegate to during execution. Rows are skills; columns are agents.

| Skill | nrql-investigator | actuate-pr-reviewer | kb-scribe | connector-pipeline-expert | release-chain-watcher | jira-landscape |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|
| `/api-endpoint-development` | | ✓ phase 7 | ✓ phase 8 | | | |
| `/autopatrol-overnight-check` | ✓ §3-5 | | ✓ post-run | | | |
| `/generate-project-docs` | | | ✓ KB copy | ✓ phase 1 (connector only) | | |
| `/kb-ask` | — | — | — | — | — | — |
| `/kb-auto` | | | ✓ steps 2d-2f | | | ✓ Jira items |
| `/kb-ingest` | | | ✓ steps 4-7 | | | ✓ Jira args |
| `/kb-lint` | — | — | — | — | — | — |
| `/kb-lookup` | — | — | — | — | — | — |
| `/kb-queue` | | | ✓ per-item | | | ✓ Jira items |
| `/kb-sync` | | | ✓ step 5 | | | ✓ step 3c |
| `/kb-synthesise` | | | ✓ step 6 | | | |
| `/stage-release` | ✓ step 7 pulse | ✓ step 2 | | | ✓ steps 3/6/7 | |
| `/write-external-docs` | | ✓ step 5 | | | | |

`—` = intentionally no agent (read-only small-output patterns that shouldn't delegate).

**Top-3 highest-value linkings:**
1. `/autopatrol-overnight-check` → `nrql-investigator` (§3-5): eliminates 5+ raw NRQL result dumps from parent per run.
2. `/kb-auto` + `/kb-ingest` + `/kb-sync` → `kb-scribe`: parent fetches (needs Atlassian/WebFetch), scribe writes. Largest context sink in KB skills.
3. `/stage-release` → `release-chain-watcher` (background, steps 3/6/7): frees the parent while the watcher polls gh + NR.

## Relation to Skills

Skills (`/kb-ingest`, `/stage-release`, `/api-endpoint-development`, etc.) and agents can overlap. Rule of thumb:

- **Skill** — a procedure with steps, invoked by the user with `/`. Runs in-context, has full repo access, user-facing.
- **Agent** — a context-protected worker. Runs in isolation, returns a summary. Best for high-volume reads (NR, Jira, large codebases) or parallelizable work.

When both apply (e.g., PR review has both `/validate-release` skill and `actuate-pr-reviewer` agent), use the skill for the full workflow and the agent inside the skill for the review step.

## Related

- [[code-review-checklist]] — what `actuate-pr-reviewer` enforces
- [[security-hardening-checklist]] — also enforced by `actuate-pr-reviewer`
- [[pydantic-schema-as-contract]] — also enforced by `actuate-pr-reviewer`
- [[nrql-efficient-query-patterns]] — baked into `nrql-investigator`
- [[nr-connector-query-cookbook]] — templates used by `nrql-investigator`
- [[nr-programmatic-deep-links]] — link rules for NR agents
- [[skill-api-endpoint-development]] — companion skill pattern
- [[feature-development-lifecycle]] — where these agents slot into the lifecycle
