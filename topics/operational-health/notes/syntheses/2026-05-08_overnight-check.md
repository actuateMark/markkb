---
title: "Overnight Health Check 2026-05-08"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-08
updated: 2026-05-08
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-08
---

# Overnight Health Check 2026-05-08

## Summary

DEGRADED — data collection failed. Headless session lacks approval for the Bash → `nr_query.py` network call (sandbox approval gate). No NR queries executed; health status is unknown for autopatrol, connector fleet, alert delivery, and NR Issues. Run the queries below from an interactive session or a Tier-1 Firebat script to obtain real signal.

## Issues Found

- **Headless sandbox blocked all NR queries.** Both parent-context Bash and four nrql-investigator subagents hit the same approval gate on `python3 /home/mork/.claude/lib/nr_query.py …`. MCP `mcp__newrelic__*` tools are not loaded in this session (only `mcp__kubefwd__*` and `mcp__aws-documentation__*` are available); `list_recent_issues` is therefore not callable here either.
- **No verdict possible** on the autopatrol pipeline, connector fleet errors, alert-delivery containers, or new NR issues opened in the last 12h.
- **Routing fix candidate (Tier-1):** this is exactly the case for which the three-tier routine-check pattern recommends a Firebat script. A headless Tier-3 LLM run that depends on interactive Bash approval cannot succeed unattended. Consider promoting `/autopatrol-overnight-check` (NR-only path) and the connector/alert/issue surveys here to a Firebat systemd-timer script that writes to `~/.local/state/claude-jobs/` and let the morning skill consume that cache.

## AutoPatrol

Not collected. Required NR queries:

- Patrols per site (sites 41158, 41178, 40672, 45061, 37837) — not run.
- autopatrol-server ERROR count — not run.
- CNCTNFAIL per site — not run.
- Connector-side `%autopatrol%` containers ERROR FACET — not run.

Cannot flag silent-patrol gaps or persistent CNCTNFAIL without the data. The /autopatrol-overnight-check skill could not be invoked even in NR-only mode because its underlying Bash calls are gated.

## Connector Fleet

Not collected. ERROR-by-container FACET (`SINCE 12 hours ago LIMIT 15`) blocked. Cannot flag any container > 100 errors.

## Alert Delivery

Not collected. ERROR FACET across the canonical names (`queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`) blocked. Cannot flag any container > 20 errors.

## New Issues

Not collected. Neither the MCP `list_recent_issues` tool (server not loaded) nor the `NrAiIncident` NRQL fallback could be executed. Severity distribution and top entities unknown.

## Raw NRQL

<details>
<summary>Queries that should have run (12h window, account 3421145, cluster_name='Connector-EKS')</summary>

```sql
-- Q1: Patrols per site (autopatrol-server log volume)
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago

-- Q2: autopatrol-server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND level='ERROR'
SINCE 12 hours ago

-- Q3: CNCTNFAIL counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago

-- Q4: Connector-side autopatrol errors by container
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- Q5: Connector fleet ERROR counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- Q6: Alert-delivery container errors (canonical names)
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker'
  )
FACET container_name
SINCE 12 hours ago

-- Q7: NR incidents by priority (issue-level requires MCP list_recent_issues)
FROM NrAiIncident SELECT count(*) FACET priority SINCE 12 hours ago

-- Q8: NR incidents top entities
FROM NrAiIncident SELECT count(*), latest(title) FACET entity.name SINCE 12 hours ago LIMIT 10
```

</details>

## End
