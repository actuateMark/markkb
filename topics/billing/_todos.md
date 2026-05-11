---
title: "Billing — Topic Todo List"
type: workstream
topic: billing
tags: [billing, todos, workstream, tightening, self-righting, reconciliation, observability]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Billing — Topic Todo List

The live worklist for the billing topic, **categorized by remediation class**. Each item carries: rationale, acceptance criteria, blocking/blocked-by, and a "promote to mark-todos" hook when an item becomes this-week scope.

This list is the **source-of-truth for what's owed in this topic**; [[mark-todos]] §N references it loosely (cross-linked, not duplicated). When an item lands in mark-todos as a §N, add a `(mark-todos §N)` annotation on its row here so the two stay in sync.

> **How to use:** before adding a new item to mark-todos under a billing scope, check that it's reflected here first. Items resolve in two ways: (a) shipped and verified — flip to `[x]` and add a wikilink to the closing artifact; (b) decided-not-to-do — flip to `[~]`, add an ADR link explaining why.

---

## Discipline

- **Don't accumulate.** Items with no decision-trigger or no movement after 60 days get a hard look — either promote or sunset (with reasoning).
- **Acceptance is testable.** Each item lists what "done" looks like in a way a follow-up audit could verify.
- **Self-righting > alerting > documentation.** When designing a fix, prefer (a) the system corrects automatically over (b) an alert tells a human to look over (c) a runbook explains the failure mode. Pick the highest available; document the others as fallback.
- **Cohort runbooks are first-class.** Until a drift class is fully automated away, its runbook lives in the auditing topic (autopatrol or billing) and stays current. Retire only when the underlying detection moves to automation.

---

## Category 1 — Tightening (close emission gaps)

Goal: every customer-serviced moment leaves a billing trace. No leaks.

### T1. Close the crash-path emit gap (HIGH)

**Why:** 2026-05-07 fleet-wide scan showed 79% AP / 67% VCH cronjobs silent over 24h. Cohort F's connector-side gaps (250 cams) are PR-#1688-addressed; the silent-scan number suggests a separate, larger class — crash / SIGKILL / early-exit before `endrun()`. Tracked in [[autopatrol-deferred-backlog]] under "Billing emit on crash / early-endrun paths."

**Acceptance:**
- Spot-check 5-10 silent containers in NR, classified into {completed-no-emit, signal-killed, crashed, stuck-in-healthcheck} per last-log-line + duration signature.
- For "completed but didn't emit": file a bug if products exist in admin — emit path is being skipped.
- For "crashed before emit": design a billing-emit-on-crash mechanism. Either: (a) resurrect `_started` at startup with downstream coordination (requires consumer-side change); (b) external watcher detecting pod-exit-without-billing-event; (c) atexit hook (limited by SIGKILL); (d) some hybrid.
- Acceptance signal: post-fix, fleet silent-cronjob rate <5% over a 24h scan, sustained for 7 days.

**Blocked by:** PR #1688 merging cleanly and the post-merge baseline establishing.

**Promote to mark-todos:** when PR #1688 lands and the bake interval clears.

---

### T2. Verify `act_a` discriminator coverage (MED)

**Why:** [[billing-events-catalog]] lists `patrol` and `healthcheck` as the known `act_a` values. If a Snowflake consumer filters on a specific subset, an emitter using a new value silently leaks. Cohort F6/F5's Snowflake-side ingestion gap may be exactly this.

**Acceptance:**
- Grep all `act_a=` assignments in vms-connector + actuate-libraries; produce exhaustive list in [[billing-events-catalog]].
- Confirm Snowflake-side filter logic (handoff to data team if needed; ref the F6/F5 tracker).
- Document any `act_a` values that are emitted but not ingested — these are silent leaks.

**Blocked by:** nothing for the grep portion. Snowflake-side requires data-team engagement.

---

### T3. Site-level vs per-stream emit invariants (MED)

**Why:** PR #1683 added a site-level fallback for empty `camera_streams`. The catalog row uses `admin_camera_id=null` for these — is the Snowflake side aware? If it filters out null `admin_camera_id`, the site-level fallback is decorative.

**Acceptance:**
- Confirm Snowflake billing table handles `admin_camera_id=null` (joins to a fallback row, treats as site-level revenue, or drops — need explicit answer).
- If dropped: the site-level fallback is a no-op; either change Snowflake side or change emit shape (e.g., use a sentinel non-null ID per the `_SITE_LEVEL_SENTINEL_CAMERA_ID` constant).

**Blocked by:** data-team confirmation.

---

### T4. Sentinel-value billing audit (LOW)

**Why:** `_MISCONFIGURED_FALLBACK_PRODUCT` and `_SITE_LEVEL_SENTINEL_CAMERA_ID` are placeholder strings. If the billing aggregation joins them to a "real" product/camera ID it might double-count, or worse, treat them as revenue-bearing. Verify they map to a known "non-billable but tracked" path in Snowflake.

**Acceptance:** Snowflake-side join logic confirmed; sentinel values either explicitly excluded from revenue aggregation OR ingested into a separate audit table.

---

## Category 2 — Self-Righting (drift detected → drift corrected)

Goal: when state drifts between admin / Immix / emit / Snowflake, the system corrects itself OR alerts with high signal-to-noise. The cleanup-Lambda is the reference pattern; replicate up the stack.

### S1. AutoPatrolSchedule post-delete propagation hook (HIGH)

**Why:** Per [[2026-04-30_data-model-cascade-semantics]] §3 — `AutoPatrolSchedule` has zero signal wiring. When the last active schedule on a customer is deleted, the customer doesn't get cascade-disabled, so its cameras stay billable. This is the "schedule → customer → site" gap surfaced 2026-04-30 (customer pk=39221).

**Acceptance:**
- `@receiver(post_delete, sender=AutoPatrolSchedule)` in `autopatrol_schedule_model.py`.
- Body: `if not customer.autopatrolschedule_set.filter(is_deleted=False).exists(): customer.delete()`.
- Guarded by feature flag (`AUTOPATROL_SCHEDULE_CASCADE_ENABLED` or similar). Cohort B-style careful rollout.
- Loop-risk check: verify `Customer.delete()` doesn't internally delete schedules (would create a cascade loop).

**Blocked by:** admin-team alignment on cascade semantics ADR (per the [[2026-05-07_cohort-b-no-backfill-decision|Cohort B no-backfill decision]], the current cascade hook stays disabled — re-opening this requires a fresh ADR or revised cohort growth signal).

**Promote to mark-todos:** when admin team has bandwidth to review the propagation-hooks ADR.

---

### S2. Customer.active → cameras propagation hook (HIGH)

**Why:** Per [[2026-04-30_data-model-cascade-semantics]] §1 — `Customer.save()` does NOT propagate `active=False` to its cameras. Today's prod admin DB has customer pk=40803 (ABC Liquor Store 23) with `active=False` and cameras still emitting billing. This is a direct revenue leak.

**Acceptance:**
- Extend the existing `pre_save` `on_change()` handler in `customer_model.py:2212`.
- When `active` flips True→False: set `is_deleted_event=True` on each non-deleted camera, then either `active=False` or `delete()` them (open design question — operator-intent matters).
- Asymmetry note: `Customer.restore()` does NOT auto-revive cameras today. Either also propagate restore() down OR document the asymmetry explicitly.
- Feature-flagged rollout.

**Blocked by:** admin-team design decision on `active=False` semantics (soft-disable vs soft-delete the cameras).

---

### S3. Contract status → tenant cascade (LOW)

**Why:** Per [[2026-04-30_data-model-cascade-semantics]] §5 — `Contract` has zero cascade. A contract going `Cancelled` is a no-op for Group/Customer. We've seen this for EU bilateral cases (tenant has both Cancelled + Active contracts, Group stays). It's a billing leak if "Cancelled" means we shouldn't bill.

**Acceptance:**
- Design first: what does Group-level "inactive" even mean (Group has no `active` field)? Without that answer the hook can't be coherent.
- If decision is to add a Group-level disable concept: `@receiver(post_save, sender=Contract)` checking `Group.tenant_contracts.filter(contract_status='Active').exists()` and cascading per the answer.

**Blocked by:** product / finance answer on contract-status semantics. May never close — could be decided that "Cancelled but still active in Immix = customer is in dispute, keep billing" — that's a valid answer.

---

### S4. Customer.restore() → cameras + schedules propagation (MED)

**Why:** Per [[2026-04-30_data-model-cascade-semantics]] §1 — `Customer.restore()` is partial. It un-soft-deletes the Customer + parent Group but does NOT reactivate cascade-deleted cameras or schedules. Today's path relies on the onboarder's normal sync to re-create them. Whether that's enough has been an open question since 2026-04-29.

**Acceptance:**
- Audit: when a customer is re-enabled, how long until they're billable again? Acceptable upper bound?
- If unacceptable: extend `Customer.restore()` to cascade-restore cameras (matching the down-cascade in `Customer.delete()`).

---

### S5. Immix `SiteDisabledOrDisarmed` routing in cleanup-Lambda (LOW)

**Why:** Per [[autopatrol-deferred-backlog]] §3 follow-ups — extend cleanup signal to also route this Immix response. Requires care: SiteDisabledOrDisarmed can be legitimately transient (business-hours arming). Design needed: longer threshold window, separate event_type or shared DDB table.

**Acceptance:** design doc + feature-flagged rollout + observable disable rate.

**Blocked by:** stage bake of the current cleanup-Lambda configuration.

---

### S6. Cleanup-Lambda canary across full state matrix (MED)

**Why:** Per [[2026-05-07_cleanup-lambda-state-matrix-verify]] — the cleanup-Lambda has had **zero `actual_disable` and zero `anomaly_reset` events in 30 days** because §17 + §3 Step E drained the organic queue. Immix-state branches (Deleted / Suspended / Paused / offline → correct outcome) are unverifiable live without a synthetic canary.

**Acceptance:** Vendor.Actuate.Prod test schedule driven through the state matrix; each branch observed correct in CloudWatch + DDB.

**Blocked by:** nothing structural; just bandwidth.

---

## Category 3 — Reconciliation (admin ↔ emit ↔ Snowflake ↔ Immix)

Goal: continuous, automated comparison across the four layers. The fact that Cohort F took weeks to discover and has unknown duration is the load-bearing post-mortem finding. Close it.

### R1. Admin ↔ emit dashboard signal (HIGH — design landed 2026-05-11)

**Why:** Today, the only check that "every active admin camera × product is producing `_ended` events at the expected rate" is a manual cohort audit. Cohort F surfaced 250 connector-side gaps; the next class will surface the same way unless we automate.

**Status (2026-05-11):** **Design spec landed** — see [[2026-05-11_billing-reconciliation-dashboard-design]]. Query shape, data-source choice (NRQL + admin DB; Snowflake deferred to R2), surface phasing (local → standalone billing dashboard → sales-dashboard), threshold ramp (5% → 1%), and 5 open implementation questions are all pinned. Implementation PR is the next loop.

**Acceptance:**
- A daily-running query that computes: `count(admin: Camera.active=True && Customer.active=True) × products` vs `count(distinct (camera, product) emitting `_ended` in trailing 24h)`.
- Surface as dashboard signal (green/yellow/red).
- Alert at >X% gap (calibrate X to baseline; start at 5%, tighten as gaps close).
- Records-per-gap-class: when the alert fires, the query payload should include a tractable list (or sample) of the gap rows so an operator can investigate.
- Replay against 2026-05-04 cohort-F window fires red — locks in the "would have caught" promise.

**Surface decision (2026-05-11):** sits on a **separate billing-dashboard**, not the operational-health dashboard. Built locally first (laptop/Firebat sketch), with future integration to the existing internal sales dashboard at `https://sales-dashboard.internal.actuateui.net/`. Deployment-repo location for sales-dashboard is unknown — see C6 below.

**Open implementation questions** (per [[2026-05-11_billing-reconciliation-dashboard-design]] §"Open questions"):
1. Product resolution chain (camera-level → site → customer → fallback?) — pin against `connector_factories/shared/billing_emit.py`.
2. Admin product model location — direct FK / M2M / inherited?
3. Newly-onboarded camera exclusion window (`created_at > now - 24h`?).
4. Phantom-pair semantics — same signal as missing-pair, or separate?
5. NR `uniques` cardinality limit at fleet scale — paginate via `FACET cid` if needed.

**Promote to mark-todos:** ASAP. This is the post-mortem's headline action item.

---

### R2. Emit ↔ Snowflake reconciliation (HIGH, data-team-owned — OUR PART DONE)

**Why:** Cohort F6/F5 (392 cameras) emitted `_ended` properly but Snowflake didn't ingest. We surfaced it via NR + Immix; Snowflake side opaque. Until reconciled, those customers were under-billed.

**Status (2026-05-11):** **Our part is done.** `autopatrol_onboarder/scripts/ops/cohort_f_tracker.json` (45 cids, status=`fixed`/`diagnosed`) pushed as follow-up commit on autopatrol_onboarder#14. Data team owns the ingestion-side reconciliation; we have no further work here unless the data team escalates back.

**What our follow-up looks like (if/when data team re-engages):**
- Provide additional NR data on emission patterns by `(event_type, act_a, cid)` if requested.
- Wire any data-team-produced reconciliation signal into the billing dashboard (R1).

**Acceptance:** R2 closes when the data team confirms F6/F5 root cause + ships ongoing daily reconciliation. Until then, this row is intentionally idle on our side.

---

### R3. Admin ↔ Immix continuous reconciliation (MED)

**Why:** The [[autopatrol-cleanup-lambda]] catches one drift class (Immix-deleted-but-admin-active). The other direction (admin-deleted-but-Immix-active) is also possible and not systematically watched. [[2026-04-30_data-model-cascade-semantics]] §"Propagation gaps observed" inventoried three concrete prod examples.

**Acceptance:**
- Periodic reconciliation Lambda fetches `/Contracts` + `/Schedules` from Immix, joins against admin DB, flags rows where one side is active and the other isn't.
- Two outcomes: cascade-fix (if confident) or alert (if not).

**Blocked by:** S1 + S2 propagation hooks — without them, "admin shows active, Immix shows deleted" doesn't have a clean correction primitive.

---

### R4. Immix tenant-failure census (LOW, partner-engagement)

**Why:** Per [[autopatrol-deferred-backlog]] "Comprehensive Immix tenant-failure census" — external-audience report cataloging every tenant_id surfacing in connector / onboarder failure logs, classified by response type. Audience: Immix engineering. Partial dialog open via the StreamFinished inquiry sent 2026-05-06 evening.

**Acceptance:** External report shippable. Immix-side investigation triggered.

**Blocked by:** Immix engineering readiness to receive a deep audit.

---

## Category 4 — Observability (dashboards, alerts, audit trails)

Goal: every load-bearing invariant in [[billing-events-catalog]] §"Lifecycle invariants" has a dashboard signal and an alert.

### O1. Cohort dashboard signals (HIGH — blocked on data source)

**Why:** Per [[autopatrol-deferred-backlog]] "Cohort dashboard signals" — five candidates:
- Lifecycle (4 NRQL-buildable today): `us_tenants_active`, `us_tenants_cascaded`, `eu_tenants_active`, `eu_tenants_cascaded`.
- Cohort (3 blocked on Snowflake export): `cohort_b_cameras`, `cohort_c_cameras`, `cohort_f_cameras`.

**Acceptance:** Signals in `~/.claude/skills/dashboard-check/config/signals.json` + collector; running daily.

**Blocked by:** Snowflake export script (`scripts/ops/fetch_silent_cameras_csv.py`) shipping. Lifecycle 4 signals are buildable today.

---

### O2. `event_queue_analytics.fifo` health dashboard (MED)

**Why:** The canonical transport for every billing event. Queue depth, age of oldest message, DLQ count, ingestion lag — none of these are first-class dashboard signals today. If queue_consumer's analytics route stalls, billing pipeline stalls invisibly.

**Acceptance:**
- Queue depth signal, alarm threshold calibrated to typical baseline.
- DLQ count signal, alarm on any growth.
- End-to-end latency (emit-time → Snowflake-row-time) — if measurable.

---

### O3. NR custom event for every billing emit failure (LOW)

**Why:** Today, failed emits log a generic exception. There's no `BillingEmitFailure` NR custom event we can aggregate / alert on. Adding one (alongside the existing emit code path) gives a first-class observability hook for free.

**Acceptance:**
- `BillingEmitFailure` custom event fires on any exception path inside `emit_site_product_event_for_stream`.
- Fields: `cid`, `tenant_id`, `event_name`, `act_a`, `admin_camera_id`, `product`, `exception_class`, `exception_message`.
- NR alert on threshold (rate vs typical baseline).

---

### O4. Idempotency-guard FACET telemetry (LOW)

**Why:** Per [[2026-05-07_handoff-pr-1681-promotion]] §"Update 2026-05-08" — idempotency-guard FACET verification was inconclusive because `admin_camera_id` isn't on NR logs. We currently can't verify per-stream idempotency at fleet scale. Two paths: (a) add `admin_camera_id` to the standard log line, (b) emit a separate per-emit-NR-custom-event with the key.

**Acceptance:** queryable in NR; one or two-line NRQL verifies idempotency guard is firing as expected on retries.

---

## Category 5 — Codification (documentation, contract, primitives)

Goal: the system's billing contract is explicit. New emit sites, new consumers, new schemas can't drift the contract because the contract is the artifact they reference.

### C1. Keep [[billing-events-catalog]] current (ONGOING, enforced by PR template)

**Why:** The catalog's absence is the post-mortem's #1 lesson. Adding emit sites without updating the catalog re-introduces the drift class.

**Acceptance:** PR template entry: "If this PR adds/removes a billing emit site or consumer, update [[billing-events-catalog]] in the same PR." Reviewer checklist: spot-check the catalog row exists.

**Promote to mark-todos:** alongside the next billing-emit PR.

---

### C2. Lock the `site_product_ended` schema (MED — SUBSTANTIALLY ANSWERED 2026-05-11)

**Why:** [[billing-events-catalog]] §"Schema" lists what we currently *believe* the schema is, reverse-engineered. The authoritative schema lives in queue_consumer + Snowflake table DDL. We should mirror it explicitly.

**Acceptance:** schema documented in [[billing-events-catalog]] from authoritative source (data-team confirmation of Snowflake table DDL or a Pydantic model in actuate-libraries).

**Status (2026-05-11):** **Filed as ENG-242** ([browse](https://actuate-team.atlassian.net/browse/ENG-242)); same day, [[sales-dashboard-repo|sales-dashboard]] surfaced as a substantial answer. Inventory captured in [[snowflake-billing-tables]]. Ticket left open, scope narrowed to "please confirm DDL files in `actuate_bi/sql/snowflake/` are authoritative" — see [[2026-05-11_eng-242-substantially-answered]]. Comment owed to the ticket.

**Blocked by:** confirming DDL in `actuate_bi/sql/snowflake/` (NF1 below — clone + inventory `actuate_bi`). On the data-team side, scope reduced to a yes/no on whether that's the authoritative source.

**Downstream unblock (already happened):** C5 (largely done via [[snowflake-billing-tables]]), C6 (done via [[sales-dashboard-repo]]), T2/T3/T4 (substantially answered, see [[2026-05-11_eng-242-substantially-answered]] table), R1's R2-half (Snowflake IS queryable today via `reports@`).

---

### C3. Sales-Order / Billing-Profile concept note (MED)

**Why:** [[worklog-alibi-billing-redesign]] is a worklog source — captures the redesign but not the steady-state semantics. A concept note in this topic for "SO Profile invariants" (SO on lowest-level site, one SO per leaf site, etc.) gives downstream readers a single doc.

**Acceptance:** `notes/concepts/sales-order-profile-invariants.md` written, cross-linked from this topic + admin-api.

---

### C4. Connector emit-site reference (LOW)

**Why:** [[billing-events-catalog]] §"Emit sites" lists the current sites but not the *reasoning* for why each is where it is. New emit sites need to know what they're being added for; existing sites need a defense against accidental deletion.

**Acceptance:** Each emit site in the catalog has a one-paragraph rationale: when it fires, what it's defending against, what tests assert it exists.

---

### C5. Snowflake-side schema mirror (LOW — LANDED 2026-05-11 via sales-dashboard inventory)

**Why:** Even if we don't own the Snowflake DDL, having a mirror in this KB topic means we can spot mismatch between what the connector emits and what Snowflake expects.

**Acceptance:** `notes/entities/snowflake-billing-tables.md` capturing table names, key columns, joins to billing-event fields.

**Status (2026-05-11):** **Landed as [[snowflake-billing-tables]]** — built from [[sales-dashboard-repo|sales-dashboard]] CLAUDE.md + `clients/snowflake.py` + `scripts/reconcile_cameras.py`. Covers `gold.billing.{usage_monthly, site_product_run_day, clip_received, top_parent}` + `raw.aws.analytics_event`, the two silent-drop classes, NR-log field mapping, and `reports@` connection contract. Follow-up: NF1 (clone `actuate_bi` for the raw DDL files).

---

### C6. Locate the sales-dashboard deployment repo (DONE 2026-05-11)

**Why:** The internal billing dashboard lives at `https://sales-dashboard.internal.actuateui.net/`. We want to land R1's billing-reconciliation signal there eventually (after building it locally first per the R1 surface decision). Step zero is knowing what repo deploys it.

**Acceptance:**
- Repo identified. Owner identified. Deploy mechanism documented in a short concept note (`notes/concepts/sales-dashboard-deployment.md` or similar).
- Cross-link to R1's local sketch so the integration path is visible.

**Status (2026-05-11):** **DONE** — see [[sales-dashboard-repo]]. Repo is `aegissystems/sales-dashboard`, cloned at `/home/mork/work/sales-dashboard`. Deploy via `kubernetes-deployments` repo at `argocd/env/388576304176/us-west-2/inference-eks-Ny9n/cluster-values.yaml` → ArgoCD auto-sync. Cluster: `inference-eks-Ny9n`. Repo entity note covers architecture, existing pages, scripts, caching, deploy mechanism, and reusable Snowflake-client surface.

---

## Category 6 — Risk / Investigation (known unknowns)

Goal: surface the gaps in our model of the pipeline. These are not "do this work" items but "we don't yet know enough to plan."

### I1. The `_started` re-introduction question

**Why:** Crash-path gap (T1) may want to resurrect `_started` as a "we know the run began" beacon. This contradicts the [[2026-05-07_site-product-started-deprecated|dormancy decision]]. Resolve by talking to billing-system consumer before any code change.

**Action:** include in T1 design doc.

---

### I2. The "is admin or Immix authoritative" question

**Why:** [[2026-04-30_data-model-cascade-semantics]] surfaces three concrete cases where admin and Immix disagree. Self-righting via cascade is a useful primitive but presumes one side is right. If a customer's Immix-side schedule is Deleted, is that the customer's intent or an Immix bug?

**Action:** ADR — "When admin and Immix disagree, which wins, and on what evidence?" Likely answer: Immix is authoritative for customer intent; admin is authoritative for billing surface. But this needs to be explicit.

---

### I3. The crash-rate baseline question

**Why:** Before designing crash-emit (T1), we need to know the actual crash rate. 79% AP-cronjob-silent is dominated by *what*? If 95% of the silent population is "ran clean, no products" the [[autopatrol-deferred-backlog]] T1 fix is already mostly addressed. If 50%+ is crash, we have a real OOM / signal-handling problem.

**Action:** spot-check at the start of T1.

---

### I4. The "are tests asserting emit?" question

**Why:** PR #1684 removed several tests asserting `_started` behavior. The remaining test suite covers `_ended` paths but coverage map is unclear. A new emit-site that silently breaks the per-stream loop would pass tests.

**Action:** test-coverage audit on the emit code path. Cross-link to [[software-architecture/_summary|software-architecture]] enforcement work if any rules emerge.

---

## Category 7 — Sales-dashboard utilization (added 2026-05-11)

Surfaced by [[2026-05-11_eng-242-substantially-answered]] when [[sales-dashboard-repo]] revealed substantial Snowflake-side billing infrastructure already in production. These items are about *using* what already exists, not building from scratch.

### NF1. Clone and inventory `actuate_bi` repo (DONE 2026-05-11 — closed C2 remainder)

**Status (2026-05-11):** **DONE.** Cloned at `/home/mork/work/actuate_bi`. Inventory in [[actuate-bi-repo]] entity note. [[snowflake-billing-tables]] updated with authoritative DDL from `tf/*.tf` (the `sql/snowflake/*.sql` files drift in spots — three known cases). Three operational-risk findings surfaced: (1) SPRD swap non-transactional → NF7, (2) Load Top Parents race vs SPRD swap → NF7, (3) SQL/TF drift → NF8.

ENG-242 closed alongside this (data team off the hook).

---

### NF2. Promote `reconcile_cameras.py` to a Tier-1 dashboard signal (DEPLOYED 2026-05-11 ✓)

**Why:** [[sales-dashboard-repo]] `scripts/reconcile_cameras.py` is already an operational implementation of the [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]] — anti-joins SPRD against `usage_monthly` (the missing-Ordway-subscription gap), categorizes results into Production / Trial / Internal / Healthcheck-only, and prints a full reconciliation balance. Promoting it to a Tier-1 signal is much less work than building from scratch.

**Acceptance:**
- Wrapper script at `~/bin/billing-reconcile-check` (Tier-1 pattern per [[three-tier-routine-check-pattern]]) that:
  - Calls `reconcile_cameras.py --month` for current month.
  - Parses the stdout output OR (better) refactors the script to emit JSON.
  - Writes structured output to `~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM-DD.json` with keys: `production_unbilled_count`, `production_unbilled_hours`, `trial_pilot_count`, `internal_count`, `provisioned_no_events_count`, `connector_gap_pct`, `clip_gap_pct`, `vch_provisioned_count`, `reconciliation_balanced` (boolean).
- systemd `--user` timer on Firebat — daily at 04:00 PT (post-1 AM EST swap).
- `~/.claude/skills/dashboard-check/config/signals.json` entry per the [[2026-05-11_billing-reconciliation-dashboard-design]] §"Implementation outline" sketch.
- Thresholds per R1 design: production_unbilled_count > 200 → yellow, > 500 → red (calibrate from baseline).
- Replay test: run against 2026-05-04 cohort F window — does the signal go red?

**Implementation effort:** **1–2 days** (vs 1 week from scratch). Most of the heavy lifting (Snowflake auth, query design, Postgres reconciliation join) is done.

**Status (2026-05-11):** **DEPLOYED TIER-1 on mork-firebat.** End-to-end success:
- Wrapper at `/home/mork/work/local_network_scripts/files/billing-reconcile-check.py` (also deployed to `mork-firebat:~/bin/billing-reconcile-check`).
- Deploy codified at `/home/mork/work/local_network_scripts/phase-16-billing-reconcile.sh` (re-runnable, idempotent).
- IAM: inline policy `billing-reconcile-readonly` on `dashboard-check-rolesanywhere` role (SM:GetSecretValue on `prod/actuate/postgres-*`). Policy JSON at `files/iam-policy-billing-reconcile-additions.json`.
- systemd: `billing-reconcile-check.timer` enabled on Firebat, fires daily 04:00 PT (next: `Tue 2026-05-12 11:00 UTC`). Persistent=true survives reboots.
- signals.json: three signals appended on Firebat (`billing_production_unbilled_cams`, `billing_reconcile_residual`, `billing_reconcile_freshness`) all enabled=true.
- First real run (manual fire from phase-16): `exit_status=ok`, `reconciliation.balanced=true`, `production_missing_subscription.cameras=2024`. **Dashboard signal currently RED** (above red_above=1500 — by design; this is the value-add demo).

**Source-of-truth `reconcile_cameras.py` is NOT modified** — the wrapper references it from outside (subprocess + stdout parser). Library extraction tracked as NF6 (only if a second consumer surfaces).

**Deploy pattern:** `phase-16-billing-reconcile.sh` is re-runnable. Use to re-deploy after pulling repo updates or rotating credentials. Two notable patches in the script: (1) `AWS_PROFILE=dashboard-check` is patched into both the systemd unit and the deployed .env (because the wrapper's env-merge order means .env wins over systemd Environment), (2) `uv sync` uses `--no-config --default-index https://pypi.org/simple/` to bypass CodeArtifact auth.

**Verification commands:**
```bash
ssh mork-firebat 'systemctl --user list-timers billing-reconcile-check.timer'
ssh mork-firebat 'jq ".exit_status, .reconciliation.balanced, .unbilled.production_missing_subscription.cameras" /home/mork/.local/state/minipc-tasks/billing/reconciliation-$(date +%F).json'
```

**Promote to mark-todos:** already there (§28 sub-item) — flip to ✅ on next pass.

---

### NF3. Production unbilled-camera follow-up — 2,024 cameras (May 2026, was 803 in Feb 2026) (DEMO of system value — not our scope to fix)

**Reframing 2026-05-11:** This is not our engineering scope to remediate. It's a *demonstration* that the reconciliation system the [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]] specs and [[sales-dashboard-repo]] `reconcile_cameras.py` already produces is **surfacing real revenue gaps in the wild — and the gap is growing**. Treat as a value-add data point to share with the right audience — likely sales ops / finance / Tatiana — not as a connector-side fix.

**The current number is the better hook than the Feb baseline:**
- May 2026 actual (per first real wrapper run 2026-05-11): **2,024 production cameras / 4,018,433 compute-hours**, missing Ordway subscription
- Feb 2026 baseline (per [[sales-dashboard-repo]] CLAUDE.md): 803 cameras
- **2.5x growth in 3 months** — exactly the slow-drift class the reconciliation system catches that nothing else does

**Where to file (TBD):** Slack to billing/sales-ops channel once we identify it. Or a recurring report. Not an ENG Jira ticket — this isn't engineering bandwidth. Pin once filing target is identified. When filing, lead with the trend (803 → 2,024) and the current $-equivalent (4M hours × rate / month).



**Why:** Per the Feb 2026 baseline in [[sales-dashboard-repo]] (CLAUDE.md L327-340 — *snapshotted Feb 2026, may have shifted by now; confirm against current month*), the following production accounts run billable products but are not in `usage_monthly` (no Ordway subscription, or subscription doesn't cover all cameras):

| Account | Unbilled (Feb 2026) | Hours | Note |
|---|---:|---:|---|
| Active Watch Security | 132 | 60,147 | Subscription doesn't cover all cameras |
| Aggregate Industries | 102 | 52,773 | **No Ordway subscription at all** |
| Alarm Watch | 46 | 4,836 | Large gap vs 89 billed |
| CAP Security | 39 | 10,266 | **No subscription** (17 healthcheck-only) |
| Eagle Eye Networks | 26 | 22,772 | **No subscription at all** |
| Bandit Systems | 15 | 8,087 | |
| Others | 84 | various | 19 smaller accounts |

This is a **direct revenue leak that's been in production for at least a month**. Each camera × month × product is a missed invoice line.

**Acceptance:**
- Confirm current state by running `reconcile_cameras.py --month` against the **current month** (Feb baseline may have shifted).
- Cross-reference with HubSpot — are these accounts in a non-Active status (which would explain the missing subscription)?
- Coordinate with sales / billing ops to either (a) create the missing Ordway subscription, (b) confirm the camera should not be billed (and document why), or (c) escalate to account owner.
- Track resolution per-account in a follow-up daily-note or concept.

**Blocked by:** nothing on our side. Belongs as a follow-up via sales/billing ops.

**Promote to mark-todos:** as a sales-ops collaboration item; not a pure-engineering workstream.

---

### NF4. Trial conversion candidates — 1,169 cameras across 52 accounts (MED — sales follow-up)

**Why:** Per Feb 2026 baseline in [[sales-dashboard-repo]] (CLAUDE.md L348-356), several trial/pilot accounts are running at production scale and are strong conversion candidates:

| Account | Unbilled | Avg Hrs/Cam | Note |
|---|---:|---:|---|
| Securitas Australia - Trial | 738 | 441 | By far the largest trial |
| Fidelity ADT - Trial | 20 | 877 | Running near 24/7 |
| Cam Security Services - Trial | 11 | 1,568 | Running 24/7 on all cameras |
| Interactive Security - Trial | 5 | 1,231 | Running 24/7 |
| Technites - Trial | 6 | 998 | |
| iNET - Trial | 9 | 958 | |
| P4 Security Solutions - Trial | 26 | 546 | |

**Acceptance:** Hand off the list to sales for outreach. Not a code/engineering deliverable.

**Blocked by:** nothing on our side. Pure sales-collaboration.

---

### NF6. Extract billing-reconcile wrapper parser to a library (LOW — only if more general use surfaces)

**Why:** The wrapper at `/home/mork/work/local_network_scripts/files/billing-reconcile-check.py` parses `reconcile_cameras.py` stdout using regex over the SUMMARY + FULL RECONCILIATION blocks. If we end up with multiple consumers of the same parsed output (e.g., a follow-up Tier-1 alert that's distinct from the dashboard signal, or another team's reporting tool), the parser belongs in a library — likely [[actuate-libraries]] under a `billing_reports` package.

**Acceptance:**
- Identify ≥2 distinct consumers needing the same parsed output.
- Move `SUMMARY_PATTERNS` + `parse_reconcile_output` into a library package.
- Wrapper script becomes a thin caller.

**Trigger:** when the second consumer surfaces. Otherwise this stays a no-op.

---

### NF7. Add `IF EXISTS` guard to SPRD daily-swap task in actuate_bi (LOW — defense-in-depth)

**Why:** Per [[actuate-bi-repo]] §"Operational risks" — the `raw.aws.analytics_event_summarize_daily` task in `actuate_bi/tf/tasks.tf` L45 (and `sql/snowflake/raw/aws/tasks/analytics_event_summarize_daily.sql`) executes a 4-statement swap WITHOUT transactional wrapping. The first RENAME has **no `IF EXISTS` guard**. The parallel clip-table swap (`clip_received_day_summary`) does have it. Add the guard to SPRD for parity.

Adjacent: investigate whether wrapping the four DDLs in `BEGIN TRANSACTION; ... COMMIT;` would actually be safe in Snowflake (some DDLs are non-transactional anyway; verify).

**Acceptance:**
- `tf/tasks.tf` SPRD task body updated with `IF EXISTS` on first RENAME.
- Or — if Snowflake supports transactional DDL wrapping — wrap the swap in an explicit transaction with proper rollback semantics.
- `terraform plan && terraform apply` from the actuate_bi repo.

**Blocked by:** nothing on our side, but **not our repo** — needs data-team ownership or coordination.

**Cross-link:** [[actuate-bi-repo]] §"Operational risks".

---

### NF8. Add CI to actuate_bi diffing `sql/snowflake/*.sql` against `tf/*.tf` deployed state (LOW — drift prevention)

**Why:** Per [[actuate-bi-repo]] §"Critical drift" — three known DDL drifts between reference SQL files and Terraform-defined deployed state (`subscription.sql` missing 2 cols, `analytics_event.sql` missing `LOAD_TIMESTAMP`, no SPRD `.sql` at all). The drift is undetected because no CI compares the two. New contributors reading the SQL get a stale picture.

**Acceptance:**
- GitHub Actions job that runs `terraform plan` on PR and surfaces any object whose state differs from declared.
- Or — `sql/snowflake/` deleted entirely if it's truly reference-only and not useful (the comment in subscription.sql literally says "saved here for reference only").
- Decision documented in the repo.

**Blocked by:** not our repo — needs data-team buy-in.

---

### NF9. Historical-month replay against pre-fix data (LOW — validation of "would have caught Cohort F" claim)

**Why:** The `billing_production_unbilled_cams` dashboard signal's `would_have_caught` field claims "Cohort F missing-subscription class (~400 of the 642 cams)." That's an unsubstantiated claim until we run [[sales-dashboard-repo]] `reconcile_cameras.py` (via the [[2026-05-11_nf2-deployment-state|NF2 wrapper]]) against a pre-Cohort-F-discovery month (e.g. 2026-04 or 2026-03) and observe the actual number. Current-month run (2026-05) already includes post-fix state; a historical replay shows the signal would have fired on the **drift**, not just the steady-state.

**Acceptance:**
- Run on Firebat: `~/bin/billing-reconcile-check --month 2026-04 --print` (and same for 2026-03 if Snowflake retention covers it — likely does, SPRD keeps a year).
- Capture the `production_missing_subscription.cameras` value for each historical month.
- Plot the trajectory: Feb (803 cams) → Mar → Apr → May (2024). If monotone increasing, the slow-drift class is exactly what the signal catches.
- If a sudden jump aligns with a known incident (PR / config change / customer onboarding wave), document it — that's the canonical example.
- Update [[2026-05-11_nf2-deployment-state]] §"First real run" with the trend table.

**Blocked by:** nothing. Each replay is ~30s of compute; trivial against Snowflake history.

**Promote to mark-todos:** when there's a 30-min window. Low priority but high-value-once-done — turns the signal from "claimed to catch" into "demonstrably caught."

---

### NF5. Wire sales-dashboard `/api/*` endpoints into local dashboard signals (MED)

**Why:** [[sales-dashboard-repo]] already exposes `/api/unbilled`, `/api/no-usage`, `/api/churn` (and more). For R1's surface — once the local Tier-1 signal works — the natural Phase-2 wiring is to read the *production* dashboard's API rather than re-running queries locally. This:
- Removes the daily Snowflake-query load duplication (the prod dashboard already caches them).
- Inherits the production cache freshness (24h Snowflake, 4h for camera-trend).
- Means our signal goes red simultaneously with the production dashboard reflecting the same — operators get one truth.

**Acceptance:**
- Local Tier-1 collector (NF2) configurable to fall back to `https://sales-dashboard.internal.actuateui.net/api/unbilled?month=YYYY-MM` instead of running Snowflake queries locally.
- Auth path: AWS Cognito (per [[sales-dashboard-repo]] guide §"Authentication"). Tier-1 needs a way to obtain the token — TBD; may require running on a machine with appropriate IAM.
- Health check: if the API is unreachable, the local collector falls back to direct Snowflake.

**Blocked by:** NF2 must ship first; auth path TBD.

**Promote to mark-todos:** Phase 2 of NF2.

---



Items currently promoted to [[mark-todos]] as active §N work:

- (none yet — this topic was scaffolded 2026-05-11; promotion is the next loop)

When promoting, format:
- This file: append `(mark-todos §N)` to the item heading.
- mark-todos §N: short summary + wikilink back to this file's anchor.

## Related

- [[_summary]] — topic overview
- [[2026-05-11_billing-pain-post-mortem]] — narrative the categories trace back to
- [[billing-events-catalog]] — catalog the items reference
- [[reading-list]] — sources informing the work
- [[mark-todos]] — workstream tracker (loose-linked, not duplicated)
- [[autopatrol-deferred-backlog]] — sibling topic backlog with overlapping items
- [[2026-04-30_data-model-cascade-semantics]] — primary source for S1-S4
