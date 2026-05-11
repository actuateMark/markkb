---
title: "Chronic Flapper Investigation — Cleanup Lambda Anomaly-Reset Repeat Offenders"
type: concept
topic: autopatrol
tags: [cleanup-lambda, anomaly-reset, vch, flapper, investigation, finding, autopatrol, immix, autopatrol, immix, autopatrol, immix, autopatrol, immix, autopatrol, immix]
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
incoming:
  - topics/personal-notes/notes/concepts/2026-04-29_cleanup-handoff.md
  - topics/personal-notes/notes/daily/2026-04-28.md
incoming_updated: 2026-05-08
---

# Chronic Flapper Investigation — Cleanup Lambda Anomaly-Reset Repeat Offenders

## Background

The cleanup Lambda's "anomaly-reset" branch fires when the per-schedule counter reaches threshold but Immix's `get_schedule()` says the schedule is still Active. PR #9 (deployed 2026-04-27) added Paused/Suspended classification so those states also route through anomaly-reset rather than incorrect disables.

After multiple days of running, 4 specific schedule_ids accumulated as **repeat offenders** in the 7-day anomaly-reset map. This investigation (2026-04-28) characterizes why they keep flapping.

## The 4 chronic flappers

7-day anomaly-reset counts as of 2026-04-28 PM:

| schedule_id | 7d resets | tenant_id | Title | scheduleStatus | integration |
|---|---|---|---|---|---|
| `fbdfdba6-f62c-...` | 9 | `47dc2c1f` (Vendor.Actuate.Prod) | VCH 9-17 | **Active** | vch |
| `c3808175-85e0-...` | 9 | `47dc2c1f` (Vendor.Actuate.Prod) | VCH 11-4 | **Active** | vch |
| `ee1822f1-67c8-...` | 8 | `47dc2c1f` (Vendor.Actuate.Prod) | VCH Test 2 | **Active** | vch |
| `56de5b0a-9094-...` | 1 | `dfda7621-f1d3-...` | AutoPatrol | **Paused** | autopatrol |

All probed live against Immix prod via `autopatrol_onboarder/scripts/probe/flapper_schedule_probe.py`.

## Class A — VCH connector emits `no_patrols` for genuinely Active schedules (3 of 4)

The 3 VCH-integration schedules under `Vendor.Actuate.Prod` are persistently flapping, but Immix's `/Schedules/{id}` reports them as `scheduleStatus=Active`. Their tenant + contract are both Active.

**Cleanup Lambda behavior:** anomaly-reset (correct — Immix says Active means "don't disable").

**Root cause hypothesis:** the connector's VCH integration emits the `no_patrols` cleanup signal even though the VCH schedule is genuinely Active. Either VCH has a different patrol-detection model than AutoPatrol (and the connector's emit predicate doesn't account for it), or VCH schedules under the test tenant `Vendor.Actuate.Prod` are intentionally configured-but-not-running.

**Tenant cascade does NOT fix this** — the parent tenant is Active, not Suspended.

**Tracked as [[mark-todos]] §17.** Investigation in flight via connector-pipeline-expert.

## Class B — Paused schedule, PR #9 anomaly-reset is correct (1 of 4)

The 1 AutoPatrol schedule (`56de5b0a`) is in `scheduleStatus=Paused` on Immix.

Paused schedules don't generate patrols by design. Connector correctly emits "no_patrols", classifier correctly treats Paused as "still-active" per PR #9, anomaly-reset clears the bucket. **No bug.**

**Possible future polish:** recognize Paused as a stable steady-state and clear the DDB row entirely rather than anomaly-resetting (since Paused is intentional, not anomalous). Saves Lambda invocations until un-paused. Not a priority — current behavior is correct, just not optimal.

## What this investigation proved

1. **None of the chronic flappers are tenant-suspension cases.** The §16 tenant cascade work is the right fix for `Remote Security Solutions` and `Legacy` (the actually-suspended tenants), but it would NOT have caught any of the chronic flappers.
2. **The classifier (PR #9) is working correctly.** All 4 flappers go through anomaly-reset for valid reasons.
3. **3 of the 4 anomaly-reset slots in the 7-day map are noise** from the VCH false-emit issue. Resolving §17 should drop the daily anomaly-reset rate from ~6 to ~3 (the Paused one stays).

## Reusable probe scripts

All in `autopatrol_onboarder/scripts/probe/`:

- **`tenant_status_probe.py`** — does Immix expose `/Tenants/{id}` or `tenantStatus`? Run periodically to monitor suspended-tenant population for tenant-cascade canary verification.
- **`flapper_schedule_probe.py`** — given a list of `(schedule_id, tenant_id)` pairs, fetches each via Immix `/Schedules/{id}` and reports `scheduleStatus` + title. The canonical "is this flapper actually a real customer-state issue or a connector bug?" tool.
- **`flapper_patrol_stream_probe.py`** — placeholder that needs `device_id` (Immix's `get_patrol_stream` requires patrol_id + device_id, NOT just schedule_id). The cleanup Lambda's actual classifier calls `get_schedule`, not `get_patrol_stream`, so this script is mostly redundant with `flapper_schedule_probe.py`. Kept for reference if a per-patrol probe ever becomes useful.

All require `AUTOPATROL_API_KEY` env var. The standard pattern:

```bash
export AUTOPATROL_API_KEY="$(AWS_PROFILE=prod aws lambda get-function-configuration \
  --function-name immix-autopatrol-schedule-cleanup --region us-west-2 \
  --query 'Environment.Variables.AUTOPATROL_API_KEY' --output text)"
.venv/bin/python scripts/probe/flapper_schedule_probe.py
```

Probes are idempotent and safe — read-only HTTP GETs with bounded timeouts.

## Related

- [[2026-04-28_tenant-status-sync-gap]] — sister investigation that surfaced the flapper class breakdown
- [[2026-04-23_cleanup-rollout-day]] — original cleanup Lambda rollout, where the chronic flappers first appeared
- [[autopatrol-cleanup-lambda]] — entity
- [[mark-todos]] §17 — VCH connector emit-side investigation
- [[mark-todos]] §16 — tenant-status sync gap (where the flapper investigation was incidentally branched off)
