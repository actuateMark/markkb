---
title: "Agent: nrql-investigator"
type: entity
topic: engineering-process
tags: [agent, new-relic, nrql, observability, context-protection]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
outgoing:
  - topics/autopatrol/notes/concepts/2026-04-17_onboarder-nr-instrumentation-gap.md
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/engineering-process/notes/entities/agent-release-chain-watcher.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/automation-overnight-check.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/autopatrol/notes/concepts/2026-04-17_onboarder-nr-instrumentation-gap.md
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/engineering-process/notes/entities/agent-release-chain-watcher.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/automation-overnight-check.md
  - topics/personal-notes/notes/daily/2026-05-04.md
incoming_updated: 2026-05-08
---

# nrql-investigator

Context-protected [[new-relic|New Relic]] investigation agent. Holds the NR MCP toolset and the team's NRQL conventions so the parent context doesn't fill with raw log rows.

**File:** `/home/mork/.claude/agents/nrql-investigator.md`
**Model:** sonnet

## When to Use

- Connector log triage (errors, patterns, specific site_ids)
- Post-deploy error rate / issue comparison
- Metric trend checks (latency, throughput, GC, thread health)
- Deployment impact analysis
- Entity / change event lookups

## When NOT to Use

- One-off `get_entity` lookup the parent can do trivially
- Building alerts or dashboards (not in tool set)
- Any write operation (agent is read-only by design)

## What It Enforces

- Never `SELECT *` — named attributes only
- Aggregate first (`count(*)` / `FACET`) before raw rows
- Always scope to `cluster_name` + `container_name`
- `SINCE 1 hour ago` default; tight windows
- `LIMIT 10` on FACET, `LIMIT 5` on raw rows
- TIMESERIES for trends

## Reference Rules Baked In

- [[nrql-efficient-query-patterns]]
- [[nr-connector-query-cookbook]]
- [[nr-programmatic-deep-links]] — deep-link rules (onenr.io / staticChartUrl only)

## Reporting Format

Returns: finding + NRQL + top-line numbers + caveats. No raw row dumps unless the user asked. Target < 300 words.

## Skill Callers

| Skill | Where in skill | Notes |
|-------|----------------|-------|
| `/autopatrol-overnight-check` | Sections 3-5 (SQS flow, server health, connector errors) | Replaces inline NRQL sections; agent already has the rules baked in |
| `/stage-release` | Step 7 (post-deploy verification) | Short 5-min error-rate pulse on dev-api container |

## Related

- [[agents-catalog]]
- [[agent-release-chain-watcher]] — uses the same NRQL rules for post-deploy windows
