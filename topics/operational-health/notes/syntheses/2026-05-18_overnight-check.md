---
title: "Overnight Health Check 2026-05-18"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, blocked]
created: 2026-05-18
updated: 2026-05-18
author: kb-bot
status: blocked
incoming:
  - topics/personal-notes/notes/daily/2026-05-18.md
incoming_updated: 2026-05-19
---

# Overnight Health Check 2026-05-18

## Summary

**Check did not execute** — all four NRQL probes were blocked by the headless sandbox's per-call approval gate on `python3` (the `nr_query.py` wrapper). No data was gathered for autopatrol, connector fleet, alert delivery, or NR Issues.

## Issues Found

- **Headless sandbox blocks `python3` subprocess calls.** Every subagent reported the same root cause: the Bash tool in this `claude -p` / subagent context prompts for approval on `python3 /home/mork/.claude/lib/nr_query.py` and the approval does not persist. NR MCP OAuth is also unavailable in headless mode, so there is no fallback path.
- **No Tier-1 Firebat cache for any of these checks.** `~/.local/state/claude-jobs/` had no fleet-health, autopatrol, alert-delivery, or NR-Issues artifacts to fall back on, so Tier 1 → Tier 2 → Tier 3 all missed.
- **Skill conversion gap:** per the three-tier pattern, this [[automation-overnight-check|overnight check]] should be a Firebat systemd timer writing JSON to `~/.local/state/claude-jobs/overnight-health/`, with the LLM only synthesising cached output. Today it ran as Tier 3 from cold and could not execute.
- **Action items for the operator:**
  1. Add `python3 /home/mork/.claude/lib/nr_query.py*` to the `allowedTools` Bash patterns in `~/.claude/settings.json` so headless invocations don't hit the approval gate.
  2. Or, deploy a Firebat overnight-health script that runs the queries below on a systemd timer and dumps JSON for the LLM tier to read.
  3. Until either is in place, run the queries in §Raw NRQL manually in the NR query builder or an interactive terminal to confirm overnight state.

## AutoPatrol

Query execution blocked. Subagent `a12db47458f2a3217` confirmed `nr_query.py` is present at `/home/mork/.claude/lib/nr_query.py`, API key at `/home/mork/.config/nr/api-key` is 32 chars, `python3` at `/usr/bin/python3` — infrastructure intact, sandbox blocked invocation. No per-site patrol counts, CNCTNFAIL counts, or autopatrol-server error data available for sites 41158, 41178, 40672, 45061, 37837. **Manual verification required** before assuming green.

## Connector Fleet

Query execution blocked. Subagent `a89abfe4cc8ecd62b` flagged this as a Tier-3 cold-run failure and recommended a Firebat timer that writes top-15-containers JSON to `~/.local/state/claude-jobs/connector-fleet-health/`. No error-count data for any container in `cluster_name='Connector-EKS'` over the last 12 h.

## Alert Delivery

Query execution blocked. Subagent `a6a606021aeb7b97e` confirmed the canonical container names are correct (no underscore-name regression risk) and queries are ready to run. No error-count data for `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, or `clips-smtp-worker`.

## New Issues

Query execution blocked. Subagent `a567a975060f59966` reported both query paths failed: `nr_query.py` (Bash sandbox) and `mcp__newrelic__list_recent_issues` (no OAuth in headless context). Cannot confirm whether any NR Issues opened in the last 12 h.

## Raw NRQL

<details>
<summary>Queries to run manually (NR query builder or interactive `python3 /home/mork/.claude/lib/nr_query.py "..."`)</summary>

```sql
-- AutoPatrol: per-site patrol counts (last 12 h)
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
SINCE 12 hours ago FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)

-- AutoPatrol: server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)

-- AutoPatrol: connector-side errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 10

-- Connector fleet: top-15 containers by error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15

-- Alert delivery: canonical container error counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name

-- NR Issues: severity distribution
FROM NrAiIssue SELECT count(*) FACET priority
WHERE accountId = 3421145 SINCE 12 hours ago

-- NR Issues: top by entity
FROM NrAiIssue SELECT latest(title), latest(priority), latest(entityName), min(timestamp)
WHERE accountId = 3421145 SINCE 12 hours ago
FACET issueId LIMIT 10
```

</details>

## End
