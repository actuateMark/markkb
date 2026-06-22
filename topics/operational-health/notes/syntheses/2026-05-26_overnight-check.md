---
title: "Overnight Health Check 2026-05-26"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, degraded]
created: 2026-05-26
updated: 2026-05-26
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-27
---

# Overnight Health Check 2026-05-26

## Summary

**Check did not run.** All four NR investigations were blocked by the Bash sandbox approval gate in this headless session, and the [[new-relic|New Relic]] MCP tools (`mcp__newrelic__*`) were not registered in the available tool manifest. No telemetry was retrieved; health verdict is **unknown**.

## Issues Found

- **Environment blocker:** Bash invocations of `python3 /home/mork/.claude/lib/nr_query.py` returned `This command requires approval` — the unattended sandbox in this headless context has no approver, so all six query attempts (four AutoPatrol, one fleet, one alert-delivery) cancelled before producing data.
- **MCP fallback missing:** `ToolSearch` for `newrelic nrql` returned no matches; the four `nrql-investigator` subagents independently reported the same — neither the NR MCP nor an approved Bash path is reachable from a subagent in this session.
- **Net effect:** Today's [[automation-overnight-check|overnight check]] produced no signal. Autopatrol per-site counts, autopatrol-server errors, CNCTNFAIL rates, connector fleet error totals, alert-delivery container errors, and NR Issues activity all remain unverified for the last 12h. Treat as a monitoring gap, not an all-clear.
- **Action:** Investigate the headless harness — either grant the wrapper script a pre-approved permission entry in `~/.claude/settings.json` (`Bash(python3 /home/mork/.claude/lib/nr_query.py:*)`) or register the `newrelic` MCP server for unattended sessions. This is a recurring Tier-3 fragility that the three-tier pattern (`2026-04-30_three-tier-routine-check-pattern.md`) calls out: a Tier-1 Firebat script writing to `~/.local/state/claude-jobs/` would not have this dependency.

## AutoPatrol

Not run. Intended queries:

- Patrol counts FACET cases on sites `41158, 41178, 40672, 45061, 37837`, `container_name='autopatrol-server'`, `message LIKE '%patrol%'`, SINCE 12h.
- `count(*)` where `container_name='autopatrol-server' AND level='ERROR'`, SINCE 12h.
- CNCTNFAIL counts FACET cases on the same five sites, SINCE 12h.
- Connector-side errors FACET `container_name` where `container_name LIKE '%autopatrol%' AND level='ERROR'`, SINCE 12h.

All four cancelled at the Bash approval gate. No per-site numbers, no flagging possible. Manual rerun command listed under **Raw NRQL** below.

## Connector Fleet

Not run. Intended query: `SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR' FACET container_name SINCE 12 hours ago LIMIT 15`. Cancelled at approval gate. No fleet error counts available; the `>100 errors` flag is uncomputed.

## Alert Delivery

Not run. Intended query targeted the canonical hyphenated names: `queue-evalink-consumer, queue-eagle-eye-consumer, smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker`. Cancelled at approval gate. The `>20 errors` flag is uncomputed for all five.

## New Issues

Not run. Intended queries against `NrAiIssue` for count, severity distribution, and top-3 entities SINCE 12h. Cancelled at approval gate. Total count, severity split, and entity ranking are all unknown.

## Raw NRQL

<details>
<summary>Queries that were prepared but did not execute</summary>

```sql
-- 1a. AutoPatrol per-site patrol counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND message LIKE '%patrol%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10

-- 1b. AutoPatrol-server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- 1c. CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10

-- 1d. Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10

-- 2. Connector fleet error totals
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- 3. Alert delivery errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name
SINCE 12 hours ago LIMIT 10

-- 4a. NR Issues severity distribution
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago LIMIT 10

-- 4b. NR Issues top entities
FROM NrAiIssue SELECT count(*) FACET entityName SINCE 12 hours ago LIMIT 5
```

Manual rerun: paste any of these into `python3 /home/mork/.claude/lib/nr_query.py "<query>"` in an approved shell, or open `one.newrelic.com` query builder against account 3421145.

</details>

## End
