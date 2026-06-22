---
title: "AutoPatrol onboarding — silent deploy-thread failure can strand a schedule"
type: synthesis
topic: autopatrol
tags: [autopatrol, onboarder, admin, observability, deploy, reliability, incident, immix]
created: 2026-05-22
updated: 2026-05-22
author: mark
incoming:
  - topics/autopatrol/notes/syntheses/2026-05-22_guardrail-B-admin-reconciliation-scoping.md
  - topics/autopatrol/notes/syntheses/2026-05-22_immix-finished-without-raise-marked-failed.md
  - topics/autopatrol/notes/syntheses/2026-06-03_ap-redeploy-flag-calendar-day-stranding.md
  - topics/personal-notes/notes/daily/2026-05-22.md
incoming_updated: 2026-06-03
---

# AutoPatrol onboarding — silent deploy-thread failure can strand a schedule

## Incident (2026-05-22)

User reported schedule `55A93D4B-FEEE-4920-3669-08DEB1143883` ("test fire", tenant `Immix.Hedrick`, site 10012 "McCall") created in Immix the previous day. All 6 patrols were returning `Timeout/Period Lapsed` — patrols were never starting.

Initial signal: zero hits across [[new-relic|NR]] connector logs and `autopatrol-server` for the ScheduleID and all 6 PatrolIDs over 36h. No K8s cronjob existed for site 10012 anywhere in the fleet. The patrols were timing out because there was no connector running to respond.

## The full chain (where each link can break)

```
[Immix]   schedule created
  ↓ (eventbridge: rate(5 minutes))
[autopatrol-onboarder Lambda]
  - get_contracts() → 18 contracts (page-size cap 100)
  - per-tenant: get_sites() → site row
  - per-site: get_awaiting/active/deactivated_schedules
  - POST admin /auto_patrol_schedule/ (bulk)
  - autopatroller.activate_schedule(tenant, schedule)
  ↓
[camera-admin]   AutoPatrolScheduleViewSet.create()
  - AutoPatrolScheduleSerializer.is_valid()
  - AutoPatrolScheduleSync.process_item():
      get_or_create(AutoPatrolSchedule) → created=True ✓ (DB row lands)
      auto_schedule.deploy_schedule_settings(call_deployer=True)
        ↓ if not COVERAGE:
        Thread(target=_delayed_deploy_settings, name=f"_delayed_deploy_settings_{id}").start()
        ↓ background thread, NO retry, NO escalation:
          - ensure_default_configurations()
          - time.sleep(5)
          - _deploy_settings()  → boto3 put_object → S3
          - if call_deployer: deploy()  → HTTP POST connector_deployer
  ↓
[connector_deployer]   creates K8s cronjob
  ↓
[K8s]  CronJob fires on cron → pod starts → reads S3 settings → connects to RTSP → runs patrol
```

The onboarder's part **succeeded for this schedule** — first sighting at 2026-05-21 21:07:55 UTC, logged as `Awaiting schedule: test fire` then `Active schedule: test fire`. Admin POST returned 2xx (no `Failed to call` log on the Lambda).

The connector_deployer **never received the request** — zero log lines in `connector-deploy` for site 10012, McCall, Hedrick, dfda7621, or 55a93d4b across the 2-day window despite ~8k other log lines.

So the break is inside the admin's background Thread, between `Thread.start()` and the call to `deploy()`. Admin pod is **not in NR** (the "admin pod missing from NR" gap (see `topics/new-relic/notes/concepts/nr-connector-query-cookbook.md:314` — separate untracked observability gap, *not* AUTO-566 which is a different config-sync issue) / see [[2026-04-17_onboarder-nr-instrumentation-gap]]), so the exact crash point is invisible.

## What's structurally wrong

These are the design properties that let a single thread failure strand a schedule indefinitely.

### 1. Fire-and-forget Thread with no idempotent recovery

`autopatrol_schedule_model.py:993` starts a `Thread`. The thread does sleep+S3+HTTP, all of which can fail or be killed by a pod restart. The outer `try/except` at line 1004 catches exceptions but only `logger.error`s them. There is:

- **No retry** — one failure ends the deploy attempt
- **No state flag** — `customer.settings_deployed = False` is set in some paths but there's no "this schedule needs a redeploy" marker that survives a thread death
- **No reconciliation loop** — nothing scans for `AutoPatrolSchedule` rows whose corresponding K8s cronjob doesn't exist
- **No alert** — admin pod logs aren't surfaced to NR, so even if the thread logged `error`, no human sees it

Once the thread dies, the schedule lives in admin DB forever with no S3 settings and no cronjob. The onboarder re-POSTs the schedule every 5 minutes, but in `process_item` only `created=True` triggers `call_deployer=True`. The second sighting onward, the schedule already exists → `created=False`, and unless `has_changes` / `devices_updated` / `products_added` / `reactivated` flips true, **the deploy thread is never re-fired**.

### 2. The onboarder is "deploy-and-forget"

`lambda_function.py:504-540` posts to admin and calls `activate_schedule` in Immix. It does not verify a cronjob was actually created. The patrol then activates in Immix → autopatrol-server starts pinging a connector that doesn't exist → all patrols time out → customer-visible failure.

### 3. Single point of observability failure

The most reliable diagnostic during this incident was the Python probe we wrote (`scripts/probe/missing_schedule_probe.py`) that queried Immix directly. Everything between Immix and the connector — onboarder Lambda CloudWatch + admin pod logs + connector_deployer — required separate tooling per layer, with no unified view. The admin pod's silence (the "admin pod missing from NR" gap (see `topics/new-relic/notes/concepts/nr-connector-query-cookbook.md:314` — separate untracked observability gap, *not* AUTO-566 which is a different config-sync issue)) made the most-suspect layer the least observable.

### 4. PHASE log lines are good, but only cover one Lambda

The onboarder added `PHASE contract_loop_complete` / `PHASE lifecycle_pass_complete` log lines that were load-bearing for THIS investigation. No equivalent exists for the admin deploy thread or for connector_deployer's response. Each link in the chain needs a single, greppable "I completed X for schedule Y" line.

## How the diagnosis actually played out

1. Started broad: searched all of NR + autopatrol-server for the 7 GUIDs → 0 hits anywhere. Concluded chain broke before patrol execution.
2. Searched all related repos for recent AP-related commits → found vms-connector PR #1709 (lifecycle change). Hypothesized lifecycle order issue, but the cronjob never existed at all, so the connector lifecycle was downstream of the actual break.
3. Wrote a one-off `missing_schedule_probe.py` that loops every tenant from `get_contracts()` and calls `get_schedule(tenant, schedule_id)` until one returns 200 — found tenant + site immediately. This is the **first useful tool** in what should become the [[autopatrol-integration-tools]] folder.
4. Searched CloudWatch for the tenant/site → found the onboarder DID pick up the schedule at 21:07:55 UTC and POST it to admin. So the onboarder is not the bug.
5. Read admin's `AutoPatrolScheduleSync.process_item` → confirmed `created=True` path does call `deploy_schedule_settings(call_deployer=True)` → confirmed it kicks off a Thread → confirmed thread errors are swallowed.
6. Confirmed connector_deployer received NOTHING via NR query → break is inside the thread.

Time-to-root-cause: ~45 minutes once tooling existed. Without the probe, would have spiraled into wrong-area investigations.

## Proposed guardrails

Three layers, listed by deployment cost ascending. (1) is the smallest immediate win; (2) is the real fix.

### Layer 1 — onboarder-side post-deploy verification (small, immediate)

For every schedule the onboarder activates, record `(schedule_id, tenant_id, site_id, activated_at)`. On the next tick, check K8s for `connector-{site_id}-autopatrol-{schedule_number}-chm-cronjob` (or similar). If absent after N minutes (~15), log a structured `OnboarderDeployStalled` event to NR and emit a Slack alert.

The onboarder Lambda doesn't have K8s access today, but it could call connector_deployer's `/list` endpoint, or admin can expose `/auto_patrol/schedules/?cronjob_deployed=false`.

### Layer 2 — admin-side reconciliation cron (the real fix)

Replace the fire-and-forget Thread pattern with a state-tracking reconciler. Schema additions on `AutoPatrolSchedule`:

```python
settings_deploy_state: str  # "pending" | "settings_uploaded" | "cronjob_created" | "failed"
settings_deploy_attempts: int
settings_deploy_last_error: str | None
settings_deploy_last_attempted_at: datetime
```

`deploy_schedule_settings` flips state to `pending` and enqueues, doesn't start a thread directly. A separate periodic job (Celery beat / cron) finds rows where state in (`pending`, `failed`) and `last_attempted_at` < N minutes ago, retries them. The thread becomes one of many workers, not the single point of execution.

This also makes the deploy chain **observable from admin's database**, not just admin's logs. A dashboard query "schedules in state != cronjob_created" is the regression signal.

### Layer 3 — admin pod into NR (the "admin pod missing from NR" gap (see `topics/new-relic/notes/concepts/nr-connector-query-cookbook.md:314` — separate untracked observability gap, *not* AUTO-566 which is a different config-sync issue))

Independent track. Once admin pod is in NR, structured logs from the deploy thread become alertable. Until then, every "is the deploy thread crashing?" question has to be answered by `kubectl logs` on the admin pod, which is laborious enough that we don't do it.

## Tooling artifact

`autopatrol_onboarder/scripts/probe/missing_schedule_probe.py` is the one-off written during this incident. It will be promoted to `scripts/integration_tools/schedule_lookup.py` as the first reusable Immix CLI, alongside a `deploy_chain_check.py` that walks the full chain (Immix → admin DB → S3 → K8s) for a given schedule. See [[autopatrol-integration-tools]] (TBD entity note once scaffolded).

## Open questions

- Why did the admin background thread fail for THIS schedule specifically? Was it a one-off (network blip during S3 upload, deployer 5xx, admin pod restart at 21:07:55 UTC) or a systemic issue (e.g. some property of the site/schedule that crashes the settings generator)? Without admin pod logs in NR we can't tell. **Mitigation**: when this schedule is manually re-deployed (after fix), see whether `deploy_schedule_settings` succeeds cleanly — if yes, it was transient and only Layer 2 prevents recurrence; if no, there's a real bug in settings generation worth chasing.
- How many other schedules are currently in this stranded state? Layer 1's "schedules in admin with no cronjob" query would tell us, but doesn't exist. Worth running once manually via `kubectl get cronjobs -A` vs `AutoPatrolSchedule.objects.all()`.

## Cross-references

- [[2026-04-17_onboarder-nr-instrumentation-gap]] — sibling observability problem (Lambda side, partially addressed). This synthesis covers the admin side.
- [[2026-04-23_postmortem-onboarder-healthcheck]] — prior onboarder failure pattern (Lambda crash with no telemetry)
- [[autopatrol-onboarder]] — entity note for the Lambda
- vms-connector PR #1709 — initially suspected; ruled out (the break is upstream of any connector code)
