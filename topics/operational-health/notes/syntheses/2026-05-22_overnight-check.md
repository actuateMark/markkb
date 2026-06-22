---
title: "Overnight Health Check 2026-05-22"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, blocked]
created: 2026-05-22
updated: 2026-05-22
author: kb-bot
status: blocked
incoming:
  - topics/personal-notes/notes/daily/2026-05-22.md
incoming_updated: 2026-05-27
---

# Overnight Health Check 2026-05-22

## Summary

**Check could not run** — Bash execution and [[new-relic|New Relic]] MCP tools were unavailable in this headless session; no NRQL queries succeeded. All four investigations returned environment-blocked, not data-blocked. Platform health is **unknown** for the 12h window ending 2026-05-22.

## Issues Found

- **Environment blocker:** Bash tool calls were rejected with "This command requires approval" both inside subagents and from the parent context. The `nr_query.py` wrapper at `/home/mork/.claude/lib/nr_query.py` could not be invoked.
- **MCP tools unavailable:** The `mcp__newrelic__*` server tools (`execute_nrql_query`, `list_recent_issues`, etc.) are not registered in this session — `ToolSearch` returned no matches for `newrelic`/`nrql`. The `nrql-investigator` subagent profile depends on these but they did not load.
- **Net effect:** Zero NRQL queries executed. No autopatrol, connector-fleet, alert-delivery, or NR-Issues data was collected.

## AutoPatrol

Not executed. Intended queries (preserved in **Raw NRQL** below) cover per-site patrol counts for 41158/41178/40672/45061/37837, autopatrol-server ERROR totals + top patterns, CNCTNFAIL per-site counts, and connector-side `%autopatrol%` container errors.

## Connector Fleet

Not executed. Intended query: ERROR count FACET container_name LIMIT 15, with >100-error follow-up for top message patterns.

## Alert Delivery

Not executed. Intended scope: queue-evalink-consumer, queue-eagle-eye-consumer, smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker (canonical dash-form names; underscore variants known stale).

## New Issues

Not executed. Intended source: NrAiIncident FACET priority/entity SINCE 12 hours ago, or MCP `list_recent_issues` if available.

## Raw NRQL

<details>
<summary>Queries that would have run</summary>

```sql
-- Q1: Patrol counts per site
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%patrol%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10;

-- Q2: autopatrol-server ERROR total + top patterns
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago;

SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
FACET message
SINCE 12 hours ago LIMIT 5;

-- Q3: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10;

-- Q4: Connector-side autopatrol containers
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10;

-- Q5: Fleet ERROR counts
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15;

-- Q6: Alert delivery
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
  AND container_name IN (
    'queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker'
  )
FACET container_name
SINCE 12 hours ago;

-- Q7: NR Issues opened
FROM NrAiIncident
SELECT count(*), latest(title), latest(priority), latest(entity.name)
FACET priority, entity.name
SINCE 12 hours ago LIMIT 10;
```

**Remediation for the wrapper script:** either pre-approve `python3 /home/mork/.claude/lib/nr_query.py` in this session's settings, or register the `mcp__newrelic__*` server so `nrql-investigator` subagents can run without Bash. The check should be moved to a Tier-1 firebat script per the three-tier routine-check pattern — running it as a headless LLM skill (Tier 3) is the wrong tier for a daily cron.

</details>

## End
