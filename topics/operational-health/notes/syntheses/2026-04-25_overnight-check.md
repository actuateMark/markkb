---
title: "Overnight Health Check 2026-04-25"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-04-25
updated: 2026-04-25
author: kb-bot
status: degraded
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Overnight Health Check 2026-04-25

## Summary

Degraded — 2 autopatrol sites (41158, 45061) had zero patrol activity in 12h; connector fleet shows broad elevated error volume led by `connector-deploy` (11.5k) and `create-detection-window` (6.0k); `queue-evalink-consumer` flagged at 124 errors; 28 NR issues opened, dominated by node-level High CPU criticals.

## Issues Found

- **AutoPatrol — sites 41158 and 45061 had zero patrol container logs in 12h.** Other three monitored sites (37837, 40672, 41178) ran consistently at 96 patrol entries each. No CNCTNFAIL on any site, no orchestrator errors.
- **Connector fleet — all 15 top containers exceed the 100-error threshold.** Worst: `connector-deploy` (11,544), `create-detection-window` (6,057), three connectors (`36681`, `10770`, `11202`) clustered ~3.7k–4.5k suggesting a shared upstream issue.
- **Alert delivery — `queue-evalink-consumer` at 124 errors** (>20 threshold). Other named alert containers clean (`queue-eagle-eye-consumer` 2; `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker` all 0).
- **NR Issues — 28 opened in 12h: 23 critical, 5 high.** Top cluster is multi-host EKS "High CPU" (>85% for 5 min); plus YOLO inference error spike and `POST /analyze` 499 spike.

## AutoPatrol

Container-name routing applies: site IDs appear in `container_name` (`connector-{site}-autopatrol-*-chm-cronjob`), not in message body. Active orchestrator is `autopatrol-server-dev` (the legacy `autopatrol-server` is stale, only 29 lines in 12h).

**Patrol counts per site (via container presence):**

| Site ID | Container Confirmed | Patrol Log Count |
|---------|---------------------|------------------|
| 37837   | connector-37837-autopatrol-1028-chm-cronjob | 96 |
| 40672   | connector-40672-autopatrol-1027-chm-cronjob | 96 |
| 41178   | connector-41178-autopatrol-350-chm-cronjob | 96 |
| 41158   | NOT FOUND in 12h window | **0 (FLAG)** |
| 45061   | NOT FOUND in 12h window | **0 (FLAG)** |

**Autopatrol-server-dev errors:** 0. **CNCTNFAIL counts (all 5 sites):** 0. **Connector-side autopatrol ERROR logs:** 0.

**Flags:**
- Sites 41158 and 45061 — no autopatrol container appearance over 12h. Cronjob may not have fired or pod failed to schedule. Needs cluster-side investigation (kubectl) — out of scope for this NR-only headless run.

## Connector Fleet

Top 15 containers by ERROR count, last 12h. **All 15 exceed the >100-error flag threshold.**

| Rank | container_name | Errors |
|------|----------------|--------|
| 1 | connector-deploy | **11,544** |
| 2 | create-detection-window | **6,057** |
| 3 | connector-36681 | 4,483 |
| 4 | connector-10770 | 4,159 |
| 5 | connector-11202 | 3,761 |
| 6 | connector-29016 | 2,717 |
| 7 | connector-45999 | 1,711 |
| 8 | connector-36679 | 1,704 |
| 9 | connector-11565 | 1,527 |
| 10 | connector-17331 | 1,508 |
| 11 | connector-12686 | 1,508 |
| 12 | connector-17328 | 1,507 |
| 13 | connector-35025 | 1,470 |
| 14 | sirix-volkswagen-boisbriand-1718 | 1,412 |
| 15 | bandit-systems-canyon-view-capital-5401 | 1,298 |

Notes:
- `connector-deploy` is the highest by ~2× the next worst — possibly a stuck/looping deploy job; warrants drill-down.
- `create-detection-window` is platform-level, not site-specific; elevated counts here are systemic (downstream dep or job-queue issue).
- `connector-36681` / `10770` / `11202` cluster at similar elevated counts (~3.7k–4.5k) — suggests a shared upstream issue (camera auth, network, or common config) rather than isolated failures.

## Alert Delivery

| Container | Errors | Flag |
|-----------|--------|------|
| queue-evalink-consumer | 124 | **>20 threshold** |
| queue-eagle-eye-consumer | 2 | normal |
| smtp-frame-receiver | 0 | — |
| cert-manager-webhook | 0 | expected (low-traffic by design) |
| clips-smtp-worker | 0 | — |

`queue-evalink-consumer` at 124 errors warrants follow-up — next step would be to FACET by message to identify dominant error pattern. `smtp-frame-receiver` zero rows is plausible under light overnight traffic but worth a quick info-level health-volume check to confirm the container is actually emitting.

## New Issues

**28 NR issues opened in 12h** — Critical: 23, High: 5, Medium: 0, Low: 0.

Top issue clusters:

1. **CRITICAL** — Multiple EKS nodes (ip-10-10-5-24, ip-10-10-22-86, ip-10-10-14-228, ip-10-10-14-179, and others) triggering "High CPU" alert repeatedly (CPU > 85% for 5 min). Accounts for the bulk of the 23 criticals — same condition re-firing across hosts.
2. **HIGH** — "YOLO inference error spike" — log-query threshold exceeded (>5.0).
3. **HIGH** — "POST /analyze 499 errors" — log-query threshold exceeded (>1.0); client-cancelled inference requests.

Caveat: NrAiIssue rows include re-fires, not just distinct opens. A `FACET title` aggregation would be useful next step to confirm whether the CPU alerts are truly multi-host vs. flaps on the same host.

## Raw NRQL

<details>
<summary>Queries used</summary>

```sql
-- AutoPatrol: patrol counts per site (site IDs live in container_name, not message)
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND message LIKE '%patrol%'
SINCE 12 hours ago
FACET cases(
  WHERE container_name LIKE '%41158%' AS '41158',
  WHERE container_name LIKE '%41178%' AS '41178',
  WHERE container_name LIKE '%40672%' AS '40672',
  WHERE container_name LIKE '%45061%' AS '45061',
  WHERE container_name LIKE '%37837%' AS '37837'
);

-- AutoPatrol: orchestrator errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server-dev' AND level='ERROR'
SINCE 12 hours ago;

-- AutoPatrol: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago
FACET cases(
  WHERE container_name LIKE '%41158%' AS '41158',
  WHERE container_name LIKE '%41178%' AS '41178',
  WHERE container_name LIKE '%40672%' AS '40672',
  WHERE container_name LIKE '%45061%' AS '45061',
  WHERE container_name LIKE '%37837%' AS '37837'
);

-- AutoPatrol: connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 10;

-- Connector fleet: top errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago
FACET container_name LIMIT 15;

-- Alert delivery: errors per canonical container
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
SINCE 12 hours ago FACET container_name;

-- NR Issues: severity + count
SELECT count(*) FROM NrAiIssue SINCE 12 hours ago FACET priority LIMIT 10;
SELECT count(*) FROM NrAiIssue SINCE 12 hours ago;
SELECT latest(title), latest(priority), latest(sources) FROM NrAiIssue SINCE 12 hours ago FACET issueId LIMIT 5;
SELECT latest(title), latest(priority) FROM NrAiIssue WHERE priority = 'HIGH' SINCE 12 hours ago FACET issueId LIMIT 5;
```

</details>

## End
