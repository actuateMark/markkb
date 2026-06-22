---
title: "AutoPatrol schedule-sync stranding — redeploy flag calendar-day defect and fix"
type: synthesis
topic: autopatrol
tags: [autopatrol, onboarding, schedule-sync, observability, redis, incident, recurrence]
jira: ""
confluence: ""
created: 2026-06-03
updated: 2026-06-03
author: kb-bot
---

# AutoPatrol schedule-sync stranding — redeploy flag calendar-day defect and fix

## Incident (2026-06-03)

A site's schedule (ScheduleID `53C62AD7-B167-4E77-F72B-08DEC0C9AF65`, TenantID `dfda7621-f1d3-4469-b6df-dea988fd81a9`, admin site 37255, lead Immix.Hedrick - Patrol) was blocked from syncing for "at least an hour or more, if not a day." Patrols showed as healthy in NR at investigation time (recovered), indicating the block was transient.

## Two distinct stranding mechanisms exist

### Mechanism A: Fire-and-forget thread (the 2026-05-22 incident pattern, strands indefinitely)

`inframap/sites/autopatrol/autopatrol_schedule_model.py:993` in `AutoPatrolSchedule.deploy_schedule_settings()` starts a background Thread running `_delayed_deploy_settings` with:

- No retry on failure
- No state machine
- Errors swallowed to `logger.error` only (invisible because admin pod is not in NR)
- Once dead, the schedule lives in admin DB forever with no S3 settings and no K8s cronjob

Presents as "all patrols time out; cronjob never exists." Full analysis at [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]].

### Mechanism B: Redis redeploy-suppression flag (NEWLY identified today, best matches the symptom)

The periodic `schedules_redeploy` djangoq job gates redeploys with a redis flag `admin:schedule_redeployed:{id}`.

**The defect:** The flag is a bare value (`1`) with a rolling 24h TTL, NOT keyed to the schedule's calendar day.

- `redis_cli.set_schedule_redeployed()` sets `1` with `ex=60*60*24`
- `was_redeployed_today()` skips the schedule whenever flag is truthy
- The flag is set at the END of `ScheduleDeployer.deploy_schedule_changes()`
- Cleared only by `ScheduleV2.save()`
- **Problem:** A flag set late in the local day suppresses the schedule's legitimate redeploy well into the NEXT calendar day (up to ~24h). No self-heal if the flag lingered. Skip was logged at INFO only (easy to miss, and invisible given the [[new-relic|NR]] gap to admin pod logs).

Mechanically matches "blocked from syncing for an hour or more, if not a day." If the flag was set at 22:00 local time and checked at 10:00 the next day, it would still suppress the redeploy for the new day. A bare TTL + no date awareness = unbounded suppression window.

## Observability gap

NR showed zero hits for the ScheduleID/TenantID across all Connector-EKS containers (autopatrol-server, djangoq, admin-auto-onboarding-*, camera-admin-staging). The reason: `schedules_redeploy` and the schedule-sync/redeploy logic run in the camera-admin web pod, which is **NOT forwarded to NR** — the "admin pod missing from NR" gap documented at `topics/new-relic/notes/concepts/nr-connector-query-cookbook.md:314` (distinct from AUTO-566). This made both the Mechanism A thread and Mechanism B flag logic invisible to typical monitoring.

Could not reach the admin cluster via kubectl from the laptop (only inference-eks-* contexts available). Live confirmation of the stranding would require CloudWatch access or an admin-EKS context.

## Fix shipped today (targeted patch)

Branch `fix/ap-redeploy-flag-calendar-day` off develop (actuate_admin). Not yet pushed/PR'd.

### Changes

1. `redis_cli.set_schedule_redeployed(schedule_id, deployed_on)` now stores the schedule-local ISO date (YYYY-MM-DD) instead of bare `1`; TTL widened to 36h as a garbage-collection backstop so the stored date — not the TTL — is authoritative.

2. `flag_schedule_redeployed` passes `get_localized_date(schedule.timezone()).isoformat()` so each schedule's deploy date is in its local timezone.

3. `was_redeployed_today` suppresses ONLY when the stored date == today's schedule-local date. Prior-day values or legacy bare `1` are treated as STALE → does NOT suppress (self-heals) and logs at WARNING (greppable in CloudWatch despite the NR gap). Handles both bytes and str values from redis (no `decode_responses` assumed).

4. Five unit tests added to `inframap/test/schedule/test_schedule_redeploy.py` (WasRedeployedTodayTests):
   - today's date → suppress
   - prior-day value → redeploy (self-heal)
   - bytes value → parse correctly
   - legacy bare flag → redeploy (self-heal)
   - no flag present → redeploy
   - All 12 tests in the file pass locally with COVERAGE=1

### Verification steps still needed (live pod)

Once merged to stage, confirm via:

1. Map ScheduleID `53C62AD7-B167-4E77-F72B-08DEC0C9AF65` to admin schedule id (via autopatrol_onboarder probe or Immix API lookup)
2. Check redis value: `redis-cli GET admin:schedule_redeployed:{id}` — should be empty (post-fix, stale bare `1` self-heals) or an ISO date from today
3. CloudWatch search in camera-admin pod logs around the incident window for: `was_redeployed_today` WARN or INFO lines showing the schedule was/wasn't suppressed

## Relation to prior incidents

This is a **recurrence of the class** documented in [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]]. That incident was Mechanism A (thread crash). This incident is Mechanism B (flag calendar-day defect), but both result from the same structural gap: **no state machine tracking deploy success, no reconciliation loop, and admin pod logs invisible**.

## Larger resilience fixes needed

The calendar-day fix is interim. The durable solution requires three layers:

- **Layer 2 (the real fix):** Admin-side reconciliation cron / DB deploy-state machine (`settings_deploy_state: pending|settings_uploaded|cronjob_created|failed`). See [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]]#Layer-2 and the deferred backlog for the full backlog of follow-ups.
- **Layer 1:** Onboarder-side post-deploy verification — verify K8s cronjob exists within ~15 min.
- **Layer 3:** Admin pod into New Relic so deploy-thread and redeploy-skip logs become alertable.

All follow-ups added to [[autopatrol-deferred-backlog]] under "AP schedule-sync resilience (post-2026-06-03)".

## Cross-references

- [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]] — prior incident (Mechanism A, thread crash); defined Layer 1, 2, 3 guardrails
- [[autopatrol-deferred-backlog]] — follow-up work and larger resilience roadmap
- `actuate_admin` branch `fix/ap-redeploy-flag-calendar-day` — this fix (in review)
