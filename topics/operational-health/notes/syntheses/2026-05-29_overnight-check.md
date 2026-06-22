---
title: "Overnight Health Check 2026-05-29"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-29
updated: 2026-05-29
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-30
---

# Overnight Health Check 2026-05-29

## Summary

**DEGRADED — data collection blocked.** The headless session's Bash sandbox refused every NRQL execution path (`python3 nr_query.py`, direct shebang, `curl` to NerdGraph). MCP [[new-relic|New Relic]] tools were also unavailable in this subagent context (OAuth-gated). No health signals were retrieved for any of the four checks.

## Issues Found

- **Headless sandbox blocking all outbound NR queries.** Both the parent context and all four delegated `nrql-investigator` subagents hit the same approval gate. This is an environment/permissions issue, not a credentials or query issue — the API key at `~/.config/nr/api-key` is present.
- **Tier-3 fallback ran when Tier 1/2 should have.** Per the three-tier routine-check pattern, this check should execute from a Firebat systemd timer or local laptop script and only fall back to the LLM skill on failure. Tier 1/2 either didn't run or didn't surface their results into this session. Recommend confirming the Firebat overnight-check timer state and the laptop-tier deployment.
- **No verdict possible** on autopatrol pipeline, connector fleet errors, alert delivery, or NR Issues for the last 12 hours.

## AutoPatrol

Blocked. Staged queries (account 3421145, `cluster_name='Connector-EKS'`, `SINCE 12 hours ago`):

- Patrol counts per site (41158, 41178, 40672, 45061, 37837) — `filter(count(*), WHERE message LIKE '%<site>%')` across autopatrol-namespace logs.
- `autopatrol-server` ERROR count — `container_name='autopatrol-server' AND level='ERROR'`.
- CNCTNFAIL counts per site — filter pattern on `message LIKE '%CNCTNFAIL%<site>%'`.
- Connector-side autopatrol errors — `FACET container_name WHERE container_name LIKE '%autopatrol%' AND level='ERROR'`.

Flags that would have applied (any site 0 patrols / >5 CNCTNFAIL / any autopatrol-server error) **could not be evaluated**.

Note: The `/autopatrol-overnight-check` skill itself requires `kubectl` + `kubefwd` MCP which are unavailable in this headless session — only the NR-only subset was attempted, and even that subset was blocked.

## Connector Fleet

Blocked. Staged query:

```
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15
```

Flag threshold (>100 errors per container) could not be evaluated.

## Alert Delivery

Blocked. Staged query (canonical hyphenated names per known-good list — old underscore names omitted):

```
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
                         'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name
```

Flag threshold (>20 errors per container) could not be evaluated.

## New Issues

Blocked. Staged queries:

```
FROM NrAiIssue SELECT count(*) WHERE event='activate' SINCE 12 hours ago FACET priority LIMIT 10
FROM NrAiIssue SELECT count(*) WHERE event='activate' SINCE 12 hours ago FACET entityName LIMIT 10
```

Issue count, severity distribution, and top-3 entities **unknown for this window**.

## Raw NRQL

<details>
<summary>Queries staged but not executed</summary>

```sql
-- Patrol counts per site
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%41158%') AS site_41158,
  filter(count(*), WHERE message LIKE '%41178%') AS site_41178,
  filter(count(*), WHERE message LIKE '%40672%') AS site_40672,
  filter(count(*), WHERE message LIKE '%45061%') AS site_45061,
  filter(count(*), WHERE message LIKE '%37837%') AS site_37837
WHERE cluster_name='Connector-EKS'
  AND namespace LIKE 'autopatrol%'
  AND (message LIKE '%patrol%' OR message LIKE '%task results%' OR message LIKE '%camera threads%')
SINCE 12 hours ago

-- autopatrol-server errors
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- CNCTNFAIL per site
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%41158%') AS cnctnfail_41158,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%41178%') AS cnctnfail_41178,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%40672%') AS cnctnfail_40672,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%45061%') AS cnctnfail_45061,
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%37837%') AS cnctnfail_37837
WHERE cluster_name='Connector-EKS'
SINCE 12 hours ago

-- Connector-side autopatrol error containers
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 10

-- Connector fleet errors
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15

-- Alert delivery errors
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
                         'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name

-- NR Issues opened
FROM NrAiIssue SELECT count(*) WHERE event='activate' SINCE 12 hours ago FACET priority LIMIT 10
FROM NrAiIssue SELECT count(*) WHERE event='activate' SINCE 12 hours ago FACET entityName LIMIT 10
```

</details>

## End
