---
title: "Overnight Health Check 2026-05-14"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-14
updated: 2026-05-14
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-15
---

# Overnight Health Check 2026-05-14

## Summary

Multiple concerns: 2 monitored autopatrol sites (41158, 45061) show no patrol log volume; connector fleet shows broadly elevated errors with 15+ containers over 100 errors (connector-34144 at ~4.9k); queue-evalink-consumer firing 192 errors; 81 CRITICAL NR Issues opened in 12h dominated by unavailable connector pods and EKS node high-CPU flapping.

## Issues Found

- **AutoPatrol — sites 41158 and 45061 have zero autopatrol log volume in 12h.** Both sites have `vch`-type cronjob containers but no `connector-{site}-autopatrol-*` containers were observed. Either not configured for autopatrol or jobs not running. Sites 40672 / 37837 / 41178 are healthy with normal log volume and zero errors.
- **Connector fleet — broadly elevated.** All top 15 containers exceed the 100-error threshold. Outliers: `connector-34144` (4,865), `connector-40439` (2,797), `create-detection-window` (2,650 — platform service), `connector-36681` (2,242).
- **Alert delivery — queue-evalink-consumer at 192 errors** (threshold >20). Other 4 alert-path containers clean.
- **NR Issues — 85 records / 31 distinct issues in 12h, 81 CRITICAL.** Themes: ~17 connectors with unavailable-pod alerts; EKS node `ip-10-10-49-112` high-CPU flapping (15 firings); platform log alerts (AI Link Timeouts/Errors, Envera Camera Unavailable, Invalid Token Spike, SMTP extension discard, Genesis failover) repeatedly firing.

## AutoPatrol

**Verdict:** Partial gap — 2 of 5 monitored sites missing; 3 active sites are clean.

| Site | Container | 12h log count |
|------|-----------|---------------|
| 40672 | connector-40672-autopatrol-1027-chm-cronjob | 840 |
| 37837 | connector-37837-autopatrol-1028-chm-cronjob | 600 |
| 41178 | connector-41178-autopatrol-350-chm-cronjob | 504 |
| 41158 | _(no autopatrol container)_ | 0 |
| 45061 | _(no autopatrol container)_ | 0 |

Naming convention: `connector-{site_id}-autopatrol-{patrol_id}-chm-cronjob`. No production `autopatrol-server` container — only `autopatrol-server-dev` (6,809 logs, not scoped to these 5 sites). Zero ERROR logs across all `%autopatrol%` containers. Zero CNCTNFAIL matches across all 5 sites.

**Flags:** sites 41158, 45061 — verify whether autopatrol is configured for these sites or whether their cronjobs failed to provision.

## Connector Fleet

**Verdict:** Broadly elevated; investigate the top 3 outliers.

| Rank | Container | ERROR count (12h) |
|------|-----------|-------------------|
| 1 | connector-34144 | 4,865 |
| 2 | connector-40439 | 2,797 |
| 3 | create-detection-window | 2,650 |
| 4 | connector-36681 | 2,242 |
| 5 | connector-36679 | 1,740 |
| 6 | connector-12686 | 1,513 |
| 7 | connector-17328 | 1,508 |
| 8 | connector-17331 | 1,508 |
| 9 | connector-35025 | 1,428 |
| 10 | connector-23430 | 1,409 |
| 11 | connector-19527 | 1,407 |
| 12 | connector-36381 | 1,405 |
| 13 | connector-17379 | 1,400 |
| 14 | connector-31563 | 1,176 |
| 15 | connector-38919 | 1,138 |

All 15 over the 100-error flag. `create-detection-window` is a platform service (not a connector) and warrants separate triage. Suggested next step: `FACET message` drill on connector-34144 and create-detection-window.

## Alert Delivery

**Verdict:** One container actively erroring; four clean.

| Container | ERROR count (12h) |
|-----------|-------------------|
| queue-evalink-consumer | **192** |
| queue-eagle-eye-consumer | 0 |
| smtp-frame-receiver | 0 |
| cert-manager-webhook | 0 |
| clips-smtp-worker | 0 |

**Flag:** queue-evalink-consumer 192 errors (>20 threshold). Drill into message patterns to identify the failure mode.

## New Issues

**Verdict:** 85 issue records / 31 distinct, 81 CRITICAL — pod availability and EKS node CPU dominate.

- **Severity distribution:** CRITICAL 81 / HIGH 4 / MEDIUM 0 / LOW 0
- **Top entity by volume:** EKS node `ip-10-10-49-112` — high-CPU >85% for 5 min (15 firings — flapping)
- **Connector unavailable-pod alerts** across ~17 deployments: 12183, 14299, 19501, 19503, 19504, 20274, 705-fs-630, 11998, 12005, 8196, 19505, 20139-fs-344, template-14920/21, test-tati (1–3 records each)
- **Recurring platform log-alerts (3 records each):** AI Link Timeouts, AI Link Errors, Envera Camera Unavailable High, Invalid Token Spike, SMTP extension discard, Genesis failover
- **HIGH severity (4):** Clip pipeline imbalance (received vs analyzed) ×3; POST /analyze 499 errors ×1

Caveat: `NrAiIssue` counts events (open/update/close) — repeated firings inflate the 85 total.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol Q1: patrol log counts per site
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%'
SINCE 12 hours ago
FACET cases(
  WHERE container_name LIKE '%connector-41158%' AS '41158',
  WHERE container_name LIKE '%connector-41178%' AS '41178',
  WHERE container_name LIKE '%connector-40672%' AS '40672',
  WHERE container_name LIKE '%connector-45061%' AS '45061',
  WHERE container_name LIKE '%connector-37837%' AS '37837')

-- AutoPatrol Q2: total ERROR count
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago

-- AutoPatrol Q3: CNCTNFAIL per site
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago
FACET cases(
  WHERE container_name LIKE '%connector-41158%' AS '41158',
  WHERE container_name LIKE '%connector-41178%' AS '41178',
  WHERE container_name LIKE '%connector-40672%' AS '40672',
  WHERE container_name LIKE '%connector-45061%' AS '45061',
  WHERE container_name LIKE '%connector-37837%' AS '37837')

-- AutoPatrol Q4: connector-side autopatrol errors
FROM Log SELECT count(*)
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago
FACET container_name LIMIT 10

-- Fleet errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15

-- Alert delivery
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name LIMIT 10

-- NR Issues
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago
FROM NrAiIssue SELECT count(*) FACET title, priority SINCE 12 hours ago LIMIT 50
-- plus MCP list_recent_issues (account 3421145)
```

</details>

## End
