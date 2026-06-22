---
title: "Overnight Health Check 2026-05-07"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, degraded-run]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-08
---

# Overnight Health Check 2026-05-07

## Summary

Run failed to gather any data — Bash and the [[new-relic|New Relic]] MCP tools are both unavailable in this headless session, so no NR queries executed. No verdict possible on autopatrol, connector fleet, alert delivery, or new issues.

## Issues Found

- **Headless session lacks both NRQL paths.** `mcp__newrelic__execute_nrql_query` is not registered in the tool set for this session (only `kubefwd` and `aws-documentation` MCPs are present). The `python3 /home/mork/.claude/lib/nr_query.py` Bash wrapper requires interactive approval that the headless harness cannot satisfy — every Bash invocation returned "This command requires approval" and was cancelled.
- **All four nrql-investigator subagents blocked identically.** Both the parent and subagent contexts hit the same gate; this is a session-config issue, not a per-agent issue.
- **Action required:** the wrapper script invocation needs to be added to the headless allowlist (likely in `~/.claude/settings.json` permissions or the cron/scheduled-agent spec that launched this run), or the NR MCP server must be registered for the headless context. Until then this scheduled check produces no useful signal.

## AutoPatrol

Not gathered. Queries below in Raw NRQL were prepared but could not execute. Sites to be checked: 41158, 41178, 40672, 45061, 37837.

If a Tier-1 Firebat run of `~/bin/autopatrol-overnight-check` ran on schedule, its cached output in `~/.local/state/claude-jobs/` is the authoritative substitute for this section.

## Connector Fleet

Not gathered. Intended query: top 15 ERROR containers in `cluster_name='Connector-EKS'` SINCE 12 hours ago.

## Alert Delivery

Not gathered. Intended containers: `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`. Threshold: >20 errors flag.

## New Issues

Not gathered. `mcp__newrelic__list_recent_issues` not available in this session.

## Raw NRQL

<details>
<summary>Queries that would have run (account 3421145)</summary>

```sql
-- Q1 per-site patrol counts
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
FACET cases(
  WHERE message LIKE '%41158%' AS 'site_41158',
  WHERE message LIKE '%41178%' AS 'site_41178',
  WHERE message LIKE '%40672%' AS 'site_40672',
  WHERE message LIKE '%45061%' AS 'site_45061',
  WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

-- Q2 autopatrol-server errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- Q3 CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS 'site_41158',
  WHERE message LIKE '%41178%' AS 'site_41178',
  WHERE message LIKE '%40672%' AS 'site_40672',
  WHERE message LIKE '%45061%' AS 'site_45061',
  WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

-- Q4 connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Q5 connector fleet errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Q6 alert delivery errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- Q7 NR Issues opened
FROM NrAiIncident SELECT count(*) FACET priority
WHERE event='open' SINCE 12 hours ago
```
</details>

## End
