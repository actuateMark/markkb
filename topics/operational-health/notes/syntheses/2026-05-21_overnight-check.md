---
title: "Overnight Health Check 2026-05-21"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-21
updated: 2026-05-21
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-27
---

# Overnight Health Check 2026-05-21

## Summary

**Check DEGRADED — all four data-gathering subagents blocked by sandbox approval gates.** No NR data collected; this is an environment failure in the headless invocation, not a fleet incident. Manual follow-up required.

## Issues Found

- **Tier-3 LLM check blocked across the board:** `python3` Bash invocations (the `nr_query.py` wrapper path) require interactive approval that no one is present to grant; NR MCP requires OAuth that doesn't bind in headless context.
- **Tier-1 Firebat cache absent for today** at `~/.local/state/claude-jobs/` (autopatrol subagent reported no fresh cache).
- **Skill-routing gap:** the routine check fell to Tier 3 because Tier-1 Firebat scripts for connector-fleet error counts and alert-delivery error counts do not appear to exist (only `autopatrol-overnight-check` is wired); this matches the [[2026-04-30_three-tier-routine-check-pattern]] retrofit inventory.
- **Recovery actions for a human:**
  1. Run `~/bin/autopatrol-overnight-check` from an interactive laptop terminal.
  2. Check `http://mork-firebat/logs/autopatrol-overnight-check-2026-05-21.stdout` for a successful Firebat run.
  3. Execute the four NRQL queries (below in **Raw NRQL**) in the NR query builder, account 3421145.
  4. Allowlist `python3 ~/.claude/lib/nr_query.py` in the headless session permissions so future overnight runs can self-serve, OR convert these three checks to Firebat Tier-1 scripts.

## AutoPatrol

**Status: BLOCKED — network access unavailable in this sandbox context.**

All four NRQL queries (patrols per site for 41158/41178/40672/45061/37837, autopatrol-server ERROR count, CNCTNFAIL per site, connector-side autopatrol errors) could not execute. The `nr_query.py` wrapper is sandbox-gated in this headless subagent environment; NR MCP requires interactive OAuth; no Tier-1 cache for today exists at `~/.local/state/claude-jobs/`.

No flags can be raised or cleared. Treat as "unknown" until manually re-run.

## Connector Fleet

**Status: BLOCKED — query executor unavailable.**

Intended query (top-15 containers by ERROR count, cluster_name='Connector-EKS', 12 h) did not execute. Bash sandbox approval gate is active and unattended; NR MCP not viable here.

No `>100 errors` flag can be raised or cleared. Run manually.

## Alert Delivery

**Status: BLOCKED — query executor unavailable.**

| Container | Errors (12 h) | Flagged |
|---|---|---|
| queue-evalink-consumer | — | — |
| queue-eagle-eye-consumer | — | — |
| smtp-frame-receiver | — | — |
| cert-manager-webhook | — | — |
| clips-smtp-worker | — | — |

No `>20 errors` flag can be raised or cleared. Run manually.

## New Issues

**Status: BLOCKED — neither `nr_query.py` nor `mcp__newrelic__list_recent_issues` reachable in headless context.**

No issue count, severity distribution, or top-entity list available. Run manually.

## Raw NRQL

<details>
<summary>Queries to run manually in NR (account 3421145)</summary>

```sql
-- AutoPatrol: patrols per site
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%patrol%'
SINCE 12 hours ago
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)

-- AutoPatrol: server ERROR count
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)

-- AutoPatrol: connector-side errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
SINCE 12 hours ago
FACET container_name LIMIT 10

-- Connector Fleet: top errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
SINCE 12 hours ago
FACET container_name LIMIT 15

-- Alert Delivery: canonical containers
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
SINCE 12 hours ago
FACET container_name

-- New Issues
FROM NrAiIssue SELECT count(*), latest(title), latest(priority), latest(entityNames)
FACET issueId, priority
SINCE 12 hours ago
LIMIT 50
```

</details>

## End
