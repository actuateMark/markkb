---
title: "Overnight Health Check 2026-06-18"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, autopatrol, connector, alerts]
created: 2026-06-18
updated: 2026-06-18
author: kb-bot
status: warn
---

# Overnight Health Check 2026-06-18

## Summary

Autopatrol pipeline is broadly healthy (143 completions/12h, 0 server errors), but two target sites show no patrol activity and the alert/issue layer is noisy — 19 CRITICAL NR issues opened, 8+ connector deployments went unavailable, and `queue-evalink-consumer` logged 276 errors.

## Issues Found

- **NR Issues — 19 CRITICAL + 3 HIGH opened in 12h.** Dominant class: "Deployment has unavailable pods" across 8+ connectors (11998, 12005, 12183, 14299, 19501, 19504, 37781, 44300-fs-1643). Also "Envera Camera Unavailable High", "AI Link Timeouts", "POST /analyze 499 errors", "YOLO inference error spike".
- **Alert delivery — `queue-evalink-consumer` at 276 errors** (threshold >20). All other alert-path containers (queue-eagle-eye-consumer, smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker) clean at 0.
- **AutoPatrol — site 41158: 0 patrols in 12h.** No autopatrol cronjob container exists (only a `vch` CHM container) — likely not enrolled in autopatrol scheduling; verify intent.
- **AutoPatrol — site 40672: 0 autopatrol-server completions despite an active cronjob** (`connector-40672-autopatrol-1027-chm-cronjob`, 2,856 log lines). Cronjob may be running patrol logic without forwarding results to autopatrol-server, or SQS messages aren't being consumed. Warrants investigation.
- **Connector fleet — all top-15 containers exceed 100 errors/12h** (1,414–6,781). `connector-11202` is the standout at 6,781 (~2× next highest). This is elevated; see note in Connector Fleet section.

## AutoPatrol

NR-only assessment (kubectl/kubefwd MCP unavailable in headless session; per-skill fallback to NR queries).

**Fleet-wide:** 143 `PATROL COMPLETED` events in 12h at a steady ~11–14/hour cadence. **0 errors** on `autopatrol-server`.

**Per-site patrol counts (target sites):**

| Site ID | Patrol log hits (12h) | Autopatrol cronjob present? | Notes |
|---|---|---|---|
| 41158 | 0 | No (vch CHM only) | **FLAG** — not enrolled in autopatrol? |
| 41178 | 2 | Yes (350-chm-cronjob) | Active, low hit count |
| 40672 | 0 | Yes (1027-chm-cronjob) | **FLAG** — cronjob active but no server completions |
| 45061 | 1 | No (vch CHM only) | Occasional hit; not autopatrol-scheduled |
| 37837 | 1 | Yes (1028-chm-cronjob) | Active, low hit count |

**CNCTNFAIL per site:** 45061 = 1; all other target sites = 0. None exceed the >5 threshold.

**Connector-side autopatrol errors:** None for target sites. Non-target offenders: connector-46767-autopatrol-1102 (19), connector-37255-autopatrol-1127 (2), connector-47738-autopatrol-1136 (1).

**Flags raised:** 41158 (0 patrols, no cronjob), 40672 (0 completions despite active cronjob). No autopatrol-server errors; CNCTNFAILs below threshold.

**Methodology caveat:** per-site FACET-by-ID is unreliable for autopatrol-server because site IDs appear only inside multi-kilobyte `RESPONSE DATA` JSON blobs, which NR `LIKE` matches inconsistently. A structured short log line (e.g. `patrol_complete site_id=NNNNN` at INFO) would give reliable per-site counts.

## Connector Fleet

ERROR counts, `cluster_name='Connector-EKS'`, SINCE 12h, top 15:

| container_name | error count |
|---|---|
| connector-11202 | 6,781 |
| connector-37601 | 3,445 |
| connector-41028 | 2,644 |
| connector-47464 | 2,419 |
| connector-31563 | 2,247 |
| connector-43276 | 1,884 |
| connector-28919 | 1,652 |
| connector-35025 | 1,627 |
| connector-47778 | 1,589 |
| connector-12686 | 1,511 |
| connector-17331 | 1,509 |
| connector-17328 | 1,508 |
| sirix-volkswagen-boisbriand-1718 | 1,414 |
| connector-23430 | 1,414 |
| connector-17379 | 1,414 |

All 15 exceed the 100-error flag threshold. `connector-11202` (6,781) is the clear outlier at ~2× the next tier; 37601 and 41028 form a second tier; the rest cluster at 1,400–2,200. Recommend a `TIMESERIES` + raw-message sample on `connector-11202` to classify burst-vs-sustained — deferred (headless, read-only triage).

## Alert Delivery

ERROR counts by canonical container name, SINCE 12h:

| Container | ERROR count | Flag |
|---|---|---|
| queue-evalink-consumer | 276 | **FLAGGED (>20)** |
| queue-eagle-eye-consumer | 0 | — |
| smtp-frame-receiver | 0 | — |
| cert-manager-webhook | 0 | — |
| clips-smtp-worker | 0 | — |

One flag: `queue-evalink-consumer` at 276 errors. Suggested drill-down: `FACET message LIMIT 10` to surface top error classes. Zero-row containers may be genuinely clean or not actively logging in-window — worth a `FACET level` liveness check on eagle-eye/smtp-frame if uptime is in doubt.

## New Issues

**22 issues opened in 12h** (plus 22 activations, 21 closes — high churn, most cycling open/close).

**Severity:** CRITICAL 19, HIGH 3, MEDIUM 0, LOW 0.

**Top 3 by volume:**
1. **Deployment has unavailable pods** (CRITICAL) — dominant class; 8+ connectors each fired: connector-11998, 12005, 12183, 14299, 19501, 19504, 37781, 44300-fs-1643.
2. **Envera Camera Unavailable High** (CRITICAL) — log threshold breach (>100 occurrences); persistent Envera-integration camera connectivity problem.
3. **POST /analyze 499 errors** (HIGH) — client-disconnect errors on inference API; likely upstream timeout/load.

Notable others: "AI Link Timeouts" (CRITICAL), "YOLO inference error spike" (HIGH), "SMTP files with extension discarded" (CRITICAL), "High CPU" on EKS nodes ip-10-10-22-212 and ip-10-10-22-97.

## Raw NRQL

<details>
<summary>Queries used (account 3421145, SINCE 12 hours ago)</summary>

```sql
-- AutoPatrol: per-site patrol log hits
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
  AND message LIKE '%patrol%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10;

-- AutoPatrol: fleet-wide completions
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
  AND message LIKE '%PATROL COMPLETED%' SINCE 12 hours ago;

-- AutoPatrol: server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
  AND level='ERROR' SINCE 12 hours ago;

-- AutoPatrol: CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago LIMIT 10;

-- AutoPatrol: connector-side errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%'
  AND level='ERROR' FACET container_name SINCE 12 hours ago LIMIT 20;

-- Connector fleet: error counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15;

-- Alert delivery: error counts by canonical container
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN (
    'queue-evalink-consumer','queue-eagle-eye-consumer',
    'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker'
  )
FACET container_name SINCE 12 hours ago;

-- NR Issues: opened count + severity
FROM NrAiIssue SELECT count(*) FACET priority WHERE event='create' SINCE 12 hours ago LIMIT 10;
FROM NrAiIssue SELECT count(*) FACET event SINCE 12 hours ago LIMIT 5;
FROM NrAiIssue SELECT count(*) WHERE event='create' OR event='activate'
  FACET title, priority SINCE 12 hours ago LIMIT 10;
```
</details>

## End
