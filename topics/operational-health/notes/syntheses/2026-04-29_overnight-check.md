---
title: "Overnight Health Check 2026-04-29"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
status: red
incoming:
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/runbooks/notes/concepts/2026-04-29_iam-access-denied-missing-resource-arn.md
incoming_updated: 2026-05-01
---

# Overnight Health Check 2026-04-29

## Summary

Multiple critical issues overnight: AutoPatrol scheduling appears broken (0 successful patrols across all 5 tracked sites in 12h) compounded by a DynamoDB IAM regression, the connector fleet logged 124k errors dominated by VMS upstream failures on three sites, and a 56-issue CRITICAL burst in NR Issues suggests a cluster-wide pod-availability event.

## Issues Found

- **CRITICAL — AutoPatrol scheduling failure across all 5 tracked sites.** Sites 41158, 41178, 40672, 45061, 37837 each ran their cronjob multiple times in 12h; every run exhausted 3 retries and exited with "No patrols to run." Zero successful patrols anywhere on the tracked list. Connectivity is clean (no CNCTNFAILs), so this is a scheduling/queue issue on the autopatrol service, not a connector-side failure.
- **CRITICAL — DynamoDB AccessDeniedException (IAM regression).** `autopatrol-microservice-role` lacks `dynamodb:Query` on `MotionFrame/index/run_timestamp` (us-west-2). 29+ occurrences in 12h. Motion stats unavailable for every patrol that does run (e.g., siteId 10111).
- **HIGH — Cluster-wide pod-availability burst.** 56 CRITICAL "Deployment has unavailable pods" issues opened in a tight ~1-minute window across many connector deployments — symptomatic of a rolling restart, node disruption, or mass deploy event. Worth correlating with change events.
- **HIGH — connector-11202 (29,205 errors)** sustained read timeouts against a single VMS relay host (`*.relay-us-dal-1-prod-dp.vmsproxy.com`); upstream relay degraded.
- **HIGH — connector-10770 (10,428 errors)** persistent empty-body responses from upstream VMS (`Expecting value: line 1 column 1 (char 0)`) across ~18 cameras.
- **MEDIUM — connector-deploy (12,175 errors)** includes a connector-14170 self-reboot loop hitting the 1-second restart guard 69×.
- **MEDIUM — queue-evalink-consumer (412 errors)** rejecting alarm POSTs with `deviceId must be 32 characters` — a tenant-config issue, not infrastructure.
- **HIGH — Clip pipeline imbalance** (clips received vs analyzed > 50) firing 3× as HIGH issues — clips analyzer lagging ingestion.

## AutoPatrol

**Window:** 2026-04-29, ~00:00–12:00 UTC

**Patrol counts per tracked site:** All 5 sites zero. The five target sites run as dedicated cronjob containers (`connector-<siteId>-*-chm-cronjob`), not via the central `autopatrol-server` container. Every cronjob run logs the same 3-line pattern:

```
WARNING: No patrols found (attempt 1/3), retrying in 10 seconds...
WARNING: No patrols found (attempt 2/3), retrying in 10 seconds...
WARNING: No patrols to run after all attempts, exiting.
```

| Site | Cronjob log lines (12h) | Runs (approx) | Successful Patrols |
|------|-------------------------|---------------|--------------------|
| 41158 | 6 | 2 | 0 |
| 41178 | 36 | 12 | 0 |
| 40672 | 36 | 12 | 0 |
| 45061 | 6 | 2 | 0 |
| 37837 | 36 | 12 | 0 |

**Autopatrol-server errors:** 100 ERROR-class log lines (query-capped). Root cause: `DynamoDBException: AccessDeniedException — autopatrol-microservice-role not authorized for dynamodb:Query on MotionFrame/index/run_timestamp (us-west-2)`. 29 occurrences in 12h. Recurs on every patrol-analysis pass for siteId 10111 and others.

**CNCTNFAILs:** Zero on any tracked site. Cluster-wide CNCTNFAIL activity is concentrated on autopatrol-server-dev (96), connector-35832 (96), connector-38580 (24), and a handful of others — none of the 5 tracked sites.

**Connector-side autopatrol containers (top error producers):** autopatrol-server-dev (184), staging-connector-35270/35272-autopatrol (144 each), connector-35830-autopatrol (142), autopatrol-server prod (100), connector-35832-autopatrol (96). Tracked sites do not appear — their cronjobs exit before reaching the analysis stage where DynamoDB errors fire.

**Verdict:** Two simultaneous CRITICALs — scheduler not enqueuing patrols for the 5 tracked sites, and IAM denying DynamoDB Query on motion stats. The IAM regression should be the fastest fix; the scheduler issue needs investigation on the patrol-server side (why is the patrol queue empty?). Worth checking when these regressions started — both may be the same deploy or unrelated.

## Connector Fleet

**Total fleet ERROR count:** 124,066 in 12h. All 15 containers in the top facet exceeded 100 errors. Three flagged for deeper drill:

| Rank | container_name | Errors | Dominant Pattern |
|------|----------------|--------|------------------|
| 1 | connector-11202 | 29,205 | VMS proxy read timeouts (`*.relay-us-dal-1-prod-dp.vmsproxy.com`, 10s) — relay host degraded; ~500 hits per camera across 5+ cameras |
| 2 | connector-deploy | 12,175 | (a) connector-14170 self-reboot loop (69× rate-limited restarts); (b) idempotent "VPA already exists" patch noise |
| 3 | connector-10770 | 10,428 | Empty-body JSON parse failures from upstream VMS (`Expecting value: line 1 column 1 (char 0)`); ~18 cameras affected, ~579 errors each |
| 4 | connector-26864 | 3,930 | (not drilled) |
| 5 | connector-36681 | 2,320 | (not drilled) |

The 11202 / 10770 errors appear to be upstream VMS-side failures rather than connector bugs. The connector-14170 restart loop is suspicious — worth checking whether the restart guard is masking a real crash-loop on a child process.

## Alert Delivery

| Container | Errors | Status |
|-----------|--------|--------|
| queue-evalink-consumer | 412 | FLAGGED |
| queue-eagle-eye-consumer | 1 | OK |
| smtp-frame-receiver | 0 | OK |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

**queue-evalink-consumer** — All 412 errors are the same root cause: [[evalink-components|Evalink]] API rejecting alarm POSTs to `/api/alarm-service/alarms` with HTTP 400 / `deviceId must be 32 characters`. 206 errors are the collapsed message form ("Failed sending alert to evalink. Status code: 400"); the other 206 are the same failure with the raw [[evalink-components|Evalink]] response body. Tenant-config issue (specific sites are sending malformed `deviceId`s), not infrastructure. A `FACET site_id` follow-up would scope the fix.

The other four canonical alert-delivery containers are clean. (Zero rows on `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker` — either genuinely quiet or the container names should be re-verified at next opportunity.)

## New Issues

**59 issues opened in last 12h — 56 CRITICAL, 3 HIGH.**

The 56 CRITICAL issues are nearly all "Deployment has unavailable pods" firing simultaneously across many connector deployments (connector-19504, connector-40480, connector-41364, connector-44565-fs-1357, connector-39097, globalguardian-crv-7139-hag-bmw-south-austin-tx-bma-6716, and many more). The burst landed in a ~1-minute window — strongly suggests a single cluster-wide disruption (rolling restart, node taint, mass deploy) rather than 56 independent connector failures.

The 3 HIGH issues are all the same alert: clips pipeline imbalance ("received vs analyzed" > 50) firing in close succession ~3.5h ago. Clips analyzer is lagging.

**Top 3 by entity:**
1. connector-19504 — Deployment has unavailable pods — CRITICAL
2. connector-40480 — Deployment has unavailable pods — CRITICAL
3. clips/log pipeline — Clip pipeline imbalance (received vs analyzed > 50) — HIGH

**Recommended follow-up:** correlate the CRITICAL burst's timestamp against `list_change_events` to identify whether a deploy or node event triggered the mass restart. A `FROM NrAiIssue SELECT count(*) TIMESERIES 30 minutes SINCE 12 hours ago` confirms whether this was a one-shot spike or recurring pattern.

## Raw NRQL

<details>
<summary>Queries used (click to expand)</summary>

```sql
-- AUTOPATROL --

-- Patrol counts per tracked site (zero results — siteIds not in autopatrol-server logs)
SELECT filter(count(*), WHERE message LIKE '%41158%') AS '41158',
  filter(count(*), WHERE message LIKE '%41178%') AS '41178',
  filter(count(*), WHERE message LIKE '%40672%') AS '40672',
  filter(count(*), WHERE message LIKE '%45061%') AS '45061',
  filter(count(*), WHERE message LIKE '%37837%') AS '37837'
FROM Log WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
  AND (message LIKE '%patrol%' OR message LIKE '%Patrol%') SINCE 12 hours ago

-- Patrol status totals (autopatrol-server, all siteIds)
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server' AND message LIKE '%patrolStatus%'
  FACET cases(WHERE message LIKE '%"patrolStatus":"Finished"%' AS 'Finished',
              WHERE message LIKE '%"patrolStatus":"Failed"%' AS 'Failed')
SINCE 12 hours ago

-- Cronjob activity per tracked site
SELECT filter(count(*), WHERE container_name LIKE 'connector-41158%') AS '41158',
  filter(count(*), WHERE container_name LIKE 'connector-41178%') AS '41178',
  filter(count(*), WHERE container_name LIKE 'connector-40672%') AS '40672',
  filter(count(*), WHERE container_name LIKE 'connector-45061%') AS '45061',
  filter(count(*), WHERE container_name LIKE 'connector-37837%') AS '37837'
FROM Log WHERE cluster_name='Connector-EKS'
  AND (container_name LIKE 'connector-41158%' OR container_name LIKE 'connector-41178%'
    OR container_name LIKE 'connector-40672%' OR container_name LIKE 'connector-45061%'
    OR container_name LIKE 'connector-37837%')
  AND message LIKE '%No patrols%' SINCE 12 hours ago

-- Autopatrol-server total ERROR
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server' AND message LIKE '%ERROR%' SINCE 12 hours ago

-- AccessDeniedException count
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server' AND message LIKE '%AccessDeniedException%'
SINCE 12 hours ago

-- CNCTNFAIL counts per tracked site
SELECT filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%41158%') AS '41158',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%41178%') AS '41178',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%40672%') AS '40672',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%45061%') AS '45061',
  filter(count(*), WHERE message LIKE '%CNCTNFAIL%' AND message LIKE '%37837%') AS '37837'
FROM Log WHERE cluster_name='Connector-EKS' SINCE 12 hours ago

-- CNCTNFAIL cluster-wide by container
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS'
  AND message LIKE '%CNCTNFAIL%'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector-side autopatrol errors by container
SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%' AND message LIKE '%ERROR%'
FACET container_name SINCE 12 hours ago LIMIT 10

-- CONNECTOR FLEET --

SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago

-- Per flagged container drilldown
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
AND container_name='<name>'
FACET message SINCE 12 hours ago LIMIT 5

-- ALERT DELIVERY --

SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name='queue-evalink-consumer'
FACET message SINCE 12 hours ago LIMIT 10

-- NR ISSUES --

-- (issued via list_recent_issues MCP tool; equivalent NRQL would be
--  FROM NrAiIssue SELECT * SINCE 12 hours ago WHERE accountIds IN (3421145))
```

</details>

## End
