---
title: "Overnight Health Check 2026-05-13"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts, blocked, new-relic]
created: 2026-05-13
updated: 2026-05-13
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-14
---

# Overnight Health Check 2026-05-13

## Summary

Check FAILED to execute — all four NR investigation paths were blocked by the headless sandbox approval gate; no health data was collected for this 12h window.

## Issues Found

- **Headless sandbox blocked all NR queries.** Every subagent reported the same root cause: in a `claude -p` / headless context, `Bash(python3 /home/mork/.claude/lib/nr_query.py ...)` is not in the pre-approved allowlist, and the [[new-relic|New Relic]] MCP tools cannot be used because they require interactive OAuth (would hang). Direct `curl` to NerdGraph was also blocked.
- **Coverage gap for 2026-05-13 overnight window** — no autopatrol, connector-fleet, alert-delivery, or NR-Issues data for the last 12h.
- **Three-tier pattern violation.** This check is currently Tier 3 (LLM skill) only. Per the three-tier routine-check pattern, it should be Tier 1 (Firebat script + systemd timer writing to `~/.local/state/claude-jobs/`) so it works without LLM tool approval. Tier 3 is the last resort, not the primary path.
- **Recommended remediations** (in priority order):
  1. Add `"Bash(python3 /home/mork/.claude/lib/nr_query.py *)"` to the `allow` list in `/home/mork/.claude/settings.json` so headless invocations can run the wrapper.
  2. Promote this check to a Firebat Tier-1 script (`~/bin/overnight-health-check`) calling NerdGraph directly via the API-key path, bypassing LLM tool approval entirely.
  3. Until either lands, run the queries below manually in NR Query Builder or in an interactive Claude Code session.

## AutoPatrol

**Status: BLOCKED — no data.**

Subagent (`nrql-investigator`) hit the Bash sandbox approval gate; `nr_query.py` could not execute and the MCP fallback is not safe headlessly. The four queries it prepared are preserved in the Raw NRQL section below.

Flags that would have been evaluated (still unevaluated for this window):

- Any of sites 41158, 41178, 40672, 45061, 37837 with 0 patrols in 12h.
- Any of those sites with >5 CNCTNFAILs.
- Any `autopatrol-server` ERROR-level log count >0.
- Any non-zero ERROR count on a `*autopatrol*` connector container.

These remain UNKNOWN for the 2026-05-13 overnight window. If autopatrol coverage is operationally critical for today, run the Q1–Q4 queries below manually.

## Connector Fleet

**Status: BLOCKED — no data.**

Subagent could not execute the FACET query on `level='ERROR'` across `Connector-EKS` containers. The >100 errors / container flag is unevaluated. UNKNOWN for the 2026-05-13 overnight window.

## Alert Delivery

**Status: BLOCKED — no data.**

Subagent could not query ERROR counts for the canonical alert containers (`queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`). The >20 errors / container flag is unevaluated. UNKNOWN for the 2026-05-13 overnight window.

## New Issues

**Status: BLOCKED — no data.**

Subagent could not query `NrAiIncident` (count, severity distribution, top 3 by entity). Both the `nr_query.py` path and the direct NerdGraph `curl` path were sandbox-blocked, and MCP is not safe in headless context. UNKNOWN for the 2026-05-13 overnight window.

## Raw NRQL

<details>
<summary>Queries that were prepared but did not execute (run manually in NR Query Builder)</summary>

**Q1 — Patrol counts per site (sites of interest):**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND message LIKE '%patrol%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10
```

**Q2 — autopatrol-server ERROR count:**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago
```

**Q3 — CNCTNFAIL counts per site:**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET CASES(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10
```

**Q4 — Connector-side autopatrol errors by container:**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name LIMIT 15
SINCE 12 hours ago
```

**Q5 — Connector fleet ERROR counts (top 15 containers):**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name LIMIT 15
SINCE 12 hours ago
```

**Q6 — Alert-delivery container ERROR counts:**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name SINCE 12 hours ago LIMIT 10
```

**Q7 — NR Issues opened (severity + entities):**
```nrql
FROM NrAiIncident SELECT count(*) FACET priority SINCE 12 hours ago
FROM NrAiIncident SELECT count(*) FACET entityName SINCE 12 hours ago LIMIT 3
```

</details>

## End
