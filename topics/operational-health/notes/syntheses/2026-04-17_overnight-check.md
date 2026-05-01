---
title: "Overnight Health Check 2026-04-17"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
status: warn
incoming:
  - topics/operational-health/notes/syntheses/2026-04-17_overnight-check-followup.md
incoming_updated: 2026-05-01
---

# Overnight Health Check 2026-04-17

## Summary

Platform degraded: 15+ connectors >100 errors/12h, [[evalink-components|Evalink]] alert delivery dropping (HTTP 400s), 21 open NR issues CRITICAL-heavy, and AutoPatrol skill failed to execute.

## Issues Found

- **AutoPatrol skill failed to execute** — returned `Execute skill: autopatrol-overnight-check` error with no output. Needs manual check.
- **connector-deploy stuck in restart loop** against site 14170 (~11k errors from rate-limited self-reboot messages).
- **connector-11202 VMS relay outage** — 6,970 HTTP read timeouts against `relay-us-dal-1-prod-dp.vmsproxy.com`, affecting all ~20 cameras at the site uniformly.
- **14 other site connectors** (31951, 34920, 29016, 32220, 38658, 34235, 21183, 34162, 28457, 16135, 32249, 40060, 27450, 11202) all exceed the 100-error threshold.
- **queue-evalink-consumer**: 290 errors — [[evalink-components|Evalink]] alarm API returning HTTP 400 Bad Request; alerts are silently dropping. Secondary `deviceId must be 32 characters` suggests malformed payload config.
- **queue-eagle-eye-consumer**: 24 errors — mostly 503s from `api.c013.eagleeyenetworks.com` (site 36273, upstream flap).
- **Container naming drift**: `queue_immix_consumer`, `queue_consumer`, `webhook_listener` (underscore names from the daily check spec) return zero rows across 7 days. Either renamed or not deployed. Spec needs updating.
- **21 NR issues opened** in 12h, 88% CRITICAL. Notable: 7 distinct connector deployments fired "Deployment unavailable pods", correlating with High CPU alerts on two EKS nodes (`ip-10-10-22-72`, `ip-10-10-22-132`) — likely node pressure cascade.
- **SMTP files discarded** (smtp-frame-receiver) — CRITICAL, 12 occurrences.
- **Genesis unmapped failover server** — 3 CRITICAL occurrences.

## AutoPatrol

Skill invocation failed with error: `Execute skill: autopatrol-overnight-check`. No report was produced. Root cause unknown — possibly a skill-runner issue or missing dependency. **Action**: run `/autopatrol-overnight-check prod` manually to confirm and, if a skill bug, fix per the Skill Post-Run Review rule.

## Connector Fleet

**NRQL:**
```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15
```

All 15 containers in the top-15 exceed 100 errors. Every result flagged.

| Container | Errors | Notes |
|---|---|---|
| connector-deploy | 11,372 | Restart loop on site 14170; VPA idempotency warnings |
| connector-11202 | 6,970 | VMS relay read timeouts, all cameras at site |
| connector-31951 | 6,240 | |
| connector-34920 | 5,420 | |
| connector-29016 | 4,270 | |
| connector-32220 | 3,746 | |
| connector-38658 | 2,946 | |
| connector-34235 | 2,565 | |
| connector-21183 | 2,316 | |
| connector-34162 | 2,257 | |
| connector-28457 | 2,160 | |
| connector-16135 | 2,145 | |
| connector-32249 | 2,143 | |
| connector-40060 | 1,876 | |
| connector-27450 | 1,785 | |

**Standout investigations:**
- `connector-deploy` (11,372): ~11k are rate-limited self-reboot messages targeting site 14170 — stuck remediation loop, not data-loss. Plus VPA "already exists, patching" idempotency warnings across ~12 site VPAs.
- `connector-11202` (6,970): 100% are `HTTPSConnectionPool read timed out (read timeout=10)` against `relay-us-dal-1-prod-dp.vmsproxy.com` while fetching camera auth strings. Uniform across all site cameras → sustained VMS relay outage, not a connector bug. **Follow-up suggested**: check whether connector-31951, 34920 and other top sites share the same relay (would widen blast radius).

## Alert Delivery

**Container-name drift note:** original spec (`queue_immix_consumer`, `queue_consumer`, `webhook_listener`) returned zero rows across 7 days. Scan was widened with `LIKE '%queue%'` / `'%webhook%'` / `'%smtp%'` to find active containers.

| Container | Errors | Status |
|---|---|---|
| smtp-frame-receiver | 0 | OK |
| queue-evalink-consumer | 290 | **NEEDS ATTENTION** |
| queue-eagle-eye-consumer | 24 | **NEEDS ATTENTION** |
| cert-manager-webhook | 0 | OK |
| clips-smtp-worker | 0 | OK |

**queue-evalink-consumer (290)**: 145 hits of `Failed sending alert to evalink. Status code: 400 Bad Request` against `/api/alarm-service/alarms`; 3 hits of `deviceId must be 32 characters`. All HTTP 400s — data/config issue, not an [[evalink-components|Evalink]] outage. Alerts silently dropping.

**queue-eagle-eye-consumer (24)**: 14 hits of `Failed to retrieve EEN account info: 503 Service Unavailable` against `api.c013.eagleeyenetworks.com` (site 36273); one 400 on event send (site 38047); one read timeout. Intermittent upstream flap.

## New Issues

**Account:** 3421145 (Actuate Connector/Platform)

| Metric | Value |
|---|---|
| Total distinct issues | 21 |
| CRITICAL event-rows | 45 |
| HIGH event-rows | 6 |
| WARNING / LOW | 0 |

**Top 3 by volume/entity impact:**

| # | Title | Severity | Status |
|---|---|---|---|
| 1 | SMTP files with an extension discarded (smtp-frame-receiver) | CRITICAL | Open, 12 occurrences |
| 2 | Envera Camera Unavailable High (Log threshold > 100) | CRITICAL | Open, 6 occurrences |
| 3 | Clip pipeline imbalance — received vs analyzed (clips-prod) | HIGH | Open, 6 occurrences |

**Notable patterns:**
- 7 distinct connector deployments fired "Deployment unavailable pods" (20139-fs-344, 41190, 19501, 12183, 14299, 19503/19504, 20274, 705-fs-251). Same condition, rolling disruption.
- Two EKS nodes (`ip-10-10-22-72`, `ip-10-10-22-132`) fired High CPU alerts — likely explains the unavailable-pod cascade.
- 3 CRITICAL Genesis "unmapped failover server" alerts — verify Genesis site config.

**Caveat:** open/closed status inferred from `list_recent_issues` (NrAiIssue `state` returned null in NRQL); 12h filter applied via `timestamp`.

## Raw NRQL

<details>

```sql
-- Connector fleet error counts
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15

-- Top messages for connector-deploy
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND container_name = 'connector-deploy' AND level = 'ERROR'
SINCE 12 hours ago FACET message LIMIT 10

-- Top messages for connector-11202
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND container_name = 'connector-11202' AND level = 'ERROR'
SINCE 12 hours ago FACET message LIMIT 10

-- Alert delivery error counts (widened after exact names returned zero rows)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND (container_name LIKE '%queue%' OR container_name LIKE '%webhook%' OR container_name LIKE '%smtp%')
  AND level = 'ERROR'
SINCE 12 hours ago FACET container_name LIMIT 20

-- Per-container top messages (evalink, eagle-eye)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND container_name = '<container>' AND level = 'ERROR'
SINCE 12 hours ago FACET message LIMIT 5

-- NR Issues opened last 12h (via list_recent_issues MCP + NrAiIssue filter by timestamp)
```

</details>

## End
