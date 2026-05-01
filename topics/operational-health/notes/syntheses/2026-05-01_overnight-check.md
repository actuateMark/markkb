---
title: "Overnight Health Check 2026-05-01"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, blocked]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: blocked
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Overnight Health Check 2026-05-01

## Summary

**BLOCKED — no health data collected.** All four NRQL investigations failed because the headless `claude -p` sandbox refuses outbound network calls (curl to `api.newrelic.com`) and `python3` execution (via `~/.claude/lib/nr_query.py`) without interactive approval. The MCP NR tools likewise require OAuth not available in headless context. Zero patrol counts, zero error counts, zero issue data — this is a data gap, not a clean signal.

## Issues Found

- **Sandbox blocks all NR queries in headless mode.** Every sub-agent attempt returned "This command requires approval" for both `python3 nr_query.py` and direct `curl https://api.newrelic.com/graphql`. The NR API key at `~/.config/nr/api-key` is present and valid (`NRAK-REDACTED-2026-06-22`); the blocker is purely the harness sandbox.
- **MCP `list_recent_issues` not usable headlessly.** Tool requires interactive OAuth that subagent contexts cannot obtain.
- **Unknown autopatrol state.** Cannot confirm or deny patrols are running for sites 41158 / 41178 / 40672 / 45061 / 37837. Cannot detect autopatrol-server errors or CNCTNFAIL spikes.
- **Unknown connector fleet error counts.** No FACET data on `container_name` errors over the last 12h.
- **Unknown alert-delivery state.** queue-evalink-consumer / queue-eagle-eye-consumer / smtp-frame-receiver / cert-manager-webhook / clips-smtp-worker error counts not retrievable.
- **Unknown NR Issues opened overnight.** Cannot enumerate critical / warning issues.

**Recommended fix (per CLAUDE.md three-tier pattern):** convert this overnight health check to a Tier 1 pure-Python script on the Firebat (`~/bin/overnight-health-check`) driven by a systemd `--user` timer. The script calls NerdGraph directly using the existing API key, writes its digest to `~/.local/state/claude-jobs/overnight-health-check-YYYY-MM-DD.stdout`, and bypasses the Claude sandbox entirely. The current LLM-orchestrated approach is the wrong tier for a fully mechanical NRQL → digest pipeline. Alternatively, invoke the headless wrapper with `--dangerously-skip-permissions` so the sandbox approval gate is pre-authorized for the run.

## AutoPatrol

**Status: UNKNOWN — query blocked.**

Intended queries (none executed):

- Per-site patrol counts via case-facet on message LIKE for sites 41158, 41178, 40672, 45061, 37837 against `container_name = 'autopatrol-server'`.
- `autopatrol-server` total ERROR count.
- Per-site CNCTNFAIL counts via case-facet on `message LIKE '%CNCTNFAIL%'`.
- Connector-side errors via `container_name LIKE '%autopatrol%' AND level = 'ERROR'` faceted by container_name.

Flags that would have been raised — none can be evaluated. **Treat autopatrol fleet state as unverified for the 12h window ending 2026-05-01.**

Note: the `/autopatrol-overnight-check` skill explicitly requires `kubectl` + `kubefwd` MCP for the deeper service health probes, neither of which is available in this headless session — so even with sandbox approval, only the NR portion would be reachable here.

## Connector Fleet

**Status: UNKNOWN — query blocked.**

Intended query: `SELECT count(*) FROM Log WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR' FACET container_name SINCE 12 hours ago LIMIT 15`. Did not execute. No top-15 error breakdown available; >100-error threshold cannot be evaluated.

## Alert Delivery

**Status: UNKNOWN — query blocked.**

Intended query against canonical (dash-form) container names — `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`. Did not execute. >20-error threshold cannot be evaluated. (Sub-agent confirmed it would not have substituted the deprecated underscore names.)

## New Issues

**Status: UNKNOWN — query blocked.**

Intended fetch via `list_recent_issues` (MCP) or NRQL against `NrAiIssue`. Did not execute. Severity distribution and top-3-by-entity cannot be reported. Critical-issue flag cannot be evaluated.

## Raw NRQL

<details>
<summary>Queries that would have run (none executed)</summary>

```sql
-- 1. Patrol counts per site (autopatrol-server)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%' OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago

-- 2. autopatrol-server ERROR count
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago

-- 3. CNCTNFAIL counts per site (case-facet, scoped to autopatrol-server + CNCTNFAIL)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%' OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago

-- 4. Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- 5. Connector fleet top-15 errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- 6. Alert-delivery container errors (canonical dash names only)
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
SINCE 12 hours ago

-- 7. NR Issues opened overnight (via MCP list_recent_issues, account 3421145, SINCE 12 hours ago)
```

</details>

## End
