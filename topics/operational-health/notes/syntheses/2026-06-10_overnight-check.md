---
title: "Overnight Health Check 2026-06-10"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-10
updated: 2026-06-10
author: kb-bot
status: warn
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-10

## Summary

AutoPatrol pipeline is fully healthy, but the connector fleet is burning elevated ERROR volume (every top-15 container >100 errors), `queue-evalink-consumer` alert delivery is flagged at 308 errors, and 62 NR Issues opened overnight (59 CRITICAL, dominated by "Deployment has unavailable pods").

## Issues Found

- **Connector fleet ERROR storm** — all 15 returned containers exceed the 100-error threshold over 12h; `connector-11202` is the outlier at **5,754** (~2.2× the next highest). LIMIT 15 means more containers >100 are likely not shown.
- **Alert delivery: `queue-evalink-consumer` flagged** — 308 ERRORs in 12h (threshold 20). `queue-eagle-eye-consumer` at 5 (OK); the other three canonical alert containers at 0.
- **62 NR Issues opened in 12h, 59 CRITICAL** — dominated by "Deployment has unavailable pods" across many connector namespaces, plus 2 "High CPU" node alerts. 3 HIGH-severity issues uncategorized (fell below top-10 facet cut).
- **Minor:** AutoPatrol site 45061 has notably lower patrol volume (107 vs 724–2,116 for other sites) — likely normal for a low-activity site but worth a glance.

## AutoPatrol

**Window:** SINCE 12 hours ago | **Account:** 3421145 | **Cluster:** Connector-EKS

**No flags triggered — pipeline healthy across all monitored sites.**

Patrol log counts per site:

| Site ID | Patrol Log Count |
|---------|------------------|
| 40672   | 2,116            |
| 41158   | 1,207            |
| 37837   | 1,054            |
| 41178   | 724              |
| 45061   | 107              |

All five sites active (none at zero).

| Flag Condition | Status |
|----------------|--------|
| Any site with 0 patrols in 12h | CLEAR — all 5 sites active |
| Any site with >5 CNCTNFAILs | CLEAR — 0 CNCTNFAIL events (query returned 0 rows) |
| autopatrol-server ERROR logs | CLEAR — 0 errors |
| Connector-side autopatrol ERRORs | CLEAR — 0 errors |

**Caveats:** Site 45061's low volume (107) is worth a follow-up if a volume floor is expected. The `CNCTNFAIL` match uses an exact `LIKE '%CNCTNFAIL%'` pattern — zero rows is clean but assumes production still emits that exact token.

## Connector Fleet

ERROR counts by container, SINCE 12h, LIMIT 15 — **every returned container exceeds the 100-error threshold:**

| container_name | error count |
|---|---|
| connector-11202 | **5,754** |
| connector-28919 | **2,597** |
| connector-31563 | **2,240** |
| connector-39490 | **1,944** |
| connector-17328 | **1,512** |
| connector-12686 | **1,510** |
| connector-17331 | **1,502** |
| connector-35025 | **1,470** |
| connector-17379 | **1,413** |
| connector-19527 | **1,412** |
| connector-17327 | **1,412** |
| connector-23430 | **1,405** |
| create-detection-window | **1,397** |
| connector-36681 | **1,353** |
| sirix-water-works-5077 | **1,137** |

**Caveats:** LIMIT 15 truncates the list — more containers >100 errors are likely present. `create-detection-window` and `sirix-water-works-5077` are platform/non-connector services mixed into the facet. To distinguish a sustained burn from a burst on the `connector-11202` outlier:
`FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND container_name='connector-11202' AND level='ERROR' SINCE 12 hours ago TIMESERIES 30 minutes`

## Alert Delivery

ERROR counts for canonical alert-delivery containers, SINCE 12h:

| Container | ERROR count | Flag |
|---|---|---|
| queue-evalink-consumer | 308 | **FLAGGED (>20)** |
| queue-eagle-eye-consumer | 5 | OK |
| smtp-frame-receiver | 0 | OK |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

**Caveats:** Zero-count containers confirmed zero for the window (FACET only returns rows with ≥1 match). To triage the `queue-evalink-consumer` spike, facet by `message` (top 5 distinct patterns) to determine single-repeated vs. multiple failure modes.

## New Issues

**Total opened in 12h: 62** — CRITICAL: 59 | HIGH: 3 | MEDIUM/LOW: 0

Top patterns by entity:

1. **"Deployment has unavailable pods" (CRITICAL)** — dominant pattern; bulk of the 59 CRITICAL issues. Entities include `connector-template-14921`, `connector-template-14920`, `connector-8196`, `connector-705-fs-630`, `connector-44300-fs-1553`, `connector-37781`, and others across connector namespaces.
2. **"High CPU" — EC2 node `ip-10-10-5-247.us-west-2.compute.internal` (CRITICAL)** — CPU >85% for 5+ min.
3. **"High CPU" — EC2 node `ip-10-10-22-165.us-west-2.compute.internal` (CRITICAL)** — same condition, second node.

**Caveats:** The 3 HIGH-severity issues fell below the top-10 facet cut and are unenumerated. Follow-up: `FACET by issueId WHERE priority = 'HIGH'` to identify them. The unavailable-pods pattern likely correlates with the connector-fleet ERROR storm above.

## Raw NRQL

<details>
<summary>Queries used (account 3421145, SINCE 12 hours ago)</summary>

```sql
-- AutoPatrol: patrol counts per site
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET cases(WHERE message LIKE '%41158%' AS '41158', WHERE message LIKE '%41178%' AS '41178',
            WHERE message LIKE '%40672%' AS '40672', WHERE message LIKE '%45061%' AS '45061',
            WHERE message LIKE '%37837%' AS '37837') SINCE 12 hours ago LIMIT 10

-- AutoPatrol: autopatrol-server errors
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
AND container_name='autopatrol-server' AND level='ERROR' SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(WHERE message LIKE '%41158%' AS '41158', WHERE message LIKE '%41178%' AS '41178',
            WHERE message LIKE '%40672%' AS '40672', WHERE message LIKE '%45061%' AS '45061',
            WHERE message LIKE '%37837%' AS '37837') SINCE 12 hours ago LIMIT 10

-- AutoPatrol: connector-side autopatrol errors
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
AND container_name LIKE '%autopatrol%' AND level='ERROR' FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet: error counts
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name LIMIT 15 SINCE 12 hours ago

-- Alert delivery: canonical containers
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver',
                       'cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

-- New Issues: opened in last 12h (via list_recent_issues / NrAiIssue)
```

</details>

## End
