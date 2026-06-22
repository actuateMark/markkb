---
title: "Overnight Health Check 2026-06-01"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-01
updated: 2026-06-01
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-06-02
---

# Overnight Health Check 2026-06-01

## Summary

**Check could not run — no [[new-relic|New Relic]] data path available in this headless session.** Both the `nr_query.py` Bash wrapper (interactive approval gate, no approver present) and the dedicated `mcp__newrelic__*` MCP server (never connected; only the OAuth-gated `claude_ai_New_Relic` proxy is registered, which needs interactive browser auth) are unavailable. No platform-health conclusions can be drawn for the last 12h; treat as **no signal**, not as healthy.

## Issues Found

- **Tooling/environment failure (not a platform finding):** The four `nrql-investigator` delegations all aborted before retrieving data.
  - Bash tool requires per-command approval; `dangerouslyDisableSandbox` does not bypass the approval gate in an unattended session.
  - The `mcp__newrelic__*` server (the path the `nrql-investigator` subagent relies on) is not connected. ToolSearch returns only `mcp__claude_ai_New_Relic__authenticate` (OAuth flow), which cannot complete headlessly.
- **Consequence:** AutoPatrol pipeline, connector fleet error counts, alert-delivery health, and new NR Issues are all **unverified** for this window.
- **Remediation:** Re-run in an interactive Claude Code session (approve the `python3 nr_query.py` invocation, or grant a persistent allow-rule), or ensure the dedicated [[new-relic|New Relic]] MCP server is authenticated/connected before the scheduled headless run. The verbatim NRQL is preserved in the Raw NRQL section below for a manual one-shot.

## AutoPatrol

**No data — query path unavailable.** Could not evaluate the flag conditions (any site at 0 patrols in 12h; any site >5 CNCTNFAILs; any `autopatrol-server` ERROR). Sites in scope: 41158, 41178, 40672, 45061, 37837. Note: the `/autopatrol-overnight-check` skill's kubectl + kubefwd path was intentionally out of scope for this headless run; the NR-only fallback also could not execute.

## Connector Fleet

**No data — query path unavailable.** Could not evaluate the >100-errors-per-container flag across `cluster_name='Connector-EKS'`.

## Alert Delivery

**No data — query path unavailable.** Could not evaluate the >20-errors flag for `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`.

## New Issues

**No data — query path unavailable.** Could not retrieve NR Issues opened in the last 12h (count, severity distribution, top-3 by entity).

## Raw NRQL

<details>
<summary>Queries intended for this run (account 3421145, <code>cluster_name='Connector-EKS'</code>, SINCE 12 hours ago) — none executed</summary>

```sql
-- 1a. AutoPatrol counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago

-- 1b. autopatrol-server ERROR count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- 1c. CNCTNFAIL counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago

-- 1d. Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago

-- 2. Connector fleet overnight errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- 3. Alert delivery health
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- 4. NR Issues opened in window
FROM NrAiIncident SELECT count(*), latest(title), latest(priority), latest(entityName)
WHERE event = 'open' SINCE 12 hours ago FACET incidentId LIMIT 50
```

Manual one-shot (interactive session):
```bash
python3 /home/mork/.claude/lib/nr_query.py "<one of the queries above>"
```
</details>

## End
