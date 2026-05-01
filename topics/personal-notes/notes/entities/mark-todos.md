---
title: "Mark's High-Level TODOs"
type: entity
topic: personal-notes
tags: [todos, mark, work-plan, priorities, personal]
created: 2026-04-16
updated: 2026-05-01
author: kb-bot
---

# Mark's High-Level TODOs

> **Note:** the "Current Jira Queue" section near the bottom is rewritten each day by [[automation-jira-sync]] — do not edit that section manually (see the HTML comment sentinels).

> **Rolling-forward convention (2026-04-27):** this file holds **open and in-flight work only**. Closed `[x]` sub-items move into that day's daily note (`topics/personal-notes/notes/daily/YYYY-MM-DD.md`) under a `## Closed Sub-items` heading the moment they close — `/daily-wrap` Step 2.7 enforces this. Whole closed workstreams (§N) move into `## Closed Workstreams` with a pointer row in the `## Archive` table at the bottom. Pre-cleanup snapshot (1219-line copy preserving all close-out history) lives at `_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md` for reference. Daily notes carry `topics:` and `workstreams:` frontmatter so cross-topic queries via grep work.

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
  - [ ] Identify `connector-23202-chm-cronjob` customer + what changed 2026-04-17 *(2026-04-27 update: customer 23202 cluster has `(copy)` template-clone suffix; human-name TBD)*
  - [ ] Consider option-3 mitigation (pin Sectigo intermediate into custom SSL context) if external timelines slip
- [ ] **[vms-connector#1656](https://github.com/aegissystems/vms-connector/issues/1656) — `streamId: null` rejection on `raise_patrol_alert` (architectural)** — Immix's `/Patrols/{id}/raise` requires GUID streamId, but streamId is only delivered from `get_patrol_stream` which is the very call that's failing when we need to CNCTNFAIL. Writeup: [[2026-04-20_streamid-null-patrol-alert-bug]]. Open actions:
  - [ ] Await Immix response on preferred remediation (optional streamId for connectivity codes, or deviceId-keyed lookup endpoint)
  - [ ] §10 cross-link: route `SiteDisabledOrDisarmed` subset through the cleanup Lambda pipeline
- **Context:** Both issues show up as "cameras offline" in customer-facing healthcheck UI — a diagnostic visibility gap. Today we can't distinguish "camera actually down" from "our TLS fails" from "Immix state hasn't propagated" from the customer's vantage point. Worth considering (future workstream): per-failure-mode healthcheck status codes that differentiate connector-side vs customer-side root causes.

> **§2b** AutoPatrol deferred-alert race condition — CLOSED 2026-04-20 → archived to [[2026-04-20]]

---

## 3. New Lambda — AutoPatrol stale-schedule cleanup

**Repo:** `autopatrol_onboarder` ([aegissystems/autopatrol_onboarder](https://github.com/aegissystems/autopatrol_onboarder))
**Deploy:** new Lambda, sibling to the onboarder Lambda (same repo, separate function)
**Status:** Step E (cleanup-enabled flip) GREEN at 4-day window; Step F (connector emit-flag flip) is the next concrete shipping step
**Plan:** `/home/mork/.claude/plans/sequential-questing-creek.md`
**Design synthesis:** [[2026-04-17_stale-schedule-cleanup-design]]
**Closed sub-items archive:** [[2026-04-17]] (§0 KB consolidation), [[2026-04-21]] (§§1/4/5/7/8 + Step D), [[2026-04-22]] (§§2/3/6 + Steps 0a/0b/A/B/C), [[2026-04-23]] (PRs #4–#8 + Step E.1/E.2)

### Problem (1-liner reminder)

Immix-side schedule deletions never flow back to our admin DB — stale cronjobs fire forever. Cleanup Lambda counter-tracks per-schedule "no patrols" emits over a cadence-aware window, confirms 404/DEACTIVATED with Immix, then soft-disables in admin with audit fields. Re-enable Lambda + admin UI button reverses any disable.

### Open work

- [ ] **Step E.3** — monitor 24-48h post-flip for the 7 known schedules emitting. Gate to Step F on: 0 DLQ growth, 0 wrong-disable events, anomaly-reset continues working as expected. *(2026-04-27 verify: GREEN at 4-day window — 102 invocations, 0 errors, 0 throttles, queues + DLQs all 0/0. Ready to advance.)*
- [ ] **Step F:** Prod US scale-up — flip `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` on prod connector pods. Lambda already consumes from prod queue. This is a volume event, not a criticality event. **PR is in `kubernetes-deployments`** (the env var lives in the connector helm chart, not on the Lambda).
- [ ] **Step G:** Prod EU — needs net-new infra (SQS + DDB + Lambda mirrors in eu-west-1). Separate track. IAM policy v2 already has EU ARNs pre-granted for when infra lands.
- [ ] **§10 follow-up:** Extend cleanup signal: route `SiteDisabledOrDisarmed` Immix responses to the same pipeline — surfaced 2026-04-20 from [[2026-04-20_streamid-null-patrol-alert-bug]] investigation (5/10 of recent CNCTNFAIL failures in [GH#1656](https://github.com/aegissystems/vms-connector/issues/1656) were `SiteDisabledOrDisarmed`). Requires care: `SiteDisabledOrDisarmed` can be legitimately transient (site armed only during business hours), unlike "no patrols" which is deterministic-deletion. Proposed: connector emits separate SQS event (distinct event_type), cleanup Lambda tracks over LONGER window than "no patrols" (e.g. 30 days vs 48h), only soft-disables if continuously in that state. Design decision needed: threshold window + share DDB table or use separate one. Not blocking current §9 rollout — layer on after stage bake.
- [ ] **§3 follow-up: Immix error-pattern observability** (surfaced 2026-04-23). Immix returns 400 + "system is unavailable" body for schedules that are actually gone — we just fixed that one case (PR #7) but Immix is known to deviate from REST conventions, so other status codes / body shapes may also mean "gone." Instrument `_check_immix` with structured log fields (`immix_status_code`, `immix_body_first_100_chars`, `verdict`) and/or an `AutoPatrolImmixResponse` NR custom event so new patterns surface in aggregation queries rather than silent multi-day retry loops. Full catalog + recommendations: [[2026-04-23_immix-api-error-patterns]].

### Monitoring / hand-off pointers (for another agent picking up)

- **Morning check-in:** run `/autopatrol-cleanup-lambda-check` — covers all the pre-flip + post-flip validation.
- **Watch list:** [[2026-04-24_morning-watch-list]] — expires 2026-04-25 once everything's green (rolling).
- **Dashboard signals** (staged in `~/.claude/skills/dashboard-check/config/signals.json`):
  - `cleanup_lambda_dlq_depth` (critical, must be 0)
  - `cleanup_lambda_errors`
  - `cleanup_lambda_actual_disable_rate` — manager-visible audit metric (actual PATCHes)
  - `cleanup_lambda_anomaly_reset_rate` — "reached threshold but Immix said active → did NOT disable" — the Immix-side-mismatch gauge
  - `cleanup_lambda_anomaly_repeat_offenders_7d` — flappy/mismatched schedule detector
  - `cleanup_lambda_would_patch_rate` (should stay near 0 post-flip)
  - `cleanup_chm_emit_24h` + `patrol_exit_emit_rate` (upstream emit volume)
- **Audit trail for manager:** `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda` — returns any schedule ever disabled by this Lambda. **First row landed 2026-04-23T22:09:58Z**: admin_pk=235 (Immix `636be1ba-57c9-4da1-c534-08de1b193ea0`), disabled after the 400-as-gone fix in PR #7.
- **Rollback path:** flip `CLEANUP_ENABLED=false` via `aws lambda update-function-configuration`. Instant. No data loss; DDB counters keep accumulating but no PATCHes fire.
- **Re-enable individual schedules:** the sibling reenable Lambda (`immix-autopatrol-schedule-reenable`) via IAM-auth'd Function URL. Reverses any disable.

### Related

- [[2026-04-17_stale-schedule-cleanup-design]] — load-bearing design synthesis
- [[2026-04-22_cleanup-lambda-bake-state]] — DDB counter snapshot, IaC drift finding, Step E flip-readiness analysis
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — post-hoc lambda build/tune recipe
- [[autopatrol-cleanup-lambda]] — entity page
- [[autopatrol-onboarder]] — sibling Lambda
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

- §1 — v5 API work this follows from (archived [[2026-04-23]])
- [[inference-api/_summary|inference-api topic]] — authorizer + endpoint surface
- [[admin-api/_summary|admin-api topic]] — user/group/customer/RBAC primitives
- [[external-api/_summary|external-api topic]] — partner-API initiative context
- [[security-hardening-checklist]] — design-review gate

---

## 5. Fleet Architecture — review and consolidate 2026-04-16 proposals

**Priority:** this-week
**Tickets:** *(pre-ticket — captured in [[fleet-architecture/_summary|fleet-architecture]] topic syntheses)*
**Status:** review phase — formal A-E re-score landed 2026-04-22; PoC selection next

### What's left

- [ ] Review each proposal and annotate with questions / concerns / deal-breakers
- [ ] Apply [[2026-04-16_evaluation-rubric|evaluation rubric]] consistently across all 5
- [ ] Pick top 2 for team deep-dive *(rescore says E first, C runner-up)*
- [ ] Decide whether [[2026-04-16_graceful-failover-design|graceful failover]] and [[2026-04-16_frame-transport-comparison|frame transport]] should become ADRs
- [ ] **Pre-PoC open question — Tier3 replication driver investigation** ($44k/year, 11.1% of S3 spend, 72.9M requests). Investigation steps: (a) S3 Storage Lens or bucket-lifecycle policy audit; (b) per-bucket Tier3 breakdown via CUR + Athena if it's worth the setup; (c) CloudTrail dive for `PutBucketLifecycleConfiguration` + `PutBucketReplication` recent events.

### Proposals

- [[2026-04-16_proposal-a-minimal-split|A — Minimal split]] (rescore: 4.45)
- [[2026-04-16_proposal-b-stage-fleets|B — Stage fleets]] (rescore: 7.25)
- [[2026-04-16_proposal-c-camera-worker|C — Camera worker]] (rescore: 7.55, PoC-2)
- [[2026-04-16_proposal-d-event-driven|D — Event-driven]] (rescore: 6.85)
- [[2026-04-16_proposal-e-hybrid-sidecar|E — Hybrid sidecar]] (rescore: 8.00, PoC-1)
- [[2026-04-22_proposal-b-prime-stateless-with-coordinator|B-prime — CLOSED 2026-04-22]] (6.25; archived [[2026-04-22]])

### Relevant KB

- [[fleet-architecture/_summary|fleet-architecture topic]]
- [[2026-04-16_evaluation-rubric|evaluation rubric]]
- [[2026-04-22_fleet-proposal-rescore-with-delta|formal rescore + addendum]]
- [[2026-04-22_fleet-coordinator-api-sketch|coordinator unification API sketch]]
- [[2026-04-16_graceful-failover-design]]
- [[2026-04-16_frame-transport-comparison]]

### Related

- [[adr-writing-guide]] — if any proposal graduates to an ADR

---

## 6. Software Architecture — sketch local implementations of the 5 projects + dashboard

**Priority:** this-week
**Tickets:** *(pre-ticket — captured in [[knowledgebase/topics/software-architecture/_summary|software-architecture]] topic syntheses)*
**Status:** prototyping phase — 1/5 sketches shipped (metrics 2026-04-23)
**Closed sub-items archive:** [[2026-04-22]] (substrate decision + scaffold), [[2026-04-23]] (init bundle + metrics sketch shipped)

Goal: stand up **minimal local sketches** of each of the 5 projects/designs drafted 2026-04-16 in the software-architecture topic. Goal is feel + viability feedback, not production-ready systems. Plan lives at [[2026-04-17_local-sketches-plan]].

### Open work

- [ ] [[2026-04-16_code-health-dashboard|Code health dashboard]] — extensible dashboard consolidating code health metrics
- [ ] [[2026-04-16_tooling-landscape|Tooling landscape]] — pick 2-3 tools from the catalog to actually try locally
- [ ] [[2026-04-16_architecture-enforcement|Architecture enforcement]] — prototype one fitness function / import-rule check
- [ ] [[2026-04-16_tech-debt-agent|Tech debt agent]] — minimal patrol-and-report pass over one repo
- [ ] Read the 5 syntheses end-to-end; capture cross-cutting integration points (what's shared? what's the data flow?)
- [ ] Sketch each of the 4 remaining at minimum fidelity. Suggested order per plan note §"Next concrete steps": ~~metrics~~ → enforcement → dashboard wiring → debt → tooling.
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
- [[2026-04-23_sketch-findings-metrics]] — first sketch's findings (radon CC across vms-connector)

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
- [ ] **admin stale Batch 1** — Onboarding/wizard cluster (`admin#551, #488, #510, #446, #694`). Pattern-setting pass for remaining 4 batches. Entry: [[actuate_admin|repo-backlog/notes/concepts/actuate_admin]] §"Codebase-scan follow-up plan."

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

**Priority:** current
**Tickets:** pre-ticket (cross-repo R&D / process)
**Status:** Phase 1a complete; Phase 1b in progress (15/19 signals enabled)
**Post-mortem:** [[2026-04-23_postmortem-onboarder-healthcheck]]
**Full cross-repo design sketch:** [[2026-04-23_dashboard-sketch]] — load-bearing
**Surface (locked 2026-04-23):** local static HTML under `/home/mork/Documents/worklog/dashboard/`, generated by `/dashboard-check` skill, view via `file://` (or via Caddy at `http://mork-firebat/dashboard/`).
**Closed sub-items archive:** [[2026-04-23]] (Phase 1a complete), [[2026-04-24]] (Phase 1b 15-signal expansion + daily-scope integration)

### Scope (cross-repo, not just AutoPatrol)

In-scope components:

| Component | Silent-regression risk | Candidate signal(s) |
|---|---|---|
| `vms-connector` (fleet) | high | `patrol-exit emits/day`, OOMKills (new per-container chronic pattern), `streamId Guid` rejection count, CNCTNFAIL rate per site |
| `actuate-libraries` (pullers / pipeline / daos / etc.) | medium | version drift alerts; consumer-side import check |
| `actuate-inference-api` | high | per-model detection throughput, 4xx/5xx rates, per-partner-API-key activity |
| `actuate_admin` (Django + RBAC) | medium | schedule-activation rate, tenant-create success, RBAC denial patterns |
| `autopatrol_onboarder` (3 Lambdas) | HIGH | per the [[2026-04-23_alarm-dashboard-sketch]] (onboarder liveness + cleanup + reenable) |
| `autopatrol-server` | medium | patrol-completion rate, CNCTNFAIL per site |
| `camera-ui` + `alert-ui` | low-medium | error rate from browser telemetry |
| Alert-delivery pipeline (`queue-*`, `smtp-frame-receiver`, `clips-smtp-worker`) | HIGH | queue depth, per-integration delivery rate |

### Principles (design-for-monitoring — echoed in fleet-arch + software-arch + engineering-process)

1. **Behavioral signals, not surface metrics.** `Errors=0`, `Invocations>0`, `200 OK` are not health signals. Activity-marker log lines + downstream side effects are.
2. **1–2 signals per component, reviewable in <60 seconds total.** Dashboard is for quick scan; drill-down is on-demand.
3. **Monitoring-friendliness is a first-class design dimension.** Every fleet-architecture proposal and every software-architecture sketch must answer "how do I know this is working?" before it's signed off.
4. **Every repo owns its signals.** Per-repo `CLAUDE.md` carries the acceptance-criteria + signal-set definition. When a new feature ships, its signals must be added before merge.
5. **Cross-repo aggregator is the daily-check surface.** `/dashboard-check` queries each per-repo signal set and renders one consolidated view.

### Phase 1b — open deliverables (continuation note: [[2026-04-24_dashboard-1b-continuation]])

- [ ] **Replay tests for 7 historical incidents** — highest-value; locks in the "would have caught" promises
- [ ] **Regression rules 3 + 4** (baseline_drift 2σ, chronic_offender_promotion) — unlocks "signal is drifting" detection vs. just static thresholds
- [ ] **Morning-summary aggregation** from sink (source_skill != dashboard-check) — surfaces cross-skill observations in the grid
- [ ] **Sparklines tier 1** — inline SVG per-signal, 24h window; sink has 227+ rows, ready to draw
- [ ] **Hero carousel** (3 cards: heat-grid / top regressions / recent gates)
- [ ] **Compact grid + inline expand** (drop description column, <details>/<summary> drawer)
- [ ] **Data hooks** — rich data.json, sink.query() helper, embedded query snippets, kb_link field
- [ ] **Catalog coverage enrichment** — actuate-admin, inference-api per-model, autopatrol-server, actuate-libraries, config-drift signals
- [ ] **Baseline recalibration pass** — after ~1 week of sink accumulation (target 2026-05-01+)
- [ ] **NEW (2026-04-23): Config-drift signals from OOM surge triage.** (a) `connector_pods_under_1gb_limit`; (b) `connector_pod_headroom_over_70pct`; (c) `vpa_updatemode_drift`; (d) (future) `s3_lifecycle_rules_disabled`. See [[2026-04-23_oom-surge-connector-limit-drift]].

### Phase 2+

- [ ] **Per-repo CLAUDE.md extension** — add "Release Acceptance Criteria" section to `vms-connector`, `actuate-inference-api`, `actuate_admin`, `actuate-libraries`, `autopatrol-server`, `camera-ui`, `alert-ui`. Canonical template: `/home/mork/work/autopatrol_onboarder/CLAUDE.md`.
- [ ] **Launch-gate wiring** — integrate into `/stage-release`, `/post-deploy-monitor`, `/validate-release`. Each release skill ends by running `/dashboard-check --gate <commit>` and BLOCKING declaration of success until green or timeout.
- [ ] **Retrofit existing check skills** — `/autopatrol-overnight-check` + `/autopatrol-cleanup-lambda-check` write sink observations
- [ ] **Rolling-window baseline calibration** — replaces static baselines once 14d of sink data
- [ ] **Cross-time anomaly detection** — "same finding N days running → promote to tracked signal"
- [ ] **Coverage expansion** — actuate-admin, actuate-libraries, autopatrol-server, camera-ui, alert-ui full signal sets
- [ ] **Phase 2 additional metrics** — SSL cert expiry, CI failure rates, NR synthetic monitors, GuardDuty, Dependabot, RDS, stale-branch
- [ ] **Slack posting on RED** — optional, to `#autopatrol-sync` or dedicated channel
- [ ] **NR instrumentation of AutoPatrol Lambdas** — unblocks APM golden metrics for autopatrol specifically
- [ ] **Prior-art follow-ups** — DDB counter retry-idempotency bug (from post-mortem); audit other Actuate Lambdas for silent-early-return patterns

### Cross-topic integration

- **`engineering-process`** — release-acceptance-criteria rule ([[2026-04-23_release-acceptance-criteria]]) filed here. Release-related notes treat "post-deploy verification against acceptance criteria" as mandatory.
- **`fleet-architecture`** — every proposal (A, B, C, D, E) must include a "monitoring & alarms" subsection.
- **`software-architecture`** — sketches must demonstrate monitoring hooks from the start. Code-health vs operational-health dashboards are kept distinct with cross-link.

### Phasing (proposed)

- ~~**Phase 0:** signal inventory~~ — complete
- ~~**Phase 1a:** build `/dashboard-check` skill, end-to-end smoke~~ — shipped 2026-04-23
- **Phase 1b (in progress):** signal-set expansion + replay tests + advanced regression rules — 15/19 signals enabled
- **Phase 2:** extend CLAUDE.md rules to every in-scope repo; add acceptance-criteria enforcement to `/stage-release` + `/post-deploy-monitor`.
- **Phase 3:** build the dashboard UI (CW or NR) for non-skill-based review; instrument missing NR wiring.
- **Phase 4 (ongoing):** negative feedback loop — any incident that surfaces a missing signal triggers a signal-set update.

### Related

- [[2026-04-23_postmortem-onboarder-healthcheck]] — the trigger
- [[2026-04-23_alarm-dashboard-sketch]] — AutoPatrol-scoped precursor (generalized here; old §9 archived [[2026-04-23]])
- [[2026-04-23_release-acceptance-criteria]] — the global rule this workstream operationalizes
- [[2026-04-24_dashboard-1b-continuation]] — pickup doc
- [[feedback_fail_fast_guards]] — hard rule surfaced by the incident
- [[feedback_acceptance_criteria_every_merge]] — hard rule surfaced by the incident
- [[skill-autopatrol-cleanup-lambda-check]] / [[skill-autopatrol-overnight-check]] — per-repo check-skill pattern
- [[2026-04-14_connector-fleet-monitoring]] — existing fleet-monitoring synthesis (partial overlap)
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

- [openclaw-claude-code](https://github.com/Enderfga/openclaw-claude-code) — programmable bridge turning coding CLIs into headless agentic engines.

### Design surface (open questions)

- [ ] **Which KB tasks are offload candidates?** — inventory current KB skills (`/kb-ingest`, `/kb-synthesise`, `/kb-auto`, `/repo-scan`, `/kb-sync`) and classify by Claude-dependency
- [ ] **Which models to route to?** — Gemini 3.x Pro (long context, cheap), Codex (code-context), self-hosted (privacy)
- [ ] **Integration surface** — new subagent type that routes to non-Claude model? Or a `kb-delegate` skill that spawns an external process? Or adopt openclaw wholesale?
- [ ] **Prompt caching strategy** — Anthropic prompt cache has 5-min TTL; trade-offs for offload
- [ ] **Output contract** — offloaded agents must return KB-shaped notes (frontmatter, wikilinks)
- [ ] **Observability** — if Gemini hallucinates a summary, how do we catch it?
- [ ] **Cost model** — map current KB ops to token cost baseline, then project savings at N% offload

### Pre-plan subtasks

- [ ] ADR on routing policy once options are clear
- [ ] Pilot: offload one `/kb-ingest` run to Gemini end-to-end; compare output quality against a Claude-ingested baseline
- [ ] Decision point: adopt openclaw, build custom, or hybrid

### Relevant KB

- [[2026-04-20_multi-agent-model-routing]] — seed synthesis (closed [[2026-04-20]])
- [[agents-catalog]] — current subagent surface (all Claude-backed)
- [[engineering-process/_summary|engineering-process topic]] — likely home for the synthesis note
- Session budget guardrails in global CLAUDE.md (KB / R&D soft-cap at ~80%)

### Related

- §7 issue hygiene — similar "delegate the grunt work" motivation; findings here may inform [[agent-issue-auditor]]

---

## 10. Laptop-config portability + disaster recovery

**Priority:** high (laptop-loss / reboot risk is always non-zero)
**Tickets:** *(pre-ticket — personal infra)*
**Status:** scoping
**Trigger:** 2026-04-23 user directive: *"I do not want to lose this monitoring setup, the rules, skills, and other configurations for all of this if I need to do a reboot or get a new computer."*

### Goal

A one-command bootstrap that reconstitutes this laptop's Actuate-related configuration on a fresh machine (or after a wipe). Covers: Claude Code skills + agents + hooks + global rules + per-project memories, systemd user services, the KB itself, the dashboard output layout, secrets-refresh runbook for things that can't be stored.

### Inventory — what needs to survive

**Claude Code config** (`~/.claude/`):
- `CLAUDE.md` — global rules
- `skills/<name>/` — all custom skills
- `agents/<name>.md` — custom subagents
- `hooks/` — session-start + stop hooks
- `lib/` — shared libraries (`nr_query.py`, `atlassian_query.py`)
- `plans/<slug>.md` — approved plan files
- `projects/<project>/memory/` — per-project memory

**systemd --user services** (`~/.config/systemd/user/`):
- `dashboard-server.service`
- `jira-sync.service` + `.timer`
- `overnight-check.service` + `.timer`

**Knowledge base** (`~/Documents/worklog/knowledgebase/`):
- The Obsidian vault, version-controlled separately

**Dashboard data** (`~/Documents/worklog/dashboard/`):
- `sink/observations.jsonl` — operational-event sink
- Per-day snapshot dirs

**Cloned repos** (`/home/mork/work/`):
- `vms-connector`, `actuate-libraries`, `actuate-inference-api`, `actuate_admin`, `autopatrol_onboarder`, `autopatrol-server`, `camera-ui`, `software-arch-sketches`, `ds-terraform-eks-v2`, `local_network_scripts`

**System deps** (package-managed):
- `python3.12-venv`, `uv`, `gh`, `aws-cli`, `jq`, `curl`, `git`, `nodejs`

**Secrets / tokens (CANNOT store; runbook-only):**
- AWS SSO, CodeArtifact, GitHub, Anthropic API key, NR API key, Atlassian API token, Slack webhooks

### Approach options

1. **Dotfiles repo with `chezmoi`** — purpose-built (handles templates, secret-exclude, post-apply hooks)
2. **Dotfiles repo with GNU `stow`** — simpler, symlink-based
3. **Plain git repo + bootstrap script** — one repo at `~/.dotfiles/` + `bootstrap.sh`. Cheapest to build.
4. **Nix home-manager** — gold-standard reproducibility but huge learning curve

Likely: **option 3** for v1, upgrade to chezmoi only if v1 friction shows up.

### What's left

- [ ] **Design phase:** pick approach (1 / 2 / 3 / 4) + decide what goes in the repo vs excluded vs runbook
- [ ] **Inventory pass:** enumerate every file/dir to track
- [ ] **Build `bootstrap.sh`** — fresh-machine setup
- [ ] **Backup story:** how the dotfiles repo gets pushed to a durable remote
- [ ] **KB as separate git repo:** verify already tracked; if not, git-init + remote
- [ ] **Dashboard sink retention:** decide whether sink rides in KB repo or separate
- [ ] **Secrets-refresh runbook** — `topics/engineering-process/notes/concepts/laptop-secrets-refresh.md`
- [ ] **Disaster-recovery test** — on a throwaway VM
- [ ] **Ongoing discipline:** every new skill/agent/hook/service is verified tracked; fold into post-push audit

### Relevant KB

- [[engineering-process/_summary|engineering-process]] — likely home for the secrets-refresh runbook
- [[core-repo-suite]] — repo clone list partially maintained there
- [[agents-catalog]] — subagent inventory

### Related

- §9 Operational Dashboard — the initiative that surfaced "I shouldn't lose this"
- §13 (archived [[2026-04-27]]) — secrets-refresh runbook example via NR/Atlassian REST wrappers
- [[skill-daily-scope]] — morning routine depends on the whole config being intact

---

## 11. Firebat minipc — follow-ups from "always-on Claude dev box" setup (2026-04-23)

**Priority:** medium (core setup complete and verified; these are enhancements, not blockers)
**Tickets:** *(personal infra — no ticket)*
**Status:** scoping
**Scripts:** `/home/mork/work/local_network_scripts/` (12-phase toolkit, reusable for future boxes via `TARGET=user@host` env var)
**Context:** [[2026-04-23_firebat-minipc-as-claude-dev-box]] · [[2026-04-23_firebat-minipc-network-setup]]
**Access:** `ssh mork@mork-firebat` (Tailscale) or `ssh mork@fe80::8647:9ff:fe34:b4f2%enp0s31f6` (direct cable fallback)

### 11a. Wire a specific scheduled Claude job

The `~/bin/claude-run-skill.sh` wrapper on the minipc is the scaffold. Smoke-test on 2026-04-23 proved end-to-end. Next:

- [ ] Decide which skill(s) get a cron slot. Candidates: `/overnight-check`, `/kb-auto`, `/dashboard-check`.
- [ ] Build systemd user `.service` + `.timer` pair at `~/.config/systemd/user/<name>.{service,timer}` on the minipc.
- [ ] `systemctl --user enable --now <name>.timer` — linger is already on (phase-02), so timers run without a login session.
- [ ] Verify first firing.
- [ ] Add to KB so we don't forget what's scheduled where: extend [[automation-overnight-check]] or new entity note `automation-minipc-timers`.

### 11b. Laptop-side dashboard sync → minipc (or run /dashboard-check on minipc)

> **Status (2026-04-24):** §12e shipped a minipc-side daily `/dashboard-check` cron. Most of this § subsumed; revisit only for the laptop-asleep continuous-poll case.

### 11c. Auto-start Claude Code inside the persistent tmux session

Goal: on attach, land directly in a ready `claude` session (or at least verify one is running). Two implementation options:

- **A. Modify the systemd ExecStart** — `tmux new-session -d -s main -c %h "claude"`. Pro: one-line change, auto-starts at boot. Con: if `claude` exits, the tmux window closes.
- **B. A watchdog timer** that checks for a claude process in the `main` session and spawns one if missing. Pro: self-heals on claude exit. Con: more moving parts.

- [ ] Pick A or B (or a variant). B is more resilient; A is pragmatic for MVP.
- [ ] Implement as a patch to `files/claude-session.service` and/or a new `files/claude-watchdog.{service,timer}` in `~/work/local_network_scripts/`.
- [ ] Update `phase-10-sessions.sh` to push whichever variant is picked.
- [ ] Verify: reboot minipc, wait 90s, `ssh -t mork@mork-firebat tmux attach -t main` lands in a live claude prompt.

**Seeded 2026-04-23.** *(2026-04-27: still down per morning probe.)*

### 11d. Push-based dashboard ingest on minipc (seeded 2026-04-24)

> **Status (2026-04-24):** re-scope needed. §12e shipped minipc-side daily `/dashboard-check`; minipc is already the primary host. Open question: does laptop need to push ALSO, or is minipc's own daily run sufficient? Revisit once §12i closes.

- [ ] **API design on minipc** — extend the minipc dashboard app (§12) with `POST /api/dashboard/snapshot`, `POST /api/dashboard/sink`, `GET /api/dashboard/latest`. Auth: Tailscale-mesh only.
- [ ] **Laptop-side push hook** — after each `/dashboard-check` run, POST to minipc.
- [ ] **Store-and-forward on push failure** — outbox queue at `~/Documents/worklog/dashboard/.outbox/` with retry.
- [ ] **Caddy routing** — `http://actuate-dev.local/dashboard/` serves latest snapshot regardless of source host.
- [ ] **KB writeup** — synthesis note `topics/operational-health/notes/syntheses/<date>_dashboard-push-arch.md`.

### 11e. Cronify-friendly refactor of `/dashboard-check` (seeded 2026-04-24)

> **Status (2026-04-24):** partially overtaken by §12e + §12i. Most of this § is subsumed — keep as design sketch; delete or collapse once §12i closes.

- [ ] **Factor out collector logic** — `~/.claude/skills/dashboard-check/collect.sh` per source type
- [ ] **NR REST wrapper** — *(2026-04-27 update: shipped as `~/.claude/lib/nr_query.py` via §13. Reuse from there.)*
- [ ] **`run-headless.sh`** wrapper — `collect.sh → render.py → push.sh`
- [ ] **systemd timer** — every 15–30 min on the minipc (and laptop as belt-and-braces)
- [ ] **Claude invocation path still works** — interactive `/dashboard-check` stays as-is
- [ ] **Verification** — after a week of cron running, sink gains ~100+ rows/day organically

### Related

- §9 Operational Dashboard — source of the dashboard artifact
- §10 Laptop-config portability — sibling workstream on the laptop side
- §12 Minipc dashboard app — the target for §11d's push API
- §13 (archived [[2026-04-27]]) — REST wrappers reusable here
- Scripts + README: `/home/mork/work/local_network_scripts/README.md`
- Memory pointer: `~/.claude/projects/-home-mork-work-local-network-scripts/memory/firebat-minipc-access.md` (creds + URLs)

---

## 12. Minipc dashboard app — interactive KB browser + query + quick surfaces

**Priority:** high (active build)
**Tickets:** ENG-179 (R&D — newly visible 2026-04-27 in Jira queue; overlap with §11/§12 to be reconciled)
**Status:** Phases 1 + 2 SHIPPED 2026-04-24; Phase 14 static-gen refactor SHIPPED 2026-04-24; phases 12c–12i in flight
**Trigger:** 2026-04-24 user ask — extend the static status dashboard with dynamic pages.
**Closed sub-items archive:** [[2026-04-24]] (Phase 1 KB browser, Phase 2 daily-note + Jira mirror, Phase 14 static-gen refactor end-to-end)
**Access:** `http://mork-firebat/app/*` (LAN + Tailscale only; no auth for MVP)

### Architecture (post-Phase-14)

- **11ty** generates `/app/*` static pages from task artifacts (5-min rebuild timer)
- **Quartz** generates `/app/kb/*` from `~/Documents/worklog/work/knowledgebase/topics/` (5-min rebuild timer)
- **Trimmed FastAPI** at `/app/api/*` (kb_query, metrics_api, healthz only)
- **Caddy** ordered most-specific first: kb/query → kb/* → api/* → */ → fallback
- **Source** lives in `/home/mork/work/local_network_scripts/minipc-app/` + `minipc-blog/` + `minipc-quartz/` on laptop (versioned with toolkit) and rsync'd to minipc by `phase-12-app.sh`

### Open phases (12c–12j)

- [ ] **§12i — Strip LLM narrative pass from minipc `/dashboard-check` cron** — run `dashboard-check.py` modules directly instead of via `claude -p`. NR-REST wrapper already exists (§13's `~/.claude/lib/nr_query.py`). Goal: $0/run, no Claude budget, predictable runtime. Deliverables: `collect-headless.sh` invoking each signal's NRQL via the wrapper, `render.py` reading those JSON outputs, replace `run-dashboard-check.service`'s `claude -p` invocation with the headless path. Closes (subsumes) §11e.
- [ ] **§12i.b — Port `/kb-recap` to script** — already drafted as `local_network_scripts/files/kb-recap.sh`. Deploy to minipc, wire into `prebuild.js`, cron the rebuild, delete superseded `run-kb-recap.{service,timer}`.
- [ ] **§12j follow-ups (queued for ~2026-05-06+)** — see [[2026-04-29_repos-dashboard-followups]]. Highest-leverage items: per-repo deltas vs prior week (needs 7d sink history), drilldown detail pages, FACET-classify behavior in render.py, vms-connector's 229 stale branches and actuate-inference-api's 724-day-old open PR (real-world findings surfaced by the new signals).

### Related

- §11 (provisioning), §9 (operational dashboard, shares palette + theming)
- [[2026-04-24_minipc-dashboard-static-gen-refactor]] — full architecture + gotchas + cookbook
- [[skill-kb-recap]] — script port

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

- [ ] **Step 1 — Infra quick-win** — apply `scalerReplicasArmDown: 20` in `kubernetes-deployments` cluster-values.yaml (us-west-2 + eu-west-1 if relevant). Reduces midnight congestion immediately. Single PR, ~15 min.
- [ ] **Step 2 — Code fix Option A** — in `actuate_admin/schedule_deployer.py:347-399`, branch on `is_override && is_running` to invoke the start action directly. Add unit + integration tests covering: (a) override starting at midnight today; (b) override starting at midnight tomorrow (should NOT immediately fire); (c) override mid-day start; (d) override end. Verify against the reproduction case (connector-16031 / schedule 197068) on stage.
- [ ] **Step 3 — Verification on prod** — after Step 2 ships, monitor the next 7 days of override-start events for any miss-on-day-1 reports.
- [ ] **Step 4 (deferred)** — evaluate Option D (separate association names) as a longer-term cleanup.

### Related

- [actuate_admin#2310](https://github.com/aegissystems/actuate_admin/issues/2310) — source issue with full timeline + 4 detailed comments
- §3 — AutoPatrol cleanup Lambda (sibling AP work, different domain)
- §9 dashboard signal candidates: `override_start_to_arm_latency_seconds` p95, `override_arm_miss_rate`
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

- [ ] **AVI/Xvid masquerading as `.mp4`** — `queue_consumer/consumers/shared/utils.py:186-187` swaps `.mp4`→`.avi` before invoking `ffmpeg ... -vcodec libxvid`, so the bytes wrapped in MIME as `application/mp4`-named-attachment are actually AVI/Xvid. Either Immix has been silently accepting this for years, or the codec is wrong and we just haven't caught it. Action: confirm with Immix what's actually expected, then either rename the attachment or fix the codec/container. Details: [[immix-mp4-mux-downstream]].
- [ ] **EU prod missing `prod-queue-immix-consumer` ECS autoscaling** — SQS queue `event_queue_immix_alarm.fifo` is provisioned in eu-west-1 but **no matching ECS autoscaling block** found in `ds-terraform-eks-v2/stages/prod/eu-west-1/`. Either EU Immix MP4 mode isn't actually consumed, or the consumer runs from the US region's ECS service against the EU queue, or it's deployed via a different mechanism. Action: verify whether EU FIFO has an active consumer.

### 15c. Migration / refactor workstreams

- [ ] **Hikcentral split-brain decode migration** — `connector_factories/hikcentral/factory.py` routes the **non-motion path to PyAV `AvUrlFramePuller`** but the **motion-gated path to legacy OpenCV `OnOffMotionBasedUrlFramePuller`**. Real-traffic VMS, complicates hwaccel rollout, breaks PTS semantics consistency. Migrate the motion-gated branch to a PyAV-based motion variant. Details: [[connector-decoder-routing-map]].
- [ ] **PyAV migration completion (general)** — most production integrations are now on `AvUrlFramePuller`, but the legacy `UrlFramePuller` (OpenCV) class still parents motion-gated variants and a handful of integration paths. This is a pre-req for [[2026-04-16_proposal-c-camera-worker|fleet-architecture proposal C]]. Scope and sequence the remaining moves; remove the legacy class once empty.
- [ ] **KVS pipeline JPEG round-trip elimination** — `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-156, 104-128` decodes MKV → JPEG-encodes via `jpegenc` inside GStreamer → JPEG-decodes via `cv2.imdecode` in Python. Two unnecessary codec ops per frame. Options: (a) move to PyAV-on-MKV like the RTSP path; (b) drop `jpegenc` and use `appsink` with raw frames + GstSample → numpy. Details: [[gstreamer-vs-ffmpeg]] + [[aws-kvs-entity]].

### 15d. Discovery / verification (small data-gathering tasks)

- [ ] **EKS prod node-pool GPU verification** — confirm whether prod connector cluster has any G-class node groups today, or if we're CPU-only. Karpenter NodePool config + connector pod placement constraints. Details: [[eks-prod-node-pool-gpu-availability]].
- [ ] **Connector Dockerfile coverage spot-check on prod** — `gnutls` audit landed [[connector-docker-system-deps]]; one more pass after the `--enable-gnutls` fix to confirm no other surprise omissions in the GPU images.

### Related

- Topic landing: [[video-processing/_summary]]
- Cross-cuts to §5 fleet-architecture (decode-locality, GPU substrate, KVS WebRTC, frame-transport payload formats)
- Bridge syntheses: [[decode-locality-per-proposal]], [[gpu-substrate-and-fleet-placement]], [[kvs-webrtc-as-fleet-frame-plane]], [[frame-transport-payload-formats]]
- Investigation notes: [[gst-rtsp-h264-only-audit]], [[immix-mp4-mux-downstream]], [[connector-decoder-routing-map]], [[connector-docker-system-deps]], [[eks-prod-node-pool-gpu-availability]]

---

## 16. Tenant-status sync gap — cascade-disable suspended tenants from cleanup Lambda

**Priority:** medium-high (real customer-affecting gap; 2 tenants currently suspended in prod with their sites still active in our admin DB)
**Status:** investigated 2026-04-28 (probe + decision); awaiting implementation
**Source:** customer/Immix-side report → live probe against Immix prod → architectural decision to piggyback on cleanup Lambda
**KB writeup:** [[2026-04-28_tenant-status-sync-gap]]

### Background

Sites under tenants that go SUSPENDED on the Immix side stay marked active in our admin DB. The onboarder's `auto_patrol/sync/` POST never carries tenant-status, and there's no reconciliation pass anywhere in the stack. The probe confirmed:

- No `/Tenants/{id}` or `/Tenants` endpoint exists on Immix (404)
- BUT `tenantStatus` is already in every `get_contracts()` response (alongside `contractStatus`)
- 18 prod contracts as of 2026-04-28 — **2 tenants Suspended/Suspended**: `Remote Security Solutions` and `Legacy`. Server-side filter `?contractStatus=Suspended` works.
- Sites carry no per-site status field

### Decision: piggyback on the cleanup Lambda

Mark's call 2026-04-28 — add tenant check as the first step in cleanup-Lambda processing. Lazy / event-driven (only fires on `no_patrols` signals), reuses existing infrastructure, no new component. Does NOT need to live in the onboarder. Rationale + tradeoffs: [[2026-04-28_tenant-status-sync-gap]] § "Architectural answer".

### Subtasks

> Steps 1-3 (admin can support cascade-disable / build admin endpoint / cleanup Lambda code change) — closed 2026-04-28; full closure detail in [[2026-04-28]] § "§16 — Tenant-status sync gap".

- [ ] **Step 4 — Stage rollout + canary verification**. Use `Remote Security Solutions` and `Legacy` (both currently `Suspended/Suspended` in Immix prod, `tenantId` known) as canaries.

  **Sub-step 4a — admin staging verify (gated on actuate_admin PR #2376 merging to staging branch + staging.yml deploying to staging.actuateui.net):**
  ```bash
  # Get an admin staging token first:
  cd /home/mork/work/autopatrol_onboarder
  ./scripts/fetch_admin_token.sh staging  # or whatever stage-specific variant exists

  export ADMIN_API_TOKEN="<paste from script>"
  STAGING_URL="https://staging.actuateui.net"

  for entry in \
      "0ee7cb3f-4a3a-49b0-bcb5-73fce964b427:Remote Security Solutions" \
      "ac399cd6-2fdf-4659-b8e5-baea54075017:Legacy"; do
    tenant_id="${entry%%:*}"
    name="${entry#*:}"
    echo "=== ${name} (${tenant_id}) — DRY RUN ==="
    curl -sS -X PATCH \
      -H "Authorization: Bearer ${ADMIN_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"tenant_id\":\"${tenant_id}\",\"dry_run\":true,\"reason\":\"stage_verify\"}" \
      "${STAGING_URL}/api/auto_patrol/disable_tenant/" | python3 -m json.tool
  done
  ```
  Expected output: `schedules_affected` and `customers_affected` > 0 (the cascade scope), plus full lists of `schedule_ids`, `customer_ids`. **DB unchanged after dry-run** — verify by re-running the same probe after a few seconds; counts should be identical.

  **Sub-step 4b — stage → prod admin promotion** (PR from `staging` → `main` once 4a is clean): handled by actuate_admin's standard flow (`protect-main.yml` enforces source=staging).

  **Sub-step 4c — autopatrol_onboarder PR #10 un-DRAFT + merge** (gated on 4b — admin endpoint must be in prod). Merging auto-deploys cleanup Lambda to US + EU prod with `TENANT_CASCADE_ENABLED=false`.

  **Sub-step 4d — DRY_RUN canary on prod cleanup Lambda** (~1h post-deploy with flag still `false`):
  ```bash
  # Watch for "would PATCH auto_patrol/disable_tenant/" log lines on the 2 known tenants
  AWS_PROFILE=prod aws logs tail /aws/lambda/immix-autopatrol-schedule-cleanup \
    --region us-west-2 --since 1h --format short \
    | grep -E 'would PATCH auto_patrol/disable_tenant'
  ```
  Expected: log lines containing `tenant_id=0ee7cb3f-...` (Remote Security Solutions) and/or `tenant_id=ac399cd6-...` (Legacy), with `TENANT_CASCADE_ENABLED=False`. Confirms the suspended-tenants fetch + matching is correct without firing any real cascades.

  **Sub-step 4e — flip the flag**:
  ```bash
  AWS_PROFILE=prod aws lambda update-function-configuration \
    --function-name immix-autopatrol-schedule-cleanup --region us-west-2 \
    --environment "Variables={TENANT_CASCADE_ENABLED=true,...keep all others...}"
  ```
  (full env-var block from §5 of `/autopatrol-cleanup-lambda-check`). Watch the next 24h for `AutoPatrolTenantCascadeDisabled` NR events firing only on the 2 known tenants. After verify-clean: §16 closes.

- [ ] **Step 5 — Re-enable path**. When a tenant is unsuspended, mirror the existing schedule-side re-enable Function URL — needs a sibling tenant-cascade-reenable code path. Probably a small extension of the existing re-enable Lambda. Defer if rare in practice; track separately if needed.

- [ ] **Step 6 — Harden `disable_tenant` permission_classes** (post-#2377 follow-up). `api/serializers/integrations/autopatrol/autopatrol_view.py:86` currently inherits `CustomGenericViewSet`'s default auth (Social/Session/TokenStrict) but has **no explicit `permission_classes`** — unlike sibling `AutoPatrolContractView` / `AutoPatrolScheduleView` which set `[CheckModelPermission]`. Net effect: any authenticated user (incl. session-auth dashboard logins) can hit the PATCH and cascade-soft-delete a tenant. Intent is "admin-only via internal Lambda token", but that is **not what's enforced**. Same posture as already-merged `sync_site` on the same viewset, so no regression introduced — but worth tightening before more callers depend on it. Options: (a) explicit `permission_classes = [CheckModelPermission]` matching siblings; (b) dedicated `IsLambdaServiceAccount` permission class keyed on the cleanup Lambda's IAM-signed token; (c) IAM-signed Function URL pattern (mirrors the existing reenable Lambda). Surfaced 2026-04-29 in PR #2377 review (see [[2026-04-29_cleanup-handoff]] §"Disable-by-tenant rollout"). Also tighten the `request.data` echo in the validation-error log path (`autopatrol_view.py:108-112`) per security-hardening-checklist §Error Response Standards. Add `ENDPOINT_ROLE_MAPPING` entry for discoverability.

### Verification artifacts

- Probe script: `autopatrol_onboarder/scripts/probe/tenant_status_probe.py` — re-runnable to monitor suspended-tenant population over time
- 7-day monitoring: count of `TenantCascadeDisabled` NR events; expect a small startup spike (the 2 currently-suspended tenants) then near-zero
- Alarm: cascade rate > 5/h sustained = something's wrong (mass suspension event OR false-positive bug)

### Related

- §3 — cleanup Lambda workstream (parent — this is a cleanup-Lambda enhancement)
- [[2026-04-28_tenant-status-sync-gap]] — full investigation writeup
- [[2026-04-17_stale-schedule-cleanup-design]] — original cleanup Lambda design
- [[autopatrol-cleanup-lambda]] — entity
- [[autopatrol-onboarder]] — entity (NOT being modified — explanation of why in the KB note)

---

## 17. VCH connector emits `no_patrols` for genuinely-Active schedules

**Priority:** low (cleanup Lambda anomaly-reset correctly refuses to disable; cost is just wasted invocations)
**Status:** identified 2026-04-28 via flapper investigation during §16 work
**Source:** [[2026-04-28_tenant-status-sync-gap]] flapper probe → `autopatrol_onboarder/scripts/probe/flapper_schedule_probe.py`

### Finding

3 of 4 chronic anomaly-reset flappers (per the cleanup Lambda's 7-day repeat-offender map) are VCH-integration schedules in genuinely Active state on Immix:

| schedule_id | title | integration | tenant_id |
|---|---|---|---|
| `c3808175-85e0-...` | VCH 11-4 | vch | 47dc2c1f (Vendor.Actuate.Prod, Active/Active) |
| `fbdfdba6-f62c-...` | VCH 9-17 | vch | 47dc2c1f (same) |
| `ee1822f1-67c8-...` | VCH Test 2 | vch | 47dc2c1f (same) |

All 3 return `scheduleStatus=Active` from Immix's `/Schedules/{id}`. Their tenant + contract are both Active. Yet the connector emits `no_patrols` for them on every cadence. Cleanup Lambda's anomaly-reset correctly refuses to disable (Immix says Active → not a cleanup candidate). Each contributes ~9 anomaly resets/week.

### Why this matters

- Wasted cleanup Lambda invocations and DDB writes
- Noise in the anomaly-reset 7-day map → harder to spot real anomalies
- Potential signal that VCH integration has a different patrol-detection model than AutoPatrol and the connector's `emit_no_patrols_signal` heuristic doesn't account for it

### Hypotheses to investigate

1. **VCH schedules don't use `/Patrols/` the same way AutoPatrol does.** VCH may have its own polling endpoint; connector's "no patrols → emit cleanup signal" check may be evaluating against the wrong endpoint or returning empty for VCH by design.
2. **Vendor.Actuate.Prod is a test/vendor tenant.** Maybe these VCH schedules are intentionally in a "configured but never run" state for test purposes — in which case they shouldn't be emitting cleanup signals at all.
3. **The connector's VCH integration code path may need a separate `emit_no_patrols_signal` decision (or an explicit skip).**

### Subtasks

> Code-locate / scope-confirm / fix-landed — closed 2026-04-28; full closure detail in [[2026-04-28]] § "§17 — VCH connector emits no_patrols". Net impact ~92% reduction in cleanup-pipeline traffic with zero loss of real-disable signal. Open items below are post-merge soak.

- [ ] **Post-merge stage verify**: after `#1662` merges to `stage`, watch staging connector logs for any new VCH error patterns; cleanup-Lambda's stage-side `integration=vch reason=no_patrols` event count should drop to zero within 24h.
- [ ] **7-day stage soak**: confirm the 3 chronic flapper schedule_ids (`c3808175`, `fbdfdba6`, `ee1822f1`) age out of the DDB and don't reappear.
- [ ] **stage → rearchitecture promotion**: cherry-pick or PR-merge to prod once stage soak is clean.

### Related

- §3 — cleanup Lambda workstream (parent observability surface for this pattern)
- §16 — tenant-status sync gap (where this was incidentally surfaced; tenant cascade does NOT fix this)
- [[2026-04-28_tenant-status-sync-gap]] — investigation note that surfaced the flapper class breakdown

---

## 18. Memory-limit drift — restore VPA floor + audit CRITICAL cohort

**Priority:** Medium-High (sustained-RED OOMKill on 2 consecutive days, customer-visible via dropped frames / restart loops)
**Status:** identified 2026-04-23 ([[2026-04-23_oom-surge-connector-limit-drift]]); promoted to its own workstream 2026-04-29 after connector-45999 sustained 96/24h two days running and connector-14170 returned to top of OOM list (13/24h today)
**Root cause:** Feb-9 commit `a5de5db` "remove vpa patch" removed the min-memory floor on VPA at pod creation. Subsequent commits (`9736971`, `4367a39`) restored a floor only for `Securitas Australia - Trial`. ~73 days of VPA learning-loop drift left **1,956 pods in the CRITICAL 384-426 MB tier** (~42% of the fleet under 1 GB).

### Today's evidence

- `fleet_new_oom_offender` 2026-04-29: connector-14170=13, clips-prod=6, create-detection-window=5, connector-39467=4, connector-44740=3, connector-38396=3, connector-39350=3, connector-33724=2 (top of fleet, sustained-RED)
- connector-45999: 96/24h sustained, 2 days running per yesterday's carry-over
- Per-incident proven-fix on connector-20628 (2026-04-23): bump 384 MB → 1.6 GB stopped OOMs immediately; working set was genuine 950 MB

### Open work

- [ ] **Restore the VPA min-memory floor for everyone** in `connector_deployer/src/yaml/deployment.py` (or wherever the VPA patch lives). Strip the `lead == "Securitas Australia - Trial"` gate. Use the same 500 MiB + 150 MiB × camera-count formula already validated on that one lead, OR pick a more conservative floor.
- [ ] **Audit the 1,956-pod CRITICAL 384-426 MB tier.** Cross-reference with last-7d working-set peaks; bump every pod whose peak is within 70% of its limit to a safer ceiling (1.6 GB seems to be the validated number for connector pods).
- [ ] **Pickup connector-45999 specifically** as the immediate offender — bump its limit by hand if needed before the broader fix lands.
- [ ] **Verify the regression-prevention signal.** [[2026-04-23_release-acceptance-criteria]] §5 was supposed to catch config-surface drift; check whether there's a deploy-time guard that would have flagged the original Feb-9 commit.

### Acceptance criteria

- VPA floor PR merged + deployed; spot-check 5 random pods to confirm `limits.memory ≥ floor`
- 24h post-deploy: `fleet_oomkills_24h` baseline drops below 50/24h (current sustained ~100+) AND no NEW connectors enter top-15 of `fleet_new_oom_offender`
- 7d soak: no pod re-enters CRITICAL 384-426 MB tier without explicit reason

### Related

- [[2026-04-23_oom-surge-connector-limit-drift]] — load-bearing investigation note (root-cause analysis + Feb-9 commit trace)
- [[2026-04-23_release-acceptance-criteria]] — §5 config-drift class is what this regression illustrates
- Dashboard signals: `fleet_new_oom_offender`, `fleet_oomkills_24h` (already in `~/.claude/skills/dashboard-check/config/signals.json`)
- Repos: `connector_deployer` (VPA patch lives here per yesterday's KB note)

---

## Not-Yet-Prioritized (backlog)

Captured during active work but not yet scheduled. Not in Jira — promote to §N workstreams when they become active, or fold into related tickets. Each item has a source workstream reference. Closed items move to that day's daily note (see `_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md` for pre-cleanup history).

### R&D agent set — formalize post-pilot (2026-04-21)

- [ ] **Formalize `synthesizer` agent definition in `~/.claude/agents/`** — `research-prospector` and `source-reader` already formalized 2026-04-21 (see [[2026-04-21]]). `synthesizer` formalization deferred until that role is piloted on a real synthesis task. Opus-tier agent.
  **Model routing considerations:** prospector is the best candidate for Gemini/Haiku (token-heavy, judgment-light); synthesizer needs Opus; source-reader can be Sonnet-tier by default, Gemini-tier once routing is wired. See [[2026-04-20_multi-agent-model-routing]] + the kb-starter catch-up task below.

### Frame-storage research workstream — remaining (2026-04-21+)

- [ ] Source-reader batch on top ~9 reading-list entries (chunks 5/6/7, 3 subagents × 3 entries).
- [ ] Synthesizer pass producing "frame-storage design-delta per fleet proposal" — first test of the synthesizer role.
- [ ] Pull S3 Cost and Usage Report data to validate the "API calls dominate" hypothesis with real fleet numbers
- [ ] Scope `/create-video` lambda ownership — who owns it, what's the migration path
- [ ] Benchmark in-process H.264/H.265/AV1 encode on connector pods (CPU budget, latency for typical 10-frame window)
- [ ] **Downstream-consumer audit of single-frame contracts (cross-repo + lambdas + external) — BLOCKS the clip-based shift.** Every entry point and contract currently expecting per-frame storage must be catalogued before we commit the paradigm shift. Deliverable: `topics/fleet-architecture/notes/concepts/frame-storage-consumer-contracts.md`. Candidate agent: a new `consumer-audit` agent or multi-session invocations of existing agents scoped per-repo.
- **Research queued** (next prospector pass):
  - Chunk 8 in [[knowledgebase/topics/watchman/reading-list]] — S3 cost analysis
  - Chunk 9 in [[knowledgebase/topics/watchman/reading-list]] — In-cluster blob storage (MinIO, Ceph, Garage, SeaweedFS, emptyDir/tmpfs, local NVMe, Redis-streams)
- **Broken-source revisit queue** maintained in [[knowledgebase/topics/watchman/reading-list]] §"Broken-source revisit queue"

### KB tooling — cycleable open-questions UX (2026-04-21)

- [ ] **Surface + answer KB open questions in a cycleable, mobile-compatible way** — source-reader and prospector runs produce per-source "Open Questions" sections that accumulate across the KB. **Mobile-compatibility is a hard requirement** so the user can process on commute. Research options: (1) native Obsidian Bases, (2) Obsidian Tasks plugin, (3) simple aggregator note, (4) custom plugin. First step: evaluate Bases. Convention needed: standardize on `open_questions:` frontmatter list or `## Open Questions` heading with `- [ ] question` checkbox syntax.

### KB tooling — catch up with upstream kb-starter (2026-04-21)

- [ ] **Review sbuffkin/kb-starter upstream updates and fold back into our KB skills** — we only pulled the initial-commit baseline; the repo has had major enhancements since. Specifically check for: Gemini/Codex/multi-model routing, session-inbox messaging, two-phase plan→execute, consensus voting, worktree-isolated parallel agents, prompt-cache-aware session stickiness.

### From §3 (AutoPatrol stale-schedule cleanup) — 2026-04-17 planning

Follow-ups spun out of the cleanup-Lambda PRs that aren't blocking the first ship, but will need attention before or shortly after prod rollout:

- [ ] **DDB module: per-table TTL support** in `ds-terraform-eks-v2`. Until it does, `autopatrol_cleanup_counters` counters don't self-expire.
- [ ] **Prod terraform for cleanup + reenable Lambdas** — `stages/prod/us-west-2/lambdas/` uses `lambdas` module (map pattern); needs investigation of how the onboarder Lambda is currently deployed to prod before mirroring.
- [ ] **Tighten IAM on cleanup + reenable Lambda roles** — first-cut used broad AWS-managed policies for parity. After ship, scope down to specific resources.
- [ ] **Function URL + AWS_IAM authorizer for reenable Lambda** — plan §5 expects an IAM-auth'd Function URL.
- [ ] **Reserved concurrency = 2 on cleanup Lambda** — runaway-disable guard.
- [ ] **CloudWatch alarm: DLQ depth > 0 pages oncall** — per plan §7 failsafes.
- [ ] **Admin UI page: "Re-enable cleanup-disabled schedules"** — list filtered by `disabled_by=cleanup_lambda&is_deleted=true`. Decide before Week 3 of rollout.
- [ ] **`connector_version` env var** — `cleanup_emitter.py` reads `CONNECTOR_VERSION` for the SQS payload. Defaults to `"unknown"` today.
- [ ] **Slack webhook config** — wire `SLACK_WEBHOOK_URL` from Secrets Manager via env var in terraform.
- [ ] **NR instrumentation for onboarder + cleanup + reenable** — code-side done; terraform layer attachment still pending.
- [ ] **Admin API call path for resolving Immix schedule_id → admin PK** — confirm filter path + cache mapping in DDB row after first lookup.

### From fan-out findings (2026-04-22)

Items surfaced during the 2026-04-22 morning fan-out that don't map to an active workstream yet.

- [ ] **§3 IaC drift: port CLI-provisioned infra into terraform** — meta-item tying together several §3 items above. Real resources live in prod/us-west-2, CLI-provisioned 2026-04-20: 4 SQS queues, 1 DDB counter table, 2 Lambdas, 2 IAM roles, 2 DLQ alarms, 1 Function URL. See [PR #69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) body. Substantial PR; not blocking functionality but IaC drift will compound.
- [ ] **§3 Step D merge-legitimacy confirmation** — `autopatrol_onboarder#3` merged 2026-04-21T16:20Z despite title "STAGE BAKE ONLY — DO NOT MERGE YET" and `CHANGES_REQUESTED` review. Was this intentional or accidental?
- [ ] **§3 §2b-style closeout for fan-out discoveries** — two one-liner KB edits worth batching: (a) clarify that emit comes from `connector-{site_id}-vch-{n}-chm-cronjob` containers, NOT the main vms-connector pod; (b) cross-link `2026-04-20_lambda-creation-and-tuning-playbook.md` into §3's Related block.
- [ ] **Fan-out findings → auto-KB-update automation** — when a morning fan-out surfaces an architectural fact that clarifies an existing synthesis, the update should happen automatically. Design direction: post-fan-out step in `/daily-scope` that diffs against referenced KB notes, offers to append a clarification line. Can piggyback on `kb-scribe` agent.
- [ ] **OOMKill fleet sizing audit** — fan-out revealed chronic fleet-wide OOMKills. Lead offenders: `connector-14170` (32/day, chronic), `connector-23730` (18), `connector-40693` (17). Verdict (nrql-investigator, 2026-04-22): chronic-camera-count-driven. Recommended: **memory limit +25-30% on the site(s) missing a memory-tier assignment**. Broader: audit fleet for sites whose camera count exceeds the threshold for the default memory tier.
- [ ] **`NoneType unpack` error 3x-up drill** — 5,174 events in last 12h vs 1,699 prior 12h (`cannot unpack non-iterable NoneType object`). One-shot investigation; schedule into a morning-followup.
- [ ] **Orphan-branch triage (3 lanes)** — `actuate-libraries@feature/autopatrol-puller-error-classification`, `autopatrol-server@fix/sqs-stuck-window-id-lookup`, `camera-ui @ main` with dirty `Login.tsx`.
- [ ] **§2d option-3 mitigation time-bound fallback** — Mark posted the nginx/apache fix recipe on [GH#1658](https://github.com/aegissystems/vms-connector/issues/1658) Sunday 21:50Z; Immix silent since. If no Immix engagement by **2026-04-28**, elevate option-3 from "backup" to "active scope."

### From synthesis-decision interview (2026-04-22)

- [ ] **`/create-video` Lambda retirement (post-PoC)** — surfaced in `2026-04-22_frame-storage-design-deltas.md` as the biggest cross-team implication of the in-cluster blob + conditional-promotion design. Once a proposal is picked, identify owner, draft stakeholder outreach, schedule migration/rewrite-vs-retire conversation.
- [ ] **AWS Cost Explorer integration for skills/checks (more uses)** — beyond `/cost-check` shipped 2026-04-22, integrate into `/autopatrol-cleanup-lambda-check` (DDB+SQS+Lambda cost trend), `/daily-scope` morning fan-out (weekly cost-drift exec item), `/overnight-logs` (unexpected overnight spikes).
- [ ] **Formal A-E re-score against evaluation rubric with frame-storage delta baked in** — Already landed 2026-04-22 (see [[2026-04-22]]); the open follow-up here is per-PoC criteria refinement based on real measurement.
- [ ] **`SlidingWindowStep.close_window` instrumentation — add `window_outcome` log line** — surfaced by 2026-04-22 NR query. Single structured INFO log line at `SlidingWindowStep.close_window` emitting `window_outcome=detection_positive|no_detection` + window_id + site_id + camera_id. ~5 LoC. Makes the non-eventful-ratio query a one-liner.

### From dashboard pull (2026-04-29)

- [ ] **`connector-11202` 26,838-error spike (24h)** — top of `fleet_error_top15` dashboard signal, ~70% of fleet error volume. Other co-top: `connector-deploy` (11,049), `connector-10770` (9,126), `connector-26864` (3,930). No prior context. First action: delegate to `nrql-investigator` agent — FACET errors by `level` + `error.message` for `container_name='connector-11202'` over 24h, then check the other top contributors. Look for tenant/cluster correlation. Surfaced 2026-04-29 alongside the no_patrols dashboard tuning ([[2026-04-29_cleanup-handoff]]).

- [ ] **`connector-14170` regressed from "correct sizing" exemplar to top OOM offender** — 2026-04-23 [[2026-04-23_oom-surge-connector-limit-drift]] cited it at 1.6 GB / 975 MB working-set as "what correct sizing looks like". 2026-04-29 dashboard shows it top of `fleet_new_oom_offender` at 13 OOMs/24h, two days running. Either VPA drifted its limit back down (Feb 9 floor-removal in `connector_deployer@a5de5db` still in effect), working set crept past 1.6 GB, or new traffic pattern. **Promotion-target decision: new §N workstream — Fleet memory-limit drift audit** (covers re-instating VPA floor, auditing the 1,956-pod <426 MB CRITICAL tier, phased limit raise). Adjacent existing issues that don't capture the floor-removal root cause: [connector_deployer#133](https://github.com/aegissystems/connector_deployer/issues/133), [vms-connector#1591](https://github.com/aegissystems/vms-connector/issues/1591). When workstream gets registered, post a cross-link comment on `connector_deployer#133` referencing the OOM-drift note + connector-14170 as a current symptom.

### From cascade rollout aftermath (2026-04-30)

- [ ] **Comprehensive Immix tenant-failure census + external-audience report** — expand [[2026-04-29_immix-zombie-tenants]] from 3 documented zombies + 2 §16 canaries into a complete catalog of every tenant_id surfacing in connector / onboarder failure logs, classified by response type. Audience: Immix engineering. Steps: (a) Scrape the full tenant_id population in `/aws/lambda/immix-autopatrol-onboarding` failure log lines over 7 days, US + EU. Use the same regex from 2026-04-29 (`for tenant`, `tenant_id:`, `for {contract_id}`). (b) For each unique tenant_id, classify what kind of failure it produces (sites empty body, contract 400, sites 400 vs 401, contract 5xx, network timeout, etc.) and enrich with: admin-DB customer/schedule counts (US prod = `admin.actuateui.net`, EU prod = `admin.actuateui.eu`) and Immix `/Contracts` lookup (does it appear at all? what tenantStatus/contractStatus?). (c) Cross-tab table: tenant_id × failure mode × Immix response × admin DB scope × (covered or not by §16 cascade). (d) Generate `topics/autopatrol/notes/concepts/2026-XX-XX_immix-tenant-failure-census.md` as the **external-facing** report — strip internal jargon, focus on observable Immix behavior + clear reproduction. (e) Reuse the 5 contract-violation taxonomy from [[2026-04-29_immix-zombie-tenants]]. Goal: a single document we can hand to Immix engineering that catalogs every distinct way their API is failing us right now, with concrete tenant-level evidence. *(Surfaced 2026-04-30 during cascade rollout — verified RSS + Legacy correctly return Suspended/Suspended via `/Contracts`, but the EU zombies and many other failing tenants aren't currently inventoried.)*

- [ ] **§16 design extension: cascade-on-suspended-detection (not just on connector emit)** — confirmed 2026-04-30 that cascade NEVER fires organically for already-Suspended tenants because their connectors are quiescent → no `no_patrols` SQS messages → DDB count never reaches `tenant_check_threshold=2` → trigger never reached. Of 5 RSS schedule_ids checked, 4 had **never had a DDB row**. Cascade as designed is purely reactive — only catches NEW suspensions where the connector is still active at suspension time. Existing Suspended-tenant backlog (RSS+Legacy: 12+74 schedules pre-cascade) will sit indefinitely unless: (a) we add a periodic reconciliation (cron-triggered Lambda fetches `/Contracts?contractStatus=Suspended` → cascades each one against admin), or (b) we trigger ad-hoc manually as we did 2026-04-30. End-to-end success of ad-hoc test on RSS proved the cascade mechanism itself works — this is purely a TRIGGER-POLICY gap. RSS ad-hoc cascade fired 2026-04-30T14:55:17Z (12 schedules + 12 customers soft-deleted, admin OK in 12s). **2026-04-30 16:02Z: deployed onboarder lifecycle pass with `ONBOARDER_TENANT_LIFECYCLE_ENABLED=true` to address this — but lifecycle log line not appearing (see "Onboarder lifecycle pass log silence" item below).**

- [ ] **Admin-side propagation hooks: schedule → customer → site → cameras** *(critical — surfaced 2026-04-30 during cascade live-fire test)*. Today's cascade endpoint correctly soft-deletes Customer + AutoPatrolSchedule rows, but does NOT propagate state changes UP from schedule deletions or DOWN from customer.active=False to cameras. Three concrete examples observed in prod admin DB: customer pk=40803 (ABC Liquor Store 23) `active=False` but cameras still active; pk=39221 (Victoria - EE Demo) all schedules deleted on Immix side but admin shows orphan rows with no schedule_id; pk=41260 (Cimino Electric) `active=True` but has 1 orphan schedule with no Immix schedule_id. **Design needed:** new admin-side post-save / post-delete signals on AutoPatrolSchedule that check "is this the last active schedule under this customer? if yes, soft-delete customer (which cascades to cameras)". Also Customer.save() should propagate `active=False` to cameras directly. Pairs with §16 cascade infrastructure but addresses a different gap.

- [ ] **One-time admin DB patch for left-behind rows** *(2026-04-30)*. The 3 customers above are examples; there's likely a broader population of admin rows in inconsistent states predating our cascade infrastructure. Build a management command (`python manage.py reconcile_autopatrol_state`) that: (a) for each Customer with active=False or no active AutoPatrolSchedule, ensure cameras are also is_deleted=True; (b) for each AutoPatrolSchedule with no Immix schedule_id, flag for manual review or auto-soft-delete; (c) for each Customer in admin DB whose tenant_id is absent from Immix /Contracts, cascade-disable. Dry-run mode first; report what WOULD change before applying.

- [ ] **Deep-dive doc: admin data model interactions** *(surfaced 2026-04-30 as critical)*. Admin DB autopatrol-related models (Group, Customer, AutoPatrolSchedule, Camera, Contract) have intricate cascade/soft-delete semantics not fully captured anywhere. User flagged this as "very intricate and tricky and sticky." Coverage needed: (a) which delete propagates where (Customer.delete() → cameras + group; AutoPatrolSchedule.delete() → undeploy; what about reverse?); (b) how `active` vs `is_deleted` interact (40803 has active=False AND is_deleted=None — that's a state our cascade doesn't produce); (c) what `schedule_status` means at each level (Awaiting/Active/Suspended/Paused/Removed/Deleted); (d) how reenable_tenant's `customer.restore()` interacts with parent Group restoration; (e) the orphan-row class (schedule with no Immix schedule_id, customer with no group). Stub seeded 2026-04-30 in `topics/admin-api/notes/concepts/2026-04-30_data-model-cascade-semantics.md`.

- [ ] **Onboarder lifecycle pass log silence — debug** *(2026-04-30 17:00Z)*. Flipped `ONBOARDER_TENANT_LIFECYCLE_ENABLED=true` on US + EU at 16:02:30Z. Both Lambdas redeployed (correct CodeSha256, ~5 min cadence). BUT the expected `tenant lifecycle pass: tenants checked=...` INFO log line is NOT appearing — and even the pre-existing `Totals: N contracts, M sites` line that's BEFORE my edit is missing. Lambda completes normally (`END RequestId`, no error visible). Hypothesis: contract loop consumes the entire 4:45 wall-clock (Lambda timeout=600s) and exits silently before reaching either log line. With 30+ failing tenants × 3 retries × 2s delay it could exhaust the budget. Needs: (a) verify deployed CodeSha matches commit `8ac055f`; (b) check if contract-loop's `for contract in contracts_list:` ever completes; (c) wrap `_run_tenant_lifecycle()` call in try/except to log if it crashed; (d) add structured "phase" log lines so we can tell where the Lambda dies.

### From NR reversal + CE validation (2026-04-22 afternoon)

- [ ] **Fleet-coordinator unification question — scoping** — `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md` tracks the structural observation. RESOLVED viable via API sketch 2026-04-22; next steps in concept note's §"Track / next steps" — sketch minimum-viable gRPC API, benchmark lease-churn, prior-art scan. **Feeds the formal A-E re-score when it runs.**
- [ ] **Formal A-E re-score — now unblocked** — real CE data is in hand. *(Note: third synthesizer pass landed 2026-04-22; this item refers to a fourth pass with refinements.)*
- [ ] **Motion-gate validation** — what fraction of raw frames does FDMD actually drop in production today? Proposals D/E assume 60–80%. Real number grounds the cost modeling. Conservative 40-50% assumed for now (PoC invalidation criterion if measured <40%).
- [ ] **Tier3 S3 replication cost investigation — $3,646.91 / 30d ($44k/year), 11.1% of S3 spend, 72.9M requests** — surfaced by `/cost-check S3 --days 30` on 2026-04-22. Investigation steps: (a) S3 Storage Lens; (b) per-bucket Tier3 breakdown via CUR + Athena; (c) CloudTrail dive for `PutBucketLifecycleConfiguration` + `PutBucketReplication` events.
- [ ] **S3 storage growth rate check** — $11,548.20 / 30d on ~1.94M GB-months = ~65TB working set. Is that growing? At what rate?
- [ ] **Inference API cost visibility** — top-10 doesn't show clear "inference API" line. Likely lumped into EC2 $121k/mo or ECS $5.7k/mo. Need to disaggregate via tags or `/cost-check EC2 --group-by INSTANCE_TYPE`.
- [ ] **AWS Config cost ($3,719/30d = $45k/year, 1.7% of total)** — surprising line item. Review Config recording scope + rules + delivery channel volume.
- [ ] **Final composite ranking after both refinements** (recorded for reference): E 8.00 (PoC-1), C 7.55 (PoC-2), B 7.25, D 6.85, A 4.45, B-prime CLOSED 6.25.
- [ ] **PoC-1 (E) invalidation criterion tightened** — if E's measured FDMD drop is <40%, C overtakes on composite. Flip primary to C unconditionally in that case.

<!-- BEGIN-AUTOSYNC-JIRA -->
## Current Jira Queue (auto-synced)

**Last synced:** 2026-05-01
**Source:** `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`

This section is **fully replaced** on every sync by the `jira-sync` automation (see [[automation-jira-sync]]). Manual edits in this section will be lost — add notes against tickets in the workstream sections above instead.

### Ready to Deploy (4)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| CS3-430 | Medium | Sub-task | Account for dummy incident type in CHM API |
| CS3-31 | Highest | Sub-task | Automatically update the reference image |
| CS3-58 | Lowest | Task | Configuration per camera |
| CS3-323 | High | Bug | Discrepancy in cam count btwn dashboard and report |

### In Progress / In Review (2)

| Ticket | Status | Priority | Type | Summary |
|--------|--------|----------|------|---------|
| ENG-198 | In Progress | Medium | Bug | AutoPatrol modelless patrol: signal-flow fixes + investigation |
| ENG-166 | In Progress | Medium | Task | AutoPatrol auto-delete lambda — design + implementation |

### To Do (4)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| ENG-183 | Medium | Task | S3 Cost Reduction — Ranked Action Plan |
| CS3-505 | Medium | Sub-task | add outcome to the API for CHM alerts |
| ENG-136 | Medium | Task | PyAV upgrade 13.1 → 17.0 (nogil pixel conversion) |
| ENG-94 | Medium | Task | Deferred alerts: send without frame as fallback when cache expires |

### Open (1)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| BT-259 | Medium | Bug | "Use Motion" toggle bug |

<!-- END-AUTOSYNC-JIRA -->

---

<!-- BEGIN-TODAY-SCOPE -->
## Today's Scope (2026-04-30)

*Wrap closed 2026-04-30 — all 5 picks closed (4 runbooks + cost-signal expansion); morning-prep allowlist landed via sibling session. Plus §16 24h cascade soak verdict came in clean (1 cascade fired against RSS canary, DLQ stayed 0). Archive: [[2026-04-30]]. Next morning's scope picks via `/daily-scope`.*

### Tracked as relevant (carry-forward to next session)

Forward context — open elsewhere, not yet picked.

- **§16 effective-close-out** — 24h soak clean: 1 expected cascade (RSS canary `0ee7cb3f`, reason=`immix_tenant_suspended`, admin OK), DLQ depth 0/24h. Tomorrow morning's `/daily-scope` should consider full §16 archival to `## Archive`. Step 5 (re-enable path) and Step 6 (`disable_tenant` permission_classes hardening) remain open per §16's subtasks.
- **§17 stage→rearchitecture promotion** — soak clean (DDB flapper counts stable {c3808175:2, fbdfdba6:1, ee1822f1:2} <3 threshold; `connector_no_patrols_to_run_24h` 34→32 trending). Cherry-pick or PR-merge PR #1662 to rearchitecture. Gate clear, not picked today.
- **§18 fleet memory-limit drift** — RED on `fleet_new_oom_offender` 2 days running (connector-14170 top, 10-14/24h). VPA floor restoration in `connector_deployer` is the fleet-wide fix; not picked today.
- **Immix zombie-tenants Jira ticket** — exec deferred from fan-out; needs Atlassian writes. Draft at [[2026-04-29_immix-zombie-tenants]]. Design-blocking for §16 EU rollout (Step G).
- **PR #77 post-merge import dance** ([ds-terraform-eks-v2#77](https://github.com/aegissystems/ds-terraform-eks-v2/pull/77)) — once CI green and merged: terragrunt import + apply per [[2026-04-29_iam-tf-import-pattern]]. Still open, awaiting review.
- **AUTO-351 BB push to prod** — §2c. Ready-to-Deploy. Brad-assigned, not Mark.
- **vms-connector#1656 streamId-null patrol-alert** — §2d.2. Unassigned.
- **ENG-94 deferred-alert frame fallback** — Jira To Do, Medium, Mark-assigned.
- **§3 Step F prod US scale-up** — gate clear (E.3 closed); one-flag flip away.
- **§3 Step G prod EU** — separate track, needs net-new infra.
- **§3 follow-ups: Immix error-pattern observability + SiteDisabledOrDisarmed routing** — design-pending.
- **HIGH overnight (carrying):** connector-deploy 11.6k err (retry storm against site 14170); connector-32460 5.5k (VMS empty/non-JSON); queue-evalink-consumer 318 (deviceId-32 data-quality); 5/5 checked AP sites running 0 patrols.
- **Sibling-session work landed today (FYI, not Mark's track):** morning-prep allowlist closed via [[2026-04-30_morning-prep-scripts-runbook]] + [[2026-04-30_morning-prep-audit]] + [[2026-04-30_three-tier-routine-check-pattern]]; §16 admin-side propagation + cascade-semantics via [[2026-04-30_admin-propagation-handoff]] + [[2026-04-30_data-model-cascade-semantics]] + [[2026-04-30_autopatrol-state-audit]]; obsidian-CLI retrofit via [[2026-04-30_kb-skill-cli-retrofit]] + [[obsidian-cli]]; NR cookbook + log-level strategy via [[nr-connector-query-cookbook]] + [[nr-log-level-strategy]].

**Surface (camera-ui audit-flag):** Login.tsx — runbook landed today; decision tree in [[2026-04-30_camera-ui-login-tsx-audit-flag]] should retire this.
**Surface (jira-sync audit-flag):** check tomorrow whether [[automation-jira-sync]] cron fired today; runbook [[2026-04-30_detecting-jira-sync-staleness]] is the recovery path.
**Surface (orphan branches):** `vms-connector@fix/vch-drop-no-patrols-emit`, `autopatrol-server@fix/ci-surface-push-failures` — investigate before any push.
**Surface (AWS dev-eu profile not configured):** non-blocking but worth a follow-up before any EU work.

<!-- END-TODAY-SCOPE -->

<!-- BEGIN-MORNING-FOLLOWUPS -->
## Morning Follow-Ups (for 2026-05-01)

Time-bound checks seeded by [[skill-daily-wrap|/daily-wrap]] and consumed by the morning ritual ([[skill-daily-scope|/daily-scope]] or a future `/morning`). Each item is tagged with how it should be handled:

- **exec** — scriptable; the morning ritual runs it automatically during health fan-out and reports the result
- **verify** — needs user eyeballs on something specific; surfaced as a briefing line
- **decide** — requires a decision that should shape today's scope before picks

Consumed items get `[x]` and **immediately move to that day's daily note's `## Closed Sub-items` section** (rolling-forward convention 2026-04-27). Items not acted on roll over with a `*(rolled YYYY-MM-DD)*` qualifier.

- [ ] **decide**: [connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160) — orphan container cleanup *(rolled 2026-04-25 → 2026-04-27 → 2026-04-28, not picked again)*. Still assigned; 2 orphans observed (`51c72148`, `798e6dde`). Scope for first session: decide approach (Option 1 recommended), draft the scan.

### Seeded for 2026-04-29

- [x] **verify**: §16 admin PR #2376 (`actuate_admin@81523258` — `disable_tenant` cascade endpoint) merge-to-staging status — **MERGED to staging 2026-04-28T20:04:14Z** ✓. Step 4a DRY_RUN canary gate clear, descoped from today's active scope (folded into "Tracked as relevant"). *(seeded 2026-04-28; ran 2026-04-29)*
- [x] **verify**: §17 vms-connector PR #1662 (`8f771f3c` — VCH `no_patrols` emit drop) stage merge status — **MERGED to stage 2026-04-28T20:01:08Z** ✓. 24h post-merge verify window opens ~20:00Z tonight; descoped from today's active scope. *(seeded 2026-04-28; ran 2026-04-29)*
- [x] **decide**: connector-45999 OOMKill promotion target — **picked into today's scope as part of "Carry-over decides"**. *(seeded 2026-04-28; rolled into 2026-04-29 scope)*
- [x] **decide**: ENG-179 close-out — **picked into today's scope as part of "Carry-over decides"**. *(seeded 2026-04-28; rolled into 2026-04-29 scope)*
- [x] **decide**: Jira Todo-audit — **picked into today's scope as part of "Carry-over decides"**. *(seeded 2026-04-28; rolled into 2026-04-29 scope)*

### Seeded for 2026-04-30

*Closed-out swept to [[2026-04-30]] § "Closed Sub-items" by `/daily-wrap` 2026-04-30. Pending items rolled to "Seeded for 2026-05-01" below.*

### Seeded for 2026-05-01

- [ ] **verify+exec**: Continuation of 2026-04-30 planning session for admin-side state propagation. **Already done:** deep-dive expanded ([[2026-04-30_data-model-cascade-semantics]] now has verified findings on all 8 open questions w/ file:line); audit synthesis with cohort filter logic ([[2026-04-30_autopatrol-state-audit]]); read-only `audit_autopatrol_state` mgmt command shipped as actuate_admin PR [#2389](https://github.com/aegissystems/actuate_admin/pull/2389) (draft, supersedes closed #2388 which had a stale base off `main` instead of `staging`). **Today's task:** (1) review + merge PR #2389 to `staging`, (2) wait for `Staging CI` (post-merge), (3) eventually flow through release-train to `main` then prod deploy, (4) `kubectl exec` on prod admin and run `python manage.py audit_autopatrol_state` to get cohort sizes, (5) paste numbers back into [[2026-04-30_autopatrol-state-audit]], (6) use the numbers to design propagation-hook ADR + `reconcile_autopatrol_state` companion command. *(seeded 2026-04-30 for 2026-05-01)*
- [ ] **verify**: §16 onboarder lifecycle pass next-day soak — confirm logs are emitting properly (post PR #13 fix at 19:07Z). Look for: (a) `tenant lifecycle pass: tenants checked=18 suspended/removed=2 active=16 cascaded=2` line on each invocation US, (b) any new `cascade-disabled tenant_id=...` lines on tenants OTHER than RSS/Legacy (would indicate new suspensions or zombie tenants surfacing), (c) `cascade-reenabled` lines (would indicate Active flip-back). Run `AWS_PROFILE=prod aws logs tail /aws/lambda/immix-autopatrol-onboarding --region us-west-2 --since 1h --format short | grep "tenant lifecycle"`. *(seeded 2026-04-30 for 2026-05-01)*
- [ ] **exec**: Still-pending — paste Jira ticket draft for **Immix zombie-tenant API contract violations** into AUTO project. Rolled from 2026-04-30 (deferred — Atlassian write not in fan-out scope). Full draft at [[2026-04-29_immix-zombie-tenants]]. *(rolled 2026-04-30 → 2026-05-01)*
- [ ] **decide**: Cascade-disable propagation hooks — schedule → customer → site → cameras (per [[2026-04-30_admin-propagation-handoff]]). Captured in cascade-rollout-aftermath section above; pull into Today's Scope if planning session bears fruit. *(seeded 2026-04-30 for 2026-05-01)*
- [x] **decide**: §17 stage→rearchitecture promotion of PR #1662 (VCH `no_patrols` emit drop). **CLOSED — bundled into vms-connector PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) (stage→rearchitecture promotion), MERGED 2026-05-01T14:28:26Z, commit `73fd3bf`.** Post-merge soak items now seeded for 2026-05-02. *(rolled from 2026-04-30 carry-forward → seeded for 2026-05-01 → ran 2026-05-01)*
- [ ] **decide**: §16 effective-close-out — 24h soak verdict came in clean (1 expected cascade against RSS canary, DLQ 0). Tomorrow's `/daily-scope` should consider full §16 archival (move §16 → `## Archive`). Open subtasks: Step 5 re-enable path + Step 6 `disable_tenant` permission_classes hardening — keep tracked even after archival. *(seeded 2026-04-30 for 2026-05-01)*
- [ ] **decide**: §18 fleet memory-limit drift pickup. RED on `fleet_new_oom_offender` 2 days running (connector-14170 top). Restore VPA min-memory floor in `connector_deployer` (strip `Securitas Australia - Trial` gate from a5de5db). Per-incident OOMKill runbook just landed for triage but the fleet fix is still §18. *(seeded 2026-04-30 for 2026-05-01)*
- [ ] **verify**: morning-prep cron output now that allowlist landed today via sibling session. Check `http://mork-firebat/logs/morning-prep-2026-05-01.summary.json` and per-skill stdout — should be populated with real `/repo-scan` + `/autopatrol-overnight-check` + `/autopatrol-cleanup-lambda-check` output now (not the BLOCKED stubs from today). If still blocked, re-open the allowlist ticket. *(seeded 2026-04-30 for 2026-05-01)*
- [ ] **decide**: Recalibrate `connector_no_patrols_to_run_24h` thresholds — gated on PR #1662 reaching prod (not stage). *(rolled 2026-04-30 → 2026-05-01)*
- [ ] **decide**: Repo-backlog per-repo concept refresh cadence — daily vs weekly. *(rolled 2026-04-30 → 2026-05-01)*

### Seeded for 2026-05-02

- [ ] **verify**: vms-connector PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) post-merge soak (merged 2026-05-01T14:28:26Z, commit `73fd3bf` to `rearchitecture`). Bundled 6 commits: AP cleanup connector emit (#1657), stream_id null guard (#1659), VCH `no_patrols` drop (#1662), YAM polygon hints (#1655), pullers stable bump (#1661), BT-949 pano-split IZ fix. Verification fan-out:
  1. **YAM emit (1h post-deploy first, 24h confirm):** any YAM-eligible site emits `motion_polygons` WKT to slicing server, no `motion_mask`-related `AttributeError` in connector logs. NRQL: `SELECT count(*) FROM Log WHERE container_name LIKE '%connector%' AND message LIKE '%motion_mask%' AND level = 'ERROR' SINCE 24 hours ago` — expect 0.
  2. **VCH `no_patrols` traffic drop (24h):** cleanup-Lambda `integration=vch reason=no_patrols` event count drops to near-zero for Vendor.Actuate.Prod. Unblocks `decide: Recalibrate connector_no_patrols_to_run_24h thresholds` once landed in prod (not just rearchitecture).
  3. **stream_id null guard (24h):** no `raise_patrol_alert` handler errors with null `stream_id`. Spot-check: `SELECT count(*) FROM Log WHERE message LIKE '%raise_patrol_alert%' AND message LIKE '%null%' SINCE 24 hours ago`.
  4. **AP cleanup connector emit (24h):** SQS `autopatrol_stale_schedule_cleanup_dev.fifo` (or prod equivalent) receives messages from connector terminal exits at expected rate. Cross-check against cleanup-Lambda invocation count.
  5. **BT-949 pano-split IZ fix (multi-day watch):** TJ Hamilton Cars M5/M7/M19 false-positive vehicle alerts trend down vs 7-day baseline. Manual spot-check needed on a pano clip with aspect > 2.0 and a drawn vehicle IZ.
  6. **Connector-pod error baseline (24h):** total connector-pod errors flat or improved vs prior 24h. Use `/post-deploy-monitor` if it's been retrofitted to take a merge timestamp.
- [ ] **exec**: File follow-up issue in vms-connector for direct unit tests on `connector_factories/shared/cleanup_emitter.py` (167 LOC, broad `except Exception`, zero direct tests). Tests should assert: emit fires under terminal exits, suppressed for pending/transient, no-op when env flag off, no-op when `schedule_id` empty. Surfaced in PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) review 2026-05-01. *(seeded 2026-05-01 for 2026-05-02)*
- [ ] **exec**: File follow-up issue (or one-line PR) for explicit `boto3.client("sqs", region_name=...)` in `cleanup_emitter.py:87` so a region-mismatched stage pod surfaces a distinguishable warning instead of opaque `NonExistentQueue`. Surfaced in PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) review 2026-05-01. *(seeded 2026-05-01 for 2026-05-02)*
- [ ] **exec**: KB synthesis closing the loop on YAM motion-bridge removal landing in connector — one-line update under `topics/vms-connector` YAM polygon-hint workstream noting PR #1660 closes the connector-side loop. Per global CLAUDE.md "After Work: Log to KB." *(seeded 2026-05-01 for 2026-05-02)*

<!-- END-MORNING-FOLLOWUPS -->

---

## Discipline

- Update this note at the end of each working session where one of these workstreams moved.
- **Closed sub-items don't accumulate here.** When a `[x]` happens inside a §N workstream, the bullet moves into that day's daily note (`topics/personal-notes/notes/daily/YYYY-MM-DD.md`) under `## Closed Sub-items`. [[skill-daily-wrap|/daily-wrap]] Step 2.7 enforces this; the global `## Task Completion Ritual` instructs same-day distribution.
- **Never delete history.** Closed sub-items persist forever in their close-day daily note. Whole closed workstreams (§N) move to `## Closed Workstreams` in that day's note + a pointer row lands in this file's `## Archive` table. Pre-2026-04-27 history is preserved in `_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md`.
- When a new high-level TODO appears, add it via [[skill-todos-add|/todos-add]] — don't let work accumulate in chat-only form.
- Periodic audit (~weekly) via [[skill-todos-audit|/todos-audit]] — catches stale workstreams, orphaned Jira tickets, untracked branches, priority drift.
- Cross-repo opportunity sweep via [[skill-repo-scan|/repo-scan]] — surfaces high-impact + low-hanging-fruit GitHub issues that aren't assigned to Mark.
- **Items in "Not-Yet-Prioritized" are not tracked in Jira** — if one becomes urgent, create a ticket and promote to a §N workstream.
- **Daily-note `topics:` + `workstreams:` frontmatter is the cross-reference primary key.** `grep -l "topic: autopatrol" topics/personal-notes/notes/daily/*.md` answers "what days touched X". Tag rigorously.

## Archive

Pointer table for fully-completed workstreams. Full content lives in the daily note linked on each row.

| Closed | Workstream | Daily note |
|--------|-----------|------------|
| 2026-04-23 | §1 Inference API v5 — finish for testing | [[2026-04-23]] |
| 2026-04-23 | §9-old AutoPatrol Alarm & Dashboard System (superseded by cross-repo §9) | [[2026-04-23]] |
| 2026-04-27 | §13 Subagent + cron MCP-bypass auth flow | [[2026-04-27]] |

## Related

- [[personal-notes/_summary|Personal Notes topic]]
- [[team-structure/_summary|Team Structure topic]]
- [[engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle|Feature Development Lifecycle]]
- [[agents-catalog]] — which agents help with which workstream
- [[automation-jira-sync]] — the daily job that refreshes the "Current Jira Queue" section
- Skills: [[skill-daily-scope|/daily-scope]], [[skill-daily-wrap|/daily-wrap]], [[skill-todos-audit|/todos-audit]], [[skill-todos-add|/todos-add]], [[skill-repo-scan|/repo-scan]]
- Pre-cleanup snapshot: `_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md`
