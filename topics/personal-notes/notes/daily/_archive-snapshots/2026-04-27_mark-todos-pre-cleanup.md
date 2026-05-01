---
title: "Snapshot: mark-todos.md pre-cleanup 2026-04-27"
type: snapshot
topic: personal-notes
tags: [snapshot, mark-todos, archive, pre-cleanup]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
source: topics/personal-notes/notes/entities/mark-todos.md
snapshot_reason: "Verbatim copy taken before the 2026-04-27 mark-todos cleanup that introduced the rolling-forward + per-day archive convention. Closed [x] items below were swept into per-date daily notes; full text preserved here as a safety net."
---

# Snapshot: mark-todos.md pre-cleanup 2026-04-27

> Read-only archival copy. The live file is at [[mark-todos]]. This snapshot exists so anything moved during the 2026-04-27 cleanup can be recovered if needed.

> **Note:** the "Current Jira Queue" section near the bottom is rewritten each day by [[automation-jira-sync]] — do not edit that section manually (see the HTML comment sentinels).

Personal workstream tracker for Mark Barbera's active work. High-level only — detail lives in individual concept/synthesis notes per topic. Update this as priorities shift.

Not the same as [[todo-list|autopatrol team todo-list]] (that one is product-team-wide).

---

<!-- BEGIN-SESSION-CLAIMS -->
## Active Session Claims

Shared coordination state for concurrent Claude Code sessions. Auto-managed by `/claim`, `/release`, and the SessionStart/Stop hooks in `~/.claude/hooks/`. Rows with heartbeat >2h stale are pruned on SessionStart.

Use `/claim <label> <scope>` at the start of any non-trivial session working on a tracked §N item. `/release` when done. `/claims` to view.

| Label | Scope | CWD | Started | Heartbeat |
|-------|-------|-----|---------|-----------|
| *(none claimed)* | | | | |<!-- END-SESSION-CLAIMS -->

---

## 2. AutoPatrol — finish outstanding tasks

### 2a. Test the release

- [ ] Verify current stage deploy is healthy
- [ ] Check prod for regressions
- Related agent: [[agent-release-chain-watcher]]

### 2b. Fix the deferred-alert race condition ✓ CLOSED 2026-04-20

- [x] Apply fix per investigation in [[2026-04-16_deferred-alert-race-condition]] — 4 commits landed 2026-04-16 on stage: `101ef2c4` (drain executors after flush), `17bbc1b4` (shutdown(wait=True) not sentinels), `e78fc3da` (guard against silent drops), `cca47fd1` (library pin bump)
- [x] Verify on stage — weekend regression check GREEN (stage-regression session)
- [x] Merge + deploy — squash-merged into rearchitecture (prod) via [vms-connector#1654](https://github.com/aegissystems/vms-connector/pull/1654) as `eeab2b43` on 2026-04-20T14:53Z; prod rollout GREEN through T+210min (see [[2026-04-20_vms-connector-pr-1654]]). Fix content verified on prod: `camera/shared/base_stream_camera.py` uses `send_executor.shutdown(wait=True)`; `camera/patrol/patrol_camera_mixin.py` has `drain_alert_executors`; new `test_vms/test_deferred_alerts.py` tests present.

### 2c. Push stage → prod with Brad Murphy's BB (bounding box) changes

**Ticket:** AUTO-351 — "Bounding boxes on AP clips to Immix" (marked ready to deploy in [[knowledgebase/topics/autopatrol/_summary|autopatrol summary]])

- [ ] Final verify on stage
- [ ] Push to prod
- [ ] Monitor Immix timeline for correct BB rendering

### 2d. AP/VCH alert-flow diagnostic enhancements

Two fleet-wide failure modes on AP/VCH alert flow surfaced during PR #1654 post-deploy investigation. Both present as "cameras offline" or "alerts not flowing" to customers but have distinct root causes and remediation paths. Grouped together because they're related investigations and need coordinated communication with the Immix team.

- [ ] **[vms-connector#1658](https://github.com/aegissystems/vms-connector/issues/1658) — `dev.powerplus.com` SSL cert-verify failure (fleet-wide)** — root-caused via `openssl s_client` probe: server serves leaf cert only, missing Sectigo DV R36 intermediate. 3,870 WebSocket attempts in 7d, 100% failing; blast radius +1 container on 2026-04-17. Cameras appear "broken" in healthcheck but are actually unreachable at TLS. Writeup: [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]]. Open actions:
  - [ ] Raise chain-completion fix with PowerPlus (via Immix)
  - [ ] Raise URL routing with Immix — why `dev.powerplus.com` for prod customers
  - [ ] Identify `connector-23202-chm-cronjob` customer + what changed 2026-04-17
  - [ ] Consider option-3 mitigation (pin Sectigo intermediate into custom SSL context) if external timelines slip
- [ ] **[vms-connector#1656](https://github.com/aegissystems/vms-connector/issues/1656) — `streamId: null` rejection on `raise_patrol_alert` (architectural)** — Immix's `/Patrols/{id}/raise` requires GUID streamId, but streamId is only delivered from `get_patrol_stream` which is the very call that's failing when we need to CNCTNFAIL. Writeup: [[2026-04-20_streamid-null-patrol-alert-bug]]. Open actions:
  - [ ] Await Immix response on preferred remediation (optional streamId for connectivity codes, or deviceId-keyed lookup endpoint)
  - [ ] Connector-side cleanup (unconditional): remove `uuid.uuid4().hex` fabrication in `patrol_camera.py:33`, remove hardcoded `""` defaults, log-and-skip instead of send-garbage
  - [ ] §10 cross-link: route `SiteDisabledOrDisarmed` subset through the cleanup Lambda pipeline
- **Context:** Both issues show up as "cameras offline" in customer-facing healthcheck UI — a diagnostic visibility gap. Today we can't distinguish "camera actually down" from "our TLS fails" from "Immix state hasn't propagated" from the customer's vantage point. Worth considering (future workstream): per-failure-mode healthcheck status codes that differentiate connector-side vs customer-side root causes.

---

## 3. New Lambda — AutoPatrol stale-schedule cleanup

**Repo:** `autopatrol_onboarder` ([aegissystems/autopatrol_onboarder](https://github.com/aegissystems/autopatrol_onboarder))
**Deploy:** new Lambda, sibling to the onboarder Lambda (same repo, separate function)
**Status:** plan approved 2026-04-17; §0 KB consolidation done; §6 admin-api fields next
**Plan:** `/home/mork/.claude/plans/sequential-questing-creek.md`
**Design synthesis:** [[2026-04-17_stale-schedule-cleanup-design]]

### Problem

Immix-side schedule deletions never flow back to our admin DB — stale cronjobs fire forever, logging "no patrols to run, exiting." No code path today flips `AutoPatrolSchedule.is_deleted=True` for these. See [[2026-04-17_autopatrol-sync-endpoint-behavior]] for why the existing bulk sync isn't the answer.

### Design (resolved)

```
VMS Connector (terminal "no patrols" exit — 6 sites)
  └─ SQS FIFO (payload includes cron + cadence_hours)
      └─ Cleanup Lambda (new)
          ├─ DDB counter keyed on schedule_id, TTL-only reset
          ├─ threshold = max(3, 48h / cadence_hours)  (cadence-aware)
          ├─ at threshold: Immix API confirms 404 / DEACTIVATED
          ├─ PATCH admin: is_deleted=True + disabled_by="cleanup_lambda"
          └─ Slack audit → #autopatrol-sync
Re-enable Lambda (sibling, IAM-auth'd Function URL)
  └─ admin UI "Re-enable" button → verify Immix → PATCH is_deleted=False
```

### Key decisions (2026-04-17 interviews)

- Revert was misaimed — keep onboarder's `auto_patrol/sync/` call (it's load-bearing for new-site creation); drop only the unused `allow_deletion` flag
- Counter state: DynamoDB owned by cleanup Lambda, TTL self-expires
- Threshold: cadence-aware, connector ships cron in payload
- Disable: soft-delete with provenance fields; fully automatic with easy-revert UI + re-enable Lambda
- Slack: existing `#autopatrol-sync`
- Terraform: `ds-terraform-eks-v2` (see [[core-repo-suite]])

### Subtasks (from plan §0–§9)

- [x] §0 KB consolidation — 10 notes created/updated
- [x] §1 Onboarder branch cleanup — drop `allow_deletion`; part of [autopatrol_onboarder#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3)
- [x] §2 vms-connector emit helper + wire 6 exit sites (feature-flagged) — [vms-connector#1657](https://github.com/aegissystems/vms-connector/pull/1657) open for stage rollout
- [x] §3 Terraform SQS + DDB + 2 Lambdas in `ds-terraform-eks-v2` — [ds-terraform-eks-v2#69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) open (dev/EU only; prod deferred)
- [x] §4 Cleanup Lambda — autopatrol_onboarder#3
- [x] §5 Re-enable Lambda (IAM-auth Function URL) — autopatrol_onboarder#3
- [x] §6 Admin-api schedule provenance fields + migration + filter — [actuate_admin#2361](https://github.com/aegissystems/actuate_admin/pull/2361) open → `develop`
- [x] §7 NR instrumentation on both Lambdas — code-side done in [autopatrol_onboarder#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3) commit `7dc6a13` (custom events + no-op import wrapper). Terraform layer attachment still pending — tracked in Not-Yet-Prioritized. See [[2026-04-17_onboarder-nr-instrumentation-gap]].
- [x] §8 Deploy pipeline matrix-build — autopatrol_onboarder#3
- [ ] §9 Rollout — multi-step, stage-first (see below)
- [ ] §10 **Extend cleanup signal: route `SiteDisabledOrDisarmed` Immix responses to the same pipeline** — surfaced 2026-04-20 from [[2026-04-20_streamid-null-patrol-alert-bug]] investigation (5/10 of recent CNCTNFAIL failures in [GH#1656](https://github.com/aegissystems/vms-connector/issues/1656) were `SiteDisabledOrDisarmed`). Requires care: `SiteDisabledOrDisarmed` can be legitimately transient (site armed only during business hours), unlike "no patrols" which is deterministic-deletion. Proposed approach: connector emits a separate SQS event on `SiteDisabledOrDisarmed` (distinct event_type from "no patrols"), cleanup Lambda tracks occurrences per schedule over a LONGER window than "no patrols" (e.g. 30 days vs 48h), and only soft-disables if the site has been in that state continuously for the full window. Design decision needed before implementation: threshold window + whether to share DDB table or use separate one. Not blocking current §9 rollout — layer on after stage bake.

### Rollout steps

- [x] **Step 0a** Create stage SQS queue + DLQ in prod/us-west-2 (manual CLI — corrected from dev/EU on 2026-04-22)
- [x] **Step 0b** Create stage DDB counter table + TTL in prod/us-west-2 (manual CLI 2026-04-22)
- [x] **Step A:** `vms-connector#1657` merged to `stage`. Stage pods auto-emit.
- [x] **Step B:** `actuate_admin#2361` migration merged to `develop`. Provenance fields + `scheduleId` filter live.
- [x] **Step C:** Lambdas provisioned in prod/us-west-2 (CLI path, terraform deferred for prod).
- [x] **Step D:** `autopatrol_onboarder#3` merged to `master`. All 6 Lambdas deployed with `CLEANUP_ENABLED=false`. ~~Dark mode bake started.~~ See "Today's work" below for how this got validated.

### Today's work — 2026-04-23 hotfix + hardening pass

- [x] **#3a onboarder healthcheck hotfix** (PR #4) — downgraded silent-bail 404 return to `logging.warning`. Resolved [[2026-04-23_postmortem-onboarder-healthcheck|47h silent-failure incident]].
- [x] **#3b cleanup Lambda retry-idempotency fix** (PR #5) — DDB `ConditionExpression` on `last_message_id` prevents counter double-counting on SQS retries.
- [x] **#3c deploy workflow hardening** (PR #6) — fails on real AWS errors (not just ResourceNotFound), masks CodeArtifact token. Found via monitoring: prior workflow silently swallowed AccessDenied for 3 days, hiding partial deploys.
- [x] **#3d IAM policy v2** — added `lambda:UpdateFunctionCode` for cleanup + reenable ARNs in both regions. Root cause of partial deploys.
- [x] **#3e DLQ drained + pk=235 row reset** — pre-fix over-counted row deleted; DLQ emptied. Clean state pre-Step-E.

### Rollout — reframed 2026-04-23T18:00Z

**Key realization:** the "stage" queue has been carrying real Immix customer tenant messages the entire bake period (2 tenants, 7 schedule_ids, all VCH integration, admin_pks 138/159/223/234/235). `AUTOPATROL_STAGE=prod` on the Lambda env means every PATCH would hit the real admin DB. The "stage vs prod" split is really only about which connector pod image emits (stage-branch vs prod-branch image), not about real-vs-synthetic data. That's why the earlier week-long bake gate was excessive — we were already testing against prod behavior.

- [x] **Step E.1** (reframed as follow-up, task #19) — retry-idempotency fix organic exercise. Safety-net via anomaly-reset makes this a nice-to-have, not a gate.
- [x] **Step E.2** — `CLEANUP_ENABLED=true` flipped on cleanup Lambda us-west-2 at **2026-04-23T17:59:26Z**. Pre-flip acceptance state: 0 actual disables all-time, 0 would-PATCH all-time, 0 DLQ, dashboard GREEN.
- [ ] **Step E.3** (shortened) — monitor 24-48h post-flip for the 7 known schedules emitting. Gate to Step F on: 0 DLQ growth, 0 wrong-disable events, anomaly-reset continues working as expected. No need for full week.
- [ ] **§3 follow-up: Immix error-pattern observability** (surfaced 2026-04-23). Immix returns 400 + "system is unavailable" body for schedules that are actually gone — we just fixed that one case (PR #7) but Immix is known to deviate from REST conventions, so other status codes / body shapes may also mean "gone." Instrument `_check_immix` with structured log fields (`immix_status_code`, `immix_body_first_100_chars`, `verdict`) and/or an `AutoPatrolImmixResponse` NR custom event so new patterns surface in aggregation queries rather than silent multi-day retry loops. Full catalog + recommendations: [[2026-04-23_immix-api-error-patterns]]. Not blocking Step E.3.
- [ ] **Step F:** Prod US scale-up — flip `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` on prod connector pods. Lambda already consumes from prod queue. This is a volume event, not a criticality event.
- [ ] **Step G:** Prod EU — needs net-new infra (SQS + DDB + Lambda mirrors in eu-west-1). Separate track. IAM policy v2 already has EU ARNs pre-granted for when infra lands.

### Monitoring / hand-off pointers (for another agent picking up)

- **Morning check-in:** run `/autopatrol-cleanup-lambda-check` — covers all the pre-flip + post-flip validation. §8b/8c/8d specifically target the 2026-04-23 fixes.
- **Watch list:** [[2026-04-24_morning-watch-list]] — expires 2026-04-25 once everything's green.
- **Dashboard signals** (staged in `~/.claude/skills/dashboard-check/config/signals.json`, `enabled: false` awaiting Phase 1b):
  - `cleanup_lambda_dlq_depth` (critical, must be 0)
  - `cleanup_lambda_errors`
  - `cleanup_lambda_actual_disable_rate` ← **new 2026-04-23, manager-visible audit metric (actual PATCHes)**
  - `cleanup_lambda_anomaly_reset_rate` ← **new 2026-04-23, "reached threshold but Immix said active → did NOT disable" — the Immix-side-mismatch gauge**
  - `cleanup_lambda_anomaly_repeat_offenders_7d` ← **new 2026-04-23, flappy/mismatched schedule detector (same sched resetting 2+ times in 7d)**
  - `cleanup_lambda_would_patch_rate` (should stay near 0 post-flip)
  - `cleanup_chm_emit_24h` + `patrol_exit_emit_rate` (upstream emit volume)
- **Audit trail for manager:** `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda` — returns any schedule ever disabled by this Lambda. **First row landed 2026-04-23T22:09:58Z**: admin_pk=235 (Immix `636be1ba-57c9-4da1-c534-08de1b193ea0`), disabled after the 400-as-gone fix in PR #7. See [[2026-04-23_cleanup-rollout-day]] §Timeline 22:09:57.
- **Rollback path:** flip `CLEANUP_ENABLED=false` via `aws lambda update-function-configuration`. Instant. No data loss; DDB counters keep accumulating but no PATCHes fire.
- **Re-enable individual schedules:** the sibling reenable Lambda (`immix-autopatrol-schedule-reenable`) via IAM-auth'd Function URL. Reverses any disable.

### Related

- [[2026-04-17_stale-schedule-cleanup-design]] — load-bearing design synthesis
- [[2026-04-22_cleanup-lambda-bake-state]] — **DDB counter snapshot, IaC drift finding, Step E flip-readiness analysis (2026-04-22T14:30Z)**
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — post-hoc lambda build/tune recipe
- [[autopatrol-cleanup-lambda]] — entity page (stub)
- [[autopatrol-onboarder]] — sibling Lambda (deletion-safety section corrected)
- [[2026-04-17_autopatrol-sync-endpoint-behavior]]
- [[2026-04-17_no-patrols-emit-points]]
- [[2026-04-17_onboarder-nr-instrumentation-gap]]
- [[todo-list|AutoPatrol team todo-list]]
- [[knowledgebase/topics/autopatrol/_summary|autopatrol topic]]

---

## 4. API keys per customer within a group (v5 follow-up)

**Status:** design phase — **interview + plan required before any implementation**
**Context:** follow-up to §1 (v5 API / EBUS); expands partner-facing API access from one-key-per-partner to one-key-per-customer-within-a-group
**Priority:** after §1 ships

### Desired behavior

1. **Group admin UX** — a new permission in group settings unlocks a page that lets a group admin generate an API key for any individual customer under their group.
2. **Customer self-serve UX** — a separate page on the config site where the customer (or the main customer contact) can generate their own key.
3. **Per-key permissions are independent** — keys track their own permission set; a customer's key can only hit the models that customer is allowed to access, regardless of what the group-level key can reach.

### Design surface (open questions — resolve in interview/plan phase)

- Where does the keygen UI actually live — admin site (`actuate_admin`), config site (camera-ui / alert-ui?), or both with slightly different affordances?
- How is "customer within a group" modeled in `actuate_admin` today? Is it a `User`, a `Customer` record, a sub-group? The data model answer drives everything else.
- Who is allowed to generate: group admins only, customer self-serve only, or both with a setting to disable self-serve per group?
- Per-key scoping granularity (MVP vs. later) — models only? endpoints (e.g. v5 detect vs. submit)? sites? detection-count limits?
- Key lifecycle — expiration default, rotation cadence, revocation UI, audit log, "who generated this" provenance.
- Authorizer impact — does the existing Rust Lambda authorizer's DynamoDB lookup support a richer permission payload, or does it need a schema change? Versioned key format to stay backward-compatible?
- Billing / usage metering — per-key, per-customer, or per-group? Needed from day one or later?
- Rate limits — per-key?

### Pre-implementation plan

- [ ] Interview: meet with the EBUS / v5 stakeholder(s) to validate the UX and nail down the "customer vs. group" data model
- [ ] ADR covering data model, auth flow, UI placement — use [[adr-writing-guide]]
- [ ] Decide MVP scope for per-key permission granularity
- [ ] Spec against existing `actuate_admin` RBAC so we don't duplicate primitives
- [ ] Authorizer impact assessment — breaking change? versioned key format? migration path for existing keys?
- [ ] Security review before building — apply [[security-hardening-checklist]] to the design (RBAC-first, bounded inputs, audit trail, revocation story)

### Related

- §1 — v5 API work this follows from
- [[inference-api/_summary|inference-api topic]] — authorizer + endpoint surface
- [[admin-api/_summary|admin-api topic]] — user/group/customer/RBAC primitives
- [[external-api/_summary|external-api topic]] — partner-API initiative context
- [[security-hardening-checklist]] — design-review gate

---

## 5. Fleet Architecture — review and consolidate 2026-04-16 proposals

**Priority:** this-week
**Tickets:** *(pre-ticket — captured in [[fleet-architecture/_summary|fleet-architecture]] topic syntheses)*
**Status:** review phase

### What's left

- [ ] Review each proposal and annotate with questions / concerns / deal-breakers
- [ ] Apply [[2026-04-16_evaluation-rubric|evaluation rubric]] consistently across all 5
- [ ] Pick top 2 for team deep-dive
- [ ] Decide whether [[2026-04-16_graceful-failover-design|graceful failover]] and [[2026-04-16_frame-transport-comparison|frame transport]] should become ADRs

### Proposals

- [[2026-04-16_proposal-a-minimal-split|A — Minimal split]]
- [[2026-04-16_proposal-b-stage-fleets|B — Stage fleets]]
- [[2026-04-16_proposal-c-camera-worker|C — Camera worker]]
- [[2026-04-16_proposal-d-event-driven|D — Event-driven]]
- [[2026-04-16_proposal-e-hybrid-sidecar|E — Hybrid sidecar]]

### Relevant KB

- [[fleet-architecture/_summary|fleet-architecture topic]]
- [[2026-04-16_evaluation-rubric|evaluation rubric]]
- [[2026-04-16_graceful-failover-design]]
- [[2026-04-16_frame-transport-comparison]]

### Related

- [[adr-writing-guide]] — if any proposal graduates to an ADR

---

## 6. Software Architecture — sketch local implementations of the 5 projects + dashboard

**Priority:** this-week
**Tickets:** *(pre-ticket — captured in [[knowledgebase/topics/software-architecture/_summary|software-architecture]] topic syntheses)*
**Status:** prototyping phase

Goal: stand up **minimal local sketches** of each of the 5 projects/designs drafted 2026-04-16 in the software-architecture topic. Goal is feel + viability feedback, not production-ready systems. Plan lives at [[2026-04-17_local-sketches-plan]].

### Projects to sketch

- [ ] [[2026-04-16_code-health-dashboard|Code health dashboard]] — extensible dashboard consolidating code health metrics
- [ ] [[2026-04-16_tooling-landscape|Tooling landscape]] — pick 2-3 tools from the catalog to actually try locally
- [x] [[2026-04-16_metrics-to-track|Metrics to track]] — complexity collector done 2026-04-23 evening (commit `263cd1a` on `main` of `/home/mork/work/software-arch-sketches`). Radon cyclomatic complexity across 239 files / 1,370 functions in vms-connector. Summary: mean 3.62, median 2, p95 13, max 121; A/B/C/D/E/F rank split 1146/128/67/22/4/3; 0 parse failures; ~0.5s runtime. Top offender: `AnalyticsSiteManager._log_memory_breakdown` (cc=121). Findings note: [[2026-04-23_sketch-findings-metrics]]. Coverage integration deferred to a later iteration; first sketch scope stays complexity-only.
- [ ] [[2026-04-16_architecture-enforcement|Architecture enforcement]] — prototype one fitness function / import-rule check
- [ ] [[2026-04-16_tech-debt-agent|Tech debt agent]] — minimal patrol-and-report pass over one repo

### What's left (phase structure)

- [ ] Read the 5 syntheses end-to-end; capture cross-cutting integration points (what's shared? what's the data flow?)
- [x] Decide the shared substrate — one repo for all sketches? one per? pick and document. **DONE 2026-04-22** via `/daily-scope` task-2 interview: one flat scratch repo, Python 3.12+, vms-connector input. Documented in `topics/software-architecture/notes/syntheses/2026-04-17_local-sketches-plan.md` "Shared substrate decisions (RESOLVED 2026-04-22)".
- [x] Scaffold the repo — `/home/mork/work/software-arch-sketches/` scaffolded 2026-04-22 with 5 sibling modules, Flask+Chart.js dashboard, JSON-on-disk data, Makefile entry points, 6-test smoke suite passing, git-init'd on `main`. See plan note "Scaffolding complete (2026-04-22)" for full file list + verification. Added to [[core-repo-suite]] Local list.
- [ ] **Init + setup (parked)** — not doing today. Bundles: (a) **first commit** of the scaffold on the `main` branch (suggested message: `scaffold: initial directory layout + stubs + smoke tests`); (b) decide **remote** — GitHub repo under `aegissystems/software-arch-sketches` or keep local-only; (c) fix the 4 `datetime.utcnow()` deprecations across `metrics/collector.py`, `enforcement/rules.py`, `debt/patrol.py`, `tooling/runners.py` (1-line each: `datetime.now(datetime.UTC)`); (d) decide **PyPI index persistence** — either refresh CodeArtifact auth at session start or drop a local `uv.toml` pinning public PyPI for the sandbox (`--index-url https://pypi.org/simple/`). None are blocking for first-sketch work since `pip install -e .[dev]` already succeeded via public PyPI override; this item closes the housekeeping loop cleanly before the repo accumulates more code.
- [ ] Sketch each of the 5 at minimum fidelity (checklist above) — 1/5 done (metrics). Suggested order per plan note §"Next concrete steps": ~~metrics~~ → enforcement → dashboard wiring → debt → tooling.
- [ ] Wire the dashboard to read from the other 4 sketches so integration points are real, not stubbed
- [ ] Per-sketch note: `software-architecture/notes/concepts/2026-XX-XX_sketch-findings-<name>.md` — what was easy, what broke, what surprised me, what it implies for real implementation
- [ ] Consolidate: summary synthesis deciding which of the 5 to invest in first

### Target outcomes

- Hands-on feel for each project before committing engineering time
- Integration points verified (the dashboard actually reads real metrics from real enforcement/debt-agent outputs, not mocks)
- Prioritized order for which to build for real

### Relevant KB

- [[knowledgebase/topics/software-architecture/_summary|software-architecture topic]] — parent
- [[2026-04-17_local-sketches-plan]] — plan note (this workstream's reference doc)
- [[2026-04-16_code-health-dashboard]], [[2026-04-16_tooling-landscape]], [[2026-04-16_metrics-to-track]], [[2026-04-16_architecture-enforcement]], [[2026-04-16_tech-debt-agent]]

### Related

- [[engineering-process]] — day-to-day counterpart topic
- [[fleet-architecture/_summary]] — separate R&D track (§5)

---

## 7. Issue hygiene + backlog audit

**Priority:** backlog
**Tickets:** *(pre-ticket — captured in [[knowledgebase/topics/software-architecture/_summary|software-architecture]])*
**Status:** design phase
**Trigger:** [[2026-04-17_scan|2026-04-17 repo scan]] surfaced that many open issues have low-signal structure (sparse labels, empty or minimal bodies, ambiguous titles) — several were agent-generated with inconsistent format.

Goal: establish issue-creation standards across major Actuate repos and normalize the existing backlog. Plan of attack lives in [[2026-04-17_issue-hygiene-plan]]; proposed automation is [[agent-issue-auditor]] (not yet built).

### Design surface

- [ ] Draft issue-creation standards (title format, body sections, label vocabulary, linking conventions)
- [ ] Scope the audit — which repos first, how to prioritize, batching strategy
- [ ] Decide audit cadence — one-shot cleanup vs. periodic sweep via agent
- [ ] Decide whether to build [[agent-issue-auditor]] or do N manual passes first (build only when manual patterns stabilize)
- [ ] Define hygiene metrics — % of open issues with label + body + clear title, before/after
- [ ] Pilot on one repo (likely `vms-connector` — largest backlog, clearest signal)

### Relevant KB

- [[knowledgebase/topics/software-architecture/_summary|software-architecture topic]] — parent
- [[2026-04-17_issue-hygiene-plan]] — plan of attack (this workstream's reference doc)
- [[agent-issue-auditor]] — proposed agent outline
- [[repo-backlog/_summary|repo-backlog topic]] — daily scan snapshots that surface hygiene patterns
- [[skill-repo-scan]] — the scan skill whose low-signal output motivated this

### Related

- [[agents-catalog]] — where the proposed agent is listed
- [[2026-04-16_metrics-to-track]] — connects: "hygiene %" is a metric the dashboard could surface

---

## 9. Operational Dashboard — cross-repo shorthand metrics + per-project signal coverage

**Priority:** current (triggered by 2026-04-23 autopatrol_onboarder incident)
**Tickets:** pre-ticket (cross-repo R&D / process)
**Status:** sketch complete, ready for Phase 1 implementation
**Post-mortem:** [[2026-04-23_postmortem-onboarder-healthcheck]]
**AutoPatrol-scoped precursor:** [[2026-04-23_alarm-dashboard-sketch]]
**Full cross-repo design sketch:** [[2026-04-23_dashboard-sketch]] — load-bearing, covers surface, content, signal set, skill, launch-gate contract, regression detection logic, rollout plan
**Surface (locked 2026-04-23):** local static HTML under `/home/mork/Documents/worklog/dashboard/`, generated by `/dashboard-check` skill, view via `file://`. No server.

### Trigger

2026-04-21 `autopatrol_onboarder` PR merged + auto-deployed US + EU. CI green; deploy workflow reported success. A new `if res.status_code not in [200, 201]: return` healthcheck gate made every 5-min cron invocation early-return. Lambda `Errors=0` throughout (early-return is a normal exit). Silent break persisted ~47 hours until a customer reported "can't activate new schedules." Found via customer report, not monitoring. Full timeline + contributing factors in the post-mortem.

Two rules codified from the incident: [[feedback_fail_fast_guards]] (never abort on HTTP failures without design-phase sign-off) and [[feedback_acceptance_criteria_every_merge]] (every non-trivial merge needs acceptance criteria + post-deploy behavioral verification).

### Scope (cross-repo, not just AutoPatrol)

The AutoPatrol alarm-dashboard sketch [[2026-04-23_alarm-dashboard-sketch]] is the first concrete example. The generalized goal is a **single dashboard surface** with 1–2 behavioral signals per production-critical component. User directive 2026-04-23: the dashboard "will need to deal with **everything**, especially vms connector and the libraries and admin. Orienting and designing for easy monitoring is critical."

In-scope components (initial pass — expand as we audit):

| Component | Silent-regression risk | Candidate signal(s) |
|---|---|---|
| `vms-connector` (fleet) | high — per-site brokenness hidden in log volume | `patrol-exit emits/day`, OOMKills (new per-container chronic pattern), `streamId Guid` rejection count, CNCTNFAIL rate per site |
| `actuate-libraries` (pullers / pipeline / daos / etc.) | medium — consumed by connector, regression visible in connector signals | version drift alerts; consumer-side import check |
| `actuate-inference-api` | high — per-model detection could silently miss | per-model detection throughput, 4xx/5xx rates, per-partner-API-key activity |
| `actuate_admin` (Django + RBAC) | medium — config mutation without downstream effect | schedule-activation rate, tenant-create success, RBAC denial patterns |
| `autopatrol_onboarder` (3 Lambdas) | HIGH — this workstream's trigger | per the [[2026-04-23_alarm-dashboard-sketch]] (onboarder liveness + cleanup + reenable) |
| `autopatrol-server` | medium | patrol-completion rate, CNCTNFAIL per site |
| `camera-ui` + `alert-ui` | low-medium — user-visible, easier to detect | error rate from browser telemetry |
| Alert-delivery pipeline (`queue-*`, `smtp-frame-receiver`, `clips-smtp-worker`) | HIGH — customer-facing | queue depth, per-integration delivery rate |

### Principles (design-for-monitoring — to be echoed in fleet-arch + software-arch + engineering-process)

1. **Behavioral signals, not surface metrics.** `Errors=0`, `Invocations>0`, `200 OK` are not health signals. Activity-marker log lines + downstream side effects are.
2. **1–2 signals per component, reviewable in <60 seconds total.** Dashboard is for quick scan; drill-down is on-demand.
3. **Monitoring-friendliness is a first-class design dimension.** Every fleet-architecture proposal and every software-architecture sketch must answer "how do I know this is working?" before it's signed off. Apply to A-E rescore and per-sketch findings notes.
4. **Every repo owns its signals.** Per-repo `CLAUDE.md` carries the acceptance-criteria + signal-set definition. When a new feature ships, its signals must be added before merge. Skills that wrap the signal set are per-repo (`/autopatrol-morning-check`, etc.).
5. **Cross-repo aggregator is the daily-check surface.** `/dashboard-check` (new skill) queries each per-repo signal set and renders one consolidated view.

### What's left

- [x] **Surface decision** — locked 2026-04-23 to **local static HTML** (`/home/mork/Documents/worklog/dashboard/` + per-day subdirs + latest symlink). No server. File-based per run. See [[2026-04-23_dashboard-sketch]] "Form" section.
- [x] **Phase 1 plan approved** — detailed plan at `/home/mork/.claude/plans/clever-tickling-swing.md` (2026-04-23). Split into 1a/1b. Additional metric categories added to catalog: CPU/memory per deployment type (user-priority), AWS Budgets + cost anomalies, NR APM golden metrics, K8s HPA + ArgoCD.

#### Phase 1a — this session (2026-04-23) ✅ COMPLETE

- [x] KB capture: 1a/1b scope in sketch + §9 + engineering-process _summary (Step 0 of plan)
- [x] `config/signals.json` full catalog (~60 signals; 2 enabled for 1a)
- [x] `config/baselines.json` static values (recalibrated 2026-04-23 after smoke-run surfaced wrong fingerprint)
- [x] Shared sink: `sink/.schema.md` + empty `sink/observations.jsonl` + `sink.py` helper (`write_observation()` + `read_recent()`)
- [x] Skill scaffold: `SKILL.md`, `run.sh` (system-python-first with venv fallback + public-PyPI override), `requirements.txt`, `README.md`
- [x] `render.py` orchestrator with regression rules 1/2/5 + sink reader for morning summary
- [x] Jinja2 templates (index + component + regressions + macros) + CSS (dark theme, self-contained)
- [x] Collectors wired inline in SKILL.md (bash blocks for 1a; dedicated collect_*.sh in 1b)
- [x] Tests: 10 pytest tests pass including `test_onboarder_silent_earlyreturn_is_red` (**canonical acceptance test** — the 2026-04-23 incident is caught by Rule 5)
- [x] One end-to-end signal wired: `onboarder_activity_us` × `onboarder_lambda_invocations_us` — both running against live CW
- [x] Smoke run: `/home/mork/Documents/worklog/dashboard/2026-04-23/index.html` viewable, overall GREEN, exit 0

**Surprises surfaced (valuable calibration):**
- Initial "Fetched N contracts" fingerprint from the postmortem was wrong for the actual log format. Real activity fires `get_sites HTTP` per tenant-invocation. Recalibrated signal + baseline; dashboard correctly flipped to GREEN after.
- This validated the whole dashboard concept in one pass: live data went through classification, regression detection, sink persistence, HTML rendering, and produced a visually-reviewable RED-then-GREEN transition that matches reality. The pipeline is sound.

#### Phase 1b — in progress (continuation session needed)

**Pickup doc (READ FIRST):** [[2026-04-24_dashboard-1b-continuation]] — **supersedes** [[2026-04-23_dashboard-phase-1b-pickup]]. Self-contained continuation runbook with current state (21 signals enabled, dashboard GREEN), 9 remaining deliverables in recommended execution order, calibration lessons learned (null NR fields, log-level-case mismatch, sink source_skill filter), and quick-start commands. Read this first.

**Progress this session (2026-04-24):**
- Signal count: 6 → **21 enabled** across 6 components (vms-connector, alert-pipeline, autopatrol_onboarder, k8s-cluster, inference-api, cost)
- Catalog fixes: 9 signals had broken queries (`cpuUsedCoresVsLimitPercent`/`memoryUsedVsLimitPercent` null; inference container filter wrong) — all corrected with real NR field names
- 6 new alert-pipeline volume signals (silent_drop rule) — because most alert-pipeline services log only `level='info'`, volume-drop is the right health signal not error-count
- Thresholds recalibrated against 7d real data (evalink was 6× too tight; all new signals p75/p95 based)
- render.py new_pattern guard (both-sides-dict requirement to prevent first-run false-positives)
- daily-scope integration: `/dashboard-check` is now a standing Step 2c exec item; Step 2bb preflight checks sink writability

**Remaining 1b deliverables** (order from continuation note):

- [ ] **Replay tests for 7 historical incidents** — highest-value; locks in the "would have caught" promises
- [ ] **Regression rules 3 + 4** (baseline_drift 2σ, chronic_offender_promotion) — unlocks "signal is drifting" detection vs. just static thresholds
- [ ] **Morning-summary aggregation** from sink (source_skill != dashboard-check) — surfaces cross-skill observations in the grid
- [ ] **Sparklines tier 1** — inline SVG per-signal, 24h window; sink has 227+ rows, ready to draw
- [ ] **Hero carousel** (3 cards: heat-grid / top regressions / recent gates)
- [ ] **Compact grid + inline expand** (drop description column, <details>/<summary> drawer)
- [ ] **Data hooks** — rich data.json, sink.query() helper, embedded query snippets, kb_link field
- [ ] **Catalog coverage enrichment** — actuate-admin, inference-api per-model, autopatrol-server, actuate-libraries, config-drift signals
- [ ] **Baseline recalibration pass** — after ~1 week of sink accumulation (target 2026-05-01+)
- [x] `/daily-scope` Step 2c integration + fan-out sink writes — shipped 2026-04-24
- [x] `/daily-scope` Step 2bb preflight extension (verify sink) — shipped 2026-04-24
- [x] 15 primary signals enabled end-to-end (of originally-planned ~19) — shipped 2026-04-24
- [x] CPU/memory per deployment subset: cluster avg + vms + inference — shipped 2026-04-24
- [ ] **NEW (2026-04-23): Config-drift signals from OOM surge triage.** Add to the signal catalog: (a) `connector_pods_under_1gb_limit` — count of `containerName LIKE 'connector-%'` with `memoryLimitBytes < 1073741824`. Would have caught: 2026-04-23 fleet under-provisioning. (b) `connector_pod_headroom_over_70pct` — count of connector pods where `memoryWorkingSetBytes / memoryLimitBytes > 0.7`. Pre-OOM early-warning. (c) `vpa_updatemode_drift` — count of VPAs in `Off` mode that should be `Auto` (or vice-versa). (d) (future, cross-component) `s3_lifecycle_rules_disabled` — flags the `aegis-all-frames-v2-sts` disabled-rule pattern. These are **config-surface drift** signals (track the delta between declared and running state), cross-refs the [[2026-04-23_release-acceptance-criteria]] §5 rule added from the OOM triage. See [[2026-04-23_oom-surge-connector-limit-drift]] for the case study.

#### Phase 2+

- [ ] **Per-repo CLAUDE.md extension** — add "Release Acceptance Criteria" section to `vms-connector`, `actuate-inference-api`, `actuate_admin`, `actuate-libraries`, `autopatrol-server`, `camera-ui`, `alert-ui`. Canonical template: `/home/mork/work/autopatrol_onboarder/CLAUDE.md`.
- [ ] **Launch-gate wiring** — integrate into `/stage-release`, `/post-deploy-monitor`, `/validate-release`. Each release skill ends by running `/dashboard-check --gate <commit>` and BLOCKING declaration of success until green or timeout. Hard rule per [[engineering-process/_summary]] top principle.
- [ ] **Retrofit existing check skills** — `/autopatrol-overnight-check` + `/autopatrol-cleanup-lambda-check` write sink observations
- [ ] **Rolling-window baseline calibration** — replaces static baselines once 14d of sink data
- [ ] **Cross-time anomaly detection** — "same finding N days running → promote to tracked signal"
- [ ] **Coverage expansion** — actuate-admin, actuate-libraries, autopatrol-server, camera-ui, alert-ui full signal sets
- [ ] **Phase 2 additional metrics** — SSL cert expiry, CI failure rates, NR synthetic monitors, GuardDuty, Dependabot, RDS, stale-branch
- [ ] **Slack posting on RED** — optional, to `#autopatrol-sync` or dedicated channel
- [ ] **NR instrumentation of AutoPatrol Lambdas** — unblocks APM golden metrics for autopatrol specifically
- [ ] **Prior-art follow-ups** — DDB counter retry-idempotency bug (from post-mortem); audit other Actuate Lambdas for silent-early-return patterns

### Cross-topic integration

This work isn't confined to one topic — it cuts across three:

- **`engineering-process`** — the release-acceptance-criteria rule ([[2026-04-23_release-acceptance-criteria]]) is already filed here. Extend `_summary.md` to reference §9 + the dashboard principle. Release-related notes should treat "post-deploy verification against acceptance criteria" as mandatory.
- **`fleet-architecture`** — every proposal (A, B, C, D, E) must include a "monitoring & alarms" subsection answering: what signals prove this proposal is working, what goes on the dashboard, what's the acceptance criterion for a rollout. Fold into [[2026-04-16_evaluation-rubric]] as a scoring dimension. Amend the [[2026-04-22_fleet-proposal-rescore-with-delta]] addendum list with a monitoring-friendliness axis if not already present.
- **`software-architecture`** — the [[2026-04-17_local-sketches-plan]] sketches must demonstrate monitoring hooks from the start. The dashboard sketch itself fits in the [[2026-04-16_code-health-dashboard]] concept — either the two collapse into one initiative, or they're kept distinct with a cross-link (operational-health vs. code-health).

### Phasing (proposed)

- **Phase 0 (this week):** complete signal inventory for autopatrol (done), plus vms-connector, inference-api, actuate_admin. Decide surface.
- **Phase 1:** build `/dashboard-check` skill with the inventoried signals, ship to morning rituals.
- **Phase 2:** extend CLAUDE.md rules to every in-scope repo; add acceptance-criteria enforcement to `/stage-release` + `/post-deploy-monitor`.
- **Phase 3:** build the dashboard UI (CW or NR) for non-skill-based review; instrument missing NR wiring (AutoPatrol Lambdas first).
- **Phase 4 (ongoing):** negative feedback loop — any incident that surfaces a missing signal triggers a signal-set update.

### Related

- [[2026-04-23_postmortem-onboarder-healthcheck]] — the trigger
- [[2026-04-23_alarm-dashboard-sketch]] — AutoPatrol-scoped precursor (generalized here)
- [[2026-04-23_release-acceptance-criteria]] — the global rule this workstream operationalizes
- [[feedback_fail_fast_guards]] — hard rule surfaced by the incident
- [[feedback_acceptance_criteria_every_merge]] — hard rule surfaced by the incident
- [[skill-autopatrol-cleanup-lambda-check]] / [[skill-autopatrol-overnight-check]] — per-repo check-skill pattern
- [[2026-04-14_connector-fleet-monitoring]] — existing fleet-monitoring synthesis (partial overlap)
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — Lambda-specific operational checks
- [[2026-04-16_code-health-dashboard]] — adjacent dashboard concept (code-health, not ops-health)
- Skill chain (target): `/daily-scope` → `/dashboard-check`; `/stage-release` → `/post-deploy-monitor` → `/dashboard-check`

---

## 8. Multi-agent / multi-model setup for KB source research

**Priority:** backlog (earmark time this week)
**Tickets:** *(pre-ticket — R&D)*
**Status:** scoping
**Trigger:** 2026-04-20 session — desire to defer KB source research (ingest, synthesis, repo scans) to cheaper / higher-quota models (Gemini, Codex, self-hosted) to preserve Opus/Sonnet token budget for code work.

### Goal

Offload high-token, low-judgment work (raw source digestion, first-pass summarisation, repo enumeration) from Claude Opus/Sonnet to secondary models, so the main Claude Code session budget is spent on orchestration, synthesis quality, and coding.

### Reference

- [openclaw-claude-code](https://github.com/Enderfga/openclaw-claude-code) — programmable bridge turning coding CLIs into headless agentic engines. Features worth studying:
  - Multi-engine sessions (Claude, OpenAI Codex, Gemini, Cursor, custom) via unified `ISession` interface
  - Multi-agent council w/ git worktree isolation + consensus voting + two-phase (plan → execute) protocol
  - Session inbox for cross-session messaging (idle = immediate, busy = queued)
  - Ultraplan (dedicated Opus planning agent, ~30 min explore → detailed plan) and Ultrareview (fleet of 5–20 bug-hunters)
  - OpenAI-compatible API surface — drop-in for existing tooling; maximises Anthropic prompt caching via stateful sessions

### Design surface (open questions)

- [ ] **Which KB tasks are offload candidates?** — inventory current KB skills (`/kb-ingest`, `/kb-synthesise`, `/kb-auto`, `/repo-scan`, `/kb-sync`) and classify by Claude-dependency (judgment-heavy vs. summarisation-heavy)
- [ ] **Which models to route to?** — Gemini 3.x Pro (long context, cheap), Codex (code-context), self-hosted (privacy). Match task profile to model.
- [ ] **Integration surface** — new subagent type that routes to non-Claude model? Or a `kb-delegate` skill that spawns an external process? Or adopt openclaw wholesale?
- [ ] **Prompt caching strategy** — Anthropic prompt cache has 5-min TTL; if we hand off to Gemini, we lose cache affinity. Acceptable trade-off when the offloaded task is self-contained (summarise-this-URL) but not for multi-turn synthesis.
- [ ] **Output contract** — offloaded agents must return KB-shaped notes (frontmatter, wikilinks, concept/synthesis/entity distinction) or a normalized intermediate that `kb-scribe` can finalize.
- [ ] **Observability** — if Gemini hallucinates a summary, how do we catch it? Quality check pass by Claude? Sample-audit cadence?
- [ ] **Cost model** — map current KB ops to token cost baseline, then project savings at N% offload.

### Subtasks (pre-plan)

- [x] Seed KB synthesis note on multi-agent architecture options — written 2026-04-20 as [[2026-04-20_multi-agent-model-routing]] in engineering-process topic; frames problem + 3 integration options (direct subagent routing, openclaw wholesale, hybrid `/kb-delegate`) + recommends hybrid pilot
- [ ] ADR on routing policy once options are clear
- [ ] Pilot: offload one `/kb-ingest` run to Gemini end-to-end; compare output quality against a Claude-ingested baseline
- [ ] Decision point: adopt openclaw, build custom, or hybrid

### Relevant KB

- [[agents-catalog]] — current subagent surface (all Claude-backed)
- [[engineering-process/_summary|engineering-process topic]] — likely home for the synthesis note
- Session budget guardrails in global CLAUDE.md (KB / R&D soft-cap at ~80%) — this workstream exists in part to raise that ceiling

### Related

- §7 issue hygiene — similar "delegate the grunt work" motivation; findings here may inform [[agent-issue-auditor]]

---

## 9. AutoPatrol Alarm & Dashboard System

> **SUPERSEDED 2026-04-23** — this narrower AutoPatrol-scoped workstream is now folded into the cross-repo §9 above ("Operational Dashboard — cross-repo shorthand metrics"). The original sketch [[2026-04-23_alarm-dashboard-sketch]] remains the concrete AutoPatrol-specific seed; the generalized design is [[2026-04-23_dashboard-sketch]]. The cross-repo §9 Phase 1a shipped 2026-04-23 with the onboarder `activity_marker_antipattern` signal wired end-to-end. Left intact for `/todos-audit` to archive on next sweep. Duplicate section-number wart will clear itself when `/daily-wrap` or `/todos-audit` reconciles.

**Priority:** high — surfaced by 2026-04-23 onboarder incident
**Tickets:** *(no ticket yet — to be filed when planned)*
**Status:** design sketch written; awaiting planner session
**Trigger:** 2026-04-23 — silent early-return on onboarder Lambda broke new-schedule activation for ~2 days before a customer reported it. No alarm fired; no dashboard anomaly visible. Need a daily-checkable consolidated health surface.

### Goal

Design + implement a consolidated alarm + dashboard surface for the AutoPatrol system so anomalies surface within hours (not days). Cover:
- Onboarder liveness (contracts fetched, sites/schedules onboarded per region)
- Cleanup Lambda pipeline health (DLQ, error rates, anomaly resets, DDB counter sanity)
- Connector emit flow (emit rate ↔ SQS delivery ↔ Lambda consume)
- Upstream Immix API health (indirect signal via our error rates)
- Alert rate anomalies (`#autopatrol-sync` Slack cadence)

### Subtasks (pre-plan)

- [x] **Sketch design** — [[2026-04-23_alarm-dashboard-sketch]] — 5 metric families, 3 impl approaches (CW dashboards, NR-first, hybrid), dashboard mockup, 5 open questions for planner
- [ ] **Hand off to planner session** — pick up the sketch, produce a formal ExitPlanMode-style plan with scoped phases
- [ ] **Phase 1: unblock by wiring onboarder to NR** (NR layer, custom events `AutoPatrolOnboarderInvocation`) — known gap since this project kicked off
- [ ] **Phase 2: CloudWatch metric filters + dashboard** — cheapest + always-available surface. Start with the 5-metric dashboard mocked up in the sketch.
- [ ] **Phase 3: alarms + daily-review skill** — `/autopatrol-morning-check` that runs all queries in parallel + produces all-green/yellow/red output with auto-drill-down
- [ ] **Phase 4: baseline calibration + threshold tuning** — 14 days of "informational only" mode before enabling page/Slack alerts

### Relevant KB

- [[2026-04-23_alarm-dashboard-sketch]] — design sketch (this workstream's starting point)
- [[2026-04-23_release-acceptance-criteria]] — upstream rule this alarm system operationalizes
- [[autopatrol-onboarder]] — onboarder entity
- [[autopatrol-cleanup-lambda]] — cleanup entity
- [[2026-04-20_cleanup-lambda-runbook]] — existing manual commands, many become alarm queries

### Hand-off

Designated for a separate session to pick up. Sketch note has the 5-metric-family table + dashboard mockup; planner session should turn it into phased plan + ticket(s). Post-implementation: fold into `/autopatrol-morning-check` skill for daily review.

---

## 10. Laptop-config portability + disaster recovery

**Priority:** high (laptop-loss / reboot risk is always non-zero)
**Tickets:** *(pre-ticket — personal infra)*
**Status:** scoping
**Trigger:** 2026-04-23 user directive: *"I do not want to lose this monitoring setup, the rules, skills, and other configurations for all of this if I need to do a reboot or get a new computer."*

### Goal

A one-command bootstrap that reconstitutes this laptop's Actuate-related configuration on a fresh machine (or after a wipe). Covers: Claude Code skills + agents + hooks + global rules + per-project memories, systemd user services, the KB itself, the dashboard output layout, secrets-refresh runbook for things that can't be stored (AWS SSO, GH auth, NR MCP tokens, CodeArtifact tokens).

### Inventory — what needs to survive

**Claude Code config** (`~/.claude/`):
- `CLAUDE.md` — global rules
- `skills/<name>/` — all custom skills (`dashboard-check`, `daily-scope`, `cost-check`, `repo-scan`, `autopatrol-overnight-check`, `autopatrol-cleanup-lambda-check`, plus ~20 more). Each has SKILL.md + supporting files.
- `agents/<name>.md` — custom subagents (`nrql-investigator`, `actuate-pr-reviewer`, `connector-pipeline-expert`, `release-chain-watcher`, `kb-scribe`, `jira-landscape`, `research-prospector`, `source-reader`)
- `hooks/` — session-start + stop hooks (session-claims-startup.py, session-claims-heartbeat.py)
- `plans/<slug>.md` — approved plan files (retain for audit trail)
- `projects/<project>/memory/` — per-project memory. `-home-mork-work/` is the main one; others are per-CWD project scopes.

**systemd --user services** (`~/.config/systemd/user/`):
- `dashboard-server.service` — HTTP server on 8765 (created 2026-04-23)
- `jira-sync.service` + `.timer` — daily Jira auto-sync into mark-todos
- `overnight-check.service` + `.timer` — scheduled overnight health check
- any future scheduled agent triggers

**Knowledge base** (`~/Documents/worklog/knowledgebase/`):
- The Obsidian vault. Large, version-controlled separately from dotfiles. Treat as its own git repo (already probably is).

**Dashboard data** (`~/Documents/worklog/dashboard/`):
- `sink/observations.jsonl` — operational-event sink; historical value increases over time
- Per-day snapshot dirs — audit trail, retained forever per schema
- Needs to survive alongside KB (sibling directory)

**Cloned repos** (`~/.work/` — /home/mork/work/):
- `vms-connector`, `actuate-libraries`, `actuate-inference-api`, `actuate_admin`, `autopatrol_onboarder`, `autopatrol-server`, `camera-ui`, `software-arch-sketches`, `ds-terraform-eks-v2`.
- These are git-managed; the bootstrap just needs to clone them.

**System deps** (package-managed):
- `python3.12-venv`, `uv`, `gh`, `aws-cli`, `jq`, `curl`, `git`, `nodejs` (for Claude Code), plus Obsidian + VS Code / editor.

**Secrets / tokens (CANNOT store; runbook-only):**
- AWS SSO — `aws sso login --profile prod` / `--profile dev-eu`
- CodeArtifact — token refresh via `aws codeartifact get-authorization-token` (flows into `UV_INDEX` / pip.conf)
- GitHub — `gh auth login`
- Anthropic API key (if outside `claude` flow)
- NR MCP — probably re-auths via browser on first use
- Atlassian MCP — same
- Slack webhooks (if any referenced by skills) — TBD

### Approach options

1. **Dotfiles repo with `chezmoi`** — purpose-built for this (handles templates, secret-exclude rules, post-apply hooks). Commit to private `aegissystems/mork-dotfiles` or personal remote. Pros: idempotent, well-tested. Cons: adds a tool to learn.
2. **Dotfiles repo with GNU `stow`** — simpler, symlink-based, no secrets handling. Good for config-only; bootstrap script handles the rest.
3. **Plain git repo + bootstrap script** — one repo at `~/.dotfiles/` tracking the files, one `bootstrap.sh` that installs deps + symlinks config + enables services + prints a secrets-refresh checklist. Cheapest to build; no new tooling.
4. **Nix home-manager** — gold-standard reproducibility but massive surface-area learning curve; overkill.

Likely: **option 3** (plain git + bootstrap script) for v1, upgrade to chezmoi only if v1 friction shows up.

### What's left

- [ ] **Design phase:** pick approach (1 / 2 / 3 / 4) + decide what goes in the repo vs excluded vs runbook
- [ ] **Inventory pass:** enumerate every file/dir that should be tracked; produce an `ls -la`-style manifest committed to the repo
- [ ] **Build `bootstrap.sh`** — fresh-machine setup: install deps, clone KB, clone dotfiles, symlink config, enable systemd services, print secrets-refresh checklist
- [ ] **Backup story:** how the dotfiles repo gets pushed to a durable remote (private GH, S3, etc.). Cadence: auto-commit nightly? On-demand?
- [ ] **KB as separate git repo:** the Obsidian vault needs its own backup/remote. Check if already tracked; if not, git-init + remote.
- [ ] **Dashboard sink retention:** decide whether `~/Documents/worklog/dashboard/sink/observations.jsonl` rides in the KB repo (valuable historical data) or is backed up separately.
- [ ] **Secrets-refresh runbook** — one-page note at `topics/engineering-process/notes/concepts/laptop-secrets-refresh.md` documenting every credential to re-establish after a fresh machine
- [ ] **Disaster-recovery test** — on a throwaway VM or container, run `bootstrap.sh` and verify the session is functional end-to-end. This is the acceptance test for this whole workstream.
- [ ] **Ongoing discipline:** every time a new skill/agent/hook/service is added, verify it's tracked by the dotfiles repo (or auto-tracked). Fold into the existing post-push audit.

### Relevant KB

- [[engineering-process/_summary|engineering-process]] — likely home for the secrets-refresh runbook
- [[core-repo-suite]] — repo clone list already partially maintained there
- [[agents-catalog]] — subagent inventory
- Existing systemd units: `jira-sync`, `overnight-check`, `dashboard-server`

### Related

- §9 Operational Dashboard — the initiative that surfaced "I shouldn't lose this." Dashboard sink needs to ride along in the portability plan.
- [[skill-daily-scope]] — morning routine depends on the whole config being intact; a fresh-machine setup should produce a runnable `/daily-scope` within 30 min.

---

## 11. Firebat minipc — follow-ups from "always-on Claude dev box" setup (2026-04-23)

**Priority:** medium (core setup complete and verified; these are enhancements, not blockers)
**Tickets:** *(personal infra — no ticket)*
**Status:** scoping
**Trigger:** 2026-04-23 setup session: minipc provisioned end-to-end (19 pass / 0 fail on `phase-11-verify`). Obsidian Sync + Tailscale + persistent tmux + status dashboard all live. Two enhancements logged while still in-session.
**Scripts:** `/home/mork/work/local_network_scripts/` (12-phase toolkit, reusable for future boxes via `TARGET=user@host` env var)
**Context:** [[2026-04-23_firebat-minipc-as-claude-dev-box]] · [[2026-04-23_firebat-minipc-network-setup]]
**Access:** `ssh mork@mork-firebat` (Tailscale) or `ssh mork@fe80::8647:9ff:fe34:b4f2%enp0s31f6` (direct cable fallback)

### 11a. Wire a specific scheduled Claude job

The `~/bin/claude-run-skill.sh` wrapper on the minipc is the scaffold. Smoke-test on 2026-04-23 proved `bin/claude-run-skill.sh recap` runs end-to-end — captured 2.3 KB of output to `~/.local/state/claude-jobs/`, auth carried over from laptop's `.credentials.json`, KB reads worked off the Obsidian-Sync-synced vault.

No timers wired yet — just the wrapper. Next:

- [ ] Decide which skill(s) get a cron slot. Candidates: `/overnight-check` (platform-wide nightly; minipc is always-on so this is a natural fit), `/kb-auto` (autonomous KB ingestion from dive queue), `/dashboard-check` (daily operational snapshot — ties into 11b).
- [ ] Build systemd user `.service` + `.timer` pair at `~/.config/systemd/user/<name>.{service,timer}` on the minipc. Template: the laptop's `overnight-check.service` + `.timer` (documented in [[automation-overnight-check]]).
- [ ] `systemctl --user enable --now <name>.timer` — linger is already on (phase-02), so timers run without a login session.
- [ ] Verify first firing: check artifact lands in `~/.local/state/claude-jobs/` and (if markdown-framed) shows up in the KB via Obsidian Sync.
- [ ] Add to KB so we don't forget what's scheduled where: either extend [[automation-overnight-check]] or a new entity note `automation-minipc-timers`.

### 11b. Laptop-side dashboard sync → minipc (or run /dashboard-check on minipc)

The minipc's Caddy serves `/dashboard/` from `~/Documents/worklog/dashboard/latest/`. That directory is **not** in the Obsidian vault (sibling dir, not a subfolder), so Obsidian Sync doesn't touch it. Phase-09 seeds it once from the laptop but it goes stale.

Two architecturally-different options — pick one:

- [ ] **Option A: laptop-side rsync timer.** After each laptop `/dashboard-check` run, rsync `~/Documents/worklog/dashboard/` → `mork@mork-firebat:Documents/worklog/dashboard/`. Either as a post-hook on the existing dashboard-check timer or a separate 15-min poll. Pro: dashboard reflects laptop's view. Con: requires laptop to be awake.
- [ ] **Option B: run `/dashboard-check` on the minipc itself via 11a's scaffold.** Minipc is always-on, so the dashboard artifact updates continuously regardless of laptop state. Pro: true always-on dashboard, no laptop dependency. Con: minipc needs all MCP auth (NR, Atlassian) that the skill uses — need to verify those carry over in `.credentials.json`.
- [ ] Recommend **Option B** — it aligns with the "minipc is the always-on one" architecture. Requires a one-time check that MCPs authenticate from the minipc.

### 11c. Auto-start Claude Code inside the persistent tmux session

Today's phase-10 kept a tmux session named `main` alive across SSH/reboots via the `claude-session.service` user unit. But the tmux window itself just holds an empty `bash` — when the user attaches via `ssh -t mork@mork-firebat tmux attach -t main`, they land at a shell prompt and have to type `claude` themselves.

Goal: on attach, land directly in a ready `claude` session (or at least verify one is running). Two implementation options:

- **A. Modify the systemd ExecStart** — change it from `tmux new-session -d -s main -c %h` to `tmux new-session -d -s main -c %h "claude"`. Pro: one-line change, auto-starts at boot. Con: if `claude` exits for any reason (bug, user Ctrl-D), the tmux window closes and the session disappears until the user service restarts; also locks the session to always-claude.
- **B. A watchdog timer that checks for a claude process in the `main` session and spawns one if missing** — a user systemd timer firing every 60s that runs `tmux list-panes -t main -F '#{pane_pid}'`, checks whether any descendant process is `claude`, and if not, sends `tmux send-keys -t main "claude" Enter`. Pro: self-heals on claude exit. Con: more moving parts.

- [ ] Pick A or B (or a variant). B is more resilient for a truly always-on box; A is pragmatic for MVP.
- [ ] Implement as a patch to `files/claude-session.service` and/or a new `files/claude-watchdog.{service,timer}` in `~/work/local_network_scripts/`.
- [ ] Update `phase-10-sessions.sh` to push whichever variant is picked.
- [ ] Verify: reboot minipc, wait 90s, `ssh -t mork@mork-firebat tmux attach -t main` lands in a live claude prompt.

**Seeded 2026-04-23.** User ask at wrap time: *"log a follow up to start a remote claude session if the one on it isn't already"*. Small-scope; estimate 30 min once the approach is picked.

### 11d. Push-based dashboard ingest on minipc (seeded 2026-04-24)

**Status (2026-04-24 cross-check):** re-scope needed. §12e shipped a minipc-side daily `/dashboard-check` cron run, and §12g wired the HTML artifact into Caddy at `/dashboard/`. The minipc is already the primary host. The open question this § needs to answer is now narrower: **does the laptop need to push ALSO, or is the minipc's own daily run sufficient?** If sufficient (and the laptop's sink is just a local cache), the push API reduces to: (a) outbound sink-row replication every 15 min so both hosts build a common dataset, or (b) drop this § entirely and rely on the minipc run. Revisit once §12i closes and sink-write patterns stabilize.

**Trigger:** 2026-04-24 user directive during dashboard 1b work: *"If it makes sense for the dev box to be the main place all of this information is stored and hosted (accessed via http://actuate-dev.local/dashboard/), we should also scope out a task to extend the API on that minipc so that we can push the results of our runs on this system to it every time, and store them for later push if/when such a thing fails."*

This supersedes §11b's rsync-only Option A with a cleaner architecture: **the minipc is the durable dashboard host, and every laptop run pushes its snapshot + sink delta to a minipc-side API endpoint**. Offline-tolerant: failed pushes queue locally on the laptop and retry on next run.

- [ ] **API design on minipc** — extend the minipc's existing dashboard app (§12) with endpoints:
  - `POST /api/dashboard/snapshot` — accept `{date, overall_status, evaluations[], source_host, html_bundle?}`; merge into minipc's `~/Documents/worklog/dashboard/` and flip `latest` symlink if newer
  - `POST /api/dashboard/sink` — accept one-or-more sink rows (`[{signal_id, timestamp, value, status, ...}]`), deduped by `(signal_id, timestamp, source_host)`. Appends to a host-partitioned sink so laptop + minipc + any future node feed the same chart
  - `GET /api/dashboard/latest` — used by Caddy redirect or a lightweight index to serve the newest available snapshot across hosts
  - Auth: Tailscale-mesh only (source IP in `100.64.0.0/10`), no bearer token for v1
- [ ] **Laptop-side push hook** — after each `/dashboard-check` run, POST the result to minipc. Path: either a post-hook in `~/.claude/skills/dashboard-check/run.sh` or a new `push.sh` helper. Use `curl --fail --max-time 10` so a flaky network fails fast.
- [ ] **Store-and-forward on push failure** — if push fails (non-2xx OR network error), enqueue the payload to `~/Documents/worklog/dashboard/.outbox/<iso-ts>_<kind>.json` and retry at next run. Prune queue entries older than 7d. A `/dashboard-check --flush-queue` flag force-retries everything in the outbox.
- [ ] **Caddy routing** — `http://actuate-dev.local/dashboard/` serves the latest snapshot (regardless of source host) and includes a dropdown or header showing "last updated by: laptop-mork" / "last updated by: minipc". Cross-host freshness is the whole point.
- [ ] **Cross-ref §11b** — once this lands, §11b Option A (rsync) is obsolete; Option B (run skill on minipc) remains useful for the continuous-polling case where the laptop is asleep. The two are complementary, not alternatives: push from laptop when awake, minipc runs its own collector when laptop is offline.
- [ ] **KB writeup** — after shipping: synthesis note `topics/operational-health/notes/syntheses/<date>_dashboard-push-arch.md` documenting the contract + sink partitioning + how to add another host.

**Scope sizing:** the API + push hook + outbox retry is probably a half-day focused work once the minipc dashboard app (§12) exposes a generic API surface. The Caddy + host-partitioned sink additions are another half-day. Gate on §12 landing its initial API scaffold.

### 11e. Cronify-friendly refactor of `/dashboard-check` (seeded 2026-04-24)

**Status (2026-04-24 cross-check):** partially overtaken by §12e + §12i. §12e shipped `run-dashboard-check.service` + `.timer` on the minipc (daily 07:15 ET, invokes `claude -p "/dashboard-check"`); §12i has "Strip LLM narrative pass from minipc `dashboard-check` cron runs — run `dashboard-check.py` modules directly instead of via `claude -p`" queued. Most of this § is therefore **subsumed** — the collect.sh / NR-REST / run-headless.sh design below is what §12i will actually produce (under a different filename). Keep this § as the design sketch; delete or collapse it once §12i closes.

**Trigger:** 2026-04-24 user directive during dashboard 1b work: *"If any parts of dashboard check can be consolidated into shell scripts or other sorts of scripts that we could create a cronjob for ... ideally these tasks should run automatically on a cadence and we should update the dashboard accordingly automatically."*

Today's `/dashboard-check` skill is invocation-time orchestrated by Claude Code — it reads the catalog, launches CLI queries, runs the renderer, writes sink rows. That's the RIGHT shape for the interactive path, but it forces a Claude Code invocation to update the dashboard, which is too expensive to run hourly on a cron.

The cron-path wants a **headless collector** that runs shell-scripted queries + renders, **no LLM in the loop**.

- [ ] **Factor out collector logic** — each enabled signal in `config/signals.json` has a query string + source type. Create `~/.claude/skills/dashboard-check/collect.sh` (bash) that reads signals.json, dispatches per source type (aws CLI for cw_*/ce_daily, `nrql-cli` or a tiny MCP-free NR REST wrapper for nr_*, gh for gh_*), writes `$TEMPDIR/*.json` in the same shape `render.py` expects. The existing `render.py` is already headless-safe.
- [ ] **NR REST wrapper** — the existing NR MCP tool requires a Claude Code session. For cron, write `~/.claude/skills/dashboard-check/nr_query.py` that hits the NerdGraph REST endpoint with an `Api-Key` (stored in `~/.config/nr/api-key`, 0600). Single file, zero runtime deps beyond `requests`.
- [ ] **`run-headless.sh`** wrapper — `collect.sh → render.py → push.sh` (push.sh from §11d when that lands). Exit-code-forwarded. Idempotent.
- [ ] **systemd timer** — once `run-headless.sh` exists, create `~/.config/systemd/user/dashboard-check.{service,timer}` firing every 15–30 min. On the minipc via §11a's scaffold; on the laptop as a secondary belt-and-braces.
- [ ] **Claude invocation path still works** — the `/dashboard-check` skill stays as-is for interactive use (can run extra diagnostics, ask about anomalies). Headless is an additive path, not a replacement.
- [ ] **Verification** — after a week of cron running, check sink gains ~100+ rows/day organically; dashboard stays <30 min stale at any time; no pile-up in outbox from §11d.

**Scope sizing:** 1-2 focused sessions. The NR REST wrapper is the biggest unknown (need to validate API-key scope + query patterns match NRQL behavior 1:1). Start there.

### Related

- §9 Operational Dashboard — source of the dashboard artifact
- §10 Laptop-config portability — sibling workstream on the laptop side of "reconstitute my config"
- §11d (new) — push-based ingest; makes the cron model useful (pushes across hosts)
- §11e (new) — cronify refactor
- §12 Minipc dashboard app — the target for §11d's push API
- Scripts + README: `/home/mork/work/local_network_scripts/README.md`
- Memory pointer: `~/.claude/projects/-home-mork-work-local-network-scripts/memory/firebat-minipc-access.md` (creds + URLs)

---

## 12. Minipc dashboard app — interactive KB browser + query + quick surfaces

**Priority:** high (active build)
**Tickets:** *(personal infra — no ticket)*
**Status:** in progress (Phase 1 under construction 2026-04-24)
**Trigger:** 2026-04-24 user ask — extend the static status dashboard with dynamic pages. Primary request: browse the Obsidian KB via the web + query it ("ask Claude about the KB") without having to SSH in. Additional build-list also approved.
**Related:** §11 (provisioning), §9 (operational dashboard, shares palette + theming)
**Access:** will live at `http://mork-firebat/app/*` (LAN + Tailscale only; no auth for MVP)

### Architecture

- **FastAPI + Jinja2 + HTMX** on the minipc, `uv run uvicorn` bound to `127.0.0.1:8081`
- **Caddy reverse-proxies** `/app/*` → `127.0.0.1:8081`
- **Systemd user service** `minipc-app.service`, restart-on-failure, auto-start at boot (linger already on from §11 phase-02)
- **Source** lives in `/home/mork/work/local_network_scripts/minipc-app/` on laptop (versioned with the rest of the toolkit) and `rsync`'d to `/home/mork/minipc-app/` on the minipc by `phase-12-app.sh`
- **CSS** reuses the `:root` light/dark custom-properties palette from `gen-status-page.sh` so the static status page and the app share a look
- **Decision: KB-ask uses Option A** — spawn `claude -p "/kb-ask <q>"` per request. Simple, stateless, ~5-20s latency. Upgrade to long-running-claude-child only if latency bites.

### 12a. Phase 1 — KB browser + KB query  *(SHIPPED 2026-04-24)*

- [x] FastAPI app scaffold (`pyproject.toml`, `main.py`, `routes/kb.py`, templates, `static/app.css`) — lives at `local_network_scripts/minipc-app/`
- [x] `GET /app/kb/` — vault tree (breadcrumbs, dir-first sort, `.obsidian` hidden)
- [x] `GET /app/kb/?path=...` — render a `.md` note (frontmatter + markdown → HTML, wikilinks rewritten to `/app/kb/?q=<slug>` with a slug-to-path resolver)
- [x] `GET /app/kb/query` — query form
- [x] `POST /app/kb/query` — async subprocess `claude -p "/kb-ask <q>"`, 150s timeout, render stdout as markdown
- [x] systemd user unit (`minipc-app.service`, Type=simple, `uv run uvicorn`) + `phase-12-app.sh` deploy script
- [x] Caddyfile update (`handle_path /app/*` → `127.0.0.1:8081`) + reload
- [x] verified `http://mork-firebat/app/` returns 200 on landing, kb/, kb/?path=..., kb/query
- **Gotcha captured:** Starlette 1.0 changed `TemplateResponse(name, {..."request": request...})` → `(request, name, {context})`. Old form throws `TypeError: unhashable type: 'dict'`.

### 12b. Phase 2 — Today's daily-note excerpt + Jira queue mirror  *(SHIPPED 2026-04-24)*

- [x] `GET /app/today/` — renders the markdown artifact produced daily by `run-kb-recap.sh`; also `/app/today.md` for raw markdown
- [x] `GET /app/jira/` — parses `mark-todos.md`'s `<!-- BEGIN-AUTOSYNC-JIRA -->
## Current Jira Queue (auto-synced)

**Last synced:** 2026-04-27
**Source:** `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`

This section is **fully replaced** on every sync by the `jira-sync` automation (see [[automation-jira-sync]]). Manual edits in this section will be lost — add notes against tickets in the workstream sections above instead.

### Ready to Deploy (4)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| CS3-31 | Highest | Sub-task | Automatically update the reference image |
| CS3-323 | High | Bug | Discrepancy in cam count btwn dashboard and report |
| CS3-430 | Medium | Sub-task | Account for dummy incident type in CHM API |
| CS3-58 | Lowest | Task | Configuration per camera |

### In Progress / In Review (1)

| Ticket | Status | Priority | Type | Summary |
|--------|--------|----------|------|---------|
| ENG-166 | In Progress | Medium | Task | AutoPatrol auto-delete lambda — design + implementation |

### To Do (6)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| AUTO-478 | High | Sub-task | Single image storage when no motion/alerts |
| AUTO-479 | High | Sub-task | Slip storage when no motion/alerts |
| CS3-505 | Medium | Sub-task | add outcome to the API for CHM alerts |
| ENG-94 | Medium | Task | Deferred alerts: send without frame as fallback when cache expires |
| ENG-136 | Medium | Task | PyAV upgrade 13.1 → 17.0 (nogil pixel conversion) |
| ENG-179 | Medium | Task | Local ops dashboard + dev box on minipc (R&D) |

### Open (1)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| BT-259 | Medium | Bug | "Use Motion" toggle bug |

<!-- END-AUTOSYNC-JIRA -->

---

<!-- BEGIN-TODAY-SCOPE -->
## Today's Scope (2026-04-27)

Picked via [[skill-daily-scope|/daily-scope]]. Line items close via [[skill-daily-wrap|/daily-wrap]] at end-of-day — closed items get a summary in the daily note, not deleted here.

User accepted explicit over-scope: *"some are probably already done and we haven't marked them as such. Lets track em all here at least."* Refined: scope items are Mark-assigned; non-Mark-assigned AP work is tracked separately below.

- [ ] **§13 NR/Atlassian wrappers** — §13 (added today). Build `nr_query.py` (NerdGraph REST) + Atlassian REST wrapper end-to-end; bridge into `nrql-investigator` agent + `overnight-check.service` + `jira-sync.service`. Unblocks daily-scope fan-out, /dashboard-check, both broken cron services. Recommended #1 — without it tomorrow's morning has the same blockers.
- [x] **admin#2310 scoping** — Decided: filed as new **§14 — AutoPatrol schedule-override midnight arm-miss race** in mark-todos. Three-part race documented (croniter seed + 5-min buffer + midnight queue congestion). Two-track fix proposed: 1-line infra quick-win (`scalerReplicasArmDown: 20`) + Option A code fix (immediate-trigger on `is_override && is_running` in `deploy_schedule_changes`). Neither shipped today; §14 awaits implementation pickup. The infra quick-win is a 15-min PR if you want to grab it standalone.
- [x] **§3 Step E.3 verify** — **GREEN, ready to advance.** 4-day CW window since flip 2026-04-23T17:59Z: 102 invocations (37/22/20/23 per day, steady), **0 errors**, **0 throttles**. Both queues `autopatrol_stale_schedule_cleanup{,_dev}.fifo` at 0/0 messages. Both DLQs at 0/0. DDB `autopatrol_cleanup_counters-dev` has 6 rows total (4 known flappers `1e2ee05f`/`c3808175`/`fbdfdba6`/`ee1822f1` reset to count=None per design + 2026-04-23 first-disable row `636be1ba` count=1 + 1 manual test row `56de5b0a`). Lambda `CLEANUP_ENABLED=true` confirmed in env; State=Active. **Side-finding:** Lambda `LastModified=2026-04-27T14:11:07Z` (~30 min before this verify ran) — someone redeployed today; worth a brief look at autopatrol_onboarder recent commits/PRs to confirm nothing unintended. **Step F (the actual flag-flip) is a separate kubernetes-deployments PR** — `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` lives in the connector helm chart, not on the Lambda. Surfaced as the next concrete sub-step in §3.
- [x] **vms-connector#1658 SSL chain — in-house actions** — Investigation update appended to [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]]. **Customer 23202 identified:** RTSP customer (mixed VCH/RTSP) with cluster of 7+ sites all carrying `(copy)` suffix ("Brightside Fire Pit", "Club verano Fire Pit", "Fire Pit Cabana", plus IDs 310410/310422/310775/310788). The `(copy)` suffix is actuate_admin's clone-from-template marker — strong signal that **the 2026-04-17 blast-radius growth was a customer-23202 site cluster being cloned + deployed on/near that date**. Customer human-name still TBD (requires admin UI lookup at `/admin/core/customer/23202/`). **Drafted Slack message for Immix** covering both the chain-completion fix recipe and the URL-routing question — ready for user to review + send. **Comms-blocked items** (raise with PowerPlus, raise URL routing): drafted but not sent — these are user actions. **Option-3 mitigation:** deferred pending Immix response timeline.

### Tracked as relevant (not active scope today)

AP-related items the user wanted surfaced for the day — assignee notes per repo-scan / Jira queue.

- **AUTO-351 BB push to prod** — §2c. Brad Murphy's bounding-box changes; Ready-to-Deploy in Jira. **Brad-assigned, not Mark.** Stage verify + prod push remains the next concrete shipping step but isn't on Mark's plate today.
- **vms-connector#1656 connector cleanup** — §2d.2 streamId-null patrol-alert. **Unassigned.** Connector-side cleanup (remove `uuid.uuid4().hex` fabrication in `patrol_camera.py:33`, drop hardcoded `""` defaults, log-and-skip) is unblocked while waiting on Immix; available for any session to grab.
- **AUTO-478 / AUTO-479 storage variants** — Jira To Do, High, Mark-assigned. Single image / Slip storage when no motion/alerts. AP-related; not in flight today.
- **ENG-94 deferred-alert frame fallback** — Jira To Do, Medium, Mark-assigned. §2b adjacent (deferred-alerts work). Not in flight today.
- **§3 Step F prod US scale-up** — Mark; gated on E.3 close (which today's scope picks up). One-flag flip once green.
- **§3 Step G prod EU** — Mark; separate track, needs net-new infra.
- **§3 follow-ups: Immix error-pattern observability + SiteDisabledOrDisarmed routing** — Mark; both design-pending, not active today.

**Descoped today:**
- Dashboard 1b pickup (§9) — owned by another session.
- admin stale Batch 1 (§7) — not picked, rolling forward.

**Surface (minipc remediation, user-only actions — reminders, not tracked items):**
- SSH `mork@mork-firebat` → `tmux attach -t main` → launch `claude` in a pane (no `claude` process inside `main` per 2026-04-27 morning probe).
- Visit `http://mork-firebat/obsidian/` → re-auth Obsidian Sync (newest mtime stuck at 2026-04-23 23:07 UTC per Friday probe).

<!-- END-TODAY-SCOPE -->

<!-- BEGIN-MORNING-FOLLOWUPS -->
## Morning Follow-Ups (for 2026-04-25)

Time-bound checks seeded by [[skill-daily-wrap|/daily-wrap]] and consumed by the morning ritual ([[skill-daily-scope|/daily-scope]] or a future `/morning`). Each item is tagged with how it should be handled:

- **exec** — scriptable; the morning ritual runs it automatically during health fan-out and reports the result
- **verify** — needs user eyeballs on something specific; surfaced as a briefing line
- **decide** — requires a decision that should shape today's scope before picks

Consumed items get `[x]` and stay in the block for the day (the wrap prunes). Items not acted on roll over with a `*(rolled YYYY-MM-DD)*` qualifier.

- [x] **verify (priority)**: **Remote Claude session on `mork-firebat`** — **STILL DOWN.** `pgrep claude` empty per 2026-04-27 SSH probe; tmux `main` session alive (created Fri 19:15) but no `claude` process inside. User remediation surfaced in Today's Scope reminders. *(seeded 2026-04-24 for 2026-04-25; ran 2026-04-27 — pending user action)*
- [x] **verify**: Obsidian Sync on `mork-firebat` re-attached — **likely STILL STALE.** SSH probe returned no recent KB files via Tailscale; consistent with Friday's 2026-04-23 23:07 UTC anchor. User remediation surfaced in Today's Scope reminders. *(seeded 2026-04-24 for 2026-04-25; ran 2026-04-27 — pending user action)*
- [x] **exec**: NR overnight health — **BLOCKED: NR MCP OAuth callback fails** (localhost:43663 unreachable from browser). Two `nrql-investigator` subagent attempts stalled 600s before kill; parent-context query also rejected by user once they saw the auth flow stalling. Cron `overnight-check.service` 08:14 ET also failed (NR MCP missing in headless `claude -p`). Structural fix tracked in newly-added §13. *(standing; ran 2026-04-27 — blocked)*
- [x] **exec**: `/autopatrol-cleanup-lambda-check` — **BLOCKED: same NR MCP gap + AWS dev-eu profile missing.** Subagent attempt stalled 600s. Today's pick #3 (§3 Step E.3→F advance) picks up the verify via AWS CloudWatch directly. *(standing; ran 2026-04-27 — blocked)*
- [x] **exec**: `/repo-scan` — **186 issues, zero weekend movement.** All 4 watch items (vms-connector#1656/#1658, admin#2310, ai-api#48) still open, same assignees. Top high-impact: vms-connector#1656 (score 11), admin#2310 (score 5, 33d unassigned), vms-connector#1658 (score 5). Note: [[2026-04-27_scan]]. *(standing; ran 2026-04-27)*
- [ ] **decide**: [connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160) — orphan container cleanup *(rolled 2026-04-25 → 2026-04-27, not picked again)*. Still assigned; 2 orphans observed (`51c72148`, `798e6dde`). Scope for first session: decide approach (Option 1 recommended), draft the scan.

### Consumed 2026-04-24

- [x] **verify**: §3 Step E decision — **GREEN, holding steady.** `CLEANUP_ENABLED=true` + `CLEANUP_TARGET_HOURS=18` both still in effect. Lambda 40 invocations / 24h / 0 errors / 0 throttles / 724ms avg. DLQs both 0. Main queues both 0. Event source Enabled. Post-PR-7 onboarder hotfix still present (line 142 `logging.warning(...)`, no early `return`). Retry-idempotency fix working: 4/4 DDB rows carry `last_message_id`. Actual disables today: 0 (audit total still 1 from yesterday's `636be1ba`). No new issues pre vs. post-24h. *(set 2026-04-23; ran 2026-04-24)*
- [x] **exec**: `/autopatrol-cleanup-lambda-check` — **pipeline GREEN.** All 3 flappy candidates that resisted disable yesterday STILL flapping: `ee1822f1` reset 2x (last 2026-04-24 12:04Z), `c3808175` reset 2x, `fbdfdba6` reset 2x in 24h. All 3 hit threshold → Immix still reports active → safety-net correctly resets patrol_exit bucket. 4th candidate `1e2ee05f` dormant (count=0, no emits). These are durable Immix-side mismatches → exactly the case the [[2026-04-23_immix-api-error-patterns]] follow-up (§3 "Immix error-pattern observability") is for; they're "we say gone / Immix says active" repeat offenders — classifier improvement needed before they can disable, but the Lambda is doing the right thing. Onboarder US: 36 worker-activity lines / 30m, EU: 6 / 30m, both 0 404-errors. *(set 2026-04-23; ran 2026-04-24)*
- [x] **exec**: NR overnight health — **YELLOW.** OOMKills 725/24h — within recovering-from-spike baseline (~800-900), not escalation; yesterday's 423 was a trough. Top OOMers: connector-14170 (132, reversal), connector-23422 (116 NEW), connector-23730 (109, reversal), connector-20628 (103, still chronic), connector-45010 (99 NEW). NoneType: smtp-frame-receiver IMPROVED out of top-10; create-detection-window now sole dominant (3016/12h); CHM cronjobs new entrants (watch). streamId Guid on :stage 0 (GREEN). §2b canaries GREEN. **2 new anomalies:** (a) connector-11202 — 23K errors / 24h DW-VMS empty-JSON camera-auth (site-level VMS bug); (b) connector-deploy — 18K errors / 24h thrash-loop on connector-14170 reboots, likely coupled to OOM loop on that same container. Synthesis: [[2026-04-24_overnight-check]]. Also: the cron session wrote an aborted stub this morning because its Claude Code MCP allowlist is missing `newrelic` — follow-up in [[automation-overnight-check]]. *(standing; set 2026-04-23; ran 2026-04-24)*
- [x] **exec**: `/repo-scan` — **186 issues surveyed across 5 repos; 5 concept files refreshed.** Top high-impact candidates: vms-connector#1656 (AP/VCH Immix CNCTNFAIL, 3d — already in §2d), actuate_admin#2310 (schedule override midnight arm miss, 29d, unassigned — **real customer bug**), actuate-inference-api#48 (Terraform plan CI comment fails, 9d — **tiny, contained**). LHF: connector#1502 (arch-doc), admin#2177 (EU proxy gap), libraries#244 (log verbosity). Scan note: [[2026-04-24_scan]]. *(standing; set 2026-04-23; ran 2026-04-24)*
- [ ] **decide (priority)**: §9 Dashboard Phase 1b *(rolled 2026-04-25 — picked up + paused mid-work)*. 15 signals enabled, daily-scope integration shipped, render.py new_pattern bug fixed; 9 deliverables remain. Entry: [[2026-04-24_dashboard-1b-continuation]] §"Execution order (recommended)". *(seeded 2026-04-23 for 2026-04-24)*
- [ ] **decide**: Walk stale-issue codebase-scan follow-up *(rolled 2026-04-25)*. Not touched. Batch 1 (Onboarding/wizard): `admin#551, #488, #510, #446, #694`. Entry: [[actuate_admin|repo-backlog/notes/concepts/actuate_admin]]. *(seeded 2026-04-23 for 2026-04-24)*

### Seeded for 2026-04-27 (Monday)

- [x] **decide**: Evaluate high-impact backlog candidates for pickup — addressed via today's `/daily-scope` interview. Repo-scan (186 issues, zero weekend movement) + AP scan + Mark-assignment refinement surfaced 4 active picks: §13 wrappers (newly-added structural unblocker), admin#2310 scoping, §3 Step E.3→F advance, vms-connector#1658 in-house actions. AUTO-351 (Brad), #1656 (unassigned), and downstream Mark-assigned AP/Jira items recorded under "Tracked as relevant" in Today's Scope. *(seeded 2026-04-23 for 2026-04-27; ran 2026-04-27)*

### Seeded for 2026-04-28

- [ ] **verify**: connector-45999 OOMKill chronic — surfaced 2026-04-27 §13 wrapper validation. 109 OOMKills/24h, **NEW** offender (not in yesterday's top-5: 14170, 23422, 23730, 20628, 45010). Tomorrow: confirm whether sustained or one-day spike; if sustained, escalate as a §3 / §9 follow-up (memory-limit drift candidate per [[2026-04-23_oom-surge-connector-limit-drift]]). *(seeded 2026-04-27 for 2026-04-28)*
- [ ] **decide**: ENG-179 "Local ops dashboard + dev box on minipc (R&D)" — newly visible in Jira queue 2026-04-27 (created since Friday's sync). Overlaps materially with §11 (firebat minipc) + §12 (minipc dashboard app). Decide: fold ENG-179 into §11/§12 as the Jira anchor, or treat as scope-overlap and discuss with whoever filed it. *(seeded 2026-04-27 for 2026-04-28)*
- [ ] **verify**: cleanup-Lambda anomaly resets — `/autopatrol-cleanup-lambda-check` 2026-04-27 surfaced **4 anomaly resets in 24h**, post-deploy of PR #9 (Paused/Suspended → active). Not alarming on its own, but plausibly the new classification logic doing its job. Tomorrow: pull the specific schedule_ids from the last 24h anomaly logs, confirm they correspond to Paused/Suspended sites (expected behaviour) rather than a different mismatch class. Command in [[skill-autopatrol-cleanup-lambda-check]] §"Interpreting results" → "Repeat offenders over 7 days". Cross-link §3. *(seeded 2026-04-27 for 2026-04-28)*

### Seeded for 2026-04-30 (week-out reviews)

- [ ] **decide**: Repo-backlog per-repo concept refresh cadence — seeded 2026-04-23 after introducing `/repo-scan` auto-refresh of `topics/repo-backlog/notes/concepts/<repo>.md` (5 files, idempotent via sentinel). Current: **daily**. Review whether that's right, or switch to **weekly**. Criteria: git-diff noise, actual consultation frequency, collision risk with mid-edit Curated notes. Switch mechanism documented in [[skill-repo-scan]] "Refresh cadence" section (add weekday gate in curate.py if switching). *(seeded 2026-04-23 for 2026-04-30)*

<!-- END-MORNING-FOLLOWUPS -->

---

## 13. Subagent + cron MCP-bypass auth flow

**Priority:** high — surfaced 2026-04-27 morning routine (3 NR-touching subagents stalled; both cron jobs failed)
**Tickets:** *(personal infra — no ticket)*
**Status:** scoping
**Trigger:** 2026-04-27 — daily-scope fan-out launched 4 subagents; 3 of them stalled indefinitely after spawning interactive NR auth prompts the subagent couldn't satisfy. Same morning, `overnight-check.service` and `jira-sync.service` both wrote FAILED stubs because their headless `claude -p` invocations couldn't reach NR or Atlassian MCP either. `/repo-scan` worked because it only used `gh` CLI.

### Problem

MCP servers (NR, Atlassian) authenticate per-Claude-Code-subprocess. Each subagent and each headless cron run gets a fresh MCP session that must complete an interactive auth handshake. Subagents can't satisfy interactive prompts — they hang. Cron `claude -p` runs without MCP creds — they fail. This blocks:
- daily-scope morning fan-out (NR overnight, cleanup-lambda check, dashboard-check)
- Scheduled overnight-check synthesis (cron job)
- Scheduled jira-sync (cron job, Atlassian)
- Future minipc-side scheduled runs (§11e)

### Approach (Option A from 2026-04-27 daily-scope review)

Bypass MCP for headless / subagent paths. Use REST API wrappers backed by API keys on disk. Subagents and cron call them via Bash; parent-context Claude continues to use MCP interactively. For 2026-04-27 only the parent ran NR queries directly as a one-off bypass (Option C); structural fix is this workstream.

### Subtasks

- [x] **NR NerdGraph REST wrapper** — `~/.claude/lib/nr_query.py` (moved out of dashboard-check to a shared lib location). Reads API key from `~/.config/nr/api-key` (0600). Stdlib only (`urllib`), no `requests` dep. Exposes `nrql(query, account_id=3421145) -> list[dict]`. CLI: `python3 ~/.claude/lib/nr_query.py "<NRQL>"`. Smoke-tested against the 2026-04-27 morning OOMKill query — returned `connector-45999` (109/24h, NEW chronic) in <1s.
- [x] **Atlassian REST wrapper** — `~/.claude/lib/atlassian_query.py`. Reads `{email, token, site}` from `~/.config/atlassian/api-token` (0600). Basic auth, cursor-paginated `/rest/api/3/search/jql`. Sub-commands `search` + `issue`. Smoke-tested: returned 12 of Mark's open issues incl. new `ENG-179` (minipc R&D ticket).
- [x] **Bridge subagents** — `nrql-investigator` agent now has `Bash` + a "How to Run NRQL" section defaulting to the wrapper (MCP kept as fallback for non-NRQL ops). `~/bin/jira-sync.sh` prompt rewritten to call the wrapper directly (no MCP). `~/bin/overnight-check.sh` inherits the fix via the agent. **Caveat:** Claude Code caches agent definitions per-session — running sessions need `/clear` to pick up `Bash`. Fresh sessions (cron + new daily-scope) load the new definition automatically.
- [x] **API-key provisioning runbook** — [[2026-04-27_headless-mcp-bypass]] in engineering-process. Setup steps, verification recipe, failure-mode catalog. Cross-linked from automation-overnight-check + automation-jira-sync.
- [x] **Verification** — wrapper-only path: ✓ subagent (general-purpose) ran `python3 nr_query.py` and returned count=3427 in 7s, no stalls. Cron path: ✓ ran `~/bin/jira-sync.sh` end-to-end, mark-todos auto-sync block refreshed with 12 issues / `Last synced: 2026-04-27`. Overnight-check verification deferred to its next scheduled run (overnight 2026-04-27 → 2026-04-28).

### Related

- §11e — cronify-friendly refactor (subsumes the NR wrapper deliverable)
- §10 — laptop portability secrets-refresh runbook
- [[automation-overnight-check]] — known cron MCP gap
- [[automation-jira-sync]] — known cron MCP gap
- [[skill-daily-scope]] — consumer of the fix (Step 2c fan-out)

---

## 16. `/kb-relink` skill hardening

**Priority:** low (skill works for the obvious cases, but produces wrong-anchor mislinks and under-covers files)
**Status:** drafted 2026-04-27 alongside the video-processing topic seed; first two production runs (manual + skill-driven) surfaced the issues below
**Source:** [[skill-kb-relink|/kb-relink]] @ `/home/mork/.claude/skills/kb-relink/SKILL.md` + seed `aliases.yaml`

### Known issues (from 2026-04-27 runs)

- [ ] **Wrong-anchor mislinks** — first thorough pass on the video-processing topic produced `[[rtmp-and-srt|VP8]]` and `[[webrtc-deep-dive|VP9]]` in `containers-overview.md`. VP8/VP9 are codecs (their KB anchor is `[[av1-vp9-future]]`), not transport protocols. The seed `aliases.yaml` likely globs codec names too loosely. **Fix:** add per-anchor disambiguation rules so codec names route to codec anchors and protocol names route to protocol anchors. Audit the seed dictionary against the topic's actual anchor inventory before next run. Manual fix already applied to `containers-overview.md`.
- [ ] **Coverage too thin** — both wikilink-enrichment runs (the manual prep pass + the skill-driven pass) only modified ~4-5 files out of 50 in the topic. The agent stopped early. Either (a) the skill body's "first mention per section" rule is being misread as "first file only", (b) the agent isn't iterating over the full glob, or (c) the alias inventory doesn't cover enough phrases to fire on most files. **Fix:** check the SKILL.md procedural text for clarity on the file iteration; consider explicit `for FILE in $FILES; do ... done` loop guidance instead of relying on agent inference.
- [ ] **Add no-anchor inventory output** — the skill should report which alias entries had ZERO matches in the scanned set. That tells us when a curated alias is dead (anchor renamed or removed) so we can prune the dictionary.

### Verification after fix

- [ ] Run `/kb-relink` against `topics/video-processing/` again; expect ~30+ files modified, no mislinks, and a "anchors with zero hits" summary block.
- [ ] Pair with `/kb-lint` immediately after to catch any new broken wikilinks the relink pass introduced.

### Related

- §15 — video-processing topic where the skill was first exercised
- [[skill-kb-relink]] — the skill itself
- [[skill-kb-lint]] — the cousin skill that catches BROKEN wikilinks (this skill catches MISSING ones)

---

## 14. AutoPatrol schedule-override midnight arm-miss race

**Priority:** medium (real prod bug, low rate — 1 confirmed miss in 33d)
**Tickets:** [actuate_admin#2310](https://github.com/aegissystems/actuate_admin/issues/2310) (filed 2026-03-25, 33d unassigned as of 2026-04-27)
**Status:** scoped 2026-04-27 via [[skill-daily-scope]], awaiting implementation pickup
**Trigger:** Customer-affecting miss — connector-16031 didn't arm on Monday 2026-03-23 because its override schedule fired the start task at 23:55 EDT but actual execution slipped past midnight, causing `croniter` to schedule the arm for *next* Monday.

### Bug

Three-part race in `actuate_admin`:

1. **`schedule_processor.py:82-87`** — converts override start date to midnight UTC (00:00 local).
2. **`override_timer.py:57`** — only `ADVANCE_TIME_BUFFER_START = 5 minutes` of pre-buffer.
3. **`schedule_deployer.py:50-52, 347-399`** — `croniter(expression, datetime.now(utc)).get_next(datetime)` returns *next* match. If now is past midnight, today's arm slot is gone. `deploy_schedule_changes` overwrites the regular cron tasks (same association name format) with the override schedule's, so the regular path also can't recover.

5 minutes isn't enough because midnight is peak congestion: every site with `has_pre_start` (overnight schedules `|******-----------******|`) queues a reboot at 00:00 local. Django Q runs at `workers=8 × replicas=10` (after the 22:30 UTC arm-down), and an "Every day" override does **21 `save_django_schedule` calls** (3 actions × 7 days). The 11-minute slip on connector-16031 was queue wait + DB churn.

### Fix landscape (jacob-aegis's analysis on the issue)

| Layer | Option | Effort | Effect |
|---|---|---|---|
| Code | **Option A** (recommended): in `deploy_schedule_changes`, detect `is_override=True && is_running` → immediately trigger the start action instead of relying on cron task | medium | Eliminates race entirely |
| Code | Option B: croniter seed logic — use `get_prev` if within window after cron time | small | Brittle |
| Code | Option C: increase `ADVANCE_TIME_BUFFER_START` to 30-60 min | small | Fragile, depends on guessed congestion |
| Code | Option D: separate association names for override tasks (so they don't overwrite regular tasks) | large | Cleanest long-term but bigger refactor |
| Infra | **Quick-win**: `scalerReplicasArmDown: 20` in `kubernetes-deployments/.../djangoq/cluster-values.yaml` (1-line change) — keep djangoq at 20 replicas overnight instead of dropping to 10. Eliminates congestion → race becomes vanishingly rare. Doesn't fix root cause. | tiny | High value, low risk |
| Infra | Add `djangoq-scaler-midnight-{up,down}` CronJobs in `templates/cronjob.yaml` | small | Same idea, more surgical |

### Subtasks (proposed sequencing)

- [ ] **Step 1 — Infra quick-win** — apply `scalerReplicasArmDown: 20` in `kubernetes-deployments` cluster-values.yaml (us-west-2 + eu-west-1 if relevant). Reduces midnight congestion immediately. Single PR, ~15 min. Customer-visible reliability improvement before the proper code fix lands.
- [ ] **Step 2 — Code fix Option A** — in `actuate_admin/schedule_deployer.py:347-399`, branch on `is_override && is_running` to invoke the start action directly. Add unit + integration tests covering: (a) override starting at midnight today; (b) override starting at midnight tomorrow (should NOT immediately fire); (c) override mid-day start; (d) override end (no immediate action expected). Verify against the reproduction case (connector-16031 / schedule 197068) on stage.
- [ ] **Step 3 — Verification on prod** — after Step 2 ships, monitor the next 7 days of override-start events for any miss-on-day-1 reports; cross-check NR for `deploy_schedule_changes` events firing at the right wall-clock time relative to the override start.
- [ ] **Step 4 (deferred)** — evaluate Option D (separate association names) as a longer-term cleanup. Tracks alongside any other override-related work.

### Related

- [actuate_admin#2310](https://github.com/aegissystems/actuate_admin/issues/2310) — source issue with full timeline + 4 detailed comments
- §3 — AutoPatrol cleanup Lambda (sibling AP work, different domain)
- §9 dashboard signal candidates (after this fixes): `override_start_to_arm_latency_seconds` p95, `override_arm_miss_rate`
- [[autopatrol-onboarder]] — schedule lifecycle entity
- [[skill-stage-release]] — flow this fix would go through

---

## 15. Video-processing topic — promotable findings (2026-04-27)

**Priority:** mixed (some quick fixes, some larger refactors)
**Status:** findings surfaced during the [[video-processing/_summary|video-processing topic seed]] (2026-04-27); promoted from KB to actionable workstreams to avoid drowning in research context
**Source:** topic-creation pass + 4 follow-up audits + 4 fleet-architecture bridge syntheses; details in [[video-processing/_summary]]

### 15a. Quick fixes (small PRs)

- [ ] **GPU FFmpeg `--enable-gnutls` build flag** — both `x86_dockerfile.gpu` and `arm_dockerfile.gpu` build FFmpeg from source but **omit `--enable-gnutls`**, while CPU ARM (`build_ffmpeg.sh:54`) includes it. Result: any `https://` snapshot URL or `rtsps://` camera silently fails to open via PyAV on GPU nodes ("Protocol not supported"). `libgnutls28-dev` is already in `apt_requirements.txt`, so this is a one-line configure-flag fix per Dockerfile. Details: [[connector-docker-system-deps]].
- [ ] **`make_video_ffmpeg` subprocess timeout** — `queue_consumer/consumers/shared/utils.py:174-204` shells out to `ffmpeg` with no timeout. Hang risk under abnormal conditions. Add a bounded timeout matching the longest acceptable clip-mux duration. Details: [[immix-mp4-mux-downstream]].
- [ ] **`fish2pano` subprocess timeout** — `actuate-libraries/actuate-pullers/src/actuate_pullers/shared/base_puller.py:333-339` invokes the bundled `fish2pano` binary with `subprocess.run(...)` but no timeout. Same family as the make_video_ffmpeg risk. Low-volume path (panorama cameras only) but a clean fix.
- [ ] **Delete `GstUrlFramePuller` + `GStreamerInputPipeline`** — zero production callers (verified in [[gst-rtsp-h264-only-audit]] + [[connector-decoder-routing-map]]). The pipeline is hardcoded H.264-only (`rtph264depay`) — a latent trap for any future PR that wires it to a modern HEVC-defaulting VMS. Removing it eliminates the trap and reduces maintenance surface in `actuate-libraries/actuate-pullers/`. Touch `__init__.py` to drop the conditional import.

### 15b. Bug-shaped questions (need investigation before action)

- [ ] **AVI/Xvid masquerading as `.mp4`** — `queue_consumer/consumers/shared/utils.py:186-187` swaps `.mp4`→`.avi` before invoking `ffmpeg ... -vcodec libxvid`, so the bytes wrapped in MIME as `application/mp4`-named-attachment are actually AVI/Xvid. Either Immix has been silently accepting this for years (in which case the filename is misleading-but-harmless), or the codec is wrong and we just haven't caught it. Action: confirm with Immix what's actually expected (MP4? AVI? either?), then either rename the attachment or fix the codec/container. Details: [[immix-mp4-mux-downstream]].
- [ ] **EU prod missing `prod-queue-immix-consumer` ECS autoscaling** — SQS queue `event_queue_immix_alarm.fifo` is provisioned in eu-west-1 but **no matching ECS autoscaling block** found in `ds-terraform-eks-v2/stages/prod/eu-west-1/`. Either EU Immix MP4 mode isn't actually consumed (and customers using it would silently get no MP4s), or the consumer runs from the US region's ECS service against the EU queue, or it's deployed via a different mechanism we missed. Action: verify whether EU FIFO has an active consumer; if not, decide whether to provision EU-side or accept US-only.

### 15c. Migration / refactor workstreams

- [ ] **Hikcentral split-brain decode migration** — `connector_factories/hikcentral/factory.py` routes the **non-motion path to PyAV `AvUrlFramePuller`** but the **motion-gated path to legacy OpenCV `OnOffMotionBasedUrlFramePuller`**. Real-traffic VMS, complicates hwaccel rollout, breaks PTS semantics consistency. Migrate the motion-gated branch to a PyAV-based motion variant. Details: [[connector-decoder-routing-map]].
- [ ] **PyAV migration completion (general)** — most production integrations are now on `AvUrlFramePuller`, but the legacy `UrlFramePuller` (OpenCV) class still parents motion-gated variants and a handful of integration paths. This is a pre-req for [[2026-04-16_proposal-c-camera-worker|fleet-architecture proposal C]] (a "universal worker image" only works with one canonical decode path). Scope and sequence the remaining moves; remove the legacy class once empty. Details: [[connector-decoder-routing-map]] + [[decode-locality-per-proposal]].
- [ ] **KVS pipeline JPEG round-trip elimination** — `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-156, 104-128` decodes MKV → JPEG-encodes via `jpegenc` inside GStreamer → JPEG-decodes via `cv2.imdecode` in Python. Two unnecessary codec ops per frame. Options: (a) move to PyAV-on-MKV like the RTSP path; (b) drop `jpegenc` and use `appsink` with raw frames + GstSample → numpy. Details: [[gstreamer-vs-ffmpeg]] + [[aws-kvs-entity]].

### 15d. Discovery / verification (small data-gathering tasks)

- [ ] **EKS prod node-pool GPU verification** — confirm whether prod connector cluster has any G-class node groups today, or if we're CPU-only. Karpenter NodePool config + connector pod placement constraints. Details (and any findings landed): [[eks-prod-node-pool-gpu-availability]] (peer concept note from this batch).
- [ ] **Connector Dockerfile coverage spot-check on prod** — `gnutls` audit landed [[connector-docker-system-deps]]; one more pass after the `--enable-gnutls` fix to confirm no other surprise omissions in the GPU images.

### Related

- Topic landing: [[video-processing/_summary]]
- Cross-cuts to §5 fleet-architecture (decode-locality, GPU substrate, KVS WebRTC, frame-transport payload formats)
- Bridge syntheses: [[decode-locality-per-proposal]], [[gpu-substrate-and-fleet-placement]], [[kvs-webrtc-as-fleet-frame-plane]], [[frame-transport-payload-formats]]
- Investigation notes: [[gst-rtsp-h264-only-audit]], [[immix-mp4-mux-downstream]], [[connector-decoder-routing-map]], [[connector-docker-system-deps]], [[eks-prod-node-pool-gpu-availability]]

---

## Not-Yet-Prioritized (backlog)

Captured during active work but not yet scheduled. Not in Jira — promote to §N workstreams when they become active, or fold into related tickets. Each item has a source workstream reference.

### R&D agent set — formalize post-pilot (2026-04-21)

- [ ] **Formalize three R&D agent definitions in `~/.claude/agents/`** — after the frame-storage pilot runs end-to-end, codify the three roles we tested ad-hoc:
  - `research-prospector` — WebSearch + WebFetch (headers only); finds + ranks sources; returns reading-list entries (title/URL/relevance/type/quality score). Does NOT read full content.
  - `source-reader` — refined `kb-scribe` variant; reads individual sources; returns structured source-note + concept proposals. Today's pilot pattern already proven.
  - `synthesizer` — Read across many source notes; cross-references; writes synthesis note + project-plan delta proposals. Opus-tier agent.
  **Trigger:** after the frame-storage pilot completes and we've seen each role's failure modes. See [[_pilot-2026-04-21-frame-storage-staging]] (will be written during pilot) for pilot report.
  **Model routing considerations:** prospector is the best candidate for Gemini/Haiku (token-heavy, judgment-light); synthesizer needs Opus; source-reader can be Sonnet-tier by default, Gemini-tier once routing is wired. See [[2026-04-20_multi-agent-model-routing]] + the kb-starter catch-up task above.

### Frame-storage research workstream (2026-04-21)

- [ ] **Frame-storage cross-cutting design for fleet redesign** — research + propose frame-storage strategy spanning the full lifecycle (in-flight pipeline cache → short-term clip retention → long-term compliance/retrieval). Specific user idea: **render alert/movement windows back into videos (MP4/WebM) to shed per-frame storage overhead.** Folds into every fleet-architecture proposal (A-E) as a cross-cutting concern. Seven research chunks: (1) internal current-state inventory; (2) in-flight active-alert storage; (3) short-term persistent; (4) long-term/compliance; (5) video-reconstruction approach; (6) alternative compression strategies (perceptual-hash dedup, differential encoding, tiered object storage); (7) industry references (Milestone, Genetec, Verkada, Kinesis Video Streams, bodycam platforms). Pilot task for the R&D agent set.
  - **Status (2026-04-21):**
    - [x] Chunks 1-2 (archaeology): done → [[frame-storage-current-state]]. Key finding: connector is **already stateless w.r.t. frames in the pipeline** (timestamps only, frames fetched on-demand from `image_cache`); no production video-reconstruction exists; clip assembly delegated to external `/create-video` lambda; frame-storage is ~44MB/camera of 270MB RSS (~16%).
    - [x] Chunks 5-7 (web research): prospector pilot done → 26 ranked sources added to [[fleet-architecture/reading-list]] §"Frame Storage — 2026-04-21 Prospector Pilot." Pilot learnings: [[2026-04-21_rd-agent-pilot-learnings]].
    - [ ] Next: source-reader batch on top ~9 reading-list entries (chunks 5/6/7, 3 subagents × 3 entries).
    - [ ] Then: synthesizer pass producing "frame-storage design-delta per fleet proposal" — first test of the synthesizer role.
    - [ ] Then: formalize the three R&D agent definitions in `~/.claude/agents/` (see follow-up task above).
  - **Output trail:** [[frame-storage-current-state]] (archaeology), [[knowledgebase/topics/watchman/reading-list]] §Frame Storage (prospector output), [[2026-04-21_rd-agent-pilot-learnings]] (agent-formalization input).
  - **Key design direction (user-surfaced 2026-04-21):** cost is dominated by **S3 API calls, not data volume**. Combined with the video-reconstruction idea, the converging design is **in-cluster blob for per-frame accumulation + conditional S3 promotion (only on detection-positive window close, as a single encoded clip object)**. Potential >50× S3-API-call reduction vs current pattern. See [[frame-storage-current-state]] §11 (cost math) and §12 (in-cluster + conditional promotion design). Favors proposals E and C (per-camera-group storage locality); awkward for B; natural alternative via NATS JetStream for D; weak fit for A.
  - **Validation TODOs added to this workstream:**
    - [ ] Pull S3 Cost and Usage Report data to validate the "API calls dominate" hypothesis with real fleet numbers (PUT/GET/LIST per frame vs storage-byte cost breakdown)
    - [ ] Scope `/create-video` lambda ownership — who owns it, what's the migration path (rewrite vs retire) when connector does in-process encoding
    - [ ] Benchmark in-process H.264/H.265/AV1 encode on connector pods (CPU budget, latency for typical 10-frame window) before committing to in-process vs offloaded encode
    - [ ] **Downstream-consumer audit of single-frame contracts (cross-repo + lambdas + external) — BLOCKS the clip-based shift.** Every entry point and contract currently expecting per-frame storage must be catalogued before we commit the paradigm shift. Scope of scan:
      - `vms-connector` producer side (already mapped in [[frame-storage-current-state]] §§4-6)
      - `actuate-libraries`: `actuate-frames`, `actuate-daos` (EnrichedFrameV2, WindowIdsV2, SceneChange*, ImageData), `actuate-alarm-senders`, `actuate-integration-calls`
      - Lambdas: `/create-video`, autopatrol-cleanup, autopatrol-onboarder, any frame-fetching lambda in `ds-terraform-eks-v2` or related infra repos
      - `queue_consumer` — alert-delivery pipeline; does it fetch frames from S3 for customer packaging?
      - `actuate_admin` — Django views / admin dashboards that render frames
      - `alert-ui` + `camera-ui` — frontend frame display; per-frame presigned URLs today, would need video-player fallback
      - Watchman / CHM / AutoPatrol pipelines — any per-frame S3 reads
      - External consumers: Immix contract (single-frame presigned URLs today), EBUS partner API, training-data exports to data-science
      - Terraform / infra: S3 bucket lifecycle policies, IAM on `detection_bucket` / `spray_bucket`
      **Deliverable:** a contract-inventory doc (tentative home: `topics/fleet-architecture/notes/concepts/frame-storage-consumer-contracts.md`) listing every entry point + current contract shape + migration path per consumer (pass-through clip URL / transcode shim / rewrite / retire). **Candidate agent for this work:** a new `consumer-audit` agent (bigger-scope sibling of `connector-pipeline-expert`), or multi-session invocations of the existing agent scoped per-repo. Can run in background; doesn't block current frame-storage research but must complete before any clip-based shift is committed.
  - **Research queued** (next prospector pass):
    - Chunk 8 in [[knowledgebase/topics/watchman/reading-list]] — S3 cost analysis (validate API-calls-dominate hypothesis + find vendor case studies)
    - Chunk 9 in [[knowledgebase/topics/watchman/reading-list]] — In-cluster blob storage (MinIO, Ceph, Garage, SeaweedFS, emptyDir/tmpfs, local NVMe, Redis-streams)
  - **Broken-source revisit queue** — prospector couldn't fetch PDFs / redirects / form-gated content; `curl + Read(pages=)` workaround proven today. Queue maintained in [[knowledgebase/topics/watchman/reading-list]] §"Broken-source revisit queue" and in [[_research-inbox/README]].
  - **R&D agent files formalized (2026-04-21):** `~/.claude/agents/research-prospector.md` and `~/.claude/agents/source-reader.md` written with today's pilot learnings baked in (PDF fallback rule, quality rubric, `_research-inbox/` convention). `synthesizer` agent still pending — will codify after the first synthesizer pilot runs on this topic.

### KB tooling — cycleable open-questions UX (2026-04-21)

- [ ] **Surface + answer KB open questions in a cycleable, mobile-compatible way** — source-reader and prospector runs produce per-source "Open Questions" sections that accumulate across the KB, but there's no good way to review + resolve them in batches. Want: a UX that cycles through open questions one at a time (next / previous), allows inline answering with free-form text, and works on Obsidian mobile. **Mobile-compatibility is a hard requirement** so the user can process on commute / off-laptop.
  - **Research options:** (1) native Obsidian **Bases** (YAML-defined table views) filtering on an `open-questions` section or a `status: open` frontmatter field — likely cleanest, zero-plugin-dependency; (2) **Obsidian Tasks** plugin — if we reformat open-questions as `- [ ] Question text #open-question` within notes, Tasks' query view provides cycleability and is mobile-supported; (3) a simple workflow — top-level `_open-questions-inbox.md` that aggregates wikilinks back to sources, user walks through serially; (4) custom Obsidian plugin (overkill unless 1-3 all fall short).
  - **First step:** evaluate Bases' filtering on frontmatter against our existing `source` notes' Open Questions sections. If Bases can present a filtered list of "notes with unresolved open questions" + click-through-to-answer flow, that's probably sufficient.
  - **Convention needed:** standardize on either a frontmatter `open_questions:` list or a structured `## Open Questions` heading with `- [ ] question` checkbox syntax. Pick one and retrofit existing source notes.
  - **Priority:** low/medium. Nice-to-have UX improvement; not blocking any research workstream. Good candidate for an afternoon exploration session.

### KB tooling — catch up with upstream kb-starter (2026-04-21)

- [ ] **Review sbuffkin/kb-starter upstream updates and fold back into our KB skills** — we only pulled the initial-commit baseline from [sbuffkin/kb-starter](https://github.com/sbuffkin/kb-starter); the repo has had major enhancements since that we should incorporate into `/kb-ingest`, `/kb-synthesise`, `/kb-queue`, `/kb-lookup`, `/kb-auto`, and the multi-agent/multi-model routing pattern discussed in [[2026-04-20_multi-agent-model-routing]]. User note: "I do not believe that it will take much effort at all ... we previously only used the 'init commit' the updates since represent some major enhancements." Specifically check whether the upstream has patterns for: Gemini/Codex/multi-model routing, session-inbox messaging, two-phase plan→execute, consensus voting, worktree-isolated parallel agents, prompt-cache-aware session stickiness. Today's pilot ([[_pilot-2026-04-21-staged]]) proved the Claude-only fan-out works; integrating upstream's routing patterns would be the natural next upgrade. Entry point: clone or diff against current state, triage each improvement, update skills incrementally.

### From §3 (AutoPatrol stale-schedule cleanup) — 2026-04-17 planning

Follow-ups spun out of the cleanup-Lambda PRs that aren't blocking the first ship, but will need attention before or shortly after prod rollout:

- [ ] **DDB module: per-table TTL support** — `modules/dynamodb` in `ds-terraform-eks-v2` doesn't support per-table TTL blocks today. Until it does, `autopatrol_cleanup_counters` counters don't self-expire. Either extend the module (adds `ttl` variable per table object), enable TTL manually via console after first apply, or have the Lambda sweep old rows on a cadence.
- [ ] **Prod terraform for cleanup + reenable Lambdas** — `stages/prod/us-west-2/lambdas/` uses the `lambdas` module (map pattern) and `stages/prod/eu-west-1/` is unclear. The dev/EU stanzas in `core-lambdas/main.tf` don't transfer directly. Needs investigation of how the onboarder Lambda is currently deployed to prod before mirroring.
- [ ] **Tighten IAM on cleanup + reenable Lambda roles** — first-cut used broad AWS-managed policies (`AmazonDynamoDBFullAccess`, `AmazonSQSFullAccess`, `SecretsManagerReadWrite`) for parity with the onboarder. After ship, scope down to: SQS Receive/Delete on the specific queue, DDB CRUD on the specific table, Secrets Manager read for the one autopatrol secret, CloudWatch logs write.
- [ ] **Function URL + AWS_IAM authorizer for reenable Lambda** — plan §5 expects an IAM-auth'd Function URL, but `modules/core-lambdas` may not support Function URLs yet. Either extend the module or define the URL inline in the stage file.
- [ ] **Reserved concurrency = 2 on cleanup Lambda** — plan §7 calls for this as a runaway-disable guard. Check if `core-lambdas` module exposes `reserved_concurrent_executions`; if not, extend or set directly.
- [ ] **CloudWatch alarm: DLQ depth > 0 pages oncall** — per plan §7 failsafes. Lives with the SQS terraform.
- [ ] **Admin UI page: "Re-enable cleanup-disabled schedules"** — list filtered by `disabled_by=cleanup_lambda&is_deleted=true`, "Re-enable" button POSTs to the reenable Lambda's Function URL. Unclear home — `actuate_admin` Django admin site vs. camera-ui React SPA. Decide before Week 3 of rollout.
- [ ] **`connector_version` env var** — `cleanup_emitter.py` reads `CONNECTOR_VERSION` for the SQS payload. Needs to be set in the connector's container/pod env (e.g. from the image git SHA) via `connector_deployer` or the settings pipeline. Defaults to `"unknown"` today — usable but lossy for debugging.
- [ ] **Slack webhook config** — cleanup Lambda posts to `#autopatrol-sync`. Reuse the onboarder's existing `SLACK_WEBHOOK_URL` from Secrets Manager, wire via env var in terraform.
- [ ] **NR instrumentation for onboarder + cleanup + reenable** — plan §7. Project pattern TBD (layer vs decorator). Bundle with the Lambda deploy-pipeline update (§8). Also unblocks observing this work post-ship.
- [ ] **Admin API call path for resolving Immix schedule_id → admin PK** — cleanup Lambda needs this to target the PATCH. Confirm the filter path (likely `GET /api/auto_patrol_schedule/?tenant=<tenant>&scheduleId=<sid>`) and cache the mapping in the DDB counter row after first lookup.
- [ ] **`dev/eu-west-1/dynamodb` stage: "0 to add" bug when new tables declared** — terragrunt render shows the new table in inputs, but terraform plan doesn't create it. Suspect: `var.tables` `object(...)` type silently drops entries where `default_attrs` provides fields not in the module schema (`use_pay_per_request`, `enable_pitr` aren't declared). Workaround: drop the unknown fields from `default_attrs` or extend the module's type. ~~Blocks `autopatrol_cleanup_counters-dev` creation.~~ *(Superseded 2026-04-22 — real table lives in prod/us-west-2, CLI-provisioned; see PR #69 body.)* Details in [[2026-04-17_local-testing-strategies-per-repo]].
- [ ] **`dev/eu-west-1/core-lambdas` stage: missing `remote_state_bucket` var** — stage passes `remote_bucket_name`, module requires `remote_state_bucket`. Pre-existing; blocks any plan on that stage. Either rename in the stage's `inputs = {...}` or align the module. ~~Blocks the `lambda_immix_autopatrol_schedule_cleanup` + `...-reenable` stanzas from planning.~~ *(Superseded 2026-04-22 — real Lambdas live in prod/us-west-2, CLI-provisioned; see PR #69 body.)*

### From fan-out findings (2026-04-22)

Items surfaced during the 2026-04-22 morning fan-out that don't map to an active workstream yet. Keep here until they become urgent enough for a §N or until `/todos-audit` promotes them.

- [ ] **§3 IaC drift: port CLI-provisioned infra into terraform** — meta-item tying together several §3 Not-Yet-Prioritized bullets above. Real resources live in prod/us-west-2 (acct `388576304176`) and were CLI-provisioned 2026-04-20: 4 SQS queues, 1 DDB counter table, 2 Lambdas, 2 IAM roles, 2 DLQ alarms, 1 Function URL. See [PR #69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) body for the full resource ARN table. Port target: `stages/prod/us-west-2/` (sqs_queue + dynamodb + lambdas — last one uses `deploy_lambda` map pattern, not the `core-lambdas` pattern from dev/EU). Needs: `modules/dynamodb` TTL extension, `core-lambdas` Function URL support (or direct resource), `terraform import` of each existing resource. Substantial PR; not blocking functionality but IaC drift will compound.
- [ ] **§3 Step D merge-legitimacy confirmation** — `autopatrol_onboarder#3` merged 2026-04-21T16:20Z despite title "STAGE BAKE ONLY — DO NOT MERGE YET" and `CHANGES_REQUESTED` review. Was this intentional (decided the bake was good enough to ship code-with-flag-off early) or accidental? Confirm before Step E (`CLEANUP_ENABLED=true` flip). Owner: cleanup-lambda session or whoever clicked merge.
- [ ] **§3 §2b-style closeout for fan-out discoveries** — two one-liner KB edits worth batching: (a) clarify in `2026-04-17_stale-schedule-cleanup-design.md` or `2026-04-17_no-patrols-emit-points.md` that emit comes from `connector-{site_id}-vch-{n}-chm-cronjob` containers, NOT the main vms-connector pod (future debugging will hunt in the wrong place otherwise); (b) cross-link `2026-04-20_lambda-creation-and-tuning-playbook.md` into §3's Related block (currently orphaned). Both are ~2-line Edits; should fold into the fan-out→KB-update automation below.
- [ ] **Fan-out findings → auto-KB-update automation** — when a morning fan-out surfaces an architectural fact that clarifies an existing synthesis (like today's "emit comes from CHM cronjob containers, not vms-connector"), the update should happen automatically instead of as an ad-hoc manual write. Design direction: post-fan-out step in `/daily-scope` that (a) diffs fan-out output against referenced KB notes, (b) offers to append a clarification line with provenance, (c) bumps the note's `updated:` date. Can piggyback on the `kb-scribe` agent. First-class example today: the CHM cronjob architecture fact; also candidate: §3 CLI-resource ARN inventory lives only in PR body, not any KB note. *User preference 2026-04-22: this class of work should be automated, not batched into manual writes.*
- [ ] **OOMKill fleet sizing audit** — fan-out revealed chronic fleet-wide OOMKills (103 events/24h across 10+ containers). Lead offenders: `connector-14170` (32/day, 7-day trend consistent — not a regression), `connector-23730` (18), `connector-40693` (17), `clips-prod` (9). Drill-down verdict (nrql-investigator, 2026-04-22): `connector-14170` is chronic-camera-count-driven — large multi-building installation running at flat 58-60% memory utilization, kills happen on ordinary allocation spikes. Recommended: **memory limit +25-30% on the site(s) missing a memory-tier assignment**. Broader scope: audit fleet for sites whose camera count exceeds the threshold for the default memory tier. Pre-ticket; candidate for a §N workstream if this happens to be a meaningful slice of customer "my cameras keep dropping" complaints.
- [ ] **`NoneType unpack` error 3x-up drill** — fan-out flagged 5,174 events in last 12h vs 1,699 prior 12h (`cannot unpack non-iterable NoneType object`). Could be daytime camera-load artifact; could be a new bug in an ingestion path. `FACET container_name` over the fingerprint to see which sites dominate. One-shot investigation; schedule into a morning-followup.
- [ ] **Orphan-branch triage (3 lanes)** — not currently assigned to any workstream, each needs "who owns, promote to § or delete":
  - `actuate-libraries@feature/autopatrol-puller-error-classification` — 1 commit "Classify init_stream errors + on_init_error callback" + dirty `pyproject.toml`/`uv.lock`. Pullers library patch-version bump; likely §3-adjacent (cleanup-lambda session?). Also an orphan synthesis `2026-04-20_lambda-creation-and-tuning-playbook.md` is associated.
  - `autopatrol-server@fix/sqs-stuck-window-id-lookup` — 1 unpushed commit "fix(queue): handle missing WindowIdsV2 entry and skip unresolvable clips." Not in any §.
  - `camera-ui @ main` with `Login.tsx` dirty — main should not be dirty; rebase off or revert.
- [ ] **§2d option-3 mitigation time-bound fallback** — Mark posted the nginx/apache fix recipe on [GH#1658](https://github.com/aegissystems/vms-connector/issues/1658) Sunday 21:50Z; Immix silent since. If no Immix engagement by **2026-04-28**, elevate option-3 (pin Sectigo DV R36 intermediate into connector's custom SSL context) from "backup" to "active scope." Escape-hatch from indefinite external-waiting.

### From synthesis-decision interview (2026-04-22)

Items surfaced by decisions taken after the frame-storage design-delta synthesis (`topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md`). Interview outcomes captured in that synthesis's "## Post-synthesis decisions" section.

- [ ] **`/create-video` Lambda retirement (post-PoC)** — surfaced in `2026-04-22_frame-storage-design-deltas.md` as the biggest cross-team implication of the in-cluster blob + conditional-promotion design. All 5 proposals retire `/create-video` under the delta; actual retirement conversation gated on PoC selection. Once a proposal is picked, identify `/create-video` owner (likely in `ds-terraform-eks-v2` or a related lambdas repo; check CloudWatch logs + terraform stanzas for authoring history), draft stakeholder outreach, schedule migration/rewrite-vs-retire conversation. **Trigger:** PoC selection complete.
- [ ] **AWS Cost Explorer integration for skills/checks** — user meta-ask 2026-04-22 during the synthesis-decision interview: "We should integrate some level of AWS cost explorer calls into our skills and checks in general. I think doing some of it during this exploration would prove very valuable." Design surface: (a) new tool/MCP or boto3-backed Bash pattern for cost-explorer access (needs `ce:GetCostAndUsage` permission scope); (b) which skills benefit — `/autopatrol-cleanup-lambda-check` for DDB/SQS/Lambda invocation cost trend, fleet-architecture investigations for S3 PUT/GET cost breakdown, `/daily-scope` morning fan-out for aggregate weekly-cost-drift exec item, `/overnight-logs` for unexpected overnight cost spikes; (c) secret/credential management pattern (which AWS profile, when to refresh SSO); (d) output shape — cost numbers as aggregates + "significantly changed" flags rather than raw rows (NR-style discipline). Pair with KB tooling work. First concrete use-case is the frame-storage S3 PUT/GET validation (pulled ad-hoc for the re-score), which doubles as the pilot for the pattern.
- [ ] **Formal A-E re-score against evaluation rubric with frame-storage delta baked in** — gated on (a) NR non-eventful-window-ratio query (ran 2026-04-22; directional validation landed, precision gap requires `create_detection_window` follow-up or instrumentation below), (b) AWS Cost Explorer pull for `detection_bucket` + `spray_bucket` S3 PUT/GET over 30 days (user-driven). When both data points land, spawn a third synthesizer pass producing weighted-score comparison matching 2026-04-16 table format. Target file: `topics/fleet-architecture/notes/syntheses/2026-04-XX_fleet-proposal-rescore-with-delta.md`. Outputs will inform PoC selection.
- [ ] **`SlidingWindowStep.close_window` instrumentation — add `window_outcome` log line** — surfaced by the 2026-04-22 NR non-eventful-window-ratio query. Current logs have a `None`-vs-window-ID split in `closing window` that does NOT cleanly map to the S3-PUT boundary (4.5M non-None window closes vs 501 patrol-alert emissions is a 9,000× gap; "has window-ID" is not a detection-positive proxy). Fix: single structured INFO log line at `SlidingWindowStep.close_window` emitting `window_outcome=detection_positive|no_detection` + `window_id` + `site_id` + `camera_id`. ~5 lines of code in `actuate-pipeline` (or wherever `SlidingWindowStep` lives — likely `actuate-libraries/actuate-pipeline/`). Very high-value for future cost-model work: makes the non-eventful-ratio query a one-liner (`FROM Log SELECT count(*) WHERE window_outcome='detection_positive' / count(*) FACET ...`). Candidate for a small connector/library PR independent of the fleet redesign; pairs with §6 metrics-to-track workstream. **Priority: low/medium (not blocking), but completion unblocks tight cost-model claims.**

### From NR reversal + CE validation (2026-04-22 afternoon)

Items surfaced after the >50× S3-reduction claim was corrected to ~1.45× via a follow-up NR query against `create-detection-window` + AWS Cost Explorer 30-day pull.

- [x] **Proposal B-prime formally closed** — `topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md` carries a CLOSEOUT BANNER. Score 6.25/10; re-solves E's problem with more moving parts; node-local tmpfs durability regression. Re-examine only if E's PoC fails on motion-drop-rate or detection-core ops load.
- [x] **Design-delta synthesis amendment published** — `topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md` carries an AMENDMENT banner at the top with the corrected non-eventful-ratio (~31%), corrected cost impact (~$4.7k/mo savings on $15k/mo PUT baseline), and notes that motion-gating at puller (proposals D/E) IS the cost lever — conditional-promotion-at-window-close is a second-order win only.
- [x] **Proposal B status clarified** — `topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md` carries a Status Note (2026-04-22): original 7.25/10 score stands; delta-synthesis's "B invalidated" claim is itself invalidated; B remains viable-but-operationally-complex.
- [ ] **Fleet-coordinator unification question — scoping** — `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md` tracks the structural observation that Proposals B-prime, C, and E each carry a coordinator-shaped control-plane service (Blob Coordinator / Assignment Controller / Site Context Service) with suspiciously overlapping responsibilities. If a single "fleet-coordinator" primitive could cover all three, proposal boundaries collapse from architectural to implementation-detail. Next steps tracked in the concept note's §"Track / next steps" — sketch minimum-viable gRPC API, benchmark lease-churn across the three use-cases, prior-art scan. **Feeds the formal A-E re-score when it runs.**
- [ ] **Formal A-E re-score — now unblocked** — real CE data is in hand ($32.8k/30d S3 cost split 62.7% API / 35.2% storage / 2.1% transfer; $15k/30d on Tier1 PUTs at 2.8B requests). Re-score was previously gated on data validation. Ready to spawn as a third synthesizer pass. Expected ranking shift: modest (E stays on top; C retains cost advantage; D gains on absolute savings; A improves slightly; B stays at original score; B-prime stays closed). Target file: `topics/fleet-architecture/notes/syntheses/2026-04-XX_fleet-proposal-rescore-with-delta.md`.
- [ ] **Motion-gate validation** — what fraction of raw frames does FDMD actually drop in production today? Proposals D/E assume 60–80%. Real number grounds the cost modeling. NR query on FDMD emit rate vs raw-frame rate; or observed pipeline throughput vs inbound RTSP rate. Data-grounded answer retires the "projected" caveats in the fleet-arch syntheses.
- [ ] **Tier3 S3 replication cost investigation — $3,646.91 / 30d ($44k/year), 11.1% of S3 spend, 72.9M requests** — surfaced by `/cost-check S3 --days 30` on 2026-04-22. Don't know what's driving it: cross-region replication? lifecycle transitions? Intelligent-Tiering moves? Could be a quick-win independent of any fleet-architecture proposal. Investigation steps: (a) S3 Storage Lens or bucket-lifecycle policy audit; (b) per-bucket Tier3 breakdown via CUR + Athena if it's worth the setup; (c) CloudTrail dive for `PutBucketLifecycleConfiguration` + `PutBucketReplication` recent events. **PRIORITY: seeded for 2026-04-23 morning** (user-prioritized 2026-04-22).
- [ ] **S3 storage growth rate check** — $11,548.20 / 30d on ~1.94M GB-months = ~65TB working set. Is that growing? At what rate? Are lifecycle rules doing what they should? One CE call with daily granularity + an S3 Storage Lens glance would answer. Feeds into proposal cost modeling and may reveal more Tier3 drivers.
- [x] **Cross-service cost landscape (top-10)** — ran `/cost-check --top-services --days 30` 2026-04-22: **Fleet total $219,854.36 / 30d = ~$2.67M/year.** EC2 compute $121,715 (55.4%), S3 $32,821 (14.9%), DynamoDB $18,220 (8.3%), EC2-Other (EBS/NAT/etc) $16,147 (7.3%), ECS $5,662 (2.6%), VPC $4,541, RDS $4,498, AWS Config $3,719 (interesting — configuration recording), CloudWatch $2,849, ELB $2,317. **Load-bearing reframe: S3 is only ~15% of total cloud spend; EC2 compute dominates. Any frame-storage savings ceiling is ~$400k/year. Compute-side efficiency (pool consolidation in C/E) has a much larger leverage ceiling. Feeds the A-E re-score.**
- [ ] **Inference API cost visibility** — the top-10 doesn't show a clear "inference API" line (Lambda is only 0.3% = $632/30d, so it's not Lambda-based). Likely inference compute is lumped into the EC2 $121k/mo or ECS $5.7k/mo. Need to disaggregate: is inference on its own EC2 node pool? Visible via tags or via `/cost-check EC2 --group-by INSTANCE_TYPE`. Relevant for proposals that change pool counts (C's "one pool per worker" consolidation, E's "camera-group-scoped pool" model).
- [ ] **AWS Config cost ($3,719/30d = $45k/year, 1.7% of total)** — surprising line item. AWS Config is a compliance/audit service; $45k/year for it might be right or might be a misconfigured recording scope. One-shot investigation: review Config recording scope + rules + delivery channel volume. Could be a quick-win worth a 30-min look.
- [x] **Formal A-E re-score synthesizer pass — LANDED 2026-04-22** — `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md` (~2,500 words, third synthesizer pilot). **Ranking (unchanged order):** E 8.05 > C 7.40 > B 7.25 > D 7.05 (+0.20 from motion-gating validation) > A 4.45 (+0.20 from delta adoption); B-prime CLOSED 6.25. **PoC recommendation:** First PoC E, runner-up C (pending WireGuard). **No further park recommendations.** **Caveat:** agent had S3 breakdown but not the top-services landscape — cost-axis reasoning undersells compute-side leverage (EC2 55% vs S3 15%). Follow-up amendment option (not blocking): dispatch a brief synthesizer pass to rescore cost-axis with compute-dominant framing, likely widens E's lead further. Left as-is for now; ranking conclusion is robust regardless.
- [ ] **Pre-PoC open questions** — progress 2026-04-22 evening:
  - [x] Motion-gate drop-rate — **user decision: conservative 40-50% assumption** rather than empirical measurement for now. Rescore addendum applied in `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md` "Addendum" section. Empirical measurement remains a PoC invalidation-criterion for E (if measured <40%, flip to C).
  - [x] Fleet-coordinator unification — **RESOLVED viable** via API sketch at `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-coordinator-api-sketch.md`. 15 RPCs, 5 resource types, verdict "coherent, not a distributed monolith." +1 to C/E on ops-simplicity applied in the rescore addendum's conditional row (now final).
  - [ ] Tier3 replication $44k/year driver — seeded as 2026-04-23 morning priority.

### Rescore addendum + fleet-coordinator sketch landed (2026-04-22 evening)

Both written inline in main session after Task background-subagent quota was hit (resets 2026-04-22T14:00 ET).

- [x] **Rescore addendum** — `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md` → new "## Addendum (2026-04-22 evening) — Cost-axis refinements" section. Bakes in (1) top-services landscape compute-dominance reframe, (2) conservative 40-50% motion-gate. Impact: E cost-axis 10→9, D cost-axis 7→6, C reinforced but ceiling-capped. Ranking order unchanged; E's lead narrows 0.65→0.45 over C. Conditional scenario (coord unification affirmative) now promoted to final.
- [x] **Fleet-coordinator API sketch** — `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-coordinator-api-sketch.md` (~1900 words, fifth synthesizer pilot). Verdict: **coherent, unification viable.** 15 RPCs across Assignment / Schedule / Config / Window-Outcome / Admin categories. Per-proposal coverage clean (C uses 5 RPCs, E uses 9, B-prime would use 4 if reopened). Est 4-6 dev-weeks for v1. Open questions: config-cache scope, schedule-eval placement, multi-region shape, audit-log integration.
- [x] **Coord concept note updated** — `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md` status flipped from "open, tracked" → "RESOLVED — coherent, unification viable" with pointer to the API-sketch synthesis.
- [ ] **Final composite ranking after both refinements** (for reference):
  - **E: 8.00** (7.85 addendum + 0.15 coord-unification) — PoC-1
  - **C: 7.55** (7.40 addendum + 0.15 coord-unification) — PoC-2
  - B: 7.25 (no coord-unification applied; B doesn't have a coordinator as originally scoped)
  - D: 6.85
  - A: 4.45
  - B-prime: 6.25 CLOSED
- [ ] **PoC-1 (E) invalidation criterion tightened** — per the rescore addendum strategic note: if E's measured FDMD drop is <40%, C overtakes on composite (C's cost-axis is structurally robust and doesn't depend on motion-gating). Flip primary to C unconditionally in that case.

### AWS Cost Explorer integration as a skill (2026-04-22)

- [x] **Cost Explorer access pattern proven + documented** — `topics/engineering-process/notes/concepts/aws-cost-explorer-access-pattern.md` captures the `AWS_PROFILE=prod` invocation, canonical queries, and post-processing recipe. Load-bearing first use was the 2026-04-22 frame-storage design-delta S3 breakdown (2.8B PUT/30d, $32.8k total S3 cost).
- [x] **`/cost-check` skill** — built 2026-04-22. `~/.claude/skills/cost-check/SKILL.md` + `run.sh` wrapper. Supports direct mode (markdown output) + sub-skill mode (`--format json`). Per-service classification rules for S3 / DynamoDB / Lambda / EC2 baked in; generic fallback for anything else. Smoke-tested end-to-end (30-day S3 breakdown matches the earlier ad-hoc CE result $32.8k/30d). Other skills can invoke as `/home/mork/.claude/skills/cost-check/run.sh <ARGS> --format json`. **Follow-up items** (not blocking): (a) integrate into `/autopatrol-cleanup-lambda-check` to surface DDB+SQS+Lambda cost trend alongside operational health; (b) integrate into `/daily-scope` morning fan-out as a weekly cost-drift exec item; (c) per-bucket / per-resource filtering via CUR + Athena (design stub only — would require CUR export setup, not in v1 scope).

---

## Discipline

- Update this note at the end of each working session where one of these workstreams moved.
- **Never delete todo blocks.** Close-outs go through [[skill-daily-wrap|/daily-wrap]]: completed line items land in the day's daily note with a short summary; fully-completed workstream sections (§N) move wholesale into the daily note and leave a pointer row in `## Archive` below.
- When a new high-level TODO appears, add it via [[skill-todos-add|/todos-add]] — don't let work accumulate in chat-only form.
- Periodic audit (~weekly) via [[skill-todos-audit|/todos-audit]] — catches stale workstreams, orphaned Jira tickets, untracked branches, priority drift.
- Cross-repo opportunity sweep via [[skill-repo-scan|/repo-scan]] — surfaces high-impact + low-hanging-fruit GitHub issues that aren't assigned to Mark (Jira auto-sync doesn't see these). Also foldable into `/daily-scope --with-repo-scan`.
- **Items in "Not-Yet-Prioritized" are not tracked in Jira** — if one becomes urgent, create a ticket and promote to a §N workstream.

## Archive

Pointer table for fully-completed workstreams. Full content lives in the daily note linked on each row.

| Closed | Workstream | Daily note |
|--------|-----------|------------|
| 2026-04-23 | §1 Inference API v5 — finish for testing | [[2026-04-23]] |

## Related

- [[personal-notes/_summary|Personal Notes topic]]
- [[team-structure/_summary|Team Structure topic]]
- [[engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle|Feature Development Lifecycle]]
- [[agents-catalog]] — which agents help with which workstream
- [[automation-jira-sync]] — the daily job that refreshes the "Current Jira Queue" section
- Skills: [[skill-daily-scope|/daily-scope]], [[skill-daily-wrap|/daily-wrap]], [[skill-todos-audit|/todos-audit]], [[skill-todos-add|/todos-add]], [[skill-repo-scan|/repo-scan]]
