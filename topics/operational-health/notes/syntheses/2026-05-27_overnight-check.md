---
title: "Overnight Health Check 2026-05-27"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-27
updated: 2026-05-27
author: kb-bot
status: blocked
incoming:
  - No backlinks found.
incoming_updated: 2026-05-27
---

# Overnight Health Check 2026-05-27

## Summary

CHECK DID NOT RUN — all four [[new-relic|New Relic]] data-gathering paths were blocked in this headless session; no health data could be collected, so platform health is UNVERIFIED (not "healthy").

## Issues Found

- **Execution blocked (infrastructure, not platform):** Every route to [[new-relic|New Relic]] data failed in this unattended session:
  - The `nr_query.py` wrapper (`/home/mork/.claude/lib/nr_query.py`) is **not on the Bash allowlist**, so each `python3` invocation returns "This command requires approval." Headless = no approver, and `skipAutoPermissionPrompt: true` suppresses the interactive prompt.
  - The [[new-relic|New Relic]] MCP tools (`mcp__newrelic__execute_nrql_query`, `mcp__newrelic__list_recent_issues`) **are on the allowlist but the server is not connected** in this session — only `kubefwd`, `atlassian`, and `aws-documentation` MCP servers came up. ToolSearch confirms no `mcp__newrelic__*` tools are registered.
  - Subagent delegation (all four nrql-investigator agents) hit the same wall: subagents do not inherit MCP bindings and the Bash sandbox gates `python3`.
- **Net effect:** AutoPatrol pipeline, connector fleet error volume, alert-delivery health, and overnight NR Issues are all UNVERIFIED for the 12h window ending 2026-05-27. No flags could be evaluated.

### Recommended remediation (one of)

1. Add `"Bash(python3 /home/mork/.claude/lib/nr_query.py *)"` to `permissions.allow` in `/home/mork/.claude/settings.json` so the wrapper runs unattended.
2. Ensure the [[new-relic|New Relic]] MCP server is started for headless sessions (it is allowlisted but was not launched).
3. Per the three-tier routine-check pattern, promote this [[automation-overnight-check|overnight check]] to a **Tier 1 Firebat script** (`~/bin/<name>`, systemd `--user` timer) that runs without shell-approval gates and writes to `~/.local/state/claude-jobs/` — zero-token, no permission wall.

## AutoPatrol

NOT RUN. Per-site patrol counts (41158, 41178, 40672, 45061, 37837), autopatrol-server error count, per-site CNCTNFAIL counts, and connector-side autopatrol errors were all uncollected. Cannot evaluate flags (zero-patrol sites, >5 CNCTNFAIL sites, autopatrol-server errors). Note: the `/autopatrol-overnight-check` skill's kubectl + kubefwd path is also unavailable in this session.

## Connector Fleet

NOT RUN. Fleet-wide ERROR counts by `container_name` (cluster_name='Connector-EKS', SINCE 12h) were not collected. Cannot evaluate the >100-errors-per-container flag.

## Alert Delivery

NOT RUN. ERROR counts for `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker` were not collected. Cannot evaluate the >20-errors-per-container flag.

## New Issues

NOT RUN. NR Issues opened in the last 12h were not retrieved (MCP `list_recent_issues` unavailable, wrapper blocked). Count, severity distribution, and top-3-by-entity are unknown.

## Raw NRQL

<details>
<summary>Queries that were prepared but could not be executed (account 3421145, cluster_name='Connector-EKS', SINCE 12 hours ago)</summary>

```sql
-- Q1: Patrol counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET CASES(
  message LIKE '%41158%' AS '41158',
  message LIKE '%41178%' AS '41178',
  message LIKE '%40672%' AS '40672',
  message LIKE '%45061%' AS '45061',
  message LIKE '%37837%' AS '37837')
SINCE 12 hours ago

-- Q2: Autopatrol-server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- Q3: CNCTNFAIL counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  message LIKE '%41158%' AS '41158',
  message LIKE '%41178%' AS '41178',
  message LIKE '%40672%' AS '40672',
  message LIKE '%45061%' AS '45061',
  message LIKE '%37837%' AS '37837')
SINCE 12 hours ago

-- Q4: Connector-side autopatrol errors by container
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Step 2: Connector fleet overnight errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Step 3: Alert delivery health
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- Step 4: NR Issues opened in last 12h (via list_recent_issues / NrAiIncident)
FROM NrAiIncident SELECT count(*), latest(title), latest(priority), latest(entityName)
WHERE event = 'open' SINCE 12 hours ago FACET incidentId, priority, entityName LIMIT 50
```

</details>

## End
