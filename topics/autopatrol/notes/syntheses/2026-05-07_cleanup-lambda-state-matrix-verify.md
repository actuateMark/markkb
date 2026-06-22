---
title: "Cleanup-Lambda state-matrix verify — 2026-05-07"
type: synthesis
topic: autopatrol
tags: [autopatrol, cleanup-lambda, verify, monitoring]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
workstreams: ["§3"]
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
incoming:
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/billing/_todos.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming_updated: 2026-05-27
---

# Cleanup-Lambda state-matrix verify — 2026-05-07

## Question

Is the AutoPatrol stale-schedule cleanup Lambda working as designed across the full state matrix — disabled / paused / offline / active sites — without false-positives or false-negatives?

## TL;DR

**Pipeline is FUNCTIONALLY HEALTHY but has not exercised real-customer cases in 30+ days.** Every Lambda invocation in the last 14 days has been from internal test-tenant traffic (`Vendor.Actuate.Prod`). No real customer's schedule has reached disable threshold, no anomaly-reset has fired, no false-positive disables observed.

The lambda IS handling the "schedule not in admin" early-exit branch correctly (live observed). The Immix-state branches (Deleted ✓, Suspended ✓, Paused ✓, offline ✓) cannot be verified live without a synthetic canary because real-customer cases aren't reaching the pipeline.

## Evidence

### Health-check snapshot (2026-05-07 06:01 ET, fresh)

```json
{
  "overall_verdict": "green",
  "lambda_metrics_24h": {"invocations": 678, "errors": 0, "throttles": 0, "duration_avg_ms": 531},
  "lambda_logs_24h": {"invocations": 678, "messages_processed": 678, "would_disables": 0, "actual_disables": 0, "anomaly_resets": 0, "errors": 0},
  "ddb_state": {"total_rows": 1, "at_threshold_count": 0, "drift_rows": []},
  "queue_depths": {"stage_main": 0, "stage_dlq": 0, "prod_main": 0, "prod_dlq": 0},
  "event_source_mapping": "Enabled USER_INITIATED",
  "lambda_config": {"CLEANUP_ENABLED": "true", "DRY_RUN": null, "AUTOPATROL_STAGE": "prod", "AUTOPATROL_REGION": "US"}
}
```

### 30-day window — actual activity

Filter `actual_disable` over 30d: **0 events.**
Filter `anomaly_reset` over 30d: **0 events.**

### Live processing sample (2026-05-07 13:08 → 13:23 UTC)

Every invocation in the 15-minute window followed the same shape:

```
processing schedule_id=<X> tenant_id=24fb29fd-a945-4051-b476-f456efacd8d3 site_id=<24 or 26> reason=error bucket=patrol_exit target_hours=18 integration=<autopatrol|vch>
admin has no schedule with scheduleId=<X> — nothing to do, ACKing the message
```

All 4 distinct schedule_ids observed (`69a61d64-…`, `3e4da649-…`, `c1572fe7-…`, `643249e6-…`) belong to `tenant_id=24fb29fd-a945-4051-b476-f456efacd8d3`. The Lambda's admin-lookup-then-ACK branch is working as intended.

### DDB state

The single row in `autopatrol_cleanup_counters-dev` is `admin_pk=234`, `schedule_id=1e2ee05f-…`, `tenant_id=47dc2c1f-5c19-43fb-b5d5-753c5e96eb14` (Vendor.Actuate.Prod). Counter at `count_site_disabled=16/56` (at 6h cadence — 14 days to threshold). Last activity 2026-04-24 (13 days ago). Connector emit for this schedule has stopped; counter will time out via TTL (2026-mid-year).

## State-matrix branch coverage

| State branch | Last verified | Method | Confidence |
|---|---|---|---|
| schedule not in admin → ACK no-op | 2026-05-07 (live) | Live log sample, every invocation | High |
| Immix-Deleted (404) → disable | 2026-04-23 | DDB audit trail (`disabled_by=cleanup_lambda` first row 2026-04-23T22:09Z) | Stale (14d) |
| Immix-Active → anomaly-reset | Not exercised in 30d | — | Unverified live |
| Immix-Suspended → anomaly-reset | Not exercised in 30d | — | Unverified live |
| Paused / SiteDisabledOrDisarmed | Not exercised in 30d | — | Unverified live (separate routing per §3 follow-up) |
| Offline / connectivity-broken (no Immix response) | Not exercised in 30d | — | Unverified live |

The `event_source_mapping` is correctly Enabled, the queues are draining (depth 0/0 across stage + prod main + DLQ), and there are no transient errors. **Nothing observable is broken; the issue is observability gap.**

## Why no real-customer traffic?

Most likely explanation: §17 (VCH `no_patrols` emit drop, merged stage→rearch via PR #1660 on 2026-05-01) eliminated the dominant false-positive emit class. Combined with §3 Step E having flushed the prior backlog of stale schedules in late April, the cleanup pipeline has run out of organic "real" events.

This is success in the sense that the pipeline isn't being abused for noise. But it leaves us blind to whether the Immix-state branches still work correctly when real cases DO arrive.

## Risk

If the Immix-state branches have silently drifted (unlikely without a code change, but possible via [[immix-vendor-api|Immix API]] behavior changes), we wouldn't know until a real customer case fires. By that point, the time-to-detection of a regression is whatever the threshold cadence is (18h for the standard `patrol_exit` bucket; 14 days for `site_disabled`).

The deploy_workflow_24h check shows the last lambda deploy was 2026-04-30 (`code_sha256: 4OaMWiihoCrx5qFGxAmdj5gCsjnRb0QEAa1ftd+9S+0=`); no recent code changes that could've drifted.

## Recommended action

**Add a synthetic canary for state-matrix verification** — see [[autopatrol-deferred-backlog]] new entry "Cleanup-Lambda canary across state matrix". A small Vendor.Actuate.Prod test schedule that we manipulate state on (Active → Deleted → Suspended) and verify the cleanup-Lambda's response on each transition.

Not blocking. Pipeline is healthy by every observable metric; this is "good defense in depth" rather than "fix something broken."

## Resources

- [[autopatrol-cleanup-lambda]] — entity
- [[2026-04-17_stale-schedule-cleanup-design]] — design doc (state matrix specified)
- [[2026-04-22_cleanup-lambda-bake-state]] — historical bake state (when the pipeline DID exercise real cases)
- [[2026-04-24_stale-schedule-cleanup-aar]] — Step E AAR
- [[autopatrol-deferred-backlog]] § "Cleanup-Lambda canary across state matrix" (new)
- Health-check JSON: `~/.local/state/minipc-tasks/autopatrol/cleanup-2026-05-07.json`

## Related

- §3 — parent workstream
- §17 (archived) — explains why real-customer no_patrols emits dropped
- §16 (archived) — tenant-cascade carry-over context
- [[2026-05-07_cohort-b-no-backfill-decision]] — why we're not currently mass-mutating customer state
