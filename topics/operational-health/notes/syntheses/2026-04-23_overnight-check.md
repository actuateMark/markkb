---
title: "Overnight Health Check 2026-04-23"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, oom, nonetype, deferred-alert, cleanup-lambda, s3-emit]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
status: degraded
---

# Overnight Health Check 2026-04-23

Cross-ref: [[2026-04-22_overnight-check]]. Supersedes the blocked headless placeholder (NR MCP was unavailable in that run).

## Summary

Degraded. OOMKill total is 423/24h (4x above the 103 baseline), with `connector-20628` as a new top offender (87 kills). The `NoneType` error locus has shifted from connector pods to platform services (`smtp-frame-receiver`, `create-detection-window`). Deferred-alert canaries and `streamId Guid` rejection on stage are both clear. §3 cleanup-Lambda gate log is inconclusive (not in NR — needs CloudWatch); §3 CHM-cronjob emit path is confirmed active on the dev queue.

## Checks Run

| Check | Result | Count / Detail |
|---|---|---|
| OOMKills 24h | ELEVATED | 423 total (baseline 103); `connector-20628` new leader at 87 |
| `streamId Guid` on `:stage` | ALL CLEAR | 0 |
| `NoneType` unpack 12h prior vs recent | CHANGED | 17,244 → 6,017 (partial); source shifted to `smtp-frame-receiver` + `create-detection-window` |
| §2b `drain_alert_executors` canaries | ALL CLEAR | ~40K+ completions in 14h, 0 errors |
| §3 Lambda gate (`admin_pk=138`) | INCONCLUSIVE | No matching logs in NR; verify via CloudWatch |
| §3 CHM emit to cleanup queue | ALL CLEAR | 28 events / 24h to `autopatrol_stale_schedule_cleanup_dev.fifo` |

## OOMKills Detail

Top-10 by OOMKill count (`K8sContainerSample`, `clusterName='Connector-EKS'`, `reason='OOMKilled'`, SINCE 24 hours ago):

| Container | Count | Note |
|---|---|---|
| connector-20628 | 87 | NEW — new top offender |
| connector-42644 | 33 | NEW |
| connector-14170 | 25 | Was ~32 baseline — improving |
| connector-46193 | 20 | NEW |
| connector-27051 | 19 | NEW |
| connector-34144 | 15 | NEW |
| connector-23730 | 12 | Was ~18 baseline — improving |
| connector-37494 | 11 | NEW |
| connector-23510 | 9 | NEW |
| create-detection-window | 9 | NEW (platform service in top-10) |

Fleet total: 423. Previously-flagged heaviest offenders (`connector-14170`, `connector-23730`) are trending down; seven new containers have entered the top-10 simultaneously. The fleet-wide 4x surge strongly suggests a shared trigger (node pressure, recent deploy, model-server saturation) rather than per-site regressions.

## NoneType Shift

TIMESERIES 12h buckets (SINCE 24 hours ago):
- Bucket 1 (older): 17,244
- Bucket 2 (recent, partial): 6,017

Per-container in recent bucket: `smtp-frame-receiver` (3,779), `create-detection-window` (2,248). Prior pattern (2026-04-22) was connector-pod-driven. Platform-service source is a new pattern — investigate `smtp-frame-receiver` NoneType root cause.

## §2b Deferred-Alert Canaries

`drain_alert_executors: completed in 0.00s` firing healthy across all endrun threads. Top thread count ~6K in 14h. Zero ERROR-level drain events. Alert executor shutdown path nominal.

Note: `tags.Deployment = 'rearchitecture'` tag filter returned no results — attribute name may differ on prod connector pods. Canary is confirmed via unfiltered prod connector logs regardless.

## §3 Cleanup Lambda Gate

No NR log data found for `lambda_immix_autopatrol_schedule_cleanup` or any equivalent cleanup container. The gate log fingerprint (`CLEANUP_ENABLED=false`, `skipping disable`, `admin_pk=138`) is absent from NR Log events. Gate-wiring validation requires CloudWatch for the Lambda function directly — carry-forward for today's scope.

## §3 CHM Emit Activity

Confirmed: `emit_no_patrols_signal` events logged to `autopatrol_stale_schedule_cleanup_dev.fifo` in 24h. Sample schedule IDs and reasons:
- `no_patrols`: schedules c3808175, fbdfdba6, 636be1ba, ee1822f1
- `error`: schedules 798e6dde, 51c72148
- `site_disabled`: schedule 1e2ee05f

28 total events. Dev queue is active. Prod queue not separately verified.

## Follow-Up Items

- [ ] Triage `connector-20628` OOM surge — check memory limits, last deploy, node pressure
- [ ] Drill `NoneType` in `smtp-frame-receiver` — `SELECT message, timestamp FROM Log WHERE container_name = 'smtp-frame-receiver' AND message LIKE '%NoneType%' SINCE 6 hours ago LIMIT 5`
- [ ] Verify §3 Lambda gate via CloudWatch for `lambda_immix_autopatrol_schedule_cleanup` around 2026-04-22T18:04Z, `admin_pk=138`
- [ ] Confirm prod cleanup SQS queue emit activity (separate from `dev.fifo`)
- [ ] Investigate fleet-wide OOM trigger — was there a deploy or node event overnight?

## Cross-Refs

- [[2026-04-22_overnight-check]] — prior-day baseline
- [[2026-04-22_cleanup-lambda-bake-state]] — §3 Step E flip-readiness context
- [[mark-todos]] — Morning Follow-Ups block updated with this run's results
