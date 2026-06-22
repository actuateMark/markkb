---
title: "Overnight Health Check 2026-05-04"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, blocked, new-relic]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: blocked
incoming:
  - No backlinks found.
incoming_updated: 2026-05-05
---

# Overnight Health Check 2026-05-04

## Summary

**Check could not execute — headless session lacks [[new-relic|New Relic]] query access.** No NR data was retrieved. All four delegated steps (autopatrol, connector fleet, alert delivery, NR Issues) returned the same environmental failure. No claim about platform health is being made by this note — green or red. Treat platform status as **UNKNOWN** for the 12h window ending 2026-05-04.

## Issues Found

- **Tooling gap (blocker for headless [[automation-overnight-check|overnight checks]]):** the `nrql-investigator` subagent invoked from this headless session cannot reach [[new-relic|New Relic]]. Both available paths failed:
  - `mcp__newrelic__*` MCP tools are not registered in this session's tool manifest (parent ToolSearch returns no matches; subagents report they're not in their tool set).
  - `python3 /home/mork/.claude/lib/nr_query.py` and `curl https://api.newrelic.com/graphql` are blocked by the sandbox approval gate in non-interactive runs.
- **Effect:** the [[automation-overnight-check|overnight check]] that this wrapper is supposed to populate produces zero signal. If a real fleet incident occurred in the 12h window, this note would not catch it.
- **Recommended fix (per the three-tier routine-check pattern in CLAUDE.md):** convert this check to a **Tier 1 Firebat script**. The check is purely mechanical — fixed NRQL, fixed thresholds, deterministic output — exactly the conversion-signal profile in the global rules. A pure-Python script on the Firebat with an NR API key in `~/.config/nr/api-key` would run on a systemd `--user` timer, write the synthesis note via cron, and bypass both the MCP-not-registered and sandbox-approval issues entirely. The LLM tier (this skill) should only be the diagnostic fallback.
- **Interim fix (faster):** add `Bash(python3 /home/mork/.claude/lib/nr_query.py *)` to the `permissions.allow` list in `/home/mork/.claude/settings.json` so headless agent invocations can run the wrapper without per-call approval. This unblocks the existing LLM-tier path until Tier 1 lands.

## AutoPatrol

**Not executed.** Delegated to `nrql-investigator` (agent id `a76e7d69115a515f4`); subagent reported the MCP NR tools are not in its tool set and `python3` / `curl` paths are sandbox-blocked. Queries were prepared but not run. See **Raw NRQL** below for the four queries that would have run.

Sites that would have been checked: `41158`, `41178`, `40672`, `45061`, `37837`. Flag thresholds that would have been applied: zero patrols/12h per site; >5 CNCTNFAILs per site; any `autopatrol-server` ERROR.

## Connector Fleet

**Not executed.** Delegated to `nrql-investigator` (agent id `a7c3b13d7eee8b6ce`); same sandbox-blocked outcome. The single `FACET container_name` query was prepared but not run. Threshold that would have been applied: any container with >100 ERRORs in 12h.

## Alert Delivery

**Not executed.** Delegated to `nrql-investigator` (agent id `a2861dc4a8ac961ed`); same sandbox-blocked outcome. Containers that would have been checked (kebab-case canonical names): `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`. Threshold: >20 ERRORs per container in 12h.

## New Issues

**Not executed.** Delegated to `nrql-investigator` (agent id `af7935dfbeedc7638`); the subagent reported `mcp__newrelic__list_recent_issues` is not present in its tool manifest in headless context, and the Bash fallback to query `NrAiIssue` via the NerdGraph wrapper hit the same sandbox approval gate. No issue counts, severity distribution, or top-3 entities are available for the 12h window.

## Raw NRQL

The queries that were prepared but not executed, exactly as they would have run against account `3421145`:

**1. Patrol counts per site (autopatrol):**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND message LIKE '%patrol%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago
```

**2. Autopatrol-server error count:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND level='ERROR'
SINCE 12 hours ago
```

**3. CNCTNFAIL counts per site:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago
```

**4. Connector-side autopatrol errors by container:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15
```

**5. Connector fleet overnight errors:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15
```

**6. Alert-delivery container errors:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name SINCE 12 hours ago
```

**7. NR Issues opened in window:**
```sql
FROM NrAiIssue
SELECT issueId, title, priority, createdAt, entityName
WHERE createdAt >= (now() - 43200000)
SINCE 12 hours ago LIMIT 50
```

## End
