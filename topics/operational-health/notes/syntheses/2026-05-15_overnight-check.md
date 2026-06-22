---
title: "Overnight Health Check 2026-05-15"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-15
updated: 2026-05-15
author: kb-bot
status: blocked
incoming:
  - No backlinks found.
incoming_updated: 2026-05-16
---

# Overnight Health Check 2026-05-15

## Summary

Check **could not execute** — Bash sandbox in this headless session denied `python3 /home/mork/.claude/lib/nr_query.py` invocations (interactive approval required), and the `mcp__newrelic__*` MCP server is not present in this context's deferred-tool list. No NR data was retrieved for any of the four planned aggregations. Verdict: **unknown / degraded run**; re-run from an interactive session or promote this check to Tier 1 (Firebat systemd) / Tier 2 (laptop cron).

## Issues Found

- **RED — Headless execution blocked:** Bash sandbox required interactive approval for every `python3 nr_query.py` call in this run. No connector/autopatrol/alert/issue data was gathered for 2026-05-15.
- **RED — Tier-1 (Firebat) cache stale:** Most recent entry in `~/.local/state/claude-jobs/` is from 2026-05-04 per subagent diagnostic; suggests the Firebat systemd timer for overnight health is not running or Firebat is unreachable. Investigate before tomorrow's run.
- **YELLOW — No Tier-2 fallback exists:** `~/bin/autopatrol-overnight-check` is absent. The three-tier pattern's Tier-2 laptop fallback is missing, so when Tier-1 (Firebat) is unhealthy and Tier-3 (LLM) is sandboxed, there is no remaining path.
- **YELLOW — NR MCP not loaded:** `mcp__newrelic__*` tools were not in the deferred-tool list for this invocation — the `newrelic` MCP server did not connect (only AWS appeared in the "still connecting" notice). Headless cron contexts cannot rely on it.

## AutoPatrol

**Status:** Unable to query. All four planned NRQL aggregations (per-site patrol counts, autopatrol-server ERROR count, per-site CNCTNFAIL counts, connector-side autopatrol ERROR FACET) were blocked at the sandbox approval gate. See `## Raw NRQL` for the exact queries staged for execution.

Site list pending verification (canonical IDs): **41158, 41178, 40672, 45061, 37837**.

Flagging thresholds (apply when query results land):

| Condition | Threshold | Severity |
|---|---|---|
| Site patrol count = 0 in 12h | any site | RED |
| CNCTNFAIL per site | > 5 | YELLOW |
| autopatrol-server errors | > 0 | YELLOW |
| autopatrol-server errors | > 50 | RED |

## Connector Fleet

**Status:** Unable to query. The 12h ERROR-by-container FACET (LIMIT 15) was blocked. Threshold for flag was > 100 errors per container as RED.

## Alert Delivery

**Status:** Unable to query. Per-container ERROR counts for the five canonical names (`queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`) were not retrieved. Threshold: > 20 YELLOW, > 100 RED.

(Reminder for future runs: the legacy underscore names `queue_immix_consumer` / `queue_consumer` / `webhook_listener` return zero rows and should not be substituted in.)

## New Issues

**Status:** Unable to query. `NrAiIssue` severity-distribution + top-3-by-entity facets were not retrieved.

## Raw NRQL

<details>
<summary>Queries staged but not executed (account 3421145, all SINCE 12 hours ago)</summary>

```sql
-- 1a. Patrol counts per site (autopatrol-server)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%Processing patrol_id%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10

-- 1b. autopatrol-server error count
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago

-- 1c. CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
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
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10

-- 2. Connector fleet ERROR FACET
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- 3. Alert-delivery container errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name
SINCE 12 hours ago LIMIT 10

-- 4a. NR Issues severity distribution
FROM NrAiIssue SELECT count(*)
FACET priority
WHERE state = 'CREATED'
SINCE 12 hours ago

-- 4b. NR Issues top-by-entity detail
FROM NrAiIssue SELECT title, priority, state, entityName
WHERE state = 'CREATED'
SINCE 12 hours ago LIMIT 10
```

</details>

### Remediation for next run

1. Promote this [[automation-overnight-check|overnight check]] to **Tier 1** — a Firebat systemd `--user` timer script that runs the eight NRQL queries above with `nr_query.py`, writes JSON to `~/.local/state/claude-jobs/overnight-health-YYYY-MM-DD.json`, and a markdown rollup to the KB sink. Tier 1 has no sandbox.
2. As a fallback, create **Tier 2** at `~/bin/overnight-health-check` deployed via `local_network_scripts/files/` so the laptop can run it when Firebat is down.
3. Investigate why the Firebat cache last updated 2026-05-04 — likely the `claude -p` regression remediated 2026-04-30 reverted, or the timer unit failed silently. `systemctl --user --machine=mork@mork-firebat status overnight-*.timer` from an interactive session.
4. Add Bash-tool allowlist entry for `python3 /home/mork/.claude/lib/nr_query.py *` in the headless run profile if Tier-3 LLM execution is to remain viable.

## End
