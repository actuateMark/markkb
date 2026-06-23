---
title: "Overnight Health Check 2026-06-16"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-16
updated: 2026-06-16
author: kb-bot
status: warn
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# Overnight Health Check 2026-06-16

## Summary

Core pipelines are running, but two autopatrol sites (41158, 45061) show zero patrol activity in 12h, alert delivery via queue-evalink-consumer logged 296 errors, and 69 NR Issues opened (55 CRITICAL) — investigation warranted.

## Issues Found

- **AutoPatrol — site 45061: no autopatrol CronJob.** VPA recommender fires every ~10 min: `CronJob rearchitecture/connector-45061-autopatrol-1025-chm-cronjob does not exist`. Strong signal the CronJob was deleted or never provisioned in the `rearchitecture` namespace.
- **AutoPatrol — site 41158: zero autopatrol container activity in 12h.** No `connector-41158-autopatrol-*` container logging to NR (only a VCH cronjob container present). May be a quiet/nightly schedule, but no patrol evidence in window.
- **Alert delivery — `queue-evalink-consumer`: 296 ERRORs** (>20 threshold). Other alert paths (eagle-eye, smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker) clean.
- **Connector fleet — all top-15 containers exceed 100 errors**, top offender `connector-36681` at 2,414. `create-detection-window` (platform service) at 1,281 may warrant separate triage. Note: this is a 12h count and connector ERROR baselines often run high; trend-compare before escalating.
- **NR Issues — 69 opened (55 CRITICAL, 14 HIGH).** Bulk of CRITICALs are "Deployment has unavailable pods" across many connectors plus clips-prod; HIGH dominated by POST /analyze 499s.

## AutoPatrol

NR-only check (k8s/kubefwd unavailable in headless session).

**Patrol activity per site (actual autopatrol container logs):**

| Site | AutoPatrol container activity | Status |
|------|-------------------------------|--------|
| 40672 | `connector-40672-autopatrol-1027-chm-cronjob` — 2,856 lines | ✅ running |
| 37837 | `connector-37837-autopatrol-1028-chm-cronjob` — 768 lines | ✅ running |
| 41178 | `connector-41178-autopatrol-350-chm-cronjob` — 516 lines | ✅ running |
| 41158 | none | ⚠️ **no activity** |
| 45061 | none (VPA: CronJob does not exist) | ⚠️ **no CronJob** |

Note: the broad `message LIKE '%patrol%'` per-site facet (40672=2133, 37837=1087, 41158=1013, 41178=718, 45061=151) is misleading — 45061's 151 are all VPA recommender errors, and 41158's count has no backing autopatrol container. Actual container activity above is the reliable signal.

- **autopatrol-server errors:** 0 — server healthy; recent `PATROL COMPLETED` summaries observed (e.g. site 47738 at 12:01 UTC).
- **CNCTNFAIL per site:** 0 across all five sites. ✅
- **Connector-side autopatrol errors** (other sites): connector-46767 (21), connector-47738 (16/4), connector-35831 (2/1), connector-35832 (1). None on the five queried sites.

**Flags:** sites 41158 and 45061 have zero autopatrol activity (45061 has a confirmed missing CronJob); no CNCTNFAIL flags; no autopatrol-server errors.

## Connector Fleet

ERROR counts, `cluster_name='Connector-EKS'`, SINCE 12h, FACET container_name, LIMIT 15 — **every returned container exceeds the 100-error threshold:**

| Container | Errors |
|---|---|
| connector-36681 | 2,414 |
| connector-31563 | 2,264 |
| connector-47778 | 1,697 |
| connector-12686 | 1,507 |
| connector-17331 | 1,506 |
| connector-17328 | 1,504 |
| connector-35025 | 1,499 |
| sirix-volkswagen-boisbriand-1718 | 1,414 |
| connector-17379 | 1,412 |
| connector-17327 | 1,411 |
| connector-23430 | 1,410 |
| connector-19527 | 1,409 |
| connector-10611 | 1,393 |
| create-detection-window | 1,281 |
| connector-32996 | 1,187 |

LIMIT 15 is not exhaustive — containers beyond rank 15 may also be elevated. `create-detection-window` is a platform service (not a site connector) and warrants separate inspection.

## Alert Delivery

ERROR counts SINCE 12h for canonical alert-path containers:

| Container | Errors | Status |
|---|---|---|
| queue-evalink-consumer | 296 | ⚠️ **flagged (>20)** |
| queue-eagle-eye-consumer | 0 | ✅ |
| smtp-frame-receiver | 0 | ✅ |
| cert-manager-webhook | 0 | ✅ |
| clips-smtp-worker | 0 | ✅ |

Only `queue-evalink-consumer` is elevated. Suggested follow-up: facet its ERRORs by `message` to identify the driver.

## New Issues

**69 Issues opened SINCE 12h** — CRITICAL: 55, HIGH: 14, MEDIUM/LOW: 0.

Top recurring titles:
1. **POST /analyze 499 errors** (HIGH, 14×) — client-disconnect errors on analyze endpoint.
2. **Deployment has unavailable pods — clips-prod** (CRITICAL, 3×) — clips-prod cycling through unavailable pods.
3. **SMTP files with an extension discarded** (3×) — inbound SMTP files dropped on smtp-frame-receiver path.

The CRITICAL bucket is dominated by "Deployment has unavailable pods" across many distinct connectors (connector-template-14921, connector-8196, connector-44712-fs-1371, connector-44300-fs-1632, …) plus two High-CPU EC2 node alerts (ip-10-10-14-199, ip-10-10-22-193). Counts reflect issue-event re-fires within the window, not unique GUIDs.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol: patrol mentions per site (broad)
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%'
FACET CASES(WHERE message LIKE '%41158%' AS '41158', WHERE message LIKE '%41178%' AS '41178',
            WHERE message LIKE '%40672%' AS '40672', WHERE message LIKE '%45061%' AS '45061',
            WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- AutoPatrol: server errors
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
AND container_name='autopatrol-server' AND level='ERROR' SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET CASES(WHERE message LIKE '%41158%' AS '41158', ... [five sites]) SINCE 12 hours ago LIMIT 10

-- AutoPatrol: connector-side autopatrol errors
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
AND container_name LIKE '%autopatrol%' AND level='ERROR' FACET container_name SINCE 12 hours ago LIMIT 10

-- AutoPatrol: actual autopatrol container activity for the five sites
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
AND (container_name LIKE '%41158%autopatrol%' OR ... [all five sites])
FACET container_name SINCE 12 hours ago LIMIT 20

-- Connector fleet error counts
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

-- New Issues (via list_recent_issues + NrAiIssue facet)
FROM NrAiIssue SELECT count(*) FACET title WHERE event = 'open' SINCE 12 hours ago LIMIT 10
```

</details>

## End
