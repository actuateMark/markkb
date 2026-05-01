---
title: "Agent: jira-landscape"
type: entity
topic: engineering-process
tags: [agent, jira, project-management, workstreams, context-protection]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# jira-landscape

Answers "who's working on what" and "what's the state of initiative X" from Jira without dumping ticket JSON into the parent context.

**File:** `/home/mork/.claude/agents/jira-landscape.md`
**Model:** haiku
**Mode:** read-only

## When to Use

- Mapping an initiative (ENG-122 umbrella, H1.2 autopatrol, H1.3 alerts)
- Per-person workload queries
- Identifying stalled epics or blocking tickets
- Getting linked / related tickets for context before starting work

## When NOT to Use

- Creating / editing / transitioning tickets — agent is read-only, parent handles writes
- Fetching full comment threads — agent stays shallow unless specifically asked
- One-off ticket lookup the parent can do in one MCP call

## Project Landscape Baked In

- **ENG** — external-API initiative (ENG-122 umbrella; ENG-123..133 workstreams)
- **AIM** — alerts-improvements (H1.3) — largely stalled as of April 2026
- **AUTO** — autopatrol (H1.2) — active, multi-workstream
- **DS** — data science / models

## KB Grounding

Reads relevant `_summary.md` first ([[external-api/_summary|external-api]], [[alerts-improvements/_summary|alerts-improvements]], [[knowledgebase/topics/autopatrol/_summary|autopatrol]], [[jira-organization/_summary|jira-organization]], [[team-structure/_summary|team-structure]]) before hitting Jira directly. Skips re-derivation when KB is fresh (< 14 days).

## JQL Hygiene

- Always `ORDER BY updated DESC`
- Default `maxResults: 25`
- Prefer epic link / linkedIssues over broad project scans

## Reporting Format

Workstream overview: status line, table (ticket / topic / owner / status / last update), blockers, notable activity. Per-person: grouped by project and status. Single ticket: title / status / assignee / blockers / links. Target < 300 words.

## Staleness Flag

If KB is > 14 days old, the agent live-checks top 3-5 tickets before reporting and flags staleness to the parent.

## Skill Callers

| Skill | Where in skill | Notes |
|-------|----------------|-------|
| `/kb-sync` | Step 3c + "Jira Projects to Scan" loop | Refresh status/assignee on tickets referenced in KB frontmatter |
| `/kb-ingest` | When argument is a Jira ticket / project keyword | Resolve ticket landscape before entity-note write |
| `/kb-auto` | When queue item is a Jira keyword | Same as kb-ingest |

## Related

- [[agents-catalog]]
- [[jira-organization/_summary|Jira organization topic]]
- [[team-structure/_summary|Team structure topic]]
