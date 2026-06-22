---
title: "Overnight Health Check 2026-05-19"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, new-relic]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-20
---

# Overnight Health Check 2026-05-19

## Summary

Check could not gather data — headless session lacks the tool capabilities needed to query [[new-relic|New Relic]]. No health verdict possible. Investigate harness configuration before next run.

## Issues Found

- **Harness gap:** Bash interpreter calls (`python3 /home/mork/.claude/lib/nr_query.py`) are sandbox-blocked in this headless context — every NRQL wrapper invocation returns "This command requires approval", with no interactive approver attached.
- **MCP gap:** The `mcp__newrelic__*` toolset (the alternative path used by the `nrql-investigator` subagent and by `mcp__newrelic__list_recent_issues`) is not registered in this session. Only `kubefwd`, `AWS`, `aws-documentation`, and `atlassian` MCP servers are connected. The newrelic MCP server is absent.
- **Subagent fallout:** All four `nrql-investigator` subagents (autopatrol pipeline, connector fleet, alert delivery, NR issues) returned the same blocker — they only have Bash + Read/Grep/Glob, and Bash is the same sandbox that blocks `python3`. None could reach NR.
- **Net effect:** Zero of the four planned data pulls completed. No autopatrol patrol counts, no CNCTNFAIL counts, no fleet error totals, no alert-delivery container errors, no NR issues list.

## AutoPatrol

**Not gathered.** Queries that would have run (preserved below in *Raw NRQL*) cover patrol counts and CNCTNFAILs for sites 41158, 41178, 40672, 45061, 37837, plus autopatrol-server and connector-side autopatrol ERROR counts. Re-run the `/autopatrol-overnight-check` skill from an interactive session, or grant python3/MCP access in the cron profile, to recover this signal.

## Connector Fleet

**Not gathered.** The 12h FACET-by-container ERROR query is blocked. Recommended fallback: log into NR query console and paste the query from *Raw NRQL* §2. Flag threshold remains >100 errors/12h per container.

## Alert Delivery

**Not gathered.** Counts for `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker` were not retrieved. Use *Raw NRQL* §3. Flag threshold remains >20 errors/12h per container.

## New Issues

**Not gathered.** `mcp__newrelic__list_recent_issues` is not registered in this session. Either restore the newrelic MCP server in the headless agent config, or use the NRQL fallback (`FROM NrAiIncident ... SINCE 12 hours ago`) from an interactive session.

## Raw NRQL

<details>
<summary>Queries that would have been run (paste into NR One query console)</summary>

**§1a — Autopatrol per-site patrol counts**
```
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10
```

**§1b — Autopatrol-server error count**
```
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND level='ERROR'
SINCE 12 hours ago
```

**§1c — Per-site CNCTNFAIL counts**
```
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10
```

**§1d — Connector-side autopatrol errors**
```
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10
```

**§2 — Connector fleet error counts**
```
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15
```

**§3 — Alert delivery container errors**
```
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name
SINCE 12 hours ago
```

**§4 — NR issues last 12h (NRQL fallback for the MCP call)**
```
FROM NrAiIncident
SELECT count(*), latest(title), latest(entityName), latest(priority)
FACET incidentId
SINCE 12 hours ago LIMIT 25
```

</details>

## End
