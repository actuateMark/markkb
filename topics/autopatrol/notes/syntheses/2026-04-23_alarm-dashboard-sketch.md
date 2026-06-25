---
title: "AutoPatrol Alarm & Dashboard System — Design Sketch"
type: synthesis
topic: autopatrol
tags: [alarms, monitoring, dashboard, observability, design-sketch]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
incoming:
  - topics/autopatrol/notes/syntheses/2026-04-23_postmortem-onboarder-healthcheck.md
  - topics/operational-health/notes/syntheses/2026-04-23_dashboard-sketch.md
  - topics/operational-health/notes/syntheses/2026-05-05_operational-dashboard-context.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-06-25
---

# AutoPatrol Alarm & Dashboard System — Design Sketch

**Status:** Sketch only. Hand-off for another session to plan + implement. Motivation: 2026-04-23 incident where a silent early-return on the onboarder Lambda broke new-schedule activation for ~2 days before a customer reported it. No alarm fired. No dashboard anomaly was spotted. We need a daily-checkable signal for anomaly classes like this.

## Problem statement

Current monitoring posture for AutoPatrol is "reactive":
- Lambda CloudWatch `Errors` metric — near-useless for early-return failures (normal exit = 0 errors)
- Individual post-deploy verification — per-PR, not continuous
- [[new-relic|New Relic]] — onboarder has no NR instrumentation at all (known gap)
- Slack `#autopatrol-sync` — only fires on disable/re-enable events, nothing about upstream health

We need a consolidated dashboard + daily-reviewable alarm set so anomalies surface within hours, not days.

## Proposed metric families

### 1. Onboarder liveness (per region: US, EU)

| Metric | Query | Healthy |
|---|---|---|
| Invocations with real work | `count(logs where "Fetched N contracts" appears AND N > 0)` per hour | > 10 per hour (12 invocations × some worked) |
| Early-exit rate | `count(log lines "Failed to connect to AutoPatrol API")` / `count(invocations)` | near 0 |
| Contracts processed per run | `AVG(N)` where N from `"Fetched N contracts"` | stable; alarm on 50%+ drop |
| Sites onboarded per hour | `count(Admin API POST .../auto_patrol/sync/ with new site_id)` | varies; alarm on 24h streak of 0 |
| Schedules activated per hour | `count(logs "activating schedule")` | varies; alarm on 24h streak of 0 |
| Per-tenant fetch error rate | `count(logs "get_sites HTTP {401,400,403}")` / `count(tenants_processed)` | baseline + 2σ alarm |

### 2. Cleanup Lambda pipeline health (US; EU once Step G lands)

| Metric | Source | Healthy |
|---|---|---|
| DLQ depth (stage + prod) | CloudWatch SQS | always 0; alarm immediately on > 0 |
| Lambda Errors | CloudWatch Lambda | 0 |
| Lambda Throttles | CloudWatch Lambda | 0 |
| Would-PATCH rate (`CLEANUP_ENABLED=false`) | Log grep "would PATCH" | baseline ~0–few/day; alarm on 10+/hour spike |
| Actual-disable rate (`CLEANUP_ENABLED=true`) | Log grep "disabled admin" | baseline tied to fleet scale; alarm on 50+/day spike (flappy) |
| Anomaly-reset rate | Log grep "anomaly: bucket=" | baseline <5/day; alarm on 10+/hour spike (classification bug or Immix flaky) |
| Transient-error rate | Log grep "transient error" | <5% of invocations; alarm on sustained >10% |
| DDB counter rows without TTL | DDB scan | 0 |
| Re-enable Lambda invocations | CloudWatch Lambda | informational; track volume |

### 3. Connector emit flow (feeds the cleanup Lambda)

| Metric | Source | Healthy |
|---|---|---|
| Connector emit log lines | NR logs `"emit_no_patrols_signal"` per hour | matches fleet cadence (~3500/day) |
| SQS messages received | CloudWatch SQS ApproximateNumberOfMessagesReceived | matches connector emits within 1-2% |
| Schedules emitting from both flows (patrol_exit + site_disabled) | Unique schedule_ids per reason | alarm on site_disabled > 10% of unique (unusual pattern) |

### 4. Upstream Immix API health (indirect signal)

| Metric | Source | Healthy |
|---|---|---|
| `get_schedule` non-200 rate | Log grep in cleanup Lambda | <1%; spike = Immix incident |
| `get_contract` failure rate | Log grep in onboarder | <5%; spike = Immix incident |
| `get_sites` permanent-failure rate per tenant | Log grep | stable per-tenant; alarm on new tenants suddenly 401'ing |

### 5. Alert system (Actuate-side, the `#autopatrol-sync` channel)

| Metric | Source | Healthy |
|---|---|---|
| Slack post rate for disable/re-enable | Slack channel activity | tied to cleanup activity; alarm on sustained 50+/day |
| Cleanup disable + Immix re-check success rate | Cleanup Lambda logs | ~100% (guard working); alarm if < 95% |

## Proposed implementation approaches

1. **CloudWatch dashboards + metric filters** — cheapest. Metric filters on CloudWatch log groups extract counts from log patterns ("Fetched N contracts", "would PATCH", "anomaly:"); dashboards chart them together; alarms fire on anomalies.

2. **Wire onboarder to [[new-relic|New Relic]] first** — fixes the known gap. Adds custom events `AutoPatrolOnboarderInvocation { contracts_fetched, sites_processed, schedules_activated, errors_count, duration_ms }` per run. NR alerts + dashboards are cheaper to build than CloudWatch-first.

3. **Hybrid** — NR for deep-dive / log search; CloudWatch dashboard for the quick-scan "is everything OK" daily view. This matches what we do for other Actuate services.

## Daily review workflow

Proposed: a `/autopatrol-morning-check` skill that:
1. Runs all the queries above (in parallel)
2. Produces a one-screen dashboard-style output: all-green / yellow-flags / red-flags
3. Drills into any flag automatically
4. Writes result to `topics/autopatrol/notes/daily/YYYY-MM-DD_morning-check.md` for audit trail

User reviews this once per morning; any red flag triggers further investigation or page to oncall.

## Dashboard mockup (layout)

```
┌──────────────────────────────────────────────────────┐
│ AutoPatrol System Health — 2026-04-23 08:00Z         │
├──────────────────────────────────────────────────────┤
│ Onboarder (US)     Contracts/hr: 288  Sites/hr: 12  │  ✓
│ Onboarder (EU)     Contracts/hr: 288  Sites/hr: 4   │  ✓
│ Cleanup Lambda     Invocations/24h: 30  DLQ: 0      │  ✓
│ Reenable Lambda    Invocations/24h: 0   errors: 0   │  ✓
├──────────────────────────────────────────────────────┤
│ Fleet signals                                         │
│  Patrol-exit emits (24h):     3502                   │
│  Site-disabled emits (24h):   12                     │
│  Would-PATCH rate:            0                      │  dark mode
│  Anomaly resets:              3                      │  ✓
│  Transient errors:            14 (2.1%)              │  ✓
├──────────────────────────────────────────────────────┤
│ Upstream Immix                                        │
│  get_schedule 5xx rate:       0.3%                   │  ✓
│  get_contract failures:       3% (within baseline)   │  ✓
├──────────────────────────────────────────────────────┤
│ Alerts                                                │
│  None active.                                         │
└──────────────────────────────────────────────────────┘
```

## Open questions for planner session

1. **NR wiring order** — do we wire onboarder to NR FIRST (unblocking NR-based alarms) or build CloudWatch dashboards in parallel?
2. **Alarm severity tiering** — which alarms page vs. Slack vs. dashboard-only?
3. **Baseline calibration** — we need 7–14 days of metrics before we can set alarm thresholds accurately. Do we ship "informational" mode first?
4. **Per-customer breakdown** — do we need dashboard drill-downs per customer/tenant, or is fleet-level enough?
5. **Cost** — CW Log Insights queries at scale get expensive. Metric filters are cheaper but less flexible. Which combination?

## Hand-off

Next step: another session picks this up, turns it into a formal plan (via `ExitPlanMode`), implements. Cross-link:
- [[autopatrol-onboarder]] — onboarder entity
- [[autopatrol-cleanup-lambda]] — cleanup entity
- [[2026-04-23_release-acceptance-criteria]] — upstream rule this alarm system enforces
- [[2026-04-20_cleanup-lambda-runbook]] — existing manual commands, many of which become alarm queries
