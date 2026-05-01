---
title: "Overnight Health Check 2026-04-28"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
status: unknown
---

# Overnight Health Check 2026-04-28

## Summary

**Health-check could not be executed: NR query path is blocked in this headless session.** No data was retrieved for any of the four checks (autopatrol, connector fleet, alert delivery, NR Issues).

## Issues Found

- **Tooling gap (P1 for the check itself, not the platform):** The unattended overnight wrapper has no working path to NR.
  - Bash invocations of `python3 /home/mork/.claude/lib/nr_query.py` are rejected by the headless sandbox with `This command requires approval`.
  - The MCP NR tools (`mcp__newrelic__execute_nrql_query`, `mcp__newrelic__list_recent_issues`) are not registered as deferred tools in this session — `ToolSearch` returned "No matching deferred tools found" — so they cannot be invoked from the parent or from `nrql-investigator` subagents.
  - All four `nrql-investigator` delegations returned the same blocker: subagent's Bash sandbox does not pre-approve `python3` / `curl`, and MCP tools are parent-context-only.
- **Action required to unblock:** add a non-interactive permission entry that pre-approves the NR query wrapper for headless runs, e.g. in `~/.claude/settings.json` `permissions.allow`:
  ```
  "Bash(python3 /home/mork/.claude/lib/nr_query.py *)"
  ```
  Or register `mcp__newrelic__execute_nrql_query` as available to the headless session so the parent context can call it directly.
- **Until that's fixed, the daily [[automation-overnight-check|overnight check]] produces no signal** — treat absence of a "degraded" verdict from this run as missing data, not as an all-clear.

## AutoPatrol

**Status: NOT RUN.** Sandbox blocked the four NRQL queries (per-site patrol counts, autopatrol-server ERRORs, per-site CNCTNFAIL counts, connector-side autopatrol ERRORs by container). Sites that should have been checked: 41158, 41178, 40672, 45061, 37837. Re-run interactively via `/autopatrol-overnight-check` (kubectl path) or by executing the queries in the "Raw NRQL" section below from an interactive session.

## Connector Fleet

**Status: NOT RUN.** The single FACET-by-container_name ERROR-count query (LIMIT 15, SINCE 12h, cluster=Connector-EKS) was blocked. No baseline available for >100-error flagging.

## Alert Delivery

**Status: NOT RUN.** The query for canonical alert containers (`queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`) was blocked. No data on >20-error threshold.

## New Issues

**Status: NOT RUN.** Both `list_recent_issues` MCP and the NRQL fallback against `NrAiIssue` were blocked. No count, severity distribution, or top-by-entity data.

## Raw NRQL

<details>
<summary>Queries that should have been executed (account 3421145, run interactively to populate this report)</summary>

```nrql
-- Q1 AutoPatrol: per-site patrol counts
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%41158%') AS '41158',
  filter(count(*), WHERE message LIKE '%41178%') AS '41178',
  filter(count(*), WHERE message LIKE '%40672%') AS '40672',
  filter(count(*), WHERE message LIKE '%45061%') AS '45061',
  filter(count(*), WHERE message LIKE '%37837%') AS '37837'
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%patrol%'
SINCE 12 hours ago

-- Q2 AutoPatrol: autopatrol-server ERROR count
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago

-- Q3 AutoPatrol: per-site CNCTNFAIL counts
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%41158%') AS '41158',
  filter(count(*), WHERE message LIKE '%41178%') AS '41178',
  filter(count(*), WHERE message LIKE '%40672%') AS '40672',
  filter(count(*), WHERE message LIKE '%45061%') AS '45061',
  filter(count(*), WHERE message LIKE '%37837%') AS '37837'
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago

-- Q4 AutoPatrol: connector-side autopatrol ERRORs by container
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago
LIMIT 10

-- Q5 Connector fleet: top error-emitting containers
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago
LIMIT 15

-- Q6 Alert delivery: ERROR counts for canonical containers
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name
SINCE 12 hours ago

-- Q7 NR Issues: severity distribution (last 12h)
FROM NrAiIssue SELECT count(*)
WHERE event = 'open'
SINCE 12 hours ago
FACET priority
LIMIT 10

-- Q8 NR Issues: top entities (last 12h)
FROM NrAiIssue SELECT count(*), latest(title)
WHERE event = 'open'
SINCE 12 hours ago
FACET entityName, priority
LIMIT 5
```

</details>

## End
