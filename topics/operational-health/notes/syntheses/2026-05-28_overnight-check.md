---
title: "Overnight Health Check 2026-05-28"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, run-failed]
created: 2026-05-28
updated: 2026-05-28
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-29
---

# Overnight Health Check 2026-05-28

## Summary

Run failed to gather data — all four NR delegations were blocked by the headless session's sandbox before reaching [[new-relic|New Relic]]. No platform-health signal collected for this 12h window.

## Issues Found

- **Tooling failure (not a platform signal):** the `nr_query.py` wrapper invocation via Bash required interactive approval in this unattended session, blocking every NRQL delegation. The `mcp__newrelic__list_recent_issues` MCP tool was not registered in the subagent context either, so the Issues check had no execution path.
- Net effect: AutoPatrol, connector fleet, alert-delivery, and NR Issues sections all returned empty. Treat this report as a tooling-incident record, not an all-clear.
- **Action for next run:** allowlist `python3 /home/mork/.claude/lib/nr_query.py` (or wrap NR access in a Tier-1 Firebat script invoked by this routine) so unattended [[automation-overnight-check|overnight checks]] can execute. The four NRQL queries are preserved verbatim below — they are correct and ready to run manually or to be wrapped.

## AutoPatrol

Status: **unknown — not gathered.**

The nrql-investigator subagent prepared the four queries (patrol counts per site, autopatrol-server ERRORs, CNCTNFAIL per site, autopatrol-side container errors) but every `Bash` invocation of `nr_query.py` was blocked by sandbox approval prompts. No site-level patrol counts or CNCTNFAIL counts were retrieved. Sites 41158, 41178, 40672, 45061, 37837 status: not verified.

The `/autopatrol-overnight-check` skill itself was skipped (kubectl/kubefwd not available in headless mode); NR-only fallback was the intended substitute and it also did not execute.

## Connector Fleet

Status: **unknown — not gathered.**

Intended query: ERROR counts FACET container_name SINCE 12 hours ago, LIMIT 15, with flag threshold > 100. Sandbox blocked the wrapper call. No container counts available.

## Alert Delivery

Status: **unknown — not gathered.**

Intended canonical containers: `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`. Flag threshold > 20. Sandbox blocked the wrapper call. No per-container error counts available.

## New Issues

Status: **unknown — not gathered.**

`mcp__newrelic__list_recent_issues` not registered in this session's subagent context. NRQL fallback via `FROM NrAiIncident` was identified but not executed (same sandbox blocker as the Log queries). Severity distribution and top-3 entities not retrieved.

## Raw NRQL

<details>
<summary>Queries prepared but not executed (run manually or wrap in a Tier-1 script)</summary>

**AutoPatrol — patrol counts per site**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10
```

**AutoPatrol — autopatrol-server ERRORs**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND level='ERROR'
SINCE 12 hours ago
```

**AutoPatrol — CNCTNFAIL per site**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
)
SINCE 12 hours ago LIMIT 10
```

**AutoPatrol — connector-side autopatrol errors**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10
```

**Connector fleet — ERROR counts**
```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15
```

**Alert delivery — canonical containers**
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
FACET container_name
SINCE 12 hours ago
```

**Issues fallback (since MCP unavailable)**
```sql
FROM NrAiIncident SELECT count(*) FACET priority SINCE 12 hours ago
FROM NrAiIncident SELECT latest(conditionName), latest(targetName), latest(priority) FACET incidentId SINCE 12 hours ago LIMIT 10
```

</details>

## End
