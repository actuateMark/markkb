---
title: "Overnight Health Check 2026-04-30"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
status: degraded
---

# Overnight Health Check 2026-04-30

## Summary

DEGRADED — connector fleet is hot (15+ containers >100 errors, ~47k errors in 12h), 47 NR issues opened (33 CRITICAL), [[evalink-components|Evalink]] alert delivery flagged (318 errors), and 5/5 checked autopatrol sites are not running patrols.

## Issues Found

- **Connector fleet HOT** — `connector-deploy` (11.7k errors: self-reboot retry storm against site 14170), `connector-11202` (11.1k: VMS proxy timeouts on a single relay), `connector-32460` (5.5k: VMS returning empty/non-JSON auth bodies). 15 containers above the 100-error gate.
- **[[evalink-components|Evalink]] alert delivery FLAGGED** — `queue-evalink-consumer` 318 errors. Dominant cause: `deviceId must be 32 characters` 400s from [[evalink-components|Evalink]] alarm API. Data-quality issue, not connectivity. Needs FACET on `site_id` to identify the bad source.
- **AutoPatrol not running on any of the 5 checked sites** — sites 41158 and 45061 have no autopatrol cronjob containers in the cluster (VCH-only). Sites 37837, 40672, 41178 have the cronjob alive but every poll returns "No patrols to run" (96/96 polls × 3 sites). Patrol scheduler has nothing dispatched for these sites in the 12h window.
- **47 NR Issues opened (33 CRITICAL / 14 HIGH)** — 23 high-CPU node alerts (5 nodes, `ip-10-10-14-9` worst), 12 clip-pipeline imbalance alerts (received >> analyzed for 10+ min), 6 Envera camera unavailability alerts, plus an autopatrol pod stuck NotReady on site 35831.
- **No CNCTNFAIL hits** on any of the 5 target autopatrol sites (the only CNCTNFAILs visible — 6 — were on site 46460).

## AutoPatrol

**Verdict: DEGRADED** — sites 41158/45061 have no autopatrol infra at all; sites 37837/40672/41178 have healthy cronjobs but receive zero scheduled work.

| Site | Autopatrol Container | Patrol Logs (12h) | CNCTNFAIL | Flag |
|------|---------------------|-------------------|-----------|------|
| 41158 | NONE (VCH only `vch-761`) | 0 | 0 | NO INFRA |
| 45061 | NONE (VCH only `vch-1058`) | 0 | 0 | NO INFRA |
| 37837 | `connector-37837-autopatrol-1028-chm-cronjob` | 96 ("No patrols to run") | 0 | QUEUE EMPTY |
| 40672 | `connector-40672-autopatrol-1027-chm-cronjob` | 96 ("No patrols to run") | 0 | QUEUE EMPTY |
| 41178 | `connector-41178-autopatrol-350-chm-cronjob` | 96 ("No patrols to run") | 0 | QUEUE EMPTY |

**Autopatrol-server:** 2,944 logs, **0 ERRORs**. 84 patrols completed in 12h (for other sites, e.g. 46460). 6 CNCTNFAIL events — all scoped to site 46460 cameras (ECRoof, ECOutdoorLocustCIA), none on the 5 checked sites.

**Connector-side autopatrol errors:** only `connector-46560-autopatrol-1066-chm-cronjob` had 1 error (timestamp-ocr-svc 15s read timeout — not a data pipeline failure).

**Caveat:** site IDs aren't embedded in autopatrol-server "Patrol ended" lines (only UUIDs), so per-site completion attribution requires correlating against the autopatrol API. The 0-patrol finding for the 3 cronjob sites is read from the cronjob containers themselves, which is authoritative.

**Action:** check whether 41158/45061 are expected to have autopatrol provisioned (config drift?); for 37837/40672/41178 check whether patrol schedules are disabled/expired in the autopatrol-server backend.

## Connector Fleet

**Verdict: HOT** — all 15 containers in the top-15 FACET exceed the 100-error gate (~47k errors total in 12h).

| Container | Errors (12h) |
|---|---|
| connector-deploy | 11,693 |
| connector-11202 | 11,117 |
| connector-32460 | 5,535 |
| connector-9987 | 2,328 |
| connector-36681 | 2,195 |
| connector-16527 | 1,714 |
| connector-36679 | 1,691 |
| connector-12686 | 1,513 |
| connector-17328 | 1,508 |
| connector-17331 | 1,507 |
| connector-35025 | 1,434 |
| connector-11478 | 1,400 |
| connector-10729 | 1,397 |
| bandit-systems-canyon-view-capital-5401 | 1,297 |
| connector-32926 | 1,242 |

**Top-3 error patterns:**

- **connector-deploy (11.7k):** rapid-fire self-reboot patch failures targeting site 14170 — `restart has already been triggered within the past second`. Tight retry storm hitting the patch API rate limit. Secondary noise: VPA already-exists patches.
- **connector-11202 (11.1k):** uniform `HTTPSConnectionPool(...relay-us-dal-2-prod-dp.vmsproxy.com, port=443): Read timed out (10s)` on `dw_url_up`. Single relay host (`a5c3b8e8-…`) is unresponsive — site fully degraded on that endpoint.
- **connector-32460 (5.5k):** `dw_url_up` JSON-decode failures (`Expecting value: line 1 column 1`) — VMS returning empty/non-JSON 200 bodies. Uniform ~369 hits per camera, suggests the upstream VMS API is blank/down.

## Alert Delivery

**Verdict: ELEVATED** — `queue-evalink-consumer` flagged.

| Container | Errors (12h) | Flag |
|---|---|---|
| queue-evalink-consumer | 318 | FLAGGED (>20) |
| queue-eagle-eye-consumer | 1 | clean |
| smtp-frame-receiver | 0 | clean |
| cert-manager-webhook | 0 | clean |
| clips-smtp-worker | 0 | clean |

**queue-evalink-consumer (318):** dominant error is `Failed sending alert to evalink. Status code: 400 Bad Request` (159 hits) with response body `deviceId must be 32 characters` (159 hits — same root cause surfaced twice). [[evalink-components|Evalink]] endpoint is reachable; this is a data-quality issue at the source. Recommended follow-up: FACET errors on `site_id` to identify which sites are emitting malformed `deviceId`s.

## New Issues

**Verdict: MANY — 47 issues opened in 12h, all CRITICAL or HIGH.**

- **Severity:** 33 CRITICAL / 14 HIGH / 0 MEDIUM / 0 LOW.
- **Top categories:**
  1. **High CPU on EKS nodes (23):** five nodes affected, worst is `ip-10-10-14-9` (9 issues). CPU >85% sustained 5+ min on multiple us-west-2 compute nodes.
  2. **Clip pipeline imbalance (12):** received clip count exceeds analyzed by >50 for 10+ min — clip processing backlog.
  3. **Envera Camera Unavailable High (6):** log-based alert on >100 camera unavailability counts at Envera sites.
- **Other notable:** POST /analyze 499s (2, client timeouts), SMTP extension-filtered discards (3), stuck autopatrol pod `connector-35831-autopatrol-310-chm` NotReady 10+ min (2).

_Source: NRQL on `NrAiIssue` (account 3421145, SINCE 12 hours ago). `list_recent_issues` MCP tool exceeded response token limit._

## Raw NRQL

```sql
-- AutoPatrol Q1: containers in autopatrol family
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
FACET container_name LIMIT 20 SINCE 12 hours ago

-- AutoPatrol Q2: autopatrol-server errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND level = 'ERROR'
SINCE 12 hours ago

-- AutoPatrol Q3: CNCTNFAIL detection (autopatrol-server JSON summaries)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago

-- AutoPatrol Q4: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name LIMIT 10 SINCE 12 hours ago

-- Fleet: top error containers
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name LIMIT 15 SINCE 12 hours ago

-- Fleet drill-down: dominant error messages per flagged container
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = '<flagged>'
  AND level = 'ERROR'
FACET message LIMIT 5 SINCE 12 hours ago

-- Alert delivery: 5 canonical containers
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
  AND container_name IN (
    'queue-evalink-consumer', 'queue-eagle-eye-consumer',
    'smtp-frame-receiver', 'cert-manager-webhook', 'clips-smtp-worker'
  )
FACET container_name LIMIT 10 SINCE 12 hours ago

-- Alert delivery drill-down (queue-evalink-consumer)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'queue-evalink-consumer'
  AND level = 'ERROR'
FACET message LIMIT 5 SINCE 12 hours ago

-- NR Issues opened in window (NrAiIssue)
SELECT count(*) FROM NrAiIssue
WHERE createdAt >= (timestamp - 12*60*60*1000)
FACET priority SINCE 12 hours ago
```

## End
