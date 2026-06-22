---
title: "Overnight Health Check 2026-05-03"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, blocked]
created: 2026-05-03
updated: 2026-05-03
author: kb-bot
status: blocked
incoming:
  - No backlinks found.
incoming_updated: 2026-05-04
---

# Overnight Health Check 2026-05-03

## Summary

**BLOCKED — no health data collected.** Every NRQL execution path was rejected by the sandbox in this headless session: `python3 /home/mork/.claude/lib/nr_query.py` invocations require interactive approval that cannot be granted, the `mcp__newrelic__*` tools are not present in this context, and even parallel-batched parent-context calls were cancelled. All four delegated subagents (autopatrol, fleet errors, alert delivery, NR issues) reported the same blocker. Recommend re-running this check from an interactive Claude Code session, or fixing the cron/headless wrapper to pre-approve `python3 /home/mork/.claude/lib/nr_query.py` so the wrapper's NerdGraph calls can complete unattended.

## Issues Found

- **Health-check infrastructure issue (not a fleet issue):** `python3 /home/mork/.claude/lib/nr_query.py` is not on the headless allowlist. Until that's addressed, this [[automation-overnight-check|overnight check]] produces no signal — false-green risk if the operator assumes "no findings = healthy."
- **No fleet data captured** for: autopatrol patrol counts, autopatrol-server errors, CNCTNFAIL counts, connector-side autopatrol errors, fleet ERROR FACET, alert-delivery container errors, or NrAiIssue-opened-in-12h. State of the fleet for the 12h window ending 2026-05-03 is unknown from this run.
- **Action:** add `python3 /home/mork/.claude/lib/nr_query.py *` to the headless permissions allowlist (or the overnight wrapper's pre-approved command set), then re-run, OR have `/autopatrol-overnight-check` and the connector [[automation-overnight-check|overnight checks]] invoked from an interactive session today.

## AutoPatrol

**Not collected.** Subagent (`a4c6194585199d1a0`) was blocked on every `nr_query.py` invocation. Queries that would have been run are listed below. Cannot confirm whether any of sites 41158, 41178, 40672, 45061, or 37837 went silent in the last 12h, whether `autopatrol-server` logged any ERROR-level events, or whether CNCTNFAIL volume is elevated. Note also that `/autopatrol-overnight-check` (Tier 3 LLM) requires `kubectl` + `kubefwd` MCP which are unavailable here — even if NRQL were unblocked, the full skill could not run in this headless context.

## Connector Fleet

**Not collected.** Subagent (`a80e33ad4f494c6c7`) was blocked. No data on top-15 ERROR-emitting containers, and no ability to flag any container exceeding the 100-error threshold for the 12h window.

## Alert Delivery

**Not collected.** Subagent (`a9c0eb99c441c3dd4`) was blocked. No data on `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, or `clips-smtp-worker` ERROR counts. Cannot evaluate the >20-errors flag.

## New Issues

**Not collected.** Subagent (`acea8f62d243d32d0`) was blocked. No NrAiIssue data — count, severity distribution, and top-3 entities are all unknown for the 12h window.

## Raw NRQL

<details>
<summary>Queries that would have been executed (none ran)</summary>

```sql
-- Q1: Patrol message counts per site (autopatrol)
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10

-- Q2: Autopatrol-server total ERROR count
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
AND level='ERROR' SINCE 12 hours ago

-- Q3: CNCTNFAIL counts per site
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10

-- Q4: Connector-side autopatrol errors
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS'
AND container_name LIKE '%autopatrol%'
AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Q5: Connector fleet top-15 ERROR-emitting containers
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Q6: Alert-delivery container ERROR counts
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name IN (
  'queue-evalink-consumer',
  'queue-eagle-eye-consumer',
  'smtp-frame-receiver',
  'cert-manager-webhook',
  'clips-smtp-worker'
) FACET container_name SINCE 12 hours ago LIMIT 10

-- Q7: NR Issues opened in the last 12h
FROM NrAiIssue
SELECT count(*), latest(priority), latest(title), latest(entityNames)
WHERE accountId = 3421145 AND event = 'open'
SINCE 12 hours ago FACET issueId LIMIT 50
```

**Subagent IDs (resumable if Bash gate is removed):** `a4c6194585199d1a0` (autopatrol), `a80e33ad4f494c6c7` (fleet errors), `a9c0eb99c441c3dd4` (alert delivery), `acea8f62d243d32d0` (NrAiIssue).

</details>

## End
