---
title: "Overnight Health Check 2026-05-06"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-07
---

# Overnight Health Check 2026-05-06

## Summary

Degraded — five tracked autopatrol sites have **no log presence whatsoever** in 12h, connector fleet logged 71,944 ERRORs (top: connector-10981 dw_url_up JSON parse failures), queue-evalink-consumer is flooding 270 HTTP 400s on a `deviceId must be 32 characters` validation error, and 18 NR Issues opened (13 CRITICAL) dominated by repeating High CPU events on a small set of EC2 nodes.

## Issues Found

- **AutoPatrol — all 5 target sites silent.** Sites 41158, 41178, 40672, 45061, 37837 each have 0 patrols and 0 log lines anywhere in Connector-EKS over 12h. autopatrol-server itself is clean (0 ERROR, 48 patrols completed) but only against test siteId 10026. Suggests the connectors for these 5 sites are not running / not deployed / inactive >12h. Investigate next.
- **connector-10981 (17,839 ERRORs)** — `dw_url_up` "Expecting value: line 1 column 1 (char 0)" — JSON parse on empty VMS auth response, single-site high volume.
- **connector-11202 (10,512 ERRORs)** — `dw_url_up` HTTPS read timeouts against `relay-us-dal-{1,2}-prod-dp.vmsproxy.com`. Likely upstream Dallas relay degradation.
- **connector-deploy (11,827 ERRORs)** — repeating "VPA already exists, patching" — deploy-loop noise, not customer-impacting, but should be cleaned up.
- **queue-evalink-consumer (270 ERRORs)** — every call rejected by [[evalink-components|Evalink]] `/api/alarm-service/alarms` with `deviceId must be 32 characters`. Data-validation regression upstream of the consumer; needs FACET by site_id to localize.
- **High CPU cluster pressure** — ip-10-10-5-88 fired 4×; ip-10-10-22-69, ip-10-10-22-174, ip-10-10-5-29 also tripped the >85%/5m condition.
- **connector-28378 FPS 3 Low** — query <1.5 for 15m, frame-throughput degradation.
- **SMTP discarded extensions ≥1/5m** — smtp-frame-receiver receiving malformed files.

## AutoPatrol

autopatrol-server clean: 0 ERRORs in 12h, 48 successful `Processing patrol → Finished` cycles — but **all** for siteId 10026 (internal test site). The five tracked production sites (41158, 41178, 40672, 45061, 37837) each return zero patrol log lines, zero CNCTNFAIL events, and zero presence in any container in cluster_name='Connector-EKS' over 12h. Connector-side autopatrol container scan: empty (no autopatrol-* containers logged ERROR). CNCTNFAIL activity exists for unrelated containers (autopatrol-server-dev: 206; connector-35832-autopatrol-260-chm-cronjob: 96; connector-35830-autopatrol-309-chm-cronjob: 96; smaller counts on 35830, 38580, 40799, 40510) but none for the 5 tracked sites. Caveat: this NR-only run cannot distinguish "connector pod is down" from "connector pod is up but not patrolling". Recommended follow-up next session (with kubectl/kubefwd available): verify pod presence for these 5 sites, and widen NR query to 7d to find last-seen timestamps.

## Connector Fleet

71,944 ERRORs across the top 15 containers in 12h; all 15 exceeded the 100-error threshold.

| Container | Errors | Notes |
|---|---:|---|
| connector-10981 | 17,839 | dw_url_up JSON parse on empty VMS auth response |
| connector-deploy | 11,827 | "VPA already exists, patching" — deploy-loop noise, not customer-impact |
| connector-11202 | 10,512 | VMS relay timeouts (relay-us-dal-{1,2}-prod-dp.vmsproxy.com) |
| connector-10770 | 6,285 | (not sampled) |
| connector-34144 | 5,082 | (not sampled) |
| connector-34619 | 4,531 | (not sampled) |
| connector-40439 | 2,499 | (not sampled) |
| connector-36681 | 2,223 | (not sampled) |
| connector-41028 | 2,010 | (not sampled) |
| connector-36679 | 1,764 | (not sampled) |
| connector-12686 | 1,506 | (not sampled) |
| connector-17328 | 1,503 | (not sampled) |
| connector-17331 | 1,495 | (not sampled) |
| connector-35025 | 1,458 | (not sampled) |
| connector-36381 | 1,410 | (not sampled) |

Top three characterized; remainder unsampled but all individually >100 — long tail warrants a triage pass.

## Alert Delivery

| Container | Errors | Flagged |
|---|---:|---|
| queue-evalink-consumer | 270 | **YES** (>20) |
| queue-eagle-eye-consumer | 3 | no |
| smtp-frame-receiver | 0 | no |
| cert-manager-webhook | 0 | no |
| clips-smtp-worker | 0 | no |

**queue-evalink-consumer**: every error is HTTP 400 from [[evalink-components|Evalink]] `/api/alarm-service/alarms` with payload `"deviceId must be 32 characters"`. Single repeating pattern across all sampled rows — consumer is sending alerts with a malformed/truncated deviceId. Upstream is rejecting 100% of those calls. Not connectivity or auth — pure data-validation regression. Next-step query: FACET by site_id / tenant tag to localize the bad device population.

## New Issues

18 NR Issues opened in 12h. Severity: **13 CRITICAL, 5 HIGH**.

- **High CPU on ip-10-10-5-88** (CRITICAL, ×4 separate issue creates) — node cycled in/out of >85%/5m threshold repeatedly.
- **High CPU on ip-10-10-22-69, ip-10-10-22-174, ip-10-10-5-29** (CRITICAL) — broader cluster-wide CPU pressure event, not isolated to one node.
- **connector-28378 "FPS 3 Low"** (CRITICAL) — query result <1.5 for 15m; frame-throughput degradation on a single connector.
- **smtp-frame-receiver "SMTP files with an extension discarded ≥1/5m"** — malformed file extensions reaching the SMTP frame ingest path.

## Raw NRQL

<details>
<summary>Queries used</summary>

**AutoPatrol — patrol counts per site**
```sql
FROM Log SELECT count(*) AS total,
  filter(count(*), WHERE message LIKE '%site_id: 41158%') AS site_41158,
  filter(count(*), WHERE message LIKE '%site_id: 41178%') AS site_41178,
  filter(count(*), WHERE message LIKE '%site_id: 40672%') AS site_40672,
  filter(count(*), WHERE message LIKE '%site_id: 45061%') AS site_45061,
  filter(count(*), WHERE message LIKE '%site_id: 37837%') AS site_37837
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
  AND (message LIKE '%patrol%' OR message LIKE '%Patrol%')
SINCE 12 hours ago
```

**AutoPatrol — server ERROR count**
```sql
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server' AND level='ERROR' SINCE 12 hours ago
```

**AutoPatrol — CNCTNFAIL per site**
```sql
FROM Log SELECT
  filter(count(*), WHERE message LIKE '%site_id: 41158%') AS site_41158,
  filter(count(*), WHERE message LIKE '%site_id: 41178%') AS site_41178,
  filter(count(*), WHERE message LIKE '%site_id: 40672%') AS site_40672,
  filter(count(*), WHERE message LIKE '%site_id: 45061%') AS site_45061,
  filter(count(*), WHERE message LIKE '%site_id: 37837%') AS site_37837
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%' SINCE 12 hours ago
```

**AutoPatrol — connector-side autopatrol containers with ERROR**
```sql
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10
```

**Connector fleet — ERROR by container**
```sql
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15
```

**Alert delivery — ERROR by container (canonical hyphenated names)**
```sql
FROM Log SELECT count(*) WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago LIMIT 10
```

**New Issues — opened in last 12h**
```sql
FROM NrAiIssue SELECT count(*) WHERE event = 'create' SINCE 12 hours ago
```
(plus `list_recent_issues` for severity + entity breakdown)

</details>

## End
