---
title: "Overnight Health Check 2026-05-12"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
status: red
incoming:
  - No backlinks found.
incoming_updated: 2026-05-13
---

# Overnight Health Check 2026-05-12

## Summary

RED — two autopatrol sites silent (41158, 45061), fleet-wide vmsproxy relay timeouts across 4 regions, connector-deploy reboot loop on connector-14170, and 44 NR issues opened (39 CRITICAL).

## Issues Found

- **RED — AutoPatrol sites 41158 and 45061**: zero patrol logs in 12h; no matching container present. Likely deprovisioned or stalled — verify with 7-day lookback.
- **RED — Fleet vmsproxy relay timeouts**: connectors 11202, 34144, 37811, 40439 (and likely the next ~10) all logging sustained 10s HTTPS read-timeouts to regional relays (Dallas, NYC-1, NYC-3, Seattle). Cross-region pattern suggests broad vmsproxy degradation.
- **RED — connector-deploy reboot loop**: 11,520 errors, dominated by self-throttled reboot attempts on connector-14170 ("restart already triggered within the past second").
- **YELLOW — queue-evalink-consumer**: 278 errors, all from one site posting a malformed `deviceId` (must be 32 chars) → HTTP 400 from [[evalink-components|Evalink]] alarm-service. One-bug-many-errors; needs site config fix.
- **YELLOW — NR Issues**: 44 opened (39 CRITICAL). Dominant themes: "Deployment has unavailable pods" across many connectors; "SMTP files with an extension discarded" (18 events); clip pipeline imbalance (received >> analyzed, 9 events); 5 EC2 nodes High CPU.
- **OK** — autopatrol-server errors (0), CNCTNFAIL on the 5 sites of interest (0), smtp-frame-receiver / cert-manager-webhook / clips-smtp-worker / queue-eagle-eye-consumer (all ≤2 errors).

## AutoPatrol

Window: SINCE 12 hours ago, cluster Connector-EKS, account 3421145.

**Per-site patrol activity** (container-name match — `autopatrol-server` logs in this window are botocore DEBUG only, so `message LIKE '%<site>%'` against the server returns zero; container-name matching against the per-site cronjob containers is the reliable signal):

| Site  | Log count (12h) | Status |
|-------|-----------------|--------|
| 40672 | 840 | OK |
| 37837 | 600 | OK |
| 41178 | 504 | OK |
| 41158 | 0   | **RED** |
| 45061 | 0   | **RED** |

Sites 41158 and 45061 produced zero `%autopatrol%` container logs and do not appear anywhere in the FACET — containers are absent, not merely silent. Recommended follow-up: 7-day lookback to determine deprovisioned vs. stalled.

**CNCTNFAIL on sites of interest**: 0 across all five. (Cluster-wide, `autopatrol-server-dev` shows 206 CNCTNFAILs — dev container noise, not production.)

**autopatrol-server ERRORs**: 0.

**Connector-side autopatrol ERRORs**: 0 across all `%autopatrol%` containers for the five sites.

## Connector Fleet

ERROR FACET by container, top 15, SINCE 12 hours ago — **all 15 exceeded 100 errors**:

| container_name | errors |
|---|---|
| connector-deploy | 11,520 |
| connector-11202 | 9,063 |
| connector-34144 | 7,781 |
| connector-37811 | 7,475 |
| connector-40439 | 2,864 |
| connector-36681 | 1,904 |
| connector-21884 | 1,846 |
| connector-36679 | 1,710 |
| connector-12686 | 1,511 |
| connector-17331 | 1,507 |
| connector-17328 | 1,503 |
| connector-35025 | 1,452 |
| connector-23430 | 1,412 |
| connector-17379 | 1,410 |
| connector-19527 | 1,407 |

**Two distinct failure modes:**

1. **connector-deploy reboot loop** — controller is rate-limiting itself trying to restart connector-14170 ("restart has already been triggered within the past second"). Secondary noise: VPA objects already-existing patches on connector-38013 and connector-45283.
2. **vmsproxy relay timeouts** — connectors 11202 / 34144 / 37811 / 40439 all logging `dw_url_up` HTTPS read-timeouts (10s) against four distinct regional relays:
   - 11202 → `relay-us-dal-2-prod-dp.vmsproxy.com`
   - 34144 → `relay-us-nyc-1-prod-dp.vmsproxy.com`
   - 37811 → `relay-us-nyc-3-prod-dp.vmsproxy.com`
   - 40439 → `relay-us-sea-1-prod-dp.vmsproxy.com`

   Multiple cameras per site hitting the same host → relay-level degradation, not per-camera. The remaining ~10 high-count connectors (1.4k–1.9k errors) were not drilled but likely share this pattern.

## Alert Delivery

| Container | errors | Flag |
|---|---|---|
| queue-evalink-consumer | 278 | **FLAGGED** |
| queue-eagle-eye-consumer | 2 | OK |
| smtp-frame-receiver | 0 | OK |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

**queue-evalink-consumer (278)** — single recurring rejection from [[evalink-components|Evalink]] alarm-service: 139× `Status code: 400. Reason: Bad Request` with downstream body `"deviceId must be 32 characters"` at `/api/alarm-service/alarms`. One malformed `deviceId` on at least one site is producing all the noise; consumer is retrying. Fix is site-config-side; next query `FACET tags.site_id` to identify the offending site(s).

## New Issues

**Total: 44 issues opened** (39 CRITICAL, 5 HIGH, 0 MEDIUM, 0 LOW).

Top by volume / impact:

1. **Deployment has unavailable pods** (CRITICAL) — dominant alert across 10+ connector deployments (connector-12183, -14299, -19501, -19503, -19504, -20274, -705-fs-630, test-tati, others).
2. **SMTP files with an extension discarded** (CRITICAL, 18 events) — highest single-condition event count; sustained SMTP frame-receiver issue dropping files. (Interesting tension: smtp-frame-receiver container has 0 ERROR-level logs in 12h — this alert is log-pattern-driven and likely matching a non-ERROR level. Worth a follow-up.)
3. **Clip pipeline imbalance** (HIGH, 9 events) — received outpacing analyzed by >50 for 10+ minutes → processing backlog.

Notable active CRITICALs: `connector-41527 FPS 3 Low` (2 events); 5 EC2 nodes (`ip-10-10-35-239` + 4 others) High CPU >85% for 5+ min; `POST /analyze 499` client-disconnect errors (2–3 events); `Genesis unmapped failover server` (1 event).

Caveat: counts are unique issue IDs (lifecycle re-triggers excluded); `list_recent_issues` MCP exceeded token limit at 24h, NRQL was used.

## Raw NRQL

<details>
<summary>Queries</summary>

```sql
-- AutoPatrol: per-site patrol activity (container-name match — reliable signal)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND container_name LIKE '%autopatrol%'
FACET CASES (
  WHERE container_name LIKE '%41158%' AS '41158',
  WHERE container_name LIKE '%41178%' AS '41178',
  WHERE container_name LIKE '%40672%' AS '40672',
  WHERE container_name LIKE '%45061%' AS '45061',
  WHERE container_name LIKE '%37837%' AS '37837'
) SINCE 12 hours ago

-- AutoPatrol: server-side ERRORs
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND container_name = 'autopatrol-server' AND level = 'ERROR'
SINCE 12 hours ago

-- AutoPatrol: CNCTNFAIL per site (message match)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET CASES (
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago

-- AutoPatrol: connector-side ERRORs by container
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- Connector fleet: ERRORs by container
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- Alert delivery: canonical container ERRORs
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN ('queue-evalink-consumer', 'queue-eagle-eye-consumer',
                         'smtp-frame-receiver', 'cert-manager-webhook', 'clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10

-- Alert delivery: drill on flagged container
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name = 'queue-evalink-consumer'
FACET message SINCE 12 hours ago LIMIT 5

-- NR Issues: severity distribution + facet by title
SELECT uniqueCount(issueId) FROM NrAiIssue SINCE 12 hours ago FACET priority LIMIT 10
SELECT count(*) FROM NrAiIssue SINCE 12 hours ago FACET priority, title LIMIT 50
```

</details>

## End
