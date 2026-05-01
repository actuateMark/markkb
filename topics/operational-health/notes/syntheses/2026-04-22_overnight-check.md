---
title: "Overnight Health Check 2026-04-22"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
status: degraded
---

# Overnight Health Check 2026-04-22

## Summary

Check could not execute — [[new-relic|New Relic]] MCP query tools were not bound in this headless session. No health data gathered; the report is an environmental failure, not a system status.

## Issues Found

- **Runtime gap: NR MCP query tools unavailable.** Only `mcp__newrelic-eu__authenticate` and `mcp__newrelic-eu__complete_authentication` were exposed as deferred tools. The query/issue tools (`mcp__newrelic__execute_nrql_query`, `mcp__newrelic__list_recent_issues`, etc.) were not registered in this session's tool surface.
- All four `nrql-investigator` sub-delegations returned the same failure — the subagent manifest claims NR tools but the runtime did not bind them. Subagents returned only NRQL templates, no live counts.
- **AutoPatrol:** not verified.
- **Connector fleet errors:** not verified.
- **Alert delivery:** not verified.
- **NR new issues:** not verified.
- **Recommended action:** reconnect the [[new-relic|New Relic]] MCP server (US account 3421145) for the headless/cron user profile, or re-run manually in an interactive session where the NR tools are bound. If the EU-only server is what's now wired up, the queries need re-routing or a US-account MCP binding needs to be added.

## AutoPatrol

**Status:** Not executed — NR MCP unavailable.

Target sites (41158, 41178, 40672, 45061, 37837) were not queried. The `nrql-investigator` subagent confirmed the query shapes are valid per the connector query cookbook but could not execute them. Recommended primary query (cookbook-aligned, completion-signal-scoped) for manual run:

```sql
SELECT count(*), latest(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND namespace LIKE 'autopatrol%'
  AND (message LIKE '%task results%'
    OR message LIKE '%All camera threads have ended%'
    OR message LIKE '%patrol%complet%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago
```

Flags that would be applied if counts were available: any site with 0 patrols, any site with >5 CNCTNFAILs, any non-zero `autopatrol-server` ERROR count.

## Connector Fleet

**Status:** Not executed — NR MCP unavailable.

Intended query (12h, account 3421145):

```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15
```

Flag threshold would be >100 errors per container. No data to evaluate.

## Alert Delivery

**Status:** Not executed — NR MCP unavailable.

Intended query (canonical current container names, not the deprecated underscore forms):

```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name SINCE 12 hours ago
```

Flag threshold would be >20 errors per container. No data to evaluate. Containers returning zero rows from ingestion entirely would warrant a separate `K8sContainerSample` pod-liveness check.

## New Issues

**Status:** Not executed — NR MCP unavailable.

Intended lookup: `list_recent_issues` SINCE 12 hours ago, summarized by severity + top 3 entities. No data to evaluate.

Manual fallback NRQL for the query console (account 3421145):

```sql
SELECT count(*), latest(priority) FROM NrAiIssue
WHERE event='activate' SINCE 12 hours ago FACET priority LIMIT 5
```

```sql
SELECT latest(title), latest(entityName), latest(priority), latest(activatedAt)
FROM NrAiIssue
WHERE event='activate' SINCE 12 hours ago FACET issueId LIMIT 3
```

## Raw NRQL

<details>
<summary>Queries prepared but not executed</summary>

**AutoPatrol patrol counts per site (container-scoped):**
```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
    OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago
```

**AutoPatrol-server ERROR count:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago
```

**CNCTNFAIL counts per site:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago
```

**Connector-side autopatrol errors:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10
```

**Fleet ERROR counts:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15
```

**Alert-delivery ERROR counts:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker'
  )
FACET container_name SINCE 12 hours ago
```

**NR issues opened:**
```sql
SELECT count(*), latest(priority) FROM NrAiIssue
WHERE event='activate' SINCE 12 hours ago FACET priority LIMIT 5
```

</details>

## End
