---
title: "Overnight Health Check 2026-06-22"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
status: attention
incoming:
  - No backlinks found.
incoming_updated: 2026-06-24
---

# Overnight Health Check 2026-06-22

## Summary

Multiple flags across all four checks — two target autopatrol sites silent, a CNCTNFAIL storm at site 35830, a 10k-error connector outlier, an evalink consumer error spike, and 50 CRITICAL NR issue events (mostly one hot EC2 host + pod-availability churn).

## Issues Found

- **Autopatrol — site 41158: 0 patrol logs in 12h.** Absent from all cluster logs, not just autopatrol containers. Connector may be down or site not configured.
- **Autopatrol — site 45061: 0 patrol logs in 12h.** Same total absence as 41158.
- **Autopatrol — site 35830: 206 CNCTNFAILs** (192 + 14 across two patrol containers) — 40× the >5 threshold. All cameras at the site repeatedly failing to connect ("Unable to run detections due to connection failure"). Not in the target five but the most severe pattern cluster-wide.
- **Connector fleet — connector-11202: 10,182 ERRORs in 12h.** ~3.7× the next-highest container; clear outlier needing drill-down.
- **Connector fleet — all top-15 containers exceed 100 ERRORs.** Tight cluster of ranks 8–15 (1,409–1,514) suggests a shared failure mode.
- **Alert delivery — queue-evalink-consumer: 650 ERRORs in 12h** (~54/hr), well over the >20 threshold.
- **NR Issues — 50 CRITICAL events**, dominated by one EC2 host (`ip-10-10-22-56`, high CPU) and recurring "unavailable pods" across several connectors + smtp-frame-receiver.

## AutoPatrol

**Target-site patrol activity (12h, autopatrol containers):**

| Site ID | Log Count | Status |
|---------|-----------|--------|
| 40672 | 1,358 | Active |
| 37837 | 313 | Active |
| 41178 | 180 | Active |
| 41158 | 0 | **FLAG — no logs anywhere in cluster** |
| 45061 | 0 | **FLAG — no logs anywhere in cluster** |

**Autopatrol-server (prod) ERRORs:** 0 — clean and active (21,702 log lines in window).

**CNCTNFAIL — target sites:** 0 for all five (41158, 41178, 40672, 45061, 37837). However **519 cluster-wide**, concentrated off-target:

| Container (site) | CNCTNFAIL |
|---|---|
| connector-35830-autopatrol-309-chm-cronjob | 192 |
| autopatrol-server-dev | 103 |
| connector-35832-autopatrol-260-chm-cronjob | 96 |
| connector-44346-vch-1049-chm-cronjob | 28 |
| connector-37255-autopatrol-1127-chm-cronjob | 24 |
| connector-40512-vch-1092-chm-cronjob | 16 |
| connector-40792-vch-1078-chm-cronjob | 16 |
| connector-35830-autopatrol-308-chm-cronjob | 14 |
| connector-47738-autopatrol-1136-chm-cronjob | 8 |
| autopatrol-server (prod) | 6 |

Site 35830 (206 combined) is the worst offender. **NOTE:** autopatrol-server-dev logging production-volume CNCTNFAILs (103) — possible dev/prod config bleed worth a look.

**Connector-side autopatrol ERRORs (35 total):** connector-37255 (12), connector-46767 (11), connector-47738 (8+1), plus singles at 35832/35831.

## Connector Fleet

ERROR counts, top 15 by container (12h) — **every container in the top 15 exceeds the >100 threshold:**

| Rank | Container | ERRORs |
|------|-----------|--------|
| 1 | connector-11202 | 10,182 |
| 2 | connector-43276 | 2,728 |
| 3 | connector-41028 | 2,621 |
| 4 | connector-31563 | 2,272 |
| 5 | connector-21884 | 2,129 |
| 6 | connector-35025 | 1,835 |
| 7 | create-detection-window | 1,650 |
| 8 | connector-17331 | 1,514 |
| 9 | connector-12686 | 1,510 |
| 10 | connector-17328 | 1,508 |
| 11 | connector-19527 | 1,415 |
| 12 | connector-39780 | 1,412 |
| 13 | connector-17295 | 1,411 |
| 14 | connector-17379 | 1,411 |
| 15 | connector-23430 | 1,409 |

- **connector-11202** is the dominant outlier (~3.7× rank 2) — drill into its message FACET next.
- **create-detection-window** (rank 7) is the only non-connector platform service in the top 15.
- Ranks 8–15 form a tight 1,409–1,514 band, suggesting a shared failure mode / common config.
- Caveat: top-15 only; the full fleet may have additional >100-error containers not shown.

## Alert Delivery

ERROR counts (12h) for canonical alert-path containers:

| Container | ERRORs | Flag |
|---|---|---|
| queue-evalink-consumer | 650 | **FLAG (>20)** |
| queue-eagle-eye-consumer | 2 | OK |
| smtp-frame-receiver | 0 (no rows) | — |
| cert-manager-webhook | 0 (no rows) | — |
| clips-smtp-worker | 0 (no rows) | — |

- **queue-evalink-consumer at 650 (~54/hr)** is the only flagged container — needs message-pattern triage.
- Three containers returned zero rows; could be genuinely error-free, not running/logging this window, or a slightly different container name. Confirm with a `level != 'ERROR'` probe if ingestion-gap concern.

## New Issues

- **Total NR issue events (NrAiIssue) opened in 12h:** 50 — all tagged **CRITICAL** (no HIGH/MEDIUM/LOW). Note these are state-change events; distinct logical issue count is lower.
- **Top 3 by event volume:**
  1. **High CPU — `ip-10-10-22-56.us-west-2.compute.internal`** (12 events) — single EC2 host persistently breaching >85% CPU over sustained 5-min windows.
  2. **SMTP files with an extension discarded** (3 events) — log-based alert on the smtp-frame-receiver pipeline.
  3. **Deployment has unavailable pods** (3 events each) — `connector-41551-fs-1457`, `connector-44300-fs-1765`, `smtp-frame-receiver-depl`; additional connectors (20139, 11998, 12005, 12183) at 2–3 events.
- Caveat: `list_recent_issues` exceeded token limits; counts derived from `NrAiIssue` NRQL (event-level). The multi-connector "unavailable pods" pattern may reflect a rollout / node-pressure event rather than isolated failures.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- Autopatrol: per-site patrol activity
FROM Log SELECT count(*)
FACET cases(WHERE message LIKE '%41158%' AS 'site_41158', /* ...one per site... */)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%'
SINCE 12 hours ago LIMIT 10

-- Autopatrol-server ERRORs
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- CNCTNFAIL per target site
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
  AND (message LIKE '%41158%' OR /* ...one per site... */)
SINCE 12 hours ago
-- (and cluster-wide variant: FACET container_name WHERE message LIKE '%CNCTNFAIL%')

-- Connector-side autopatrol ERRORs
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet ERROR counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery ERRORs
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

-- NR Issues opened
FROM NrAiIssue SELECT count(*) FACET title, priority SINCE 12 hours ago
```

</details>

## End
