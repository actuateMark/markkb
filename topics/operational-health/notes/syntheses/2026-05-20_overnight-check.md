---
title: "Overnight Health Check 2026-05-20"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
status: blocked
incoming:
  - No backlinks found.
incoming_updated: 2026-05-21
---

# Overnight Health Check 2026-05-20

## Summary

**BLOCKED** — All four data-gathering steps failed. The headless `claude -p` context has Bash sandboxed behind interactive approval, which prevents `python3 /home/mork/.claude/lib/nr_query.py` from reaching `api.newrelic.com`. No NR data was retrieved; health status of autopatrol, connector fleet, alert delivery, and new issues is **unknown** for the 12h window ending 2026-05-20.

## Issues Found

- **Tooling regression (process, not platform):** Headless [[automation-overnight-check|overnight check]] has no working path to [[new-relic|New Relic]]. All four nrql-investigator subagent invocations returned the same blocker — Bash → `urllib.request` → `api.newrelic.com` requires interactive sandbox approval that no one is present to grant. NR MCP OAuth also unavailable in headless context.
- **No Tier-1 cached fallback** exists for these specific queries at `~/.local/state/claude-jobs/` or `~/.local/state/minipc-tasks/`. The three-tier routine check pattern is not yet retrofit for this check.
- **Action needed:** Add Firebat-side Tier-1 scripts (systemd `--user` timers, ~10 min before this check fires) that run the four NRQL queries and drop JSON to `~/.local/state/minipc-tasks/overnight-health/YYYY-MM-DD.json`. This skill then reads the cached file instead of hitting NR live. Pattern mirrors `ecr-lifecycle-audit` and `billing/reconciliation`. Owner: §dashboard / §operational-health workstream.
- **Platform health for the 12h window: unverified.** A human or interactive session should re-run the queries below before assuming green.

## AutoPatrol

**Status: unknown — query execution blocked.** Sites 41158, 41178, 40672, 45061, 37837 not checked for patrol counts or CNCTNFAILs. autopatrol-server ERROR count not retrieved. Connector-side autopatrol-* containers not surveyed.

Skill `/autopatrol-overnight-check` requires kubectl + kubefwd MCP, neither available in headless context (per task instructions). NR-only fallback queries are prepared (see Raw NRQL) but could not be executed.

## Connector Fleet

**Status: unknown — query execution blocked.** Top-15 ERROR-emitting containers in `cluster_name='Connector-EKS'` SINCE 12 hours ago not retrieved. Cannot flag containers >100 errors.

## Alert Delivery

**Status: unknown — query execution blocked.** ERROR counts for the five canonical alert-pipeline containers (queue-evalink-consumer, queue-eagle-eye-consumer, smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker) not retrieved. Cannot flag containers >20 errors.

## New Issues

**Status: unknown — `list_recent_issues` MCP tool unavailable in headless subagent context** (newrelic MCP not surfaced, and Bash-path Python wrapper blocked). Cannot report issue count, severity distribution, or top-3 affected entities.

## Raw NRQL

<details>
<summary>Queries that should have been run (account 3421145, cluster_name='Connector-EKS', SINCE 12 hours ago)</summary>

**Q1 — Patrol counts per site (autopatrol-server):**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10
```

**Q2 — Autopatrol-server total ERRORs:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND level='ERROR'
SINCE 12 hours ago
```

**Q3 — CNCTNFAIL counts per site:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%'
       OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10
```

**Q4 — Connector-side autopatrol errors:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10
```

**Q5 — Connector fleet ERROR survey:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
FACET container_name
LIMIT 15
SINCE 12 hours ago
```

**Q6 — Alert-delivery container errors:**
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
FACET container_name
SINCE 12 hours ago
```

**Q7 — NR Issues opened (NerdGraph `list_recent_issues`, 12h window, account 3421145).**

</details>

## End
