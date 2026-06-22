---
title: "AutoPatrol Deferred Backlog"
type: entity
topic: autopatrol
tags: [autopatrol, backlog, deferred, mark, work-plan, immix, billing]
created: 2026-05-07
updated: 2026-06-03
author: kb-bot
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/autopatrol/notes/syntheses/2026-05-07_cleanup-lambda-state-matrix-verify.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cohort-b-no-backfill-decision.md
  - topics/billing/_summary.md
  - topics/billing/_todos.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/entities/billing-deferred-backlog.md
  - topics/billing/notes/entities/billing-events-catalog.md
  - topics/billing/notes/syntheses/2026-05-11_billing-pain-post-mortem.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
  - topics/personal-notes/notes/concepts/2026-05-11_billing-and-followups-handoff.md
incoming_updated: 2026-05-27
---

# AutoPatrol Deferred Backlog

Work items related to AutoPatrol cleanup, cohort recovery, and admin-side cascade hygiene that have been **deferred** from active scope. Items live here when:

- a decision (do we deactivate? do we promote?) is pending team alignment
- the work is ready but not on Mark's critical path
- code is shipped but rollout is intentionally paused

Active AP work — anything still moving — stays in [[mark-todos]] under its own §N. This file holds the "decided to wait" tail. Promote back into mark-todos when a decision comes in.

> Companion to: [[todo-list|AutoPatrol Team Todo List]] (team-wide), [[mark-todos]] (Mark's active workstreams), [[autopatrol-cleanup-lambda]] (cleanup-Lambda entity).

## Index

| Item | Source §N | Status | Decision Owner | Decision Trigger |
|------|-----------|--------|----------------|------------------|
| [AP schedule-sync resilience (post-2026-06-03)](#ap-schedule-sync-resilience-post-2026-06-03) | 2026-06-03 incident | Interim fix shipped | Mark | Layer-2 promotion if next redeploy-suppression incident, or Layer-3 (NR instrumentation) lands independently |
| [§25 Cohort B no-backfill decision](#25-cohort-b-no-backfill-decision-archived-2026-05-07) | §25 archived 2026-05-07 | DECIDED — no backfill | Mark | Re-open if cohort grows or customer complaints surface |
| [§26 Cohort F + §16 hardening tail](#26-cohort-f--16-hardening-tail) | §26 deferred 2026-05-07 | Wait | Mark | PR #14 merge + first end-to-end classifier run |
| [§27 Group demotion PR 1](#27-autopatrol-group-demotion-pr-1) | §27 deferred 2026-05-07 | Wait | Mark + admin team | Ops manual-promotion volume becomes painful |
| [§3 Step F prod US scale-up](#3-step-f-prod-us-scale-up) | §3 (still active for verify) | Pause | Mark | After cleanup-Lambda verify pass holds |
| [§3 Step G prod EU](#3-step-g-prod-eu) | §3 (still active) | Wait on infra | Mark + infra | EU SQS + DDB + Lambda mirrors land |
| [§3 follow-ups: observability + SiteDisabledOrDisarmed](#3-follow-ups-observability--sitedisabledordisarmed) | §3 (still active) | Wait | Mark | After EU rollout dust settles |
| [§3 IaC drift: port CLI-provisioned infra to terraform](#3-iac-drift) | §3 backlog | Wait | Mark + infra | Background work; not customer-facing |
| [§16 Step 5 — re-enable path](#16-step-5--re-enable-path) | §16 archived; carryover | Wait | Mark | Real customer hits this case |
| [§16 Step 6 — disable_tenant permission_classes hardening](#16-step-6--disable_tenant-hardening) | §16 archived; carryover | Wait | Admin team | After bigger admin perms refactor |
| [Onboarder lifecycle log silence debug](#onboarder-lifecycle-log-silence-debug) | from §16 cascade aftermath | Wait | Mark | If lifecycle pass needed for new evidence |
| [Admin propagation hooks (schedule→customer→cameras)](#admin-side-propagation-hooks) | from §16 cascade aftermath | Wait | Admin team | After §25 backfill decision settles broader pattern |
| [Admin DB one-time reconcile mgmt command](#admin-db-one-time-reconcile-mgmt-command) | from §16 cascade aftermath | Wait | Admin team | After propagation hooks ADR |
| [Admin data-model cascade-semantics deep-dive doc](#admin-data-model-cascade-semantics-deep-dive) | from §16 cascade aftermath | Stub seeded | Mark | After admin-team alignment |
| [Comprehensive Immix tenant-failure census](#comprehensive-immix-tenant-failure-census) | from §16 cascade aftermath | Wait | Mark | When Immix engineering is ready to receive |
| [§16 cascade-on-suspended-detection design extension](#16-cascade-on-suspended-detection) | from §16 cascade aftermath | Wait | Mark | After lifecycle pass log silence resolved |
| [§17 vch_no_patrols stage→rearch promotion](#17-vch-no_patrols-promotion) | §17 — close to done | Wait on stage soak | Mark | Soak verdict |
| [Recalibrate connector_no_patrols_to_run_24h thresholds](#recalibrate-connector_no_patrols_to_run_24h-thresholds) | §17 follow-up | Wait | Mark | After PR #1662 reaches prod |
| [Cohort dashboard signals (cohort_b/c/f_cameras + lifecycle)](#cohort-dashboard-signals) | §26.5+6 | Wait on data source | Mark | Snowflake export script ships |
| [Past-week Jira closeout](#past-week-jira-closeout) | §26 admin chore | Wait | Mark | Backlog hygiene pass |
| [Immix zombie-tenants Jira ticket draft](#immix-zombie-tenants-jira-ticket) | rolled morning followup | Wait | Mark | When ready to engage Immix engineering |
| [Cleanup-Lambda canary across state matrix](#cleanup-lambda-canary-across-state-matrix) | §3 follow-up | Surfaced 2026-05-07 | Mark | Real customer case fires unexpectedly OR before next §3 code change |
| [Billing emit on crash / early-endrun paths](#billing-emit-on-crash--early-endrun-paths) | PR #1675 / #1680 / #1682 follow-up | Surfaced 2026-05-07 | Mark | After PR #1683 (rename + VCH started-fix) lands; investigate when crash patterns surface in fleet_error_top15 |
| [PR #1662 VCH no_patrols suppression verify](#pr-1662-vch-no_patrols-suppression-verify) | §17 / dashboard signal investigation | Surfaced 2026-05-19 | Mark | VCH share of `connector_no_patrols_to_run_24h` doesn't drop after rolling-restart fully rolls the #1662 image |
| [6 autopatrol pods looping empty queue](#6-autopatrol-pods-looping-empty-queue) | dashboard signal investigation 2026-05-19 | Surfaced 2026-05-19 | Mark | Count grows beyond 6, or any of these 6 sites becomes a customer escalation |
| [AP schedule settings regen-from-here capability](#ap-schedule-settings-regen-from-here-capability) | empty-metrics fix 2026-05-27 | Surfaced 2026-05-27 | Mark + admin team | Next time a schedule needs a settings-only regen and we're not at an admin UI |

---

## §25 Cohort B no-backfill decision (archived 2026-05-07)

**Decision:** Do **not** backfill the 31 customers / 353 cameras in Cohort B (cleanup-Lambda-disabled schedules with admin-active cameras). Cascade hook stays disabled (`AUTOPATROL_SCHEDULE_CASCADE_ENABLED=False`).

**Decision rationale:** see [[2026-05-07_cohort-b-no-backfill-decision]] for full ADR.

**Re-open conditions:**
1. Cohort B population grows materially (e.g. >50 customers / >500 cameras) without explanation
2. Customer-facing complaint that admin shows cameras as active for a customer they intended to delete
3. Storage/cost pressure from the orphan camera state

**What's already shipped, paused at the flag:**
- `actuate_admin#2406` (hotfix bundle including cascade hook) merged to main 2026-05-06; flag default `False`
- `actuate_admin#2405` (Mark's standalone cascade PR) → close as redundant
- `actuate_admin#2408` (`deactivate_customers_by_cids` mgmt command) — drafted, not merged; same code unblocks Cohort B + F3a if revived

**Resources:**
- [[2026-05-04_silent-camera-diagnosis]] — audit data
- [[2026-05-05_cohort-b-backfill-runbook]] — DRY-RUN + APPLY procedure (kept current; revive if decision flips)
- [[2026-05-04_admin-schedule-cascade-design]] — design doc
- `actuate_admin#2406` — merged hotfix (cascade hook behind flag)

---

## §26 Cohort F + §16 hardening tail

**Status:** PR [autopatrol_onboarder#14](https://github.com/aegissystems/autopatrol_onboarder/pull/14) (cohort-F deep classifier + per-customer tracker) drafted off `feat/cohort-f-deep-classifier`. Not blocking anything customer-facing.

**Why deferred:** Cohort F was reframed 2026-05-06 — see [[2026-05-06_cohort-f-investigation]]. 22 of 45 customers are Snowflake-ingestion gaps (out of connector scope); 23 are real connector-side billing gaps largely already addressed by `vms-connector#1675` (billing-emit invariant, merged to stage 2026-05-06). The deep classifier work continues to have value for ongoing audits, but doesn't unblock anything for next 1-2 weeks.

**Open work (when revived):**
- Merge PR #14 once team-reviewed
- First end-to-end classifier run with `NEW_RELIC_USER_KEY` + fresh Snowflake CSV
- Snowflake export query check-in (`scripts/ops/fetch_silent_cameras_csv.py`) — table-shape blocker; needs guidance from data team
- Investigate staging-suffix prod customers (F1/F2 sub-cohort)
- §16 Step 5 re-enable path (see below — separate item)
- §16 Step 6 `disable_tenant` permission_classes hardening (see below)

**Resources:**
- [[2026-05-04_silent-camera-diagnosis]], [[2026-05-01_silent-cameras-diagnosis]]
- [[2026-05-06_cohort-f-investigation]] — reframe
- `autopatrol_onboarder/scripts/ops/diagnose_silent_cameras.py`

---

## §27 AutoPatrol group demotion PR 1

**Status:** Design complete, code change scoped, twice-deferred from active scope.

**Why deferred:** Stop creating autopatrol groups as `parent_account=True`. New autopatrol groups become sub-groups under "Auto Patrol"; ops manually promotes when needed. Smaller fix than email-fallback. Original incident (US contract POST 100% failing 7+d) resolved via `actuate_admin@~16:04Z 2026-05-05` deploy fix that addressed the unique-constraint collision; the demotion is preventative for the next round. Not blocking active prod traffic.

**Re-open trigger:** ops reports manual-promotion volume becoming painful, OR new contract-POST collision pattern emerges.

**Open work (when revived):**
- PR off `actuate_admin/staging`:
  - `api/serializers/integrations/autopatrol/autopatrol_base_sync.py::process_tenant_data` — drop `parent_account: True` from filter; flip default to `False`
  - `api/serializers/group/group_view.py:65::list_patrol_group_ids` — relax filter to `tenant_id__isnull=False`
  - `inframap/management/commands/demote_autopatrol_dup_groups.py` (default dry-run + `--apply`)
  - 5 unit tests per design doc
- Stage canary verify
- Prod rollout via release train
- Mgmt command in prod with `--apply`

**Resources:**
- [[2026-05-05_admin-deploy-customer-name-incident]] — incident synthesis
- [[2026-05-05_autopatrol-group-demotion-design]] — design doc

---

## §3 Step F prod US scale-up

**Status:** Gate cleared (Step E.3 closed at 4-day window). One-flag flip.

**Why deferred:** "Sites stay as-is per user" 2026-05-06. The cleanup pipeline runs on stage at full prod-equivalent volume already; flipping prod is a volume-only event (no new criticality). Re-evaluate after next cleanup-Lambda verify pass holds.

**Open work (when revived):** Single PR in `kubernetes-deployments` flipping `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` on prod connector pods. Lambda already consumes from prod queue.

---

## §3 Step G prod EU

**Status:** Wait on net-new infra in `eu-west-1` (SQS + DDB counter table + Lambda mirrors).

**Why deferred:** Separate track from US. IAM policy v2 already has EU ARNs pre-granted. Infra work hasn't been queued.

---

## §3 follow-ups: observability + SiteDisabledOrDisarmed

**Open items:**

- **Immix error-pattern observability** — instrument `_check_immix` with structured log fields + `AutoPatrolImmixResponse` NR custom event so future Immix-side response-shape changes surface in aggregation rather than silent retry loops. See [[2026-04-23_immix-api-error-patterns]].
- **SiteDisabledOrDisarmed routing** — extend cleanup signal to also route this Immix response. Requires care: SiteDisabledOrDisarmed can be legitimately transient (business-hours arming). Design needed: longer threshold window than "no patrols", separate event_type, share or split DDB table. Not blocking current rollout — layer on after stage bake.

---

## §3 IaC drift

**Status:** Real resources live in prod/us-west-2, CLI-provisioned 2026-04-20: 4 SQS queues, 1 DDB counter table, 2 Lambdas, 2 IAM roles, 2 DLQ alarms, 1 Function URL. Substantial PR; not blocking functionality.

**Resources:** [PR #69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69), [[2026-04-29_iam-tf-import-pattern]].

---

## §16 Step 5 — re-enable path

When a tenant is unsuspended, mirror the existing schedule-side re-enable Function URL — needs a sibling tenant-cascade-reenable code path. Probably small extension of the existing re-enable Lambda. Defer until a real customer hits this case.

---

## §16 Step 6 — disable_tenant hardening

`api/serializers/integrations/autopatrol/autopatrol_view.py:86` lacks explicit `permission_classes` — currently inherits `CustomGenericViewSet` defaults. Tighten to `[CheckModelPermission]` or dedicated `IsLambdaServiceAccount` permission. Also tighten `request.data` echo in validation-error log. Add `ENDPOINT_ROLE_MAPPING` entry.

**Why deferred:** admin team's bigger perms refactor will likely subsume this; standalone PR adds friction.

---

## Onboarder lifecycle log silence debug

Flipped `ONBOARDER_TENANT_LIFECYCLE_ENABLED=true` 2026-04-30 16:02Z. Expected `tenant lifecycle pass: tenants checked=...` INFO log line never appeared, even on US where deploys verified the right CodeSha. Hypothesis: contract loop consuming entire wall-clock and exiting before reaching log line. Not investigated since reframe — only re-open if we need lifecycle data for new evidence.

---

## Admin-side propagation hooks

Schedule → customer → site → cameras propagation. Current cascade endpoint correctly soft-deletes Customer + AutoPatrolSchedule rows but does NOT propagate state changes UP from schedule deletions or DOWN from `customer.active=False` to cameras. Three concrete examples in prod admin DB observed 2026-04-30: customer pk=40803 (ABC Liquor Store 23) `active=False` but cameras still active; pk=39221 schedules deleted on Immix side, orphan rows in admin; pk=41260 active=True with orphan schedule.

**Design needed:** new admin-side post-save / post-delete signals on AutoPatrolSchedule; Customer.save() propagating `active=False` to cameras directly. Pairs with §25 cascade infrastructure but addresses different gap. Defer to admin team's owner.

---

## Admin DB one-time reconcile mgmt command

Build `python manage.py reconcile_autopatrol_state` with: (a) Customer with active=False or no active AutoPatrolSchedule → soft-delete cameras; (b) AutoPatrolSchedule with no Immix schedule_id → flag for review or auto-soft-delete; (c) Customer in admin DB whose tenant_id absent from Immix /Contracts → cascade-disable. Dry-run first. Pairs with the propagation hooks ADR.

---

## Admin data-model cascade-semantics deep-dive

Stub seeded 2026-04-30 in `topics/admin-api/notes/concepts/2026-04-30_data-model-cascade-semantics.md`. Captures: which delete propagates where (Customer.delete() → cameras + group; AutoPatrolSchedule.delete() → undeploy); how `active` vs `is_deleted` interact; what `schedule_status` means at each level; how reenable_tenant's `customer.restore()` interacts with parent Group restoration; orphan-row class.

**Why deferred:** Needs admin-team alignment on which semantics are intentional vs accidental before formalizing.

---

## Comprehensive Immix tenant-failure census

External-audience report cataloging every tenant_id surfacing in connector / onboarder failure logs, classified by response type. Audience: Immix engineering. Steps + structure detailed in [[2026-04-29_immix-zombie-tenants]] (3 documented zombies) — expand to full population (US + EU, 7-day window).

**Why deferred:** Immix engineering not yet ready to receive a deep audit; partial dialog open via the StreamFinished inquiry sent 2026-05-06 evening.

---

## §16 cascade-on-suspended-detection

Cascade NEVER fires organically for already-Suspended tenants (no `no_patrols` SQS messages → DDB count never reaches threshold → trigger never reached). Of 5 RSS schedule_ids checked 2026-04-30, 4 had **never had a DDB row**. Cascade as designed is purely reactive — only catches NEW suspensions where the connector is still active at suspension time.

**Options:**
- (a) periodic reconciliation Lambda fetches `/Contracts?contractStatus=Suspended` → cascades each one against admin
- (b) ad-hoc trigger as we did 2026-04-30

**Why deferred:** lifecycle pass log silence (above) needs root-cause first.

---

## §17 vch_no_patrols promotion

PR #1662 (VCH `no_patrols` emit drop) merged to stage 2026-04-28T20:01Z; bundled into PR #1660 stage→rearchitecture which merged 2026-05-01. Soak items rolled multiple days. **Status as of 2026-05-07:** rearch-side promotion DONE via #1660; close-out the §17 references in mark-todos.

---

## Recalibrate connector_no_patrols_to_run_24h thresholds

Gated on PR #1662 reaching prod (not stage). Currently sits as a YELLOW signal at 31. Once VCH `no_patrols` drop reaches prod (via the next stage→rearch→prod release train), threshold should drop materially; recalibrate to baseline.

---

## Cohort dashboard signals

Five candidate signals split across two data sources:

1. **Lifecycle (4 signals — buildable today via NRQL):** `us_tenants_active`, `us_tenants_cascaded`, `eu_tenants_active`, `eu_tenants_cascaded`. Parsed from `tenant lifecycle pass: tenants checked=N suspended/removed=M active=K cascaded=C` log line in `/aws/lambda/immix-autopatrol-onboarding`. Add to `~/.claude/skills/dashboard-check/config/signals.json` + collector.
2. **Cohort (3 signals — blocked on data source):** `cohort_b_cameras`, `cohort_c_cameras`, `cohort_f_cameras`. Read from `silent-camera-diagnosis.json` on firebat. **Blocker:** Snowflake export script doesn't exist yet (was de-scoped 2026-05-06; table-shape question never resolved). Re-open when `scripts/ops/fetch_silent_cameras_csv.py` or equivalent ships.

---

## Past-week Jira closeout

Map cleanup #9/#10, onboarder #11/#12/#13, admin #2376 to AUTO/AC tickets; update each with verification summary. Open new tickets for §25 (Cohort B cascade — even if archived as no-backfill, cascade infra ticket is still trackable) and §26 (Cohort F investigation).

---

## Immix zombie-tenants Jira ticket

Full draft at [[2026-04-29_immix-zombie-tenants]]. Rolled morning followup. Defer until Immix engineering posture on multi-issue audits is clearer; the StreamFinished inquiry sent 2026-05-06 evening is a smaller probe of partner responsiveness first.

---

## Billing emit on crash / early-endrun paths

Surfaced 2026-05-07 during the post-deploy verify of PR #1682. The fleet-wide silent-billing scan returned much higher rates than expected (79% AP cronjobs, 67% VCH cronjobs silent over 24h). Initial methodology counted any container with zero billing emits as "silent," but the diagnostic question is: of those silent containers, **how many ran to completion vs crashed/early-exited before reaching the billing-emit path**?

PR #1682 only addresses the "ran clean, products empty" case (the `_HEALTHCHECK_FALLBACK_PRODUCT` / `_MISCONFIGURED_FALLBACK_PRODUCT` path). It does NOT cover:

1. **Crashes mid-run** — process dies (exception, OOMKill, SIGKILL) before `endrun()` is reachable. Both AP and VCH affected.
2. **VCH containers that never reach `_send_product_ended_events_once`** — for whatever reason (e.g. stuck in healthcheck loop, alert-thread `join(timeout=30)` hits, container terminates while still in `start_healthcheck`). The 67% VCH silent rate likely splits across this and the legitimate-completion-but-no-emit case.
3. **Early-exit paths in CHM/VCH that don't go through `endrun`** — if any code path in `BaseHealthcheckCamera.run()` exits before reaching the bottom of the function.

**Why deferred:** the proper fix is observability + targeted intervention per failure-mode. We can't blanket-emit-on-crash from a SIGTERM handler the way AP does because VCH's signal handler in `_graceful_shutdown` already calls `endrun()` — so if endrun isn't being reached on signal, something else is wrong (likely the signal isn't firing at all, or the container's exit is via SIGKILL with no grace period).

**Open work (when revived):**
- Spot-check 5-10 silent containers in NR — for each, classify: completed / signal-killed / crashed / stuck in healthcheck. Use last-log-line + duration as the signature.
- For the "completed but didn't emit" subset: confirm via admin API whether products are actually configured; if yes, we have a bug (the emit path is being skipped despite products existing); if no, it's the misconfig case PR #1682 addresses.
- For the "crashed before emit" subset: design a billing-emit-on-crash mechanism. Options: (a) emit `_started` at run-startup so at least we know the run happened (even if `_ended` never fires), (b) external watcher that detects pod-exit-without-billing-event and emits a synthetic event, (c) in-process atexit hook that fires emit on any termination path (limited by SIGKILL).

**Re-open trigger:**
- After PR #1683 (rename + VCH started-fix) lands and we have clean signal on the fallback path's true firing rate.
- If `fleet_error_top15` or a new dashboard signal flags crash-related billing leaks at material rate.

**Resources:**
- 2026-05-07 silent-billing scan results (in mark-todos history; specific containers spot-checked: TBD per [scan finding deliverable])
- PR #1675 — added the per-product emit walk
- PR #1680 — per-stream idempotency guard
- PR #1682 — healthcheck fallback for empty-products case
- PR #1683 (in-flight) — rename to `"misconfigured"` + VCH started-emit fix

---

## Cleanup-Lambda canary across state matrix

Surfaced 2026-05-07 during the §3 verify pass — see [[2026-05-07_cleanup-lambda-state-matrix-verify]] for the full finding. The cleanup-Lambda has had **zero `actual_disable` and zero `anomaly_reset` events in 30 days** because §17 + §3 Step E together drained the organic "real" cleanup queue. Only Vendor.Actuate.Prod test traffic flows through it now. The Immix-state branches (Deleted/Suspended/Paused/offline → correct outcome) are unverifiable live without a synthetic canary.

**Why deferred:** Pipeline is healthy by every observable metric and lambda code hasn't drifted (last deploy 2026-04-30, `code_sha256: 4OaMWiihoCrx5qFGxAmdj5gCsjnRb0QEAa1ftd+9S+0=`). This is defense-in-depth, not fix-something-broken.

**Open work (when revived):**
- Pick a Vendor.Actuate.Prod test schedule (existing or fresh)
- Drive its Immix state through the matrix: Active → Deleted (expect: counter accumulate → disable at threshold), Active → Suspended (expect: anomaly-reset, no disable), Active → Paused (expect: anomaly-reset; or `SiteDisabledOrDisarmed` routing per the §3 follow-up if implemented), offline (expect: anomaly-reset)
- Observe each branch in CloudWatch logs + DDB state changes
- If any branch is broken, it's a §N promotion candidate

**Re-open trigger:**
- A real customer case fires unexpectedly (lambda doesn't disable when it should, OR disables when it shouldn't)
- Before any §3 code change touches the state-decision logic
- Before §3 Step F prod-US scale-up flips (currently deferred but if revived, do canary first as part of pre-flip gate)

**Resources:**
- [[2026-05-07_cleanup-lambda-state-matrix-verify]] — verify finding
- [[2026-04-17_stale-schedule-cleanup-design]] — state-matrix design
- [[autopatrol-cleanup-lambda]] — entity
- Health-check JSON: `~/.local/state/minipc-tasks/autopatrol/cleanup-YYYY-MM-DD.json`

---

## PR #1662 VCH no_patrols suppression verify

Surfaced 2026-05-19 while root-causing the `connector_no_patrols_to_run_24h=32` RED signal that previously hid under `error` (sink renderer bug, also fixed 2026-05-19 — see [[2026-05-19_dashboard-signal-repairs]] once written). Of the 32 distinct containers logging "No patrols to run after all attempts" in 24h, **25 are VCH containers** (4 hits/pod, ~1/cron tick). PR #1662 was supposed to drop this emit from VCH integration containers — clearly incomplete on rearch.

**Why deferred:** Not customer-facing; signal is steady-state noise not a regression. But it means the actually-noisy autopatrol subset (the other 6/32) is masked by the VCH residual, so the threshold can't be recalibrated downward without first fixing VCH.

**Open work (when revived):**
- Pull the deployed `:rearchitecture` image SHA for a VCH pod (e.g. site 41261 — first VCH in the FACET list)
- Confirm PR #1662's suppression code is present in that image (`integration_type` gate at the emit site)
- If present-but-not-firing: the gate condition is wrong (logging integration_type at runtime would confirm)
- If absent: the rearch image hasn't picked up #1662's changes — investigate via Argo / image promotion chain
- After fix lands + rolls: recalibrate `connector_no_patrols_to_run_24h` thresholds (pairs with the existing "Recalibrate connector_no_patrols_to_run_24h thresholds" entry above)

**Re-open trigger:**
- VCH share of `connector_no_patrols_to_run_24h` doesn't drop after the next rolling-restart fully rolls the latest rearch image
- A real autopatrol regression hides because we can't see it through the VCH noise floor

**Resources:**
- vms-connector PR [#1662](https://github.com/aegissystems/vms-connector/pull/1662) — VCH `no_patrols` emit drop (merged stage 2026-04-28 → rearch 2026-05-01 bundled in #1660)
- `connector_no_patrols_to_run_24h` signal in `~/.claude/skills/dashboard-check/config/signals.json`
- nrql-investigator 2026-05-19 finding (`FACET container_name SINCE 24 hours ago` → 32 containers, 25 VCH / 7 autopatrol)

---

## 6 autopatrol pods looping empty queue

Surfaced 2026-05-19 during the `connector_no_patrols_to_run_24h=32` investigation. Of the 32 containers firing "No patrols to run after all attempts", 6 are autopatrol pods looping every 15 min on an empty queue:

| Site | Container | Hits/24h |
|------|-----------|----------|
| 38316 | `connector-38316-autopatrol-597` | 96 |
| 46560 | `connector-46560-autopatrol-1066` | 96 |
| 37837 | `connector-37837-autopatrol-1028` | 24 |
| 41070 | `connector-41070-autopatrol-1029` | 24 |
| 40672 | `connector-40672-autopatrol-1027` | 24 |
| 41178 | `connector-41178-autopatrol-350` | 24 |
| 46560 | `connector-46560-autopatrol-1100` | 2 |

96/24h = once per 15 minutes — matches the cron schedule firing repeatedly against an empty patrol queue. Almost certainly schedules in "Awaiting" state on admin side, OR misconfigured dispatch.

**Why deferred:** Pre-existing, not escalating, no customer escalation tied to these sites yet. The time-series is flat over 24h — no spike. These are the kind of items that get fixed in batch when an admin ops sweep happens, not one-off.

**Open work (when revived):**
- Cross-reference each of the 6 site_ids against admin Postgres: `select id, name, autopatrol_schedule_id, schedule_status from camera_site where id in (38316, 46560, 37837, 41070, 40672, 41178)` — or via admin UI
- For each: confirm whether the schedule is `Awaiting`, `Active`, or `Disabled`; whether the connector is supposed to be running autopatrol at all
- Decide per site: re-activate schedule, disable cronjob, or accept noise (e.g. customer-paused)
- If a pattern emerges (e.g. all 6 came through cohort-F migration), document it in [[2026-05-06_cohort-f-investigation]] as a sub-class

**Re-open trigger:**
- Count grows materially beyond 6
- Any of these 6 sites becomes a customer escalation
- Operational ops sweep schedules a batch admin-cleanup pass

**Resources:**
- nrql-investigator 2026-05-19 finding (per-pod 24h FACET counts)
- `connector_no_patrols_to_run_24h` signal description: see `~/.claude/skills/dashboard-check/config/signals.json`

---

## AP schedule-sync resilience (post-2026-06-03)

Surfaced 2026-06-03 during incident recovery for ScheduleID `53C62AD7-B167-4E77-F72B-08DEC0C9AF65` (site 37255). Redeploy-suppression flag used a rolling 24h TTL with no calendar-day awareness, causing up to ~24h of legitimate-redeploy suppression. Calendar-day fix shipped in `fix/ap-redeploy-flag-calendar-day`; larger resilience backlog below.

See [[2026-06-03_ap-redeploy-flag-calendar-day-stranding]] for incident and diagnosis.

### Open work (resilience layers)

1. **Admin-side reconciliation cron / DB deploy-state machine (Layer 2 — the real fix):** `AutoPatrolSchedule.settings_deploy_state` (pending|settings_uploaded|cronjob_created|failed) + attempts + last_error + last_attempted_at. Replace fire-and-forget Thread with enqueue + periodic retry of pending/failed rows. Makes deploy chain observable from the DB (dashboard query "schedules not in cronjob_created"). Covers BOTH Mechanism A (thread crash) and Mechanism B (redeploy flag).

2. **Bounded retry + error escalation + structured greppable logging in _delayed_deploy_settings (Mechanism A):** Currently no retry on thread failure; silent death via `logger.error` in admin pod not in NR.

3. **Tie redeploy-suppression flag to committed deploy-success marker (DB last_successful_deploy_date), not just "deploy_schedule_changes ran":** Today's calendar-day fix is interim; this is the durable version. Suppression can never outlive an actually-failed sync.

4. **Admin pod into New Relic (Layer 3):** Gap documented at `topics/new-relic/notes/concepts/nr-connector-query-cookbook.md:314` (separate from AUTO-566). Deploy-thread + redeploy-skip logs become alertable. Independent track.

5. **Onboarder-side post-deploy verification (Layer 1):** For each activated schedule, verify the K8s cronjob exists within ~15 min; emit OnboarderDeployStalled + Slack alert if absent.

6. **Deploy_chain_check tool:** Immix → admin DB → S3 → K8s for a given schedule_id, building on `missing_schedule_probe.py` from [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]] (see [[autopatrol-integration-tools]] TBD).

**Why deferred:** Calendar-day fix is shipped as interim. Layers 2–6 are the durable architecture; trigger Layer-2 promotion if another redeploy-suppression incident surfaces or Layer-3 (NR instrumentation) lands independently.

---

## AP schedule settings regen-from-here capability

Surfaced 2026-05-27 closing out the empty-metrics fix (vms-connector #1712 + [[actuate_admin]] #2451). After both fixes shipped, the two still-broken sites (37837, 41070) needed their S3 settings **regenerated** — the code fix only changes future generation, it doesn't rewrite existing `settings.json`. We discovered there's **no clean way to trigger a settings-only regen remotely**:

- **The clean call** — `AutoPatrolSchedule.deploy_schedule_settings(call_deployer=False)` (rewrites S3 only, no cronjob churn) — needs a **prod Django shell**, which isn't wired up locally (local admin bring-up uses a DB restore, not prod RDS).
- **The only remote trigger** — `PATCH /api/autopatrol_schedule/{id}/` (`autopatrol_schedule_view.py:64` `update`) — fires `deploy_schedule_settings(**call_deployer=True**)`, which also re-invokes the deployer and redeploys the cronjob (heavier than needed), needs a valid PATCH payload (mutation risk on a live customer schedule), and is gated by `CheckModelPermission` (the connector's read-mostly `api-token-prod` likely 403s on write).

So today the practical path is an **admin-UI save** (what was done 2026-05-27 — worked for 37837, the 41070 trigger silently didn't land) or a prod shell one-liner if you have access.

**Open work (when revived):**
- Add a dedicated DRF `@action`, e.g. `POST /api/autopatrol_schedule/{id}/redeploy_settings/` (detail=True), that calls `deploy_schedule_settings(call_deployer=False)` and returns the resulting S3 key + a non-empty-metrics assertion. Settings-only, idempotent, no cronjob redeploy. Gate with `CheckModelPermission` or a service-account permission.
- OR: extend the headless MCP-bypass pattern ([[2026-04-27_headless-mcp-bypass]]) with an admin-write helper (`~/.claude/lib/admin_write.py`) that hits the new endpoint with a write-scoped token — so regen + the follow-on verification (S3 non-empty → connector fallback clears) can run start-to-finish from here.
- Either way, pair with a small batch helper: given a list of `deployment_id`s, regen each + verify the new settings carry non-empty metrics, and report State-A (fixed) vs State-B (stream_metrics empty in DB → needs data fix).

**Why deferred:** not blocking — the immediate two sites get handled via UI save. This is about not having to round-trip through the admin UI (or a coworker) the next time settings need a forced regen. Pairs naturally with whoever owns the admin endpoint surface.

**Re-open trigger:** next time a schedule needs a settings-only regen and we're not sitting at an admin UI — or when the empty-metrics dashboard signal (`ap_empty_metrics_warn_6h`) flags a new site and we want to self-serve the fix.

**Resources:**
- vms-connector PR [#1712](https://github.com/aegissystems/vms-connector/pull/1712) — connector-side `empty_metrics_dict` guard
- [[actuate_admin]] PR [#2451](https://github.com/aegissystems/actuate_admin/pull/2451) — generator fallback (commit `0d8f1e5a`, in main/develop/staging)
- [[autopatrol-aws-objects]] — where the regenerated `settings.json` lands (`actuate-settings` bucket)
- [[2026-04-27_headless-mcp-bypass]] — the wrapper pattern to extend for admin writes
- `autopatrol_schedule_view.py:64` (`update`) / `autopatrol_schedule_model.py:937` (`deploy_schedule_settings`) — current trigger surface

---

## Discipline

- **Don't accumulate.** Every entry should have a clear "decision trigger" so it doesn't rot. If an entry has been here >60 days without a trigger move, sweep it to a closed-with-reason archive or fold into the parent topic synthesis.
- **Promote back to mark-todos** when the trigger fires — don't half-resurrect items in this file.
- **Cross-link with [[mark-todos]] §N** when an item is mid-flight. The active surface is mark-todos; this file is the parking lot.

## Related

- [[mark-todos]] — Mark's active workstreams
- [[todo-list|AutoPatrol Team Todo List]] — team-level tracker
- [[autopatrol-cleanup-lambda]] — entity for the cleanup-Lambda system
- [[autopatrol-onboarder]] — sibling Lambda
- [[2026-05-04_silent-camera-diagnosis]] — Cohort A-F audit
- [[2026-05-06_cohort-f-investigation]] — Cohort F reframe
- [[2026-05-07_cohort-b-no-backfill-decision]] — Cohort B ADR
