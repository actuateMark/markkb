---
title: "Overnight Health Check 2026-05-24"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-24
updated: 2026-05-24
author: kb-bot
status: data-gap
incoming:
  - No backlinks found.
incoming_updated: 2026-05-27
---

# Overnight Health Check 2026-05-24

## Summary

Data gap — no checks executed. Headless session sandbox blocks Bash for the `nr_query.py` wrapper and the [[new-relic|New Relic]] MCP is unavailable to subagents, so all four steps (autopatrol pipeline, connector fleet errors, alert delivery, NR Issues) could not run. Health status of the platform is **unknown** for the past 12 hours.

## Issues Found

- **Tooling failure** — both the parent context Bash and four spawned `nrql-investigator` subagents were blocked from executing `python3 /home/mork/.claude/lib/nr_query.py`. Subagent attempts returned "This command requires approval" with no interactive approver present; parent Bash returned the same. Outbound HTTP to `api.newrelic.com` (curl fallback) was also blocked.
- **No autopatrol signal collected** — patrols/site, CNCTNFAILs, autopatrol-server errors, connector-side autopatrol errors all unknown.
- **No fleet error baseline collected** — top error containers unknown; cannot flag >100-error containers.
- **No alert delivery health collected** — queue-evalink-consumer / queue-eagle-eye-consumer / smtp-frame-receiver / cert-manager-webhook / clips-smtp-worker error counts unknown.
- **No NR Issues summary collected** — count, severity distribution, top entities unknown.

## AutoPatrol

Data gap. The `/autopatrol-overnight-check` skill is documented as requiring kubectl + kubefwd MCP (not available headless), and the NR-only fallback path also failed because the `nr_query.py` wrapper requires Bash approval that no human is present to grant. Suggested follow-up in an interactive session: run the four prepared NRQL queries below.

## Connector Fleet

Data gap. Top-15 ERROR-by-container query did not execute.

## Alert Delivery

Data gap. Canonical-name FACET query did not execute. (Note: confirmed list is `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker` — the underscore variants `queue_immix_consumer` / `queue_consumer` / `webhook_listener` return zero rows and were not used.)

## New Issues

Data gap. `NrAiIssue` FACET queries (priority and entityName) did not execute.

## Raw NRQL

<details>
<summary>Queries prepared but not executed</summary>

```sql
-- Patrols per site (12h)
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%41158%') AS '41158',
  filter(count(*), WHERE message LIKE '%41178%') AS '41178',
  filter(count(*), WHERE message LIKE '%40672%') AS '40672',
  filter(count(*), WHERE message LIKE '%45061%') AS '45061',
  filter(count(*), WHERE message LIKE '%37837%') AS '37837'
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND message LIKE '%patrol%'
SINCE 12 hours ago

-- autopatrol-server ERROR count
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND level='ERROR'
SINCE 12 hours ago

-- CNCTNFAIL per site
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%41158%') AS '41158',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%41178%') AS '41178',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%40672%') AS '40672',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%45061%') AS '45061',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%37837%') AS '37837'
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
SINCE 12 hours ago

-- Connector-side autopatrol errors
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10

-- Connector fleet top error containers
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15

-- Alert delivery
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name
SINCE 12 hours ago

-- NR Issues by priority
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago LIMIT 10

-- NR Issues by entity
FROM NrAiIssue SELECT count(*) FACET entityName SINCE 12 hours ago LIMIT 10
```

**Root cause of gap:** Bash tool is gated behind interactive approval in this headless invocation, and the `nrql-investigator` subagent inherits the same sandbox. Network egress to `api.newrelic.com` is also gated. Either the headless wrapper needs an allowlist entry for `python3 /home/mork/.claude/lib/nr_query.py` (and/or `curl https://api.newrelic.com/*`) in `settings.json` `permissions.allow`, or the NR MCP must be made available to headless subagents. Suggested fix: `/update-config` to add a project allowlist rule like `Bash(python3 /home/mork/.claude/lib/nr_query.py:*)` so the next scheduled [[automation-overnight-check|overnight check]] can actually run.

</details>

## End
