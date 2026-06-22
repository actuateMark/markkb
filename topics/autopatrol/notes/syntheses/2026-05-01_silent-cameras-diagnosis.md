---
title: "Silent autopatrol cameras — fleet-wide diagnosis (2026-05-01)"
type: synthesis
topic: autopatrol
tags: [autopatrol, vch, silent-cameras, diagnosis, propagation, cleanup-lambda, gap, fleet, immix, billing]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
jira: TBD
outgoing:
  - topics/autopatrol/notes/concepts/2026-05-05_cohort-b-backfill-runbook.md
  - topics/autopatrol/notes/data/2026-05-04_silent-camera-diagnosis.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-01_pre-endrun-crashes-resolution.md
  - topics/autopatrol/notes/syntheses/2026-05-04_admin-schedule-cascade-design.md
  - topics/autopatrol/notes/syntheses/2026-05-06_cohort-f-investigation.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/personal-notes/notes/concepts/2026-05-01_pre-endrun-crashes-handoff.md
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/daily/2026-05-04.md
incoming:
  - topics/autopatrol/notes/concepts/2026-05-05_cohort-b-backfill-runbook.md
  - topics/autopatrol/notes/data/2026-05-04_silent-camera-diagnosis.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/syntheses/2026-05-01_pre-endrun-crashes-resolution.md
  - topics/autopatrol/notes/syntheses/2026-05-04_admin-schedule-cascade-design.md
  - topics/autopatrol/notes/syntheses/2026-05-06_cohort-f-investigation.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/billing/notes/syntheses/2026-05-12_week-in-review-non-technical.md
  - topics/billing/reading-list.md
  - topics/personal-notes/notes/concepts/2026-05-01_pre-endrun-crashes-handoff.md
incoming_updated: 2026-05-27
---

# Silent autopatrol cameras — fleet-wide diagnosis (2026-05-01)

## TL;DR

Mark exported a CSV of **1,415 active cameras** on the autopatrol/VCH integration. He'd been told only ~500-600 were producing patrol activity. **Reality is much worse.**

- **1,637 active autopatrol/VCH cameras** in prod admin (live count, vs 1,415 CSV snapshot)
- **119 distinct customers** carry those cameras
- **Only 6 distinct sites produced any patrol activity in NR over the last 7 days** (3 confirmed admin Customer pks — `hanwha 2`/cid=46560, `hanwha 3`/cid=46460, `Site A`/cid=36799 — plus 3 from the Immix Finished webhook path)
- Sum of cameras at those 3 confirmed-active customers: **62**. Even with generous estimates for the 3 Immix-side sites, total truly-active is **~100-200 cameras**.
- **~1,400+ cameras are silent.** The pipelines we built so far (cleanup-Lambda `no_patrols_24h`, onboarder lifecycle pass, audit_autopatrol_state mgmt command) do not catch most of these.

The user vetoed running ad-hoc Django shell on prod ([[feedback_no_adhoc_prod_shell]]); this investigation used `aws ecs run-task` with code-reviewed inline Python against the prod admin Fargate task definition.

## What "active" means and where it's signaled

Per the connector-pipeline-expert investigation 2026-05-01:

- **The canonical signal of a successful patrol is `container_name='autopatrol-server'` log lines** containing `Processing patrol_id ...` (queued) or `patrolStatus: Finished` (completed). Note: the original "Analysis completed" string we hypothesized from earlier docs **does not exist** — the agent confirmed it.
- Granularity is **`site_id` (admin Customer pk)** for the Processing path, and **Immix-side `siteId`** for the Finished path. **Camera-level granularity is NOT logged**; per-camera silence has to be inferred from site-level activity + the camera's customer FK.
- Per-site connector pods log `Schedule {schedule_id} Patrol {patrol_id} is ready, scheduled for ...` — a stronger "the cronjob ran" signal but uses `schedule_id`, not `camera_id`.

## Methodology

1. **CSV inventory** — parsed `/home/mork/Downloads/Active_Cameras.csv` for 1,415 camera pks.
2. **Admin DB join** — ECS run-task on `prod-camera-admin` cluster ran an inline Python script: filter `Camera.objects.filter(is_deleted=False, active=True, customer__integration_type__name__in=['autopatrol','vch'])` → group by customer → annotate schedule states. Output via firelens → NR.
3. **NR activity query** — last 7 days, distinct site_ids in `autopatrol-server` Processing + Finished log paths.
4. **Diff** — admin-active customer set vs NR-active site set.

The full per-customer dataset (119 rows: cid, cams, customer-active flag, schedule totals split by status) is captured below.

## Headline numbers

```
INTEGRATION_NAMES=['autopatrol', 'vch']
total_active_autopatrol_cameras=1637
distinct_customers=119
customers_with_alive_schedules=78        # 65% of customers
customers_with_no_alive_schedules=41     # 35% of customers
customers_only_deleted_immix=31          # of the 41 silent: status=Deleted/Removed + is_deleted=False
customers_only_paused=2                  # customer-controlled silence (not a bug)
NR_active_distinct_site_ids_7d=6         # admin pks 46560, 46460, 36799 + Immix siteIds 10111, 10026, 10003
```

## Categorization of the 119 customers (summary table)

| Category | Count | Cause | Existing pipeline catches it? |
|---|---|---|---|
| **A. `customer.active=False` but cameras still active** | 11 (4 also `is_deleted=True`) | Customer was deactivated through some non-cascade path (manual admin edit, or onboarder marking inactive without soft-deleting). Cameras don't follow `customer.active`. | **No** — Cohort A in the audit command already counts these but isn't connected to a cleanup action. |
| **B. Schedules `status=Deleted/Removed AND is_deleted=False`** (real Cohort B) | 31 | Onboarder synced status from Immix but never `is_deleted`-flipped the row. Schedule appears live in admin's default queryset; cleanup Lambda's per-schedule path queries Immix and fails because the schedule is gone. | **No** — the original cohort filter (`schedule_id=''`) returned 0 because schedule_id is never null. The actual orphan signal is `schedule_status` not `schedule_id`. |
| **C. Customers with **alive** schedules but no NR activity in 7d** | ~75 (78 alive − 3 confirmed-active admin pks) | The biggest population. Schedule appears configured correctly, customer is active, BUT no patrol events emitted. Possible causes (need per-customer drill-down): (1) cronjob never deployed in K8s, (2) connector pod fails silently before SQS write, (3) cron expression empty / always_on=False with no time window, (4) SQS DLQ silently absorbing jobs, (5) Immix returns empty patrol list (no work → no log). | **Partially** — cleanup-Lambda's `no_patrols_24h` fires only if the connector pod actually runs and explicitly fails 3× in a row. Cases (1), (3), and (5) are invisible to it. |
| **D. Schedules paused (status=Paused/Suspended)** | 2 | Customer-controlled non-running state. **Not a bug — expected silence.** | N/A; these correctly skip the cleanup-Lambda (per §17 fix 2026-04-27). |

(Category C is dominant in camera count — 78 customers × avg 13 cameras = ~1000 cameras in that bucket.)

## Specific named examples

| Customer | cid | cams | cust_active | sched_total | alive | deleted_immix | category |
|---|---|---|---|---|---|---|---|
| Victoria - EE Demo | 39221 | 2 | True | 4 | 0 | **4** | **B** — confirms 4 orphan schedules per the original handoff, but signal is `status=Deleted/Removed`, not `schedule_id=None` |
| ABC Liquor Store 23 | 40803 | 16 | **False** | 1 | 1 | 0 | **A** — customer inactive, schedule alive, cameras still active |
| Cimino Electric | 41260 | 10 | True | 1 | **1** | 0 | **C** — schedule alive but no NR activity. The user's "running but no patrols" symptom |
| ABC Liquor Stores 18-28 | 40792-40803 (10 stores) | 188 cameras total | mixed (6 inactive, 4 active) | each has 1 schedule | mostly alive | 0 | **A** + **C** mix |
| Site 1 (largest) | 35829 | 100 | True | 5 | 0 | 3 (+2 paused) | **B + D** — biggest single customer, all schedules either Deleted or Paused |
| 400 North Ashley | 35878 | 18 | True | 3 | 0 | 3 | **B** — 3 schedules all status=Deleted/Removed, no alive ones |
| 400 North Ashley (different cid) | 37744 | 20 | True | 3 | **3** | 0 | **C** — 3 alive schedules but no NR activity |
| AutoPatrol-Live | 40672 | 28 | True | 1 | 1 | 0 | **C** |
| hanwha 2 | 46560 | 6 | True | 2 | 1 | 1 | **Confirmed-active in NR** (Processing path, 203 events/7d) |
| hanwha 3 | 46460 | 14 | True | 3 | 1 | 2 | **Confirmed-active in NR** (Processing path, 143 events/7d) |
| Site A | 36799 | 42 | True | 5 | 1 | 3 (+1 paused) | **Confirmed-active in NR** (Processing path, 5 events/7d — note: thin) |

The 3 confirmed-active customers carry **62 cameras out of 1,637** (3.8%). The other 96.2% — **1,575 cameras** — produced no NR patrol-server activity in the past 7 days.

## Diagnosis: why the existing pipelines miss this

### What the cleanup-Lambda DOES catch
Per `vms-connector/connector_factories/shared/cleanup_emitter.py:33` — `emit_no_patrols_signal` fires when:
- The connector pod **runs** AND
- Explicitly fails **3 times in a row** at one of 6 connector exit sites
- Reasons: `no_patrols` (empty Immix patrol list), `error` (non-OK Immix response), `exception`, `site_disabled` (puller `on_init_error`)

DDB counter increments per emit; threshold = `max(3, 48h / cadence_hours)`; counter TTL of `max(threshold × cadence × 2, 72h)` resets when emits stop.

### What it MISSES (Categories A, B, C above)

1. **Schedules whose cronjob was never created or got deleted** — no pod → no emit → counter never increments → invisible.
2. **Schedules where the connector succeeds at fetching from Immix but `autopatrol-server` never gets the SQS job** — broken SQS write, the connector "succeeded" so no failure emit.
3. **Cameras that exist in admin DB but have no associated cronjob/pod scheduled** — schedule_status alive in admin but K8s doesn't know about it.
4. **Sites where the connector emits "patrols ready" but downstream `autopatrol-server` analysis never logs** — SQS DLQ silently absorbing the job.
5. **Customers with `customer.active=False` but `cameras.active=True`** — admin-side propagation gap (Cohort A from the audit command's design).
6. **Schedules with `status=Deleted/Removed AND is_deleted=False`** — the Cohort B class, but using the right signal (NOT `schedule_id=''` which the audit command currently filters on).

### Why the audit_autopatrol_state mgmt command also misses this

The audit command's Cohort B definition (`schedule_id=''` OR `IS NULL`) returned **0 rows** on prod (run via PR #2389 → ECS run-task on 2026-05-01T16:10Z). The `schedule_id` field is non-null CharField populated with UUIDs from Immix; "orphan" is a different axis entirely.

The audit command needs to redefine Cohort B as `schedule_status IN ('Deleted', 'Removed') AND is_deleted=False`. With that change, the same query that returned 0 will return ~31 customers — the real orphan-schedule population.

### Cohort D (active customers with zero schedules) was correctly counted

Audit found 4 such customers; 3 were clearly test entries (`TRAVIS TEST`, `Alibi Vigilant - TEST - TO BE DISABLED`, `StoredVideo`), 1 (`CC260` cid=41798) might be real. This category is small + tractable; not the dominant problem.

## Path forward

### Short-term (within 1 week)

1. **Fix audit_autopatrol_state Cohort B/C definitions.** Replace `schedule_id=''` with `schedule_status IN ('Deleted', 'Removed') AND is_deleted=False`. This unlocks the ~31-customer "real orphan" population for the reconcile-patch design. Branch off staging, single-line change to filter; ship through release-train.

2. **Add a "Category C" (silent-but-alive-schedule) cohort to the audit command.** This requires joining admin-DB state with NR signal, which is harder than a pure DB query. Two paths:
   - **Lighter:** add a `--site-ids-with-activity '36799,46560,46460,...'` flag to the audit command. Operator feeds in the NR-derived list; command outputs customers whose schedules are alive but whose admin pk is NOT in the activity list.
   - **Heavier:** build a new admin endpoint `GET /api/auto_patrol/silent_customers/?since=7d` that runs the diff internally. Requires NR API integration on the admin side.

3. **One-time DB patch (`manage.py reconcile_autopatrol_state`)** — armed with the corrected Cohort B definition, soft-delete the ~31 customers' Deleted/Removed schedules, then per the existing `disable_tenant`-style cascade (or a new "cascade per customer when last alive schedule deletes") propagate to cameras and group.

4. **Cohort A action** — for the 11 `customer.active=False` cases, decide policy: cascade-disable cameras automatically? Manual review? Use the §16 disable_tenant endpoint per-customer? Trivial fix in scope; just needs the call.

### Medium-term (within 1 month)

5. **New propagation hook in admin: `Customer.active=False → cameras follow`.** Extend the existing pre_save signal at `customer_model.py:2212` (currently broadcasts `site_disabled` event) to also set `is_deleted_event=True` on cameras and soft-delete them. Feature-flagged for safe rollout. See [[2026-04-30_data-model-cascade-semantics]] for the design.

6. **New propagation hook: "last alive schedule deleted → cascade-disable customer."** Add `@receiver(post_delete, sender=AutoPatrolSchedule)` that checks `customer.autopatrol_schedules.filter(is_deleted=False, schedule_status__in=['Active','Awaiting']).count() == 0` and triggers the same cascade as `disable_tenant`. Critical: must NOT loop with `customer.delete()` chain (verify the existing chain doesn't delete schedules).

7. **Per-site silence detector.** A new EventBridge-scheduled Lambda that:
   - Polls `autopatrol-server` NR query for site_ids with activity in last 24h
   - Compares against admin's set of customers with alive schedules
   - For mismatches > 24h, increments a DDB counter (mirroring the cleanup-Lambda pattern)
   - At threshold, emits a `silent_site` SQS message that triggers cascade-disable
   
   This catches Categories C and D directly. **Bigger lift (~1 week), but it's the only way to catch case 1-4 in the "What it misses" list above.**

### Long-term (architecture)

8. **Reconsider whether the cleanup-Lambda's "connector emits failure" trigger is the right primitive at all.** The fundamental issue is that it depends on the connector RUNNING to know there's a problem. A better signal: K8s cronjob existence + last-run timestamp directly. If a customer has alive schedules but no recent cronjob run, that's a definitive silence signal that doesn't require the connector to participate. This is a design conversation — not a fix to ship — but worth having before the next cycle of patrol-pipeline work.

9. **Add per-camera activity** to autopatrol-server's log line. Currently logs `site_id` only — would need a connector-side change to also include `camera_id` in the SQS message and the log line. Then we can do real per-camera silence detection without needing the customer→cameras inference. **Probably not worth doing for this audit — site-level is enough — but useful for fine-grained alerting later.**

## Jira ticket draft

```
Title: AutoPatrol fleet-wide silence — 1,400+ cameras across 116 customers not producing patrols

Type: Bug / Investigation
Priority: High
Component: autopatrol, cleanup-lambda, admin-api

Description:
Audit on 2026-05-01 of all active autopatrol/VCH cameras in prod admin
showed 1,637 cameras across 119 customers, but only 6 distinct sites
(3 confirmed admin pks) produced patrol activity in NR over the last 7
days. ~1,400+ cameras are silent. Existing cleanup-Lambda
(`no_patrols_24h`) catches only ~5% of these, due to architectural
limits in its trigger logic.

See KB synthesis: topics/autopatrol/notes/syntheses/2026-05-01_silent-cameras-diagnosis.md

Acceptance criteria:
- [ ] Audit command's Cohort B redefined (schedule_status IN ('Deleted','Removed') AND is_deleted=False)
- [ ] One-time reconcile_autopatrol_state patch run on the ~31 Cohort B customers
- [ ] Cohort A propagation hook implemented (Customer.active=False → cameras follow)
- [ ] Cohort B propagation hook implemented (last alive schedule deleted → cascade)
- [ ] Per-site silence detector Lambda design ADR written (deferred to next cycle if scope-too-big)
- [ ] Customers with active=False status hand-cleaned via §16 disable_tenant

Linked tickets: §16 admin-side state propagation work
```

## Cross-references

- [[2026-04-30_admin-propagation-handoff]] — original §16 follow-up that surfaced 3 named customers, which expanded into this fleet audit
- [[2026-04-30_autopatrol-state-audit]] — audit_autopatrol_state command synthesis; current Cohort B definition (`schedule_id=''`) is wrong and needs the redefinition above
- [[2026-04-30_data-model-cascade-semantics]] — admin model cascade semantics, esp. the 8 verified findings on signal + propagation behavior
- [[2026-04-17_no-patrols-emit-points]] — the 6 connector exit sites where cleanup-Lambda gets its data
- [[2026-04-17_stale-schedule-cleanup-design]] — original cleanup-Lambda design (now seen to have the gap above)
- `vms-connector/connector_factories/shared/cleanup_emitter.py:33` — `emit_no_patrols_signal`
- `vms-connector/connector_factories/autopatrol/autopatrol_factory.py:104` — patrol-ready log line
- ECS run-task `65c4c79505fe4880b0f9e07065f850ac` — the prod audit task that produced these numbers
- NR query results (anonymized): autopatrol-server 7d FACET `site_id` returned 6 distinct: 36799, 46460, 46560, 10003, 10026, 10111

## Deeper investigation — 2026-05-01 follow-up

After the headline numbers landed, we dug into the 78 customers with alive schedules but no NR activity (Category C above). Three new data sources joined:

### K8s cronjob inventory

`kubectl get cronjobs -n rearchitecture | grep autopatrol` on inference-eks-Ny9n (US prod):

- **27 autopatrol cronjobs total** (19 prod + 8 staging)
- **13 distinct customer pks have ANY autopatrol cronjob deployed**
- 19 distinct schedule pks deployed (prod-only)

Cross-referenced against the 97 admin schedules with `status=Active AND is_deleted=False`:

| | Count |
|---|---|
| Admin-Active schedules | 97 |
| K8s prod cronjobs | 19 |
| **Overlap (admin-Active AND K8s-deployed = "working")** | **18** |
| **Admin-Active but NOT in K8s (deployer failed)** | **79** |
| K8s-deployed but NOT admin-Active (zombie cronjob) | 1 (sched_pk=295) |

**81% of admin-Active autopatrol schedules have no corresponding K8s cronjob.**

### K8s pod state for the 18 "working" set

Among the deployed cronjobs, recent pod runs show:

- Customer 35831 — **3 of 4 pods are `InvalidImageName`** (cronjob deployed with a tag the registry doesn't have)
- Customer 35830-309 — **3 retries all `Error`** (running but crashing on every invocation)
- Customers 36799, 37837, 41178, 46560, 38316 — `Completed` exits (working as designed)

So even the "working" set has internal failures: ~30% of the deployed cronjobs aren't actually completing. Real-truly-working count is closer to ~12 schedules out of 97 (12%).

### Immix probe — `scripts/ops/immix_probe_deployer_failed.py`

For each of the 79 deployer-failed schedules, ask Immix's API "what status is this schedule in your system?". Result:

| Immix status | Count | What this means |
|---|---|---|
| **Active** | **51** | **Immix says it's running. Admin agrees. K8s has no cronjob. Pure deployer failure.** |
| Deleted | 14 | Admin's status drifted from Immix. The Cohort B class with the *correct* signal (`schedule_status='Deleted' AND is_deleted=False`). |
| NOT_FOUND (401 "No Tenant Found" / "No Active Contract Found") | 9 | Zombie tenants — Immix has lost the contract entirely; admin still has customers + schedules under it. |
| Paused | 4 | Customer-controlled silence; admin lags Immix. |

**51 schedules** are the smoking-gun deployer-failure population. Tenant `7b533b5a-a071-43ab-beb9-fb1cb9ea4ce1` (ABC Liquor) carries 37 of the 79 deployer-failed schedules (47% concentration in one tenant).

### Failure mode attribution per silent customer

Putting it all together for the ~110 silent customers (out of 119 total):

| Mode | Count | Detection method | What's broken |
|---|---|---|---|
| **Deployer failed (clean)**: admin Active + Immix Active + no cronjob | **51 schedules** | K8s diff + Immix probe | The deployer is silently dropping schedule deploys. **This is the dominant production bug.** |
| **Schedule status drift**: admin Active + Immix Deleted | 14 schedules | Immix probe | Onboarder lifecycle pass isn't catching this — admin row never gets the status update from Immix. |
| **Zombie tenants**: admin Active + Immix says no tenant | 9 schedules across 3+ tenants | Immix probe (401 response) | Onboarder isn't catching tenant disappearance + cascading to admin. |
| **Paused (correctly silent)** | 4 schedules | Immix probe | Not a bug (D class). |
| **Image broken**: cronjob deployed but `InvalidImageName` | ~3 pods | K8s pod state | Deployer used wrong image tag at create time. |
| **Pod crashes**: cronjob runs, exits Error | ~3 pods | K8s pod state | Connector code bug specific to that customer. |
| **Customer-active=False (audit Cohort A)** | ~11 customers (~150 cameras) | Admin-only audit | Admin propagation gap; customer marked inactive but cameras live. |

### Does the existing audit/scan capture this?

**No.** The `audit_autopatrol_state` mgmt command (PR #2389) only queries the admin DB. It can detect:
- Cohort A (customer.active=False but undeleted)
- Cohort C (customers with only orphan-status schedules) — once Cohort B's filter is corrected to `schedule_status IN ('Deleted','Removed')`
- Cohort D (active customers with zero schedules)

It **cannot** detect:
- Schedules that are configured-active in admin but have no K8s cronjob (the 51 + 79 sets above)
- Cronjobs that exist but are persistently failing (image broken, pod crashing)
- Zombie tenants (Immix lost the contract)

To capture the deployer-failed set, the audit needs a **K8s join** OR a **per-schedule "deploy state" field maintained by the deployer**. The simplest mechanical addition: a new mgmt command `find_undeployed_schedules` that exec's into the K8s cluster (or queries the connector_deployer service) and returns the diff.

### Deployer retry mechanism (sketch — proposed for admin)

The user proposed admin as the home for retry. The natural shape:

1. **Periodic Django-Q task** running every N minutes/hours (e.g. every 30 min) that:
   - Queries admin's `AutoPatrolSchedule.objects.filter(is_deleted=False, schedule_status__in=['Active','Awaiting'])`
   - Cross-checks against K8s state via the existing `connector_deployer` HTTP API ([[connector-deployer|connector deployer]] has a "list deployed cronjobs" endpoint, or can be queried per-schedule)
   - For schedules missing in K8s: re-trigger deploy
   - Track retry count + last-attempt timestamp on the schedule row (new fields: `last_deploy_attempt_at`, `deploy_retry_count`, `deploy_last_error`)
   - At max retries (e.g. 5), surface to a ticket/alert; don't infinite-loop

2. **Note on K8s shape**: the [[connector-deployer|connector deployer]] creates either CronJobs (for recurring schedules) or one-off Jobs (for ad-hoc patrols). The retry needs to handle both. Naming pattern is `connector-{customer_pk}-autopatrol-{schedule_pk}-chm-cronjob`. Job/CronJob distinction is on the deployer's choice based on schedule shape.

3. **Risk**: re-triggering deploy on a schedule that the deployer is failing on for a structural reason (e.g. customer FK gone, customer.active=False) just spins. Need preflight: skip retry if customer is inactive, or if previous attempts errored on a known-permanent reason.

4. **Surface**: Slack alert on `deploy_retry_count >= max_retries`. Admin UI column on the schedule list showing deploy state.

This is **a multi-day feature**, not a quick patch. Recommend: ship the diagnostic command first (find_undeployed_schedules), then design + ship the retry as a separate workstream.

### The deployer-side question (separate Jira/GH issue)

The deployer itself needs to be investigated: why are 51 schedules that should be deployable not getting deployed? Hypotheses:
- Admin's "deploy" call to connector_deployer succeeds with HTTP 2xx but K8s create silently fails downstream
- connector_deployer drops requests on retry (e.g. K8s API rate limit)
- Schedule creation in admin happens before the deploy trigger fires; the trigger never runs
- Something in connector_deployer was rolled back or a misconfig dropped some cronjobs en masse

Need to grep the connector_deployer repo for the deploy handler + add observability (the audit shows the symptom; we need cause).

## Updated path forward (replaces the prior 9-action list)

| # | Action | Owner / where |
|---|---|---|
| **1** | **HIGH-priority issue cut**: [aegissystems/connector_deployer#164](https://github.com/aegissystems/connector_deployer/issues/164) — 51 admin+Immix-Active autopatrol schedules with no K8s cronjob. Production silence at scale. | aegissystems/connector_deployer |
| 2 | Manually re-trigger deploy for the 51 known-good schedules — admin-side script + the connector_deployer's `POST /deploy` endpoint. [[watch-entity|Watch]] for which succeed vs fail. Tells us if it's a cold-start problem (works on retry) or a structural problem (fails on retry too). | [[actuate_admin]] one-off mgmt command |
| 3 | Fix audit_autopatrol_state Cohort B (the existing PR chain): redefine to `schedule_status IN ('Deleted','Removed') AND is_deleted=False`. Catches the 14 Drift class. | [[actuate_admin]] (in flight) |
| 4 | New mgmt command `find_undeployed_schedules`: queries K8s (or connector_deployer) for the deploy-state diff. Catches the 79 set going forward. | [[actuate_admin]] |
| 5 | Run the §16 disable_tenant cascade for the 9 zombie tenants (Immix `No Tenant Found` 401). Onboarder lifecycle pass should already be doing this; verify it didn't run for these. | [[actuate_admin]] |
| 6 | Cohort A propagation hook: `Customer.active=False → cameras follow`. ~150 cameras affected. | [[actuate_admin]] |
| 7 | Deployer retry feature in admin: periodic Django-Q task scans for schedules missing in K8s, re-triggers deploy, tracks retry count, alerts on max-retries. **Multi-day feature.** | [[actuate_admin]] |
| 8 | Per-site silence detector Lambda (item #7 from prior list, kept): catches the case where deployer succeeds but autopatrol-server never sees the patrol. | new infra |
| 9 | Onboarder fix: investigate why the 14 status-drift schedules + 9 zombie-tenants weren't caught by the lifecycle pass. | autopatrol_onboarder |

## Redeploy attempt 2026-05-01T20:01Z — pivots the remediation plan

Tested the "if we redeploy the 51 known-good schedules, K8s will pick them up" hypothesis. Ran an admin one-off ECS task (`1e7178ac22d3425c8196561719217315`) that called `AutoPatrolSchedule.deploy()` for 10 of the 51 (pks 4, 137, 138, 139, 141, 156, 159, 200, 894, 1049 — diverse tenants).

**Result: zero new cronjobs in K8s.**

Every single deploy call:
- Reached connector_deployer at `https://ingress.actuateui.net/connector/deploy/chm`
- Returned **HTTP 200 with body `b'null'`**
- Took ~100ms (no timeout)

The deployer is **silently no-op'ing prod deploys** while returning success status. Admin's `deploy()` method has no way to detect this — to it the call succeeded.

### Secondary finding — stage-field data integrity

Schedule payloads showed varying `stage` values:

| `stage` value | count | should deploy to prod K8s? |
|---|---|---|
| `rearch` | 7 | Yes — prod rearchitecture branch |
| `staging` | 2 (cid=35832) | No — routes to staging cluster |
| `feature/autopatrol-cleanup-emit` | 1 (cid=35831) | No — feature branch artifact |

For the 3 non-`rearch` cases, a 200/null no-op may be intentional (deployer correctly refusing to put a non-prod-tagged schedule into prod). That's an admin **data integrity bug** — those customers' deployment_phase is pointing at non-prod stages.

For the 7 `rearch`-tagged ones, the deployer is silently dropping legitimate prod deploys. **That's the real deployer bug.**

### Pivots to remediation

1. **Retry-in-admin won't unstick this.** Admin already gets HTTP 200; no signal to retry on. The diagnostic mgmt command is still valuable (visibility), but auto-retry in admin won't fix the symptom.
2. **The deployer fix is upstream** of any other action. Until connector_deployer either creates cronjobs for `rearch` schedules OR returns a non-200 on no-op, calling `deploy()` repeatedly is thumping a black hole.
3. **The 41 remaining redeploys are paused** — same outcome expected. Skip until deployer fix lands.
4. **Three new follow-ups:**
   - connector_deployer: identify the no-op code path; return structured response. (Now in [issue #164](https://github.com/aegissystems/connector_deployer/issues/164) update comment.)
   - [[actuate_admin]]: investigate why customers have `stage='staging'` / `stage='feature/...'` in prod. Possibly stale data from staging→prod migrations that didn't update the field. Catalog: cid=35831, 35832 (sched_pks 4, 138, 159).
   - [[actuate_admin]]: build the diagnostic mgmt command (`find_undeployed_schedules`) — reads admin schedules, calls connector_deployer's "list deployed" endpoint (or queries K8s directly), prints diff. Without this, operators have no way to see the gap. **Highest immediate-value admin-side action.**

## CORRECTION 2026-05-01T20:30Z — deployer-failed finding was wrong

**The "79 deployer-failed schedules" finding was a measurement error on my end.** I was grepping K8s with `grep autopatrol`, which excludes VCH (Visual Camera Health) cronjobs. VCH schedules deploy as `connector-{cid}-vch-{spk}-chm-cronjob`, not `connector-{cid}-autopatrol-{spk}-chm-cronjob`.

**Corrected numbers:**

| | Wrong filter | Corrected (autopatrol+vch) |
|---|---|---|
| K8s CHM cronjobs | 19 | **102** |
| admin-Active schedules in K8s | 18 | **97 (all of them)** |
| "deployer-failed" | 79 | **0** |
| K8s zombie (cronjob without admin-Active match) | 1 | 5 |

**The redeploy attempt I ran DID create cronjobs** — they just landed under the VCH naming pattern. The 200/null response from connector_deployer is the success path of `create_chm_cronjob()`, which returns None implicitly (FastAPI defaults to 200/null).

GH issue [#164 was retracted](https://github.com/aegissystems/connector_deployer/issues/164#issuecomment-4361422383) with the correction.

### So what's the REAL cause of fleet silence?

- 97 admin-Active schedules — all deployed in K8s
- BUT only 6 distinct site_ids in `autopatrol-server` Processing log path over 7 days

Three remaining hypotheses:

1. **Pod-level failures** — `InvalidImageName`, `Error` exits. K8s shows several:
   - cid=35831 (Axis site) — 3 of 4 recent pods `InvalidImageName`
   - cid=35830-309 — 3 consecutive `Error` exits
   - Need a fleet-wide pod-state survey
2. **Empty `cronjob_expression`** — many redeploy payloads showed `cronjob_expression=''`. The deployer must derive a schedule from `cadence` (e.g., `cadence: 6` → every 6 hours). Worth verifying that derivation actually produces a working cron in the K8s CronJob spec.
3. **`autopatrol-server` consumption gap** — connectors successfully fetch + send to SQS, but autopatrol-server doesn't log `Processing patrol_id` for some reason. Could be DLQ silently absorbing, log-level filter, or a different log path being used.

### Stage-field data integrity (still real)

Independent of the above, some schedules have `stage='staging'` or `stage='feature/...'` because their customer's `deployment_phase` field is `STAGE` or `CUSTOM`. The deployer correctly creates cronjobs for these, but the image tag is non-prod (e.g., `:stage`, `:custom`, or even `:feature/autopatrol-cleanup-emit` which K8s would reject as `InvalidImageName`). That's the source of the `InvalidImageName` failures in (1).

The `connector_deployer.src.methods.__get_image_name()` function (read 2026-05-01) maps `stage` to ECR repo + tag:

```python
"prod":      ("arm_connector",         "connectors",         tag),
"rearch":    ("arm_connector_rearch",  "connectors_rearch",  tag),
"dev":       ("arm_connector_dev",     "connectors_dev",     tag),
"rearchdev": ("arm_connector_rearch",  "connectors_rearch",  "rearch-dev"),
"staging":   ("arm_connector_rearch",  "connectors_rearch",  "stage"),
"custom":    ("arm_connector_rearch",  "connectors_rearch",  "custom"),
```

If `stage` isn't in this dict (e.g., `feature/autopatrol-cleanup-emit`), it falls through to `repo:{stage}` which produces an invalid ECR tag (slashes aren't allowed in tags). That cronjob can never start a pod successfully.

**Fix:** for the schedules with `customer.deployment_phase IN ('STAGE', 'CUSTOM')` running in prod admin DB, audit and either set them to `PROD` (default → `rearch` stage) or remove them. The catalog ECS task `5348e85240a5412b95b7158dd2775a82` was kicked off to enumerate the affected customers.

## Firebat alarms (follow-up — per user request)

Add to `~/work/local_network_scripts/files/` two new daily-fired NRQL/admin queries:

1. **admin-Active vs K8s mismatch** — runs daily, alerts if any admin-Active schedule isn't in K8s. Equivalent of "the deployer-failed catalog" but as a continuous monitor. Should always be 0 if everything is healthy.
2. **K8s zombie cronjobs** — alerts on K8s cronjobs without a matching admin-Active schedule. Currently 5; should ideally be 0 (those are stale; should be cleaned up by the cleanup-Lambda or manual prune).
3. **admin-vs-Immix drift** — schedules with `status=Active` in admin but `Deleted/Removed/NOT_FOUND` in Immix. Caught some of these in the probe; ongoing monitor would catch new drift fast.

Each runs once a day at 6am UTC (or whatever fits the morning ritual). Output to `~/Documents/worklog/dashboard/sink/observations.jsonl` for the dashboard.

## SECOND CORRECTION 2026-05-01T20:50Z — CHM ≠ autopatrol patrol runner

**The cronjobs aren't autopatrol patrol runners. They're Camera Health Monitoring (CHM).**

`/connector/deploy/chm` is the camera-healthcheck deploy endpoint. The pods log "CHM healthcheck completed", send `event_type: site_product_ended, act_a: healthcheck` events, run connectivity checks. They don't go through `autopatrol-server`'s Processing log path because that's a different pipeline.

All 97 admin-Active schedules in the audit have `patrol_type='VisualCameraHealth'`. **Zero have `patrol_type='AutoPatrol'`**. So:

- 102 CHM cronjobs in K8s = the camera-health-check schedulers, working as designed
- The 6 site_ids in NR `autopatrol-server` are the actual autopatrol (scene-patrol) customers, a small subset
- The diff I computed was between two different pipelines

The user's "1,415 cameras → only 500-600 active" premise is measuring something other than `autopatrol-server` Processing. Need to re-define what "active" means before re-running the audit. Likely candidates:
- Per-camera health-check pass/fail rates from CHM pod outputs (camera-level connectivity events)
- A per-camera dashboard field I haven't located yet
- Frame-upload counts to S3

### Stage-field data integrity (the actually-real follow-up)

The catalog ECS task (`5348e85240a5412b95b7158dd2775a82`) returned the deployment_phase distribution across the 119 active autopatrol/VCH customers:

```
{'REARCH': 100, 'STAGE': 13, 'CUSTOM': 2, 'DEV': 1}
```

**16 of 119 customers have non-default deployment_phase**, which means their schedules deploy with non-prod image tags:

| Phase | Count | Image tag generated |
|---|---|---|
| `STAGE` | 13 | `arm_connector_rearch:stage` (works if stage tag exists in prod ECR) |
| `CUSTOM` | 2 | `arm_connector_rearch:{cv_tag}` (e.g., `feature/autopatrol-cleanup-emit` — invalid ECR tag) |
| `DEV` | 1 | `arm_connector_dev:None` (works if dev image exists) |

The `CUSTOM` cases with feature-branch tags (e.g., cid=35831 `Axis site` with `cv_tag='feature/autopatrol-cleanup-emit'`) are **the real cause of `InvalidImageName` pod failures**. Slashes aren't valid in ECR tags, so the pod can never start.

Action item: catalog all customers with non-default deployment_phase, decide policy:
- For STAGE: revert to PROD/REARCH if accidentally tagged
- For CUSTOM with stale feature-branch cv_tag: clear cv_tag (revert to default `:custom` tag)
- For DEV: same — usually shouldn't be in prod admin

### What's actually real after all the corrections

Verified findings, in priority order:

1. **Stage-field data integrity** — 16 customers with non-default `deployment_phase`. Probably the real source of `InvalidImageName` pod failures. Worth a one-time cleanup PR.
2. **schedule_status drift (Cohort B with the right filter)** — 14 admin-Active schedules show `Deleted/Removed` in Immix. Admin's lifecycle pass isn't catching this. Onboarder bug.
3. **Zombie tenants** — 9 schedules under tenants Immix says don't exist. Onboarder fix territory.
4. **Cohort A** — 11 customers with `active=False` but cameras still active. Admin propagation gap.
5. **Firebat alarms** — daily NRQL/admin-DB checks for admin↔K8s↔Immix consistency. Three monitors per the user's request.

NOT real:
- "Deployer is silently dropping deploys" — false. Deployer works.
- "79 deployer-failed schedules" — false. Was a grep error.
- "Fleet-wide silence in autopatrol pipeline" — undetermined; need to redefine "active" before re-measuring.

GH issue [#164](https://github.com/aegissystems/connector_deployer/issues/164) was retracted with both corrections noted in the comments. Marked safe-to-close.

## Final diff — audit vs NR pod activity (2026-05-01T21:00Z)

After the second correction (CHM cronjobs ARE the autopatrol/VCH patrol runners; I overcorrected earlier), ran the right NR query: distinct customer pks producing pod activity in `Connector-EKS` for `*-chm-cronjob-*` containers (filtered to autopatrol/vch integration patterns), 7-day window.

| | Count |
|---|---|
| Audit customers (active autopatrol/VCH cameras in admin) | 115 distinct cids |
| NR-active customers (pod activity in last 7d) | 166 distinct cids |
| **Working — in audit AND in NR** | **78** |
| **Silent — in audit but NOT in NR (the gap)** | **37 customers** |
| Extras — in NR but not in audit | 88 customers |

**The 37 silent customers are the primary investigation target.** Their cameras are listed in the CSV as active, schedules exist, K8s cronjobs are deployed (per the corrected count of 102), but no pod activity in 7d.

The 88 "extras" in NR are likely VCH-only customers with cameras that didn't pass the audit's `(active=True AND is_deleted=False AND integration in [autopatrol,vch])` filter — could be cameras flagged inactive in admin but still scheduled, or cameras with different filter exclusions. Lower priority for this investigation.

Files:
- `/tmp/audit_not_in_nr.txt` — 37 cids of silent customers
- `/tmp/nr_not_in_audit.txt` — 88 cids of NR-active extras

The Jira ticket draft (ready-to-paste, no Atlassian write access from this session) is at `/tmp/jira_silent_cameras_ticket.md`. Should land in project AUTO.

## Status

**Investigation complete (with corrections) 2026-05-01.** All catalog data captured at:
- `/tmp/deployer_failed_schedules.csv` — 79 admin-Active-but-not-deployed schedules with full per-schedule fields
- `/tmp/immix_probe_results.csv` — Immix state for each
- `/tmp/autopatrol_cronjobs.txt` — K8s cronjob inventory (US prod)

The `[[2026-04-30_autopatrol-state-audit]]` synthesis note still has Cohort B defined with the empty-string filter — that note's TBD section should be updated to reference this synthesis as the corrected source of truth. The Jira ticket from the prior section should be **upgraded to High-High priority** based on the 51-schedule deployer-failure finding.
