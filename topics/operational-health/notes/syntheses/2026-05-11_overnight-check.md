---
title: "Overnight Health Check 2026-05-11"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, data-gap]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-12
---

# Overnight Health Check 2026-05-11

## Summary

**Data gap — all NR queries blocked by Bash sandbox.** Today's headless check could not collect any signals. Health status of autopatrol, connector fleet, alert delivery, and NR Issues is **unknown** for the 12h window ending 2026-05-11.

## Issues Found

- **Tooling regression (blocker for this skill):** The Bash tool in this headless invocation rejected every `python3 /home/mork/.claude/lib/nr_query.py …` invocation with "This command requires approval" — both in the parent context and in all four delegated nrql-investigator subagents. No NRQL was executed.
- **No fallback path available:** MCP NR tools require interactive OAuth and are not usable headless. The nr_query.py wrapper is the intended fallback, but the sandbox is intercepting it before it reaches the NerdGraph API.
- **Last good snapshot:** 2026-05-08 [[automation-overnight-check|overnight check]] (per the kb-bot summary). 2026-05-09 and 2026-05-10 status not verified from this run.

**Action item:** the headless overnight-check wrapper needs `python3 /home/mork/.claude/lib/nr_query.py` on the allowlist (`.claude/settings.json` `allowedTools` or invoke `claude -p` with `--dangerouslySkipPermissions`), or the check should be promoted to a Tier-1 Firebat cron script that calls `nr_query.py` directly without the Claude sandbox layer (per the three-tier routine-check pattern).

## AutoPatrol

**Not collected — sandbox block.**

Intended queries (cluster_name='Connector-EKS', SINCE 12 hours ago):
- Patrol counts faceted on message LIKE for sites 41158, 41178, 40672, 45061, 37837.
- autopatrol-server ERROR count.
- CNCTNFAIL counts per site (same case-facet shape).
- Connector-side autopatrol ERROR counts faceted on container_name LIKE '%autopatrol%'.

Run manually from an interactive session to recover today's signal. Without these we cannot flag silent-site or CNCTNFAIL conditions for 2026-05-11.

## Connector Fleet

**Not collected — sandbox block.**

Intended query:
```
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15
```

## Alert Delivery

**Not collected — sandbox block.**

Intended query (canonical hyphenated container names — do NOT substitute the underscore variants, which return zero rows):
```
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago
```

## New Issues

**Not collected — sandbox block.**

Intended: NR Issues opened in the last 12h, with severity distribution and top-3 entities. Both `mcp__newrelic__list_recent_issues` (OAuth-blocked in headless) and the nr_query.py NerdGraph wrapper (Bash-blocked in headless) were unavailable.

## Raw NRQL

<details>
<summary>Queries that would have run (paste into NR query builder, account 3421145)</summary>

```sql
-- Q1 Patrols per site
SELECT count(*) AS total,
  filter(count(*), WHERE message LIKE '%41158%') AS site_41158,
  filter(count(*), WHERE message LIKE '%41178%') AS site_41178,
  filter(count(*), WHERE message LIKE '%40672%') AS site_40672,
  filter(count(*), WHERE message LIKE '%45061%') AS site_45061,
  filter(count(*), WHERE message LIKE '%37837%') AS site_37837
FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%patrol%'
SINCE 12 hours ago

-- Q2 autopatrol-server errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago

-- Q3 CNCTNFAIL per site
SELECT count(*) AS total,
  filter(count(*), WHERE message LIKE '%41158%') AS site_41158,
  filter(count(*), WHERE message LIKE '%41178%') AS site_41178,
  filter(count(*), WHERE message LIKE '%40672%') AS site_40672,
  filter(count(*), WHERE message LIKE '%45061%') AS site_45061,
  filter(count(*), WHERE message LIKE '%37837%') AS site_37837
FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago

-- Q4 Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Q5 Connector fleet errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Q6 Alert delivery errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago
```

</details>

## End
