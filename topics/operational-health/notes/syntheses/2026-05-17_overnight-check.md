---
title: "Overnight Health Check 2026-05-17"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-17
updated: 2026-05-17
author: kb-bot
status: yellow
incoming:
  - No backlinks found.
incoming_updated: 2026-05-18
---

# Overnight Health Check 2026-05-17

## Summary

Yellow — autopatrol prod server idle since 07:16 UTC restart (dev server handling traffic); 2 of 5 monitored sites have no patrol activity in 12h; `queue-evalink-consumer` ERROR count well above threshold; large platform-wide error volume on `create-detection-window`; 2 NR issues still active (AI Link Timeouts, High CPU on ip-10-10-61-242).

## Issues Found

- **autopatrol-server (prod) idle** — restarted at 07:16 UTC, only 58 log lines since (all startup/DEBUG). Verify it is consuming jobs after restart.
- **autopatrol-server-dev handling prod-adjacent traffic** — 6,655 log entries including CNCTNFAIL patrol summaries for sites 35830/35832. Verify intentional.
- **Site 41158 — 0 patrol activity in 12h** (no cronjob container found in cluster). Verify scheduling / offboarding.
- **Site 45061 — 0 patrol activity in 12h** (same — no cronjob container found).
- **`queue-evalink-consumer` — 146 ERRORs** (threshold >20). Drill: `SELECT message FACET message LIMIT 10` for triage.
- **`create-detection-window` — 9,223 ERRORs** (platform service, ~2x next-highest). Likely independent issue worth its own investigation.
- **All 15 connector containers above 100-error threshold** — fleet-wide noise consistent with prior baselines but worth a periodic re-baseline.
- **2 NR issues still ACTIVE** — AI Link Timeouts (Log query entity, `actuate_ailink`/`clips-prod`), High CPU on host `ip-10-10-61-242.us-west-2.compute.internal` (open since 01:22 UTC, 5+ min above 85%).

## AutoPatrol

Per-site activity (patrol cronjob containers, last 12h):

| Site | Cronjob container | Log count | Patrol active? |
|---|---|---|---|
| 41158 | (none found) | 0 | NO |
| 41178 | connector-41178-autopatrol-350-chm-cronjob | 504 | yes |
| 40672 | connector-40672-autopatrol-1027-chm-cronjob | 840 | yes |
| 45061 | (none found) | 0 | NO |
| 37837 | connector-37837-autopatrol-1028-chm-cronjob | 600 | yes |

Per-site CNCTNFAIL counts: all 5 monitored sites = 0. (Note: 442 total CNCTNFAILs in 12h were concentrated on sites 35830/35832/35831, not the monitored set.)

- `autopatrol-server` ERROR count: **0** in 12h (caveat: `level` attr is null on these logs; level is embedded in message text, so structured filtering is unreliable).
- `container_name LIKE '%autopatrol%' AND level='ERROR'`: **0** structured ERRORs across all autopatrol containers.
- **Flag**: autopatrol-server (prod) appears idle since 07:16 UTC restart — only startup logs since. autopatrol-server-dev is producing prod-adjacent volume.

Caveat on the prescribed queries: the `message LIKE '%<site_id>%'` patterns returned 0 rows for all sites because site IDs appear in container names (cronjob naming), not message bodies. Substituted with per-site cronjob container log counts.

## Connector Fleet

ERROR counts by container, last 12h, top 15 (all 15 above 100-error flag threshold):

| Container | Errors |
|---|---|
| create-detection-window | 9,223 |
| connector-36681 | 4,480 |
| connector-11202 | 3,681 |
| connector-10700 | 2,366 |
| connector-37081 | 1,994 |
| connector-36679 | 1,692 |
| connector-17328 | 1,501 |
| connector-12686 | 1,501 |
| connector-34144 | 1,501 |
| connector-17331 | 1,500 |
| connector-35025 | 1,422 |
| connector-17379 | 1,414 |
| connector-36381 | 1,410 |
| connector-23430 | 1,408 |
| connector-19527 | 1,407 |

`create-detection-window` is a platform service (not a site connector); its 9,223 errors are ~2x the next-highest and look like an independent issue. The connector fleet errors cluster at ~1,400–1,500 for many sites, suggesting a possible shared upstream pattern.

## Alert Delivery

| Container | Errors (12h) |
|---|---|
| **queue-evalink-consumer** | **146** ⚠ |
| queue-eagle-eye-consumer | 0 |
| smtp-frame-receiver | 0 |
| cert-manager-webhook | 0 |
| clips-smtp-worker | 0 |

- **Flag**: `queue-evalink-consumer` at 146 errors (threshold >20). Triage next.
- Other four canonical names returned zero ERROR rows. Caveat: zero rows means no matching ERROR-level logs, not necessarily that containers are healthy/up.

## New Issues

4 NR Issues opened in last 12h. All CRITICAL severity (this account has no WARNING/INFO issues).

Severity distribution: CRITICAL=4, WARNING=0, INFO=0.

Status: 2 ACTIVATED, 2 CLOSED.

Top 3 by entity:

1. **"Log query" — AI Link Timeouts** (policy: AI Link Errors) — STILL OPEN. Activated recently; `actuate_ailink`/`clips-prod` timeout patterns.
2. **`ip-10-10-61-242.us-west-2.compute.internal` — High CPU** (policy: Golden Signals) — STILL OPEN since ~01:22 UTC, CPU >85% sustained.
3. **"Log query" — SMTP files with an extension discarded** (policy: SMTP files discarded) — CLOSED after ~2 min (smtp-frame-receiver around 09:10 UTC).

Fourth (closed): AI Link Errors (auto-resolved in ~3 min).

## Raw NRQL

<details>
<summary>Queries executed</summary>

```sql
-- AutoPatrol Q1: per-site patrol counts (prescribed — returned 0 rows; site ID lives in container name)
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND message LIKE '%patrol%'
FACET cases(WHERE message LIKE '%41158%' AS '41158',
            WHERE message LIKE '%41178%' AS '41178',
            WHERE message LIKE '%40672%' AS '40672',
            WHERE message LIKE '%45061%' AS '45061',
            WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol Q2: autopatrol-server ERROR count
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- AutoPatrol Q3: per-site CNCTNFAIL counts
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(WHERE message LIKE '%41158%' AS '41158',
            WHERE message LIKE '%41178%' AS '41178',
            WHERE message LIKE '%40672%' AS '40672',
            WHERE message LIKE '%45061%' AS '45061',
            WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol Q4: connector-side autopatrol ERRORs
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet ERRORs
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery ERRORs
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
                         'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- NR Issues: pulled via list_recent_issues MCP (24h window), filtered client-side to createdAt >= now - 12h
```

</details>

## End
