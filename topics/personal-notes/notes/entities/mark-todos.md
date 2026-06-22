---
title: "Mark's High-Level TODOs"
type: entity
topic: personal-notes
tags: [todos, mark, work-plan, priorities, personal]
created: 2026-04-16
updated: 2026-06-22
last_scope: 2026-06-22
last_wrap: 2026-06-16
author: kb-bot
backlog: topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
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

## 2. AutoPatrol — outstanding alert-flow follow-ups

### 2c. AUTO-351 BB push to prod (Brad-assigned)

- [ ] Brad's track — Mark monitors only. Ready-to-Deploy per Jira queue.

### 2d. AP/VCH alert-flow diagnostic gaps (waiting on Immix)

- [ ] **vms-connector#1658** dev.powerplus.com SSL cert chain — waiting on Immix/PowerPlus engagement; option-3 mitigation (pin Sectigo intermediate) is the time-bound fallback. Detail in [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]].
- [ ] **vms-connector#1656** `streamId: null` on `raise_patrol_alert` — waiting on Immix preferred remediation; cross-links to [[autopatrol-deferred-backlog]] § "§3 follow-ups: SiteDisabledOrDisarmed routing".
- **Context:** both surface as "cameras offline" in customer healthcheck UI; per-failure-mode status code differentiation is a future workstream.

> **§2a "test the release"** retired 2026-05-07 — that's just routine ops; covered by `/dashboard-check` + post-deploy soak monitors.
> **§2b** deferred-alert race CLOSED 2026-04-20 → [[2026-04-20]].

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

- [ ] **Verify pipeline correctness for disabled / paused / not-working sites** (active, 2026-05-07) — confirm the cleanup-Lambda behaves as designed across the full state matrix: Immix-Deleted (should disable), Immix-Suspended (should NOT disable; anomaly-reset), Paused (should NOT disable), genuine offline/connectivity-broken (should NOT disable). Use stage logs + DDB inspection + the per-state assertions in the cleanup-lambda playbook. Spot-check the recent disable trail (`disabled_by=cleanup_lambda`) for any case that shouldn't have fired.
- [ ] **Step F + Step G + follow-up follow-ups** moved to [[autopatrol-deferred-backlog]] (2026-05-07). Active path is verify-only this week.

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

## 4. API keys per customer within a group (v5 follow-up) — DEFERRED 2026-05-07

> **Deferred 2026-05-07.** Design-only workstream that follows from §1 (archived); never picked up. Re-open trigger: EBUS / v5 stakeholder asks for per-customer keys, OR v5 partner workload exposes a need for per-key permission separation. Full design surface preserved in [[external-api/_summary|external-api topic]] for when revived.

---

## 5. Fleet Architecture — review and consolidate 2026-04-16 proposals

**Tickets:** *(pre-ticket — captured in [[fleet-architecture/_summary|fleet-architecture]] topic syntheses)*
**Status:** review phase — formal A-E re-score landed 2026-04-22; PoC selection next. Run Service sub-project drafted (dual-mode permanent control plane).
**Priority:** this-week

Active checkboxes only — proposal rescores, Run Service framing, Tier3 replication detail, KB cross-refs all factored to [[2026-05-05_fleet-architecture-workstream-context]].

> **2026-06-02 — Watchman Phase-0 fleet fit decided.** Best fit = **E (simplified)** = "E's split + C's bin-packing"; grow-into target = **v10 via E**. Greenfield standalone repo, RTSP-only, per-camera (no site), Redis Streams, uniform bin-packed pullers, stateless trimmed detection, WMS-as-FleetCoordinator. Frontend sketch cataloged. Full analysis + M0–M5 build plan: [[2026-06-02_watchman-phase0-fleet-fit]]. Sketch: [[2026-06-02_frontend-sketch-ui]].

> **2026-06-16 — Watchman pipeline/backend meeting.** Backend direction = **doubletake-pattern Lambda** (invoked during connector run, writes to window-id table/db); storage **OPEN** (Postgres vs OpenSearch [Jagadish] vs S3-vector [Otzar]); forensic search needs GPUs + sentence-transformers + vector DBs; **AWS stays on dev account w/ Terraform** (no new account → avoids separate NR + GDPR); Valeri building connector-side Lambda (~end of next week). Open Qs: storage choice timing, Lambda invocation point (sync vs async), alert grouping/id cleanup, pipeline-vs-connector parity. Full integration vs phase-0: [[2026-06-16_watchman-pipeline-backend-meeting]].

### Review + PoC selection

- [ ] Review each proposal and annotate with questions / concerns / deal-breakers
- [ ] Apply [[2026-04-16_evaluation-rubric|evaluation rubric]] consistently across all 5
- [ ] Pick top 2 for team deep-dive *(rescore says E first, C runner-up)*
- [ ] Decide whether [[2026-04-16_graceful-failover-design|graceful failover]] and [[2026-04-16_frame-transport-comparison|frame transport]] should become ADRs
- [ ] **Pre-PoC open question — Tier3 replication driver investigation** ($44k/year, 11.1% of S3 spend, 72.9M requests). Investigation steps: (a) S3 Storage Lens or bucket-lifecycle policy audit; (b) per-bucket Tier3 breakdown via CUR + Athena if it's worth the setup; (c) CloudTrail dive for `PutBucketLifecycleConfiguration` + `PutBucketReplication` recent events.

### Run Service — paradigm scoring + PoCs

- [ ] Score the 3 paradigms against the **persistent-mode rubric** ([[2026-04-16_evaluation-rubric]]) — paradigm notes only carry ephemeral-lens scores today
- [ ] PoC-1 (E or C, whichever lands first) — Lambda + translator + init container + minimal K8s manifest. Stress-test with **mixed persistent + ephemeral load** on the same primitives, not single-mode.
- [ ] Decide whether the chosen paradigm must serve both modes with the same primitives (no parallel implementations) or whether bimodal config is acceptable
- [ ] Write `comparison-matrix.md` after PoCs run head-to-head — combine both rubrics

### Run Service — translator + spec

- [ ] Resolve top-level `customer.server_ip`/`username` vestigial fields under multi-camera RTSP — highest-priority translator blocker
- [ ] Confirm whether connector image has a `validate` subcommand or whether it's a new ENG ticket
- [ ] Sensitivity preset numeric calibration — needs inference-team sign-off on `low/medium/high` per product (intruder, weapon, loitering, line-crossing, etc.)
- [ ] Sensitivity preset versioning policy — pin existing runs vs migrate live? Default pin
- [ ] Per-product sensitivity scales — universal `low/medium/high`, or per-product variants (loitering's dwell-time, line-crossing's directionality)?
- [ ] Products registry — formalize the list of supported product types (intruder / weapon / loitering / line-crossing / ...) and their schemas
- [ ] Model registry hot-reload — config map / DynamoDB-backed, or in-code redeploy?

### Run Service — API contract

- [ ] Decide between Cognito, API key + tenant, or both for v1 auth (default: both)
- [ ] Webhook secrets — inline + `POST /v1/secrets` (default both supported)
- [ ] Cost-per-camera-hour coefficient for cost-ceiling refusal — needs benchmark
- [ ] Frame URL TTL default + per-tenant max — tentatively 1h default / 24h max
- [ ] Event replay retention window — default 90d (matches run record retention)
- [ ] OpenAPI spec authoring — generate from Pydantic (recommended) or hand-author
- [ ] SDK languages for v1 — Python first; Go and TypeScript secondary
- [ ] Webhook batching threshold for events — fixed batch size or rate-aware
- [ ] Persistent-mode webhook fanout cost — pull-by-default (SSE/GET) with webhook opt-in?
- [ ] Events store at scale — DynamoDB acceptable for v1, when to migrate to S3-Parquet/Athena
- [ ] Per-product alert filters inside a config — defer unless requested
- [ ] Multi-region — single us-east-1 for v1; revisit when required

### Run Service — operational + infrastructure

- [ ] Final project name (lock `run-service` or pick something else) → triggers folder/file rename pass
- [ ] Build the canary (Tier 1 firebat systemd) with the 11-fixture corpus
- [ ] Operational ownership — on-call rotation, SLA targets, dashboards
- [ ] Migration of admin-api-side concepts (alert configs, model registry sharing) — separate design doc

**Full context + proposals review:** [[2026-05-05_fleet-architecture-workstream-context]]

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

**Tickets:** pre-ticket (cross-repo R&D / process)
**Status:** Phase 1a complete; Phase 1b in progress (15/19 signals enabled)
**Priority:** current

Cross-repo silent-regression dashboard generated by `/dashboard-check`, surfaced as static HTML under `/home/mork/Documents/worklog/dashboard/` (also via Caddy at `http://mork-firebat/dashboard/`). Scope, design principles, signal-coverage matrix, and phasing live in the synthesis note linked below. Continuation pickup doc: [[2026-04-24_dashboard-1b-continuation]]. Post-mortem trigger: [[2026-04-23_postmortem-onboarder-healthcheck]]. Closed sub-items archived in [[2026-04-23]] (Phase 1a) + [[2026-04-24]] (Phase 1b 15-signal expansion).

### Phase 1b — open deliverables

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
- [ ] **NEW (2026-05-14): Wire existing inference-api E2M signals into firebat dashboard.** Three rules created 2025-09-11 in [[2026-05-14_inference-api-e2m-rules]]: `inferenceApi.billing.requests`, `inferenceApi.billing.frames`, `inferenceApi.inference.slices`. Each gets a tracked dashboard signal with baseline + regression rule so silent drops in any of the three count classes surface in `/dashboard-check`. One-shot; closes when all three render on the dashboard. *Pre-req:* resolve the account-ID question (graphql targets `7081731`, KB-documented primary is `3421145`) before wiring queries.
- [ ] **NEW (2026-05-14, ongoing discipline): Every new inference-api E2M rule ships with a dashboard signal.** When adding a rule to `EventsToMetricRules.graphql` (or via NR UI), update `~/.claude/skills/dashboard-check/config/signals.json` in the same change. Don't let metric series exist without a regression-aware view. Permanent standing item — does not close; reminder lives here as a discipline gate. Active surface: [[2026-05-14_v5-tracking-fields-e2m-design]] proposed follow-up rules (per-camera, per-error) when written must include dashboard signals.

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

**Full context + signal coverage matrix:** [[2026-05-05_operational-dashboard-context]]

---

## 8. Multi-agent / multi-model setup for KB source research — ARCHIVED 2026-05-08

> **Archived 2026-05-08** → see [[2026-05-08]] § Closed Workstreams. Fully subsumed by [[#24-internal-llm-shop-on-npu-server-shared-multi-purpose|§24 LLM shop]] — every design-surface question (KB tasks to offload, model routing, integration surface, output contract, cost model, observability) has been answered and shipped under §24's `llm-shop-delegate` subagent + `kb-intake`/`kb-deep-intake`/`kb-todo`/`code-delegate` harnesses on `npu-server`. Re-open conditions: prompt-cache economics shift, or §24 infra retirement. Capping syntheses: [[2026-05-07_kb-deep-intake-architecture]], [[2026-05-07_long-running-multi-agent-pattern]], [[2026-05-07_overnight-batch-pattern]]. Original seed: [[2026-04-20_multi-agent-model-routing]].

---

## 10. Laptop-config portability + disaster recovery

**Priority:** high (laptop-loss / reboot risk is always non-zero)
**Tickets:** *(pre-ticket — personal infra)*
**Status:** scoping

One-command bootstrap to reconstitute this laptop's Actuate config (Claude Code skills/agents/hooks/rules, systemd user services, KB, dashboard layout, secrets-refresh runbook) on a fresh machine. Likely v1 approach: plain git dotfiles repo + `bootstrap.sh`; upgrade to `chezmoi` if v1 friction shows up.

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

### Related

- §9 Operational Dashboard — the initiative that surfaced "I shouldn't lose this"
- [[skill-daily-scope]] — morning routine depends on the whole config being intact

**Full context + DR plan:** [[2026-05-05_laptop-config-portability-context]]

---

## 11. Firebat minipc follow-ups — COLLAPSED 2026-05-07

> **§11a/c/d** are largely subsumed by §12 (minipc dashboard app) and the firebat tier-1 systemd timer pattern that's now live (`~/bin/morning-prep.sh`, `~/bin/run-dashboard-check.sh`, autopatrol cleanup-check, repo-scan). §11b subsumed by §12e. §11e closed 2026-05-06. Setup history preserved at [[2026-05-05_firebat-minipc-followups-context]].
>
> Re-open trigger: a new firebat tier-1 capability needed (e.g., dashboard-push API) that doesn't fit naturally into §12.

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

- ~~§12i — Strip LLM narrative pass from minipc `/dashboard-check` cron~~ → CLOSED 2026-05-06, moved to [[2026-05-06]] § Closed Sub-items. Subsumes §11e.
- ~~§12i.b — Port `/kb-recap` to script~~ → CLOSED 2026-05-07 (verification only — already deployed). See [[2026-05-07]] § Closed Sub-items + [[2026-05-07_firebat-enhancements-batch]].
- ~~§12j core dashboard follow-ups (per-repo 7d deltas, FACET-classify in render.py, sparklines per metric, drilldown detail pages)~~ → CLOSED 2026-05-07. See [[2026-05-07_firebat-enhancements-batch]]. **§12j tail still open:**
  - [ ] **Cleanup-lambda interpretive checks (Step 8b/8d remaining)** — Step 8c DONE 2026-05-07: new `onboarder_healthcheck_hotfix_in_effect` git_local signal (boolean, red_below=1) catches revert of 2026-04-23 healthcheck-warning hotfix. 8b (DDB drift, 4-6h, needs new `cw_dynamodb` source) and 8d (gh-log scan, "last or never") still optional. Handoff: [[2026-05-07_handoff-cleanup-lambda-interpretive-checks]].
  - [ ] **vms-connector stale-branch review** — dedicated session: walk all 229 stale branches (>60d), classify each (merged-elsewhere / abandoned / WIP-someone-still-cares), produce a report with per-branch recommendation + author callout, post to team for approval, then execute the cleanup. Output is a *reviewable artifact*, not a unilateral delete. Single-session scope, ~2-3h. Surfaced by 2026-05-07 dashboard signals.
  - [ ] **actuate-inference-api 724d-old open PR** — single-PR review: re-baseline against current main, decide rebase / close / hand-off. Single-session, ~30min.

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

## 15. Video-processing topic — quick fixes only (refactors deferred)

**Status:** quick fixes kept inline; bigger refactors moved to [[video-processing/_summary|video-processing topic]] backlog 2026-05-07.

### 15a. Quick fixes (small PRs — keep inline)

- [ ] **GPU FFmpeg `--enable-gnutls` build flag** — `x86_dockerfile.gpu` and `arm_dockerfile.gpu` both omit it; CPU ARM has it. One-line per Dockerfile. Result: `https://` snapshots and `rtsps://` cameras silently fail to open via PyAV on GPU nodes. Details: [[connector-docker-system-deps]].
- [ ] **`make_video_ffmpeg` + `fish2pano` subprocess timeouts** — both shell out without bounded timeouts (`queue_consumer/consumers/shared/utils.py:174-204` and `actuate-libraries/actuate-pullers/.../base_puller.py:333-339`). Add timeouts matching the longest acceptable runtime per call. Details: [[immix-mp4-mux-downstream]].
- [ ] **Delete `GstUrlFramePuller` + `GStreamerInputPipeline`** — zero production callers per [[gst-rtsp-h264-only-audit]] + [[connector-decoder-routing-map]]. Hardcoded H.264-only — a latent trap for any future HEVC wiring. Touch `__init__.py` to drop the conditional import.

### 15b/c/d (refactors + investigations) — DEFERRED 2026-05-07

> Moved to [[video-processing/_summary|video-processing topic]] for tracking. Includes: AVI/Xvid masquerading as `.mp4`, EU `prod-queue-immix-consumer` ECS autoscaling check, Hikcentral split-brain decode migration, PyAV migration completion (pre-req for fleet-arch proposal C), KVS pipeline JPEG round-trip elimination, EKS prod GPU node verification, Dockerfile coverage spot-check.

### Related

- Topic: [[video-processing/_summary]]
- Bridge syntheses: [[decode-locality-per-proposal]], [[gpu-substrate-and-fleet-placement]], [[kvs-webrtc-as-fleet-frame-plane]], [[frame-transport-payload-formats]]

---

## 17. VCH connector emits `no_patrols` for genuinely-Active schedules — ARCHIVED 2026-05-07

> **Archived 2026-05-07** → see [[2026-05-07]] § Closed Workstreams. PR #1660 stage→rearch (bundling #1662 VCH `no_patrols` emit drop) merged 2026-05-01. Recalibration of `connector_no_patrols_to_run_24h` thresholds tracked in [[autopatrol-deferred-backlog]] (gated on PR #1662 reaching prod). Investigation history: [[2026-04-28_tenant-status-sync-gap]].

---

## 18. Memory-limit drift — restore VPA floor + audit CRITICAL cohort

**Priority:** Medium-High (sustained-RED OOMKill on 4+ consecutive days, customer-visible via dropped frames / restart loops)
**Status:** identified 2026-04-23 ([[2026-04-23_oom-surge-connector-limit-drift]]); promoted to its own workstream 2026-04-29; **tickets filed 2026-05-05 → handed off to Paolo / Mike** ([ENG-214](https://actuate-team.atlassian.net/browse/ENG-214) + [connector_deployer#165](https://github.com/aegissystems/connector_deployer/issues/165))
**Root cause:** Feb-9 commit `a5de5db` "remove vpa patch" removed the min-memory floor on VPA at pod creation. Subsequent commits (`9736971`, `4367a39`) restored a floor only for `Securitas Australia - Trial`. ~73 days of VPA learning-loop drift left **1,956 pods in the CRITICAL 384-426 MB tier** (~42% of the fleet under 1 GB).

### Today's evidence

- `fleet_new_oom_offender` 2026-04-29: connector-14170=13, clips-prod=6, create-detection-window=5, connector-39467=4, connector-44740=3, connector-38396=3, connector-39350=3, connector-33724=2 (top of fleet, sustained-RED)
- connector-45999: 96/24h sustained, 2 days running per yesterday's carry-over
- Per-incident proven-fix on connector-20628 (2026-04-23): bump 384 MB → 1.6 GB stopped OOMs immediately; working set was genuine 950 MB
- **2026-05-21 LHF triage finding:** `connector-36180` (32 OOMs/24h) is a Global Guardian / Avigilon **rearchitecture** pod — new cohort vs the original Securitas-Trial gate-strip analysis. Worth folding into the broader VPA-floor audit once the §18 PR is in flight; not Securitas-cohort-specific. Surfaced via [[skill-daily-scope|/daily-scope]] fleet-RED sweep.

### Open work

- [ ] **Restore the VPA min-memory floor for everyone** in `connector_deployer/src/yaml/deployment.py` (or wherever the VPA patch lives). Strip the `lead == "Securitas Australia - Trial"` gate. Use the same 500 MiB + 150 MiB × camera-count formula already validated on that one lead, OR pick a more conservative floor.
- [ ] **Audit the 1,956-pod CRITICAL 384-426 MB tier.** Cross-reference with last-7d working-set peaks; bump every pod whose peak is within 70% of its limit to a safer ceiling (1.6 GB seems to be the validated number for connector pods).
- [ ] **Pickup connector-45999 specifically** as the immediate offender — bump its limit by hand if needed before the broader fix lands.
- [ ] **Verify the regression-prevention signal.** [[2026-04-23_release-acceptance-criteria]] §5 was supposed to catch config-surface drift; check whether there's a deploy-time guard that would have flagged the original Feb-9 commit.
- [ ] **Lower log level on VPA "already exists, patching" path in `connector_deployer`** *(surfaced 2026-05-04 fleet_error_top15 triage)*. `connector-deploy` container logs ~14,800 ERROR events / 24h, and the dominant pattern is `VPA connector-<id>-vpa already exists, patching` across 12,169+ unique VPA object names — the patch then succeeds. This is the **#1 ERROR-volume source in the fleet right now**, drowning real signal in `fleet_error_top15`. The `already exists, patch instead of create` path is a successful happy path, not a failure mode — log level should be WARNING or INFO, not ERROR. ~1-line fix in the deployer, but huge dashboard-noise reduction.

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

## 19. vms-connector `s3alerts` branch — DEFERRED 2026-05-07

> **Deferred 2026-05-07.** Housekeeping. Branch still serves a small set of internal/Actuate-led sites pinned via `ConnectorVersion`. Disposition (retire vs. realign with rearch) tracked in [[autopatrol-deferred-backlog|connector-deferred backlog]] (will create dedicated `vms-connector` backlog if/when needed). Today's stop-gap (cherry-picked fix commit `41a88fe2` 2026-05-01) keeps it functional.

---

## 20. `dw_url_up` empty-body errors — fleet-wide DW auth endpoint flake

**Priority:** This week (high noise floor on `fleet_error_top15`, not customer-facing outage)
**Status:** **PR #1671 merged to stage 2026-05-05T19:59:57Z (commit `7cf8bc4c`).** 24h soak window opens — verify `dw_url_up` ERROR volume drops vs prior baseline + new WARNING lines surface. Promotion stage→rearchitecture follows after stage clean.
**Tickets:** [vms-connector#1670](https://github.com/aegissystems/vms-connector/issues/1670) (tracking issue)
**PRs:** [vms-connector#1671](https://github.com/aegissystems/vms-connector/pull/1671) (`fix/dw-url-up-empty-body-guard` → stage, **merged 2026-05-05**)

### Finding

- New top-1 (`connector-10160`: 6535 errors) and top-3 (`connector-29016`: 3060 errors) entrants in today's ERROR top-15. Yesterday: zero errors at these containers.
- Step-function onset at **04:00-05:00 UTC 2026-05-01**, ~10h *before* today's rearchitecture deploy (PR #1660 merged 14:28 UTC). **Not deploy-caused** — site-side or partner-side trigger.
- Identical error at both sites:

  ```
  ERROR(dw_url_up): Exception when retrieving authorization string for camera <CamN>:
    Expecting value: line 1 column 1 (char 0)
  ```

  `json.loads()` failing on an empty / non-JSON body from the Digital Watchdog camera-auth endpoint. Code path does not guard for it.
- Per-camera-per-day rate is ~400-550 errors → consistent with an unbounded retry loop running full-speed against a transient site-side fault. Connector is contributing to the volume, not just observing it.

### Investigation outcome (2026-05-04)

`dw_url_up` is the daemon thread name (`dw_camera.py:196`); actual crash site is `r.json()["token"]` / `response.json()` at lines 327, 345, 392 of `camera/digital_watchdog/dw_camera.py`. DW NVR auth endpoints (`login/tickets`, `getNonce`) intermittently return empty or non-JSON bodies; bare subscripts raise `JSONDecodeError` into a broad `except Exception` logged at ERROR.

**Fleet-wide, not isolated.** Original sites (10160, 29016) self-quieted ~16h ago (likely camera-side TTL correction), but issue rotates daily. 2026-05-04 last-1h: connector-44342 (75 errors), 34968 (54), 41021 (17), 35118 (14), 4 others — same exact JSON-parse signature.

**Site-side cred rotation will NOT fix this.** Fix tier is library hardening.

### Open work

- [ ] **NEW: DW relay-host timeout investigation (Monitex-Security)** — distinct failure mode surfaced 2026-05-12. `connector-37811` (lead=Monitex-Security, integration=digital_watchdog) hits `b7d3f761-…relay-us-nyc-1-prod-dp.vmsproxy.com` with `HTTPSConnectionPool Read timed out (read timeout=30)` at ~700/hr (99.96% pure — 2,854 of 2,855 ERRORs in 4h). Trend escalating: peak 12h bucket = 9,261 vs historical 1-4k. 0 LINECROSS_ALERT_FIRED in 4h → camera reachability degraded for this site. Other 11 connectors hitting same relay cluster show ≤176 events in 4h (minor spillover). **Diagnosis:** vendor-side (DW relay) or customer-side (NVR) connectivity, not Actuate code. **Recommended actions:** (a) ping CS/Monitex about NVR/relay health, (b) consider code-side circuit-breaker / exp-backoff on these timeouts — pounds the sick endpoint at 700/hr with no payoff. File a Jira ticket once you pick a path.
- [ ] **NEW: WARN-downgrade the four catch-all `except Exception` arms in DW auth retry loops** *(surfaced 2026-05-21 fleet-RED triage)*. PR #1671's `JSONDecodeError`-specific WARNING fix narrowed the cohort but the generic catch-all below it is still firing at ERROR — ~22k events/24h today (connector-11202=14k DW auth, connector-39966=2.9k at 1100 Rt 208). All four sites are inside `while retries < 3` retry loops and have an in-code precedent two lines above: `_DwAuthBodyError` is already commented `# WARNING already logged inside _parse_dw_auth_response. Treat as transient endpoint flake — retry without ERROR-level noise.` The generic `except Exception` arms got missed in PR #1671's scope. **Sites:** `camera/digital_watchdog/dw_camera.py:400`, `dw_camera.py:490`, `camera/digital_watchdog/dw_healthcheck_camera.py:257`, `dw_healthcheck_camera.py:321`. **Fix:** 4× `logging.error(...)` → `logging.warning(...)`. Closes the §20 acceptance criteria "Empty-body / non-JSON responses log as WARNING (not ERROR)" against the catch-all arm. Per the new [[feedback-error-vs-warn-evaluation]] rule.

### Acceptance criteria

- Empty-body / non-JSON responses log as WARNING (not ERROR), don't surface in `fleet_error_top15`.
- `dw_url_up` ERROR volume drops ≥10x for currently-affected sites (assuming upstream firmware unchanged).
- Diagnostic body previews appear in NR so future fleet-wide patterns are visible.

### Related

- Investigation today (this session's NR correlation pass — no KB note yet; write one if/when this gets a real diagnosis)
- Dashboard signal: `fleet_error_top15` (new-entrant rule fired)
- §18 — Memory-limit drift (today's other dashboard-RED, independent issue)
- Repos: `vms-connector` (`dw_url_up` code path), `actuate_admin` (lead/integration lookup)

---

## 28. Customer Billing Pipeline — tighten + self-right

**Priority:** This-week (post-mortem-driven; topic just scaffolded 2026-05-11)
**Status:** Topic [[billing/_summary|billing]] just created. Founding post-mortem, events catalog, and categorized todo list seeded. No items promoted as discrete §N work yet — this section is the loose-link header.
**Tickets:** ENG-242 (Snowflake DDL request, filed + **closed Done same day 2026-05-11** — [[sales-dashboard-repo]] + [[actuate-bi-repo]] together fully answered the ask, no data-team action needed)
**Topic todos:** [[billing/_todos|billing/_todos.md]] — categorized list (Tightening / Self-Righting / Reconciliation / Observability / Codification / Risk-Investigation)
**Post-mortem:** [[2026-05-11_billing-pain-post-mortem]] — narrative arc from cohort F discovery through the PR-#1675 → PR-#1685 → PR-#1688 chain; structural lessons distilled
**Next-session handoff:** [[2026-05-11_billing-and-followups-handoff]] — covers billing + carried-over fleet/software-arch follow-ups (rubric monitoring+billing dimensions, reading-list additions, enforcement sketch spec, reeval scan)

### Why this exists as a workstream

Weeks of incremental connector PRs (#1675, #1680, #1682, #1683, #1684, #1685, plus the #1681/#1686/#1687/#1688 promotion chain) closed five distinct customer-billing-emit gap classes but surfaced two more: (a) crash-path emit gap (79% AP / 67% VCH cronjobs silent in the 2026-05-07 scan), (b) Snowflake-side ingestion gap (Cohort F6/F5 — 392 cams emitted-not-ingested). The structural lesson is that we lack continuous reconciliation across admin ↔ emit ↔ Snowflake — drift was invisible until a manual cohort audit surfaced it, and the duration of the drift is unknown. This §N is the parent workstream to make that pipeline **tight** (no leaks) and **self-righting** (drift auto-detected, auto-corrected where safe).

### Highest-priority next moves (sourced from [[billing/_todos]])

- [ ] **T1 — Close the crash-path emit gap.** Spot-check 5-10 silent containers in NR; design crash-emit mechanism; aim for fleet silent-cronjob rate <5% over 24h sustained 7d. Blocked-by: PR #1688 baseline established. *(billing/_todos T1)*
  - [ ] **T1 pre-impl — Spot-check 5-10 silent containers in NR** (~4h). Classify each into {completed-no-emit, signal-killed, crashed, stuck-in-healthcheck} per last-log-line + duration signature. Pre-impl research for the crash-emit design. Top-2 per [[2026-05-11_pre-impl-research-priority-reorder]]. *(billing/_todos T1 step 1)*
- [ ] **R1 — Admin↔emit dashboard signal (continuous reconciliation).** Design landed 2026-05-11: [[2026-05-11_billing-reconciliation-dashboard-design]] (query shape, NRQL+admin-DB data source, separate billing dashboard local-first, 5% → 1% threshold ramp, 5 open impl questions pinned). Implementation PR is the next loop. This is the post-mortem's headline action item — closes the "unknown drift window" risk. *(billing/_todos R1)*
  - [ ] **NF1 — Clone + inventory `actuate_bi` repo** (~2h). Find DDL files in `sql/snowflake/`, mirror in [[snowflake-billing-tables]] §"Table inventory" replacing inferred column lists, document the swap-task schedule mechanism. Closes ENG-242 remainder. *(billing/_todos NF1)*
  - [ ] **NF3 — Production unbilled-camera ops follow-up** (sales coordination). **2,024 cameras** (May 2026 actual via NF2's first real run — up from 803 in Feb 2026, +150%). 4M compute-hours/month. Re-frame: not engineering scope, but a demo that the reconciliation signal NF2 just shipped is surfacing real growing revenue gaps. Filing target TBD — likely Slack to sales-ops/Tatiana with the trend. *(billing/_todos NF3)*
- [ ] **R2 — Emit↔Snowflake reconciliation.** Data-team-owned. Engage on the Cohort F6/F5 ingestion gap; produce a daily SQS-sent vs Snowflake-landed delta query. *(billing/_todos R2)*
- [ ] **S1 — AutoPatrolSchedule post-delete propagation hook.** Last-active-schedule deletion cascades to customer disable. Blocked-by: admin-team cascade-semantics ADR. *(billing/_todos S1)*
- [ ] **C1 — Keep [[billing-events-catalog]] current.** PR template entry: "If this PR adds/removes a billing emit site or consumer, update [[billing-events-catalog]] in the same PR." Reviewer checklist enforcement. *(billing/_todos C1)*

The full categorized list (24 items across 6 categories) lives in [[billing/_todos]]. Promote items here as §N sub-items only when they become active this-week scope; otherwise the topic todos is the source-of-truth.

### Adjacent / cross-cutting

- §3 (cleanup-Lambda) — the existing self-righting prototype for one drift class (Immix-deleted-but-admin-active). Pattern to replicate up the stack.
- §9 (Operational Dashboard) — billing-drift signal (R1 above) is a first-class candidate panel.
- §5 (Fleet Architecture) — whichever fleet paradigm wins must preserve and ideally tighten billing emission. Add "Billing & Reconciliation" alongside the to-be-added "Monitoring & Alarms" rubric dimension.
- §6 (Software Architecture sketches) — enforcement sketch could include a billing-emit-site fitness function (no emit site outside `billing_emit.py`; idempotency guard always reached).
- §25 (archived Cohort B cascade) — pattern source; revival trigger is the same self-righting design space.
- §26 (deferred Cohort F + §16 tail) — directly billing-adjacent; cohort F connector-side fixes shipped in PR #1688.

### Related

- [[billing/_summary]] — topic overview
- [[billing/_todos]] — categorized todo list (source-of-truth; this §N references loosely)
- [[2026-05-11_billing-pain-post-mortem]] — post-mortem
- [[billing-events-catalog]] — single source of truth for billing events
- [[2026-05-07_handoff-pr-1681-promotion]] — promotion chain that closed the recent emit gaps
- [[autopatrol-deferred-backlog]] — sibling backlog with overlapping items (esp. "Billing emit on crash / early-endrun paths")
- [[2026-05-06_cohort-f-investigation]] — the audit that drove this whole arc

---

## 29. Custom-branch deploy lifecycle — admin endpoints + CI/CD cleanup

**Priority:** Active 2026-05-20 (scope expanded; ENG-282 cut). **2026-05-21: local e2e cycle verified.**
**Status:** Local admin on `localhost:8001` ([[2026-05-20_actuate-admin-local-bringup]]). Migration `0547_custombranch_branchdeploymentevent` applied locally. All 8 endpoints (3 per-customer + 5 branch-scoped) implemented. **End-to-end cycle verified 2026-05-21** ([[2026-05-21_deploy-branch-e2e-cycle-verified]]) — STAGE customer → register → deploy → delete-branch orchestrator → flipped back, 4 audit events. Safe-test-site convention codified ([[actuate-admin-safe-test-sites]]). Full design: [[2026-05-20_deploy-branch-full-scope]].
**Tickets:** ENG-269 (per-customer surface) · ENG-282 (branch-scoped surface + CI/CD cleanup)

### Why

Per-customer surface alone leaks sites onto stale custom branches after a feature branch merges. CI/CD-driven register/cleanup with a first-class `CustomBranch` object closes the loop. Full design + acceptance criteria in [[2026-05-20_deploy-branch-full-scope]].

### Open work (local-first — no CI/CD until local end-to-end passes)

*Scaffolding through dev + staging-PR closed 2026-05-20 + 2026-05-21; verbatim `[x]` history swept to [[2026-05-20]] § Closed Sub-items + [[2026-05-21]] § Closed Sub-items by /daily-wrap.*

- [ ] **`expire_custom_branches` cron — two-phase body** (per-customer TTL + per-branch TTL).
- [ ] **Fill 16 existing test stubs** in `api/tests/test_customer_deploy_branch.py` (still pytest.skip).
- [ ] **Add ~20 new tests** for branch-scoped surface; mock the deployer call.
- [ ] **Seam-A ADR** — `CustomerViewSet` vs new `DeployBranchViewSet`.
- [ ] **CI/CD wiring (separate PR, gated on PR #2445 deploy)** — vms-connector GH Actions on `pull_request: [opened, closed]`.

### Related

- Synthesis (full design): [[2026-05-20_deploy-branch-full-scope]]
- Local bring-up runbook: [[2026-05-20_actuate-admin-local-bringup]]
- Original design (per-customer only): [[2026-05-12_internal-test-deploy-lane]]
- Customer model dissection (Seam-A context): [[2026-05-13_customer-model-dissection]]
- §3 / §27 (AutoPatrol routing) — SQS-side precedent for cohort-based dev routing
- §5 (Fleet Architecture) — any fleet redesign must accommodate per-site image-tag overrides
- §28 (Billing Pipeline) — internal-test traffic must NOT pollute billing-emit counts; cohort opt-in needs a billing-suppression switch

---

## 31. Gmail tier-1 digest — passive inbox surfacing for critical-but-quiet threads

**Priority:** This-week (small scope, high leverage on missed-thread risk)
**Status:** Scoped 2026-05-12. Design in [[2026-05-12_gmail-tier-1-digest-design]]. Not yet built.
**Tickets:** *(pre-ticket — personal infra)*

### Why

Triggering use case: a slightly dead Gmail thread about v5 inference-api testing that needs better visibility. Broader pattern: external partner replies, dead-but-active threads, and critical-sender pings all go quiet inside a heavy inbox. A nightly tier-1 firebat script can convert inbox state into a structured digest the morning ritual reads, with zero token cost per check.

### Open work

- [ ] **Phase 0** — Google Cloud project + OAuth desktop client (~15 min). Confirm `actuate.ai` workspace allows OAuth desktop apps; if blocked, fall back to IMAP + app password.
- [ ] **Phase 1** — `gmail-digest.py` skeleton + auth bootstrap on laptop (~30 min). Prove headless refresh-token flow works end-to-end.
- [ ] **Phase 2** — Classification (awaiting-reply / stale-mine / critical-sender) + noise filters (promotions / GitHub / Jira) + markdown digest writer (~30 min). Output to `~/.local/state/claude-jobs/gmail-digest/YYYY-MM-DD.md`.
- [ ] **Phase 3** — systemd `--user` unit + timer (06:00 daily, before morning ritual) (~15 min). Source-controlled in `local_network_scripts/files/`.
- [ ] **Phase 4** — Deploy to firebat (one-time scp of `token.json` after laptop OAuth consent) (~15 min). Add deploy script.
- [ ] **Phase 5** — Wire into `/daily-scope` (~15 min). Read digest pre-pick; surface critical entries as scope candidates, awaiting-reply as Morning Follow-Ups verify lines.

### Cross-references

- §10 (Laptop-config portability) — `credentials.json` / `token.json` must enter the bootstrap inventory; without them a fresh laptop loses inbox surfacing.
- `/daily-scope` skill — consumer.
- Three-tier routine-check pattern: [[2026-04-30_three-tier-routine-check-pattern]].

**Full design:** [[2026-05-12_gmail-tier-1-digest-design]]

---

## 30. Profiling & Optimization Initiative — VMS + libraries

**Priority:** Background — Phase 1 items are quick wins; Phase 2+ scheduled as bandwidth allows.
**Status:** Phase 2 v1 on `actuate-libraries/feature/actuate-instrumentation-v1` (**unpushed; push blocked on verify gate**). Plan [[2026-05-12_actuate-instrumentation-v1-verification-plan]]; ADR [[2026-05-12_adr-actuate-instrumentation-v1]]; install [[2026-05-12_actuate-instrumentation-v1-installed]]; roadmap [[2026-05-12_profiling-toolkit-and-roadmap]]. **2026-05-13**: harness + `actuate-profile` CLI scaffolded; Exp 1 GREEN. **2026-05-14**: `report` subcommand ([[2026-05-14_actuate-profile-report-subcommand]]) + first hotspot read ([[2026-05-14_first-hotspot-findings]]) — −42% cumulative bytes, −86% in `actuate_movement`. 47 tests pass. **2026-05-15**: cv2 dst= PRs pushed — [aegissystems/actuate-libraries#349](https://github.com/aegissystems/actuate-libraries/pull/349) + [aegissystems/vms-connector#1696](https://github.com/aegissystems/vms-connector/pull/1696), both draft, CI green. **2026-05-18**: webcam test fixture landed on #1696 ([[2026-05-18]]); 90 s validation pass clean. **2026-05-19**: plan revised — cv2-dst stays on dev pin until a real-customer soak signs off (handoff [[2026-05-19_handoff-cv2-dst-stage-deploy]] superseded); new Phase 2.6 sub-block added for the [vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703) PyAV 17 / FFmpeg 8 / OpenCV 4.13 bump driven by MISS-685; Live Streaming v1 plan decomposed into KB (umbrella [[2026-05-19_live-streaming-v1-plan]] + per-repo concepts + crosscut [[2026-05-19_streaming-pyav17-crosscut]]). Exp 2/3 still gated. ENG-246 status comment 2026-05-14.

### Context

Connector has a mature in-process memory hook (`_log_memory_breakdown` w/ jemalloc + smaps + tracemalloc gating) and several one-shot tools (`cpu_profile.sh`/py-spy, `memory_profile.sh`/memray, GIL benchmarks, frame-deletion A/B). Libraries side is essentially empty — no telemetry primitives, `actuate-instrumentation` is a misnamed stub. Python 3.15 stdlib `profiling.sampling` (PEP 799) is genuinely new but blocked behind 3.15 final (~Oct 2027); py-spy stays the equivalent until then.

### Phase 1 — quick wins (unblocked today)

- [ ] **Item 1: Wire `FrameBufferPool.get_stats()` into `_log_memory_breakdown`** — pull `PooledTTLImageCache.get_pool_stats()` per camera, log aggregate hit-rate + per-shape pool sizes. ~30 min. `vms-connector/site_manager/connector/analytics_site_manager.py`.
- [ ] **Item 2: Promote `test_vms/test_gil_benchmarks.py` to a nightly CI job** — new `nightly-perf.yml` GHA workflow, perf-baseline file, regression notification when GIL metrics drift > 20%. Not a PR gate (too noisy on shared runners). ~2 h.
- [ ] **Item 5: New Relic dashboard tile — RSS per camera by integration** vs the 270 MB target from `CLAUDE.md`. Add to local operational dashboard sink too. ~1 h.

### Phase 2 — library-side foundation

**← START HERE.** This phase is the kickoff. The README expansion is the cheapest, lowest-risk first action and sets the scope contract that everything in Phase 2 is built against. Phase 1 connector items are independent and can happen in parallel.

- [ ] **Wire Exp 2 (`@timed` vs py-spy) verdict in the verify command** — probe's @timed-on-pre_process histogram captures are scaffolded (dumps p50/p95/p99 every 30 s); py-spy speedscope cross-read primitive (`exp2_timed_vs_pyspy.pyspy_p95_ms_for_function`) is implemented. Remaining: have `verify --experiment 2` accept a probe-output + speedscope path and run the comparison; OR fold both spawns into a single self-contained `verify --experiment 2` that runs the connector under both the probe AND py-spy in parallel sessions.
- [ ] **Self-contained `verify --experiment 1`** — currently the workflow is "run probe_runner externally, then run verify --experiment 1 --exp1-parity-log path." Fold the connector spawn into the verify command directly so a single CLI invocation produces a verdict. Will need to handle the PYTHONPATH override (lib is 0.0.3 in the connector venv; harness lives only in the unpushed v1 source).
- [ ] **Tune Exp 3 pass threshold** — first standalone run on the plan's parameters (reservoir=1000, N=18000, log-normal) hit 12% spread vs the plan's 8% threshold. Either the threshold is too aggressive for those parameters or `ReservoirHistogram` has more variance than ideal; investigate before treating Exp 3 as a real gate.
- [ ] **Pre-push verification gate** — Exp 1 ✅; Exp 2 still requires the verify-command wiring; Exp 3 threshold tuning. Push blocked until all three pass; experiments 4-5 are post-PR.
- [ ] **Push branch + open PR** *(blocked by gate)* — `git push -u origin feature/actuate-instrumentation-v1`; preserve `[major:actuate-instrumentation]` in squash subject; strip dev-bump bot lines from squash body.
- [ ] **Connector dogfood PR** — replace inline tracemalloc block in `_log_memory_breakdown` with `actuate_instrumentation.memory.tracemalloc_top`; keep existing log-line format. ~half-day.
- [ ] **Remove `LogTimeElapsedMixin` from `actuate-log`** — next minor after `actuate-instrumentation` 1.0.0 lands (one-cycle overlap).

### Phase 2.5 — easy-fix candidates surfaced by first report (2026-05-14)

- [ ] **cv2 `dst=` preallocation in `actuate-movement`** — [aegissystems/actuate-libraries#348](https://github.com/aegissystems/actuate-libraries/issues/348). Implementation + numerical-equivalence tests done; library PR [#349](https://github.com/aegissystems/actuate-libraries/pull/349) + connector test PR [#1696](https://github.com/aegissystems/vms-connector/pull/1696) both draft, CI green for 3 days. Webcam fixture validated 2026-05-18. **Updated 2026-05-19: do NOT promote #349 to stable yet.** Plan: keep #349 draft, keep #1696 on the `1.2.7.dev1+...` dev pin, deploy the dev-pinned connector branch to a real customer site via connector_deployer first, soak, then promote.
  - [ ] Pick soak target site (TBD — avoid co-stacking with [[2026-05-19_pyav17-ffmpeg8-migration|#1703]] candidate cust 41399 if possible)
  - [ ] **Deploy `feature/test-actuate-movement-cv2-dst` to the soak target site — use §29's new admin-API custom-branch deploy flow (PREFERRED) once it's wired, OR connector_deployer as fallback.** *(blocked by §29 per-customer endpoint bodies + DeployBranchActionMixin wire-in)*. Pinned for 2026-05-21 follow-through: if §29 lands its per-customer surface today, this is the first end-to-end customer of the new flow and validates the deploy-lifecycle path against a real branch with bundled connector changes (cv2-dst + #1694). If §29 slips, fall back to connector_deployer same-day rather than further delay. Verify the cronjob's `container_image` tag is slash-encoded either way (`feat-foo` not `feat/foo`) — see `feedback_check_image_tag_after_deployer_push`.
  - [ ] Soak 24–48 h, compare RSS slope + motion-event counts + alert verdicts vs same-site `rearchitecture` baseline
  - [ ] If clean → ready #349 → merge → bump #1696 pin to stable → merge to stage
  - [ ] If regressed → keep dev pin, iterate on library branch
  Original (now superseded) merge-tomorrow handoff is in [[2026-05-19_handoff-cv2-dst-stage-deploy]] for reference.
- [ ] **Investigate SSL-context churn in vms-connector** — [aegissystems/vms-connector#1693](https://github.com/aegissystems/vms-connector/issues/1693). 1.25 M `ssl_wrap_socket` calls (60% of all allocations by count). Confirm intent first (may be deliberate per-tenant isolation); if not, hoist to persistent `Session` / shared boto3 client.
- [ ] **Configurable `_log_memory_breakdown` interval (vms-connector)** — [aegissystems/vms-connector#1694](https://github.com/aegissystems/vms-connector/issues/1694). Root-cause why 390s memray run captured zero cycles, then expose the interval via env-var so verify-mode runs capture cycles.
- [ ] **memray flamegraph render hang on larger output.bin** — surfaced 2026-05-18 webcam validation run. Process goes to `S` state with 0% CPU; never produces HTML. Same root cause appears to break `memray stats --json` (report's allocation-hotspots section comes up empty). Fix: timeout the `subprocess.run` in the harness's `render_flamegraph` and fall back to stats-only. See [[2026-05-19_handoff-cv2-dst-stage-deploy#harness-papercuts-not-blocking-step-1-but-worth-landing-before-the-next-long-run]].
- [ ] **Drop `--idle` from py-spy invocation if set** — `expire_items` (TTLImageCache sleep loop) showing as 11% CPU is a measurement artifact. Check `runners/pyspy.py`. ~5 min, no GH issue needed.
- [ ] **Native `webcam-local` harness scenario** — current wrapper at `vms-connector/test_settings/run-webcam-profile.sh` swaps LOCAL_WEBCAM settings over LOCAL_RTSP to route around the missing scenario. Drop the swap when the harness lands stable.

### Phase 2.6 — PyAV/FFmpeg/OpenCV bump (#1703) — testing arc

[aegissystems/vms-connector#1703](https://github.com/aegissystems/vms-connector/issues/1703). PyAV 13.1 → 17.0.1, FFmpeg 7.1.3 → 8.1.1, OpenCV 4.11 → 4.13. Primary driver is MISS-685 (HEVC corruption / gray-frame missed detection). Supersedes older PR [#1621](https://github.com/aegissystems/vms-connector/pull/1621). Risk surface, breaking-changes audit, Graviton 4 CPU caveat: [[2026-05-19_pyav17-ffmpeg8-migration]]. Sequencing vs Live Streaming v1: [[2026-05-19_streaming-pyav17-crosscut]].

- [ ] Open `actuate-pullers` feature branch with the API renames (`av.AVError` → `av.FFmpegError` at 2 sites; `codec_context.skip_frame` strings → `SkipType` enum at 6 sites)
- [ ] Bump `pyproject.toml` pins (`av~=17.0.0`, `opencv-python-headless~=4.13`); bump FFmpeg in `docker_files/dependencies/build_ffmpeg.sh` to `n8.1.1` (or evaluate dropping the custom build entirely — see migration concept §"Drop the custom FFmpeg build?")
- [ ] Wait for dev wheel publish; pin dev wheel in a vms-connector feature branch
- [ ] Deploy via connector_deployer to **cust 41399 (Eyeforce: AmeriGas Sacramento)** — the MISS-685 site, known-bad camera; immediate signal
- [ ] Run 24–48 h soak; compare:
  - Stream-lost / broken-stream reconnect rate vs ~28/4h baseline on cam ST24-3
  - Snapshot preview quality in admin UI (no gray previews)
  - Inference detection rate (MISS-685 is a missed-detection case)
  - CPU per pod (Graviton bench predicts ~+5%; confirm or refute)
- [ ] If clean → deploy to 1–2 other HEVC-heavy sites for wider read
- [ ] Promote library to stable; bump connector pin; merge to `stage`
- [ ] Stage soak; if clean, promote to `rearchitecture` with `[minor:actuate-pullers]`
- [ ] Decide custom-FFmpeg-build fate (drop or keep) once the GPU connector roadmap is concrete

### Phase 3 — workflow tooling

- [ ] **Item 4: `/profile-on-stage` skill** — kubectl-debug sidecar (py-spy + memray + ptrace cap), record for N minutes, pull artifacts to `~/Documents/worklog/profiles/YYYY-MM-DD/`. ~1 day.
- [ ] **Item 6: Memory regression baseline file + PR diff comment** — `.perf-baselines/memory.json` in vms-connector; CI runs `frame_deletion_memory_test.py`, posts PR comment on >threshold delta. ~1 day (deterministic-environment risk).

### Phase 4 — production observability (separate workstream once Phase 1-3 ground)

- [ ] **Item 7: Profiler sidecar `ACTUATE_PYSPY=1`** — Helm-toggleable; py-spy attaches to main container PID via `shareProcessNamespace: true` + `CAP_SYS_PTRACE`; dumps to shared volume, uploads to S3 on shutdown. Touches `vms-connector`, `kubernetes-deployments`, `connector_deployer`. ~3–5 days when scheduled.

### Watchlist

- [ ] **Python 3.15 migration** — revisit `profiling.sampling` adoption when connector reaches 3.15. Hard blocker is profiler/target minor-version match. Tracked also in `docs/OPTIMIZED-CONNECTOR.md` 3.13/3.14 evaluation sections.

### Out of scope

Rust hot-loop acceleration, GStreamer puller alternative, scalene adoption, full OpenTelemetry stack — referenced in [[2026-05-12_profiling-toolkit-and-roadmap]] decision log.

### Related

- §6 (Software Architecture) — any local prototype that touches the inference path benefits from Phase 2 timing primitives
- §18 (Memory-limit drift) — Phase 1 item 5's dashboard tile directly supports this workstream
- §28 (Billing Pipeline) — billing-emit overhead is one of the future targets for per-stage timing
- KB topic: [[profiling-and-performance/_summary]]
- Roadmap synthesis: [[2026-05-12_profiling-toolkit-and-roadmap]]
- 3.15 brief: [[2026-05-12_python-3.15-profiling-sampling-watchlist]]
- Tooling inventory: [[tooling-inventory]]
- Adjacent connector docs: `docs/OPTIMIZED-CONNECTOR.md` (82 KB authoritative roadmap)

---

## 32. Local Test Stack — expand beyond AutoPatrol to every connector run type

**Priority:** This-week. Builds on the AP-validated harness ([[2026-05-20_local-ap-e2e-stack-installed]]).
**Status:** Scoped 2026-05-20. AP path works end-to-end. Spec + expansion start 2026-05-21.

### Why

The harness at `/home/mork/work/local-test-stack/` already drives a single AutoPatrol run through the full vms-connector → SQS → autopatrol-server chain with no real AWS (LocalStack + Immix monkey-patch). Cost was ~half a day; payoff was immediate (validated the AP-summary-disable change before opening PRs). The pattern generalizes — every other connector run type has the same shape: settings.json + factory + site manager + lifecycle → side-effects. With seed extensions + a settings file per run type we get a laptop-resident validation harness for the whole connector surface.

### Run types to cover

- [ ] **Analytics (main RTSP / Milestone / Avigilon / etc.)** — the dominant path. Most cameras, longest-running, hits inference pool + alerting + S3 frame writes. Probably needs a mock inference endpoint or stubbed YOLO client.
- [ ] **Camera Health Monitoring (CHM)** — periodic health metrics emit. Probably less infra-dependent than Analytics; check what DDB/SQS targets it touches.
- [ ] **Video Camera Healthcheck (VCH)** — the "verified clip" path with `_end_patrol_once`. Touches autopatrol API + SQS. Confirm whether it needs its own emulator targets (autopatrol-server consumes from a different queue, possibly).
- [ ] **AutoPatrol (DONE — 2026-05-20)** — baseline. ✅
- [ ] **Generic Patrol** — `PatrolSiteManager` (distinct from AutoPatrol). Same SQS path? Verify.
- [ ] **Clip-related runs** — verify which mode is "clip-only" (Verifier?). Some path raises clips to an inference pool without the full Analytics loop. Need to inventory.
- [ ] **Spray / low-confidence / blacklist** — sub-flows of Analytics, not separate run types, but worth confirming the stack covers them.

### Spec deliverables

- [ ] Inventory: enumerate every `Factory` subclass in `connector_factories/`, map each to a run type + the AWS resources it touches (SQS queues, DDB tables, S3 buckets, external APIs). Use the `connector-pipeline-expert` agent.
- [ ] Settings catalog: identify or stage a minimal `test_settings/*.json` for each run type that routes to LocalStack-side resources (queue_stage=dev pattern works for AP; verify analogs for others).
- [ ] Stub catalog: for each external API touched (Immix already done; possibly admin API, inference endpoints, queue_consumer-side), spec the stub shape and where it lives in `pythonpath/sitecustomize.py` or a new entry.
- [ ] Seed extension: list new SQS queues / DDB tables / S3 buckets / secrets the seed script needs for each run type. Capture real prod key schemas via `aws dynamodb describe-table` where placeholder `id:S` doesn't suffice.
- [ ] Runner scripts: one `run-<runtype>.sh` per run type (or a single `run-connector.sh <runtype>` dispatcher).
- [ ] Per-run-type validation procedure documented in `topics/local-test-stack/notes/syntheses/`.

### Phase plan

1. **Phase 0** — Spec (`topics/local-test-stack/notes/syntheses/2026-05-21_runtype-expansion-spec.md`). ~half day.
2. **Phase 1** — Analytics first (largest unlock). ~1 day.
3. **Phase 2** — VCH + CHM. ~half day each.
4. **Phase 3** — Generic Patrol + Clip-related. ~half day each.
5. **Phase 4** — CI gating (run the full stack on PR open against multiple connector branches). Future work, gated on whether Phases 1-3 stay green for a few weeks.

### Stretch goals

- [ ] Real RTSP frame ingestion via the existing `rtsp-camera-simulator` container — point a test camera at it and assert detections flow through the inference stub.
- [ ] Real DDB schema fidelity — dump every prod schema we hit and update `seed.sh` so writes succeed instead of relying on the broad try/except in service code.
- [ ] One-shot harness exits with non-zero rc if expected Immix-call fingerprint doesn't match — turns the validation into an assertion not just a recording.

### Cross-references

- [[local-test-stack/_summary]] — topic.
- [[2026-05-20_local-ap-e2e-stack-installed]] — what we built first.
- [[2026-05-20_localstack-vs-elasticmq-decision]] — emulator choice.
- §30 (Profiling & Optimization) — adjacent infra work; coverage of the same code paths but for performance not lifecycle.

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
- [ ] **`NoneType unpack` error 3x-up drill** — 5,174 events in last 12h vs 1,699 prior 12h (`cannot unpack non-iterable NoneType object`). One-shot investigation; schedule into a morning-followup. **2026-05-04 update:** still active — `create-detection-window` is the top container today at ~3,200-5,800 errors / 24h (per fleet_error_top15 triage). Possibly a new high-water mark vs the 2026-04-22 baseline. Priority bump: this is the #4 source of fleet ERROR volume today, behind connector-deploy VPA noise + 2 dw_url_up sites (one fix in flight via PR #1671).
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

### From §21 — post-archive (2026-05-04)

§21 archived 2026-05-04 ([[2026-05-04]] § "Closed Workstreams"). Two forward-looking items remain to track:

- [ ] **`silent_drop_inverse` calibration on billing signals** — once 7d of history accumulates (~2026-05-10), confirm the rule on `vch/chm/autopatrol/analytics/fleet_billing_emit_6h` doesn't false-positive on weekend traffic dips. Tune `yellow_below` if needed. Signals at `~/.claude/skills/dashboard-check/config/signals.json`.
- [ ] **Optional sibling signal `vch_runs_6h`** — count of distinct VCH cronjob pods that ran. Pairs with `vch_billing_emit_6h` to show events-per-run alongside the absolute. Useful if the per-camera multiplier ever drifts (e.g., a new emit gap drops events-per-run from 10 → 6 without changing run count). Defer until a real symptom shows up.

### Generic config / settings integrity scanner — cross-project (2026-05-19)

Mark surfaced 2026-05-19 mid-Phase-1B: the pattern of "load real settings, parse through the production code, surface integrity issues" generalizes beyond vms-connector. AIT's `validate` (Phase 2) is the connector-specific instance, but other repos with config-driven behaviour (autopatrol-server, connector_deployer, actuate-inference-api, admin-API tenant settings, kubernetes-deployments helm values) all have the same shape of bug: a config field gets silently dropped / misinterpreted / mis-mapped because the parser's table is incomplete.

Two existing AIT findings illustrate the shape and value:
1. Branded vehicle ID metric keys missing from `METRIC_KEY_TO_AUTOPATROL_CODE` — fixed via [actuate-libraries#353](https://github.com/aegissystems/actuate-libraries/pull/353).
2. `non_ups` metric key also missing (still open, tracked in [[2026-05-19_ait-phase-1-diff]]).

A generic scanner would let us surface these classes of bug across repos without writing a per-repo tool each time.

Open design questions for a follow-up session:

- [ ] What's the right abstraction layer? "Walk a parsed config and surface fields not appearing in known mappings" feels right. Probably a `Scanner` base class + per-repo subclasses that supply (a) settings-fetch source, (b) parse function, (c) integrity-check battery.
- [ ] Where does it live? A new repo (`actuate-config-scanner`?) or as a subpackage of `actuate-integration-tools`? Lean toward separate repo with `ait` as a consumer once it grows beyond the vms-connector case.
- [ ] Discovery: how do we automatically find "fields that look like detection codes / metric keys / branded labels but aren't mapped"? Heuristics include enum-value membership, snake_case naming patterns, model-output label vocabularies. Probably starts manual (annotate known taxonomies per repo) and grows toward automated detection later.
- [ ] What's the trigger model? Manual CLI invocation (like `ait`)? Scheduled fleet sweeps? Pre-merge git hooks? Likely all three eventually.
- [ ] Integration with the existing dashboard signals (`~/.claude/skills/dashboard-check/config/signals.json`) — could surface scanner findings as additional signals.

Not started — surface area is wide. Start with the focused tool (AIT phases 1-3) and let the generic pattern crystallize from concrete experience.

### actuate-integration-tools — what else should live here? (2026-05-19)

Created `/home/mork/work/actuate-integration-tools` 2026-05-19 — a standalone Python package that loads a real connector's `settings.json` from S3 (key pattern `actuate-settings/<deployment_id>/settings.json`, same code path the connector itself uses), parses it through `actuate-config`, and exposes derived properties via a CLI (`ait tier <deployment_id>`, `ait detections ...`, `ait dump ...`). Its first real-customer query (site 35831) surfaced a silent under-classification bug in `METRIC_KEY_TO_AUTOPATROL_CODE` that would have shipped to prod otherwise — branded vehicle IDs (`ups`/`fedex`/etc.) were missing from the table. Fix shipped same day via [actuate-libraries#353](https://github.com/aegissystems/actuate-libraries/pull/353).

The clear-win pattern: **load real customer config, parse through the actual library code, surface derived properties as a CLI — no connector boot, no NR logs needed.** That pattern is reusable for many other classes of question. Candidates to consider:

- [ ] **`ait diff <deployment_a> <deployment_b>`** — side-by-side comparison of two deployments' configs. Useful for "why is site A behaving differently from site B" debugging. Output: structured diff of detection codes, integration types, healthcheck flags, feature_deployments. Probably highest-impact next addition.
- [ ] **`ait validate <deployment_id>`** — runs every `actuate-config` constructor assertion + a few semantic checks (e.g. patrol_type matches integration_type, branded vehicle ID feature_deployments are paired with a base intruder/vehicle deployment, etc.) and surfaces failures. Effectively pre-flight checks before customer-facing deploys.
- [ ] **`ait scan-fleet --metric-key foo`** — sweeps every deployment in the `actuate-settings` bucket and reports which have a specific metric key configured. Useful for "how many sites have CROWD enabled?" / "where is feature X used?" answers. Bucket-scale risk: lots of S3 calls; bound it with prefix-listing + selective fetch.
- [ ] **Mock Immix endpoint** for testing AutoPatrol API flows without touching live Immix. Different shape from the CLI tools — would be a fastapi server you point a feature-deployment at. Larger scope; defer until there's an active test case demanding it.
- [ ] **`ait audit-tier-emissions`** — given a deployment_id, predict the tier it *should* emit per the spec, then NR-query its recent `raise_patrol_alert` log lines and assert they match. Useful for catching drift between config and runtime behaviour (e.g. if the library is bumped on one branch but not another).
- [ ] **Property-based testing harness** — given a real settings.json, generate variations (drop cameras, swap detection types, mutate feature_deployments) and assert invariants hold. Helps catch the "configured set is empty → tier defaults to 1" class of bug *before* shipping.
- [ ] **Library: add a `logging.info` line in `autopatrol_api.get_patrol_stream`** before the request so the `Tier=N` query param becomes NR-observable. Closes the live-validation gap on the stream-fetch tier surface that the actuate-pr-reviewer flagged on PR #1699.

Promotion criteria: when the tool has 3+ subcommands actively used and another contributor wants to extend it, promote `/home/mork/work/actuate-integration-tools` to its own GitHub repo (`aegissystems/actuate-integration-tools`) and wire up CI. Until then, keep it as a local-only repo to avoid premature governance overhead.

### VCH multi-frame entropy + AutoPatrol tier work — merge follow-up (2026-05-18)

Validated on Eyeforce site 16258 over the weekend: NOVIDEO alerts dropped from 39/39 baseline to 0–8 per run (~91% drop), multi-frame drain working, alert copy `"Camera Image Blank"` confirmed in raw payloads. Source: [[2026-05-15]] § Closed Line Items.

Branch sits at `feat/vch-multi-frame-quality-sampling` HEAD `572f33478` (vms-connector). It currently bundles two unrelated things: (a) the VCH multi-frame + copy fix (validated on Eyeforce); (b) AutoPatrol tier dev-pin bumps to four `actuate-libraries` dev wheels (NOT validated end-to-end yet — VCH-only site doesn't exercise the patrol-wide tier path).

To merge to `stage`:

- [ ] **Open the actuate-libraries PR for the tier work** — branch `feat/autopatrol-tier-from-configured-codes` is pushed to actuate-libraries with the helper + accessor + sender/puller wiring. PR to `main`. Squash subject must carry the right `[patch:<lib>]` tags for each of the 4 changed libs (or split into per-lib PRs if reviewers prefer); strip any auto-bump commit lines from the squash body so CI publishes stable.
- [ ] **Wait for stable publish**, then bump the connector's `pyproject.toml` from the 4 dev pins back to the published stables (`actuate-integration-calls`, `actuate-config`, `actuate-alarm-senders`, `actuate-pullers`). Run `uv lock` with CodeArtifact auth.
- [ ] **Validate AutoPatrol tier path on a non-VCH AutoPatrol site** — VCH=Tier 1 path is unchanged so Eyeforce alone is insufficient. Pick an AP patrol with mixed intrusion + threat detections configured and confirm both `get_patrol_stream` and `raise_patrol_alert` carry the patrol's highest configured tier. Spot-check raw payloads.
- [ ] **PR vms-connector → `stage`** — base `stage` per [[feedback_feature_branches_target_stage]]. Pre-merge: confirm no `.devN+` pins remain in `pyproject.toml`/`uv.lock`, CHANGELOG entry covers both pieces of work.
- [ ] **Stage → rearchitecture promotion** in its own PR per the established workflow. Bundle into the next `/pre-merge-workflow` batch if convenient.

Side items (separable):

- [ ] **Bring [[2026-05-14_chm-multi-frame-quality-sampling-followup]] off the shelf** once the VCH soak has accumulated ~2 weeks of green: decide whether to flip `_score_full_clip = True` on non-VCH `*HealthcheckCamera` subclasses (RTSP/DW/Avigilon/Exacq/Hikcentral/Openeye/Star4Live). Needs a metric review first (max vs median aggregation, S3-cost impact).
- [ ] **Track [aegissystems/connector_deployer#171](https://github.com/aegissystems/connector_deployer/issues/171)** — slash-in-tag bug. Not blocking the VCH merge (we worked around it via `kubectl patch`), but every future feature-branch deploy with a `/` will hit it until fixed.

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

---

## 33. RDS Postgres extended-support upgrades

**Priority:** current (cost + EOL — ~$613/mo extended-support surcharge; PG12 Year-3 cost-cliff ~Mar 2027)
**Tickets:** [BACK-625](https://actuate-team.atlassian.net/browse/BACK-625) (supportwiki, To Do) · [BACK-673](https://actuate-team.atlassian.net/browse/BACK-673) (jobschedulerdjangoq + dev EU Aurora, filed 2026-06-03)
**Status:** supportwiki **UPGRADED to PG16.11 2026-06-17** (verified, rehearsed first) — saves $297.60/mo; other two DBs not yet started
**Runbook:** [[2026-06-02_rds-extended-support-upgrade-runbook]]

Three Postgres DBs on EOL majors incur AWS RDS Extended-Support surcharges (real CE figures, May 2026). Target **PG16** — single-step `12.22→16.11` / `13.20→16.11` direct upgrade verified for all three. Full procedure + CLI + rollback in the runbook.

| DB | ver | acct/region | $/mo |
|---|---|---|---|
| actuateadminsupportwiki | PG12 (Multi-AZ) | prod / us-west-2 | $297.60 |
| jobschedulerdjangoq | PG13 | prod / us-west-2 | $148.80 |
| actuate-dev-eu-west-1-aurora-writter | Aurora PG12 | dev / eu-west-1 | $166.66 |

### Open work

- [x] **Apply #99 → supportwiki PG12→16.11** — DONE 2026-06-17 ~20:30 UTC (immediate, not the window). Snapshot taken, preflight clean, **fixed module bug** (`allow_major_version_upgrade` never wired to standalone-instance path; commit `f86c599`), **dress-rehearsed** (snapshot→temp→PG16, schema+data parity confirmed), then real `--apply-immediately`. Verified: 16.11/default.postgres16, schema md5 + rowcounts match (cms 102/9751, kbcms 37/5481), VACUUM ANALYZE done, error log clean, kb+support.actuateui.net 302→login→200.
- [ ] **Final confirmations (supportwiki):** human logged-in article/search spot-check on kb+support.actuateui.net; surcharge→$0 in Cost Explorer (~48h); transition BACK-625 Done; delete pre-pg16 snapshot after ~30d.
- [ ] **Apply #99 → jobschedulerdjangoq PG13→16.11** — single-AZ; coordinate with `job_scheduler` ECS service (no quiet window). Same snapshot→apply→ANALYZE→verify flow. (module fix `f86c599` now unblocks this standalone-RDS path too.)
- [ ] **Apply #100 → dev EU Aurora PG12→16.11** — dev/low-risk; snapshot first (retention only 1d) → `terragrunt apply` → `ANALYZE` → verify surcharge→$0. Also weigh r6g.large right-size / whether dev EU Aurora is still needed.
- [ ] **Verify surcharge → $0** next Cost Explorer cycle after each apply.

### Related

- [[2026-06-02_rds-extended-support-upgrade-runbook]] — e2e procedure
- §28 Customer Billing Pipeline · §9 dashboard cost signals

---

## 23. Obsidian Web Clipper viability evaluation (follow-up)

**Status:** queued — not blocking
**Priority:** P3
**Surfaced:** 2026-05-03 during `/dev-kit` lift-and-shift session
**Spec:** [[obsidian-clipper-evaluation]] (`topics/obsidian/notes/entities/obsidian-clipper-evaluation.md` — written into the dev-kit's KB scaffold; mirror it into the live KB when this picks up)
**Upstream:** https://github.com/obsidianmd/obsidian-clipper

### The question

Can the kit's source-ingestion pipeline (`/kb-ingest`, `/kb-queue`, `/kb-auto`) use [Obsidian Web Clipper](https://github.com/obsidianmd/obsidian-clipper) — directly OR by drawing inspiration from its architecture — instead of the current HTTP-fetch + retry loops? Web Clipper handles the parts the current loops handle poorly: JS-rendered pages, paywalls (logged-in user), iframe-loaded content, lazy images, boilerplate-stripping.

### Open work

- [ ] **Failure-mode distribution audit** — what's the actual breakdown of fetch failures in `reading-list.md`s today? Need data, not intuition. Probably one Sunday afternoon's worth.
- [ ] **kb-starter Rule 23 fit** — does kb-starter's existing Clippings-folder convention give us most of "Path A — direct integration" for free?
- [ ] **`/kb-auto` headless-vs-Web-Clipper-interactive trade-off** — Web Clipper requires a click. Does losing headless overnight ingestion matter for actual usage patterns?
- [ ] **Decide: A (direct integration), B (inspired-by, build server-side w/ Playwright), or C (hybrid — Web Clipper for problematic domains, HTTP-fetch for the rest).** Likely answer: C.
- [ ] **If picking A or C** — wire `/kb-queue` to scan the `clippings/` folder and process new items.
- [ ] **Mirror [[obsidian-clipper-evaluation]] from dev-kit/kb-scaffold into live KB at `topics/obsidian/notes/entities/`** — currently it only exists in the dev-kit staging.

### Context

Surfaced while building out the `dev-kit` lift-and-shift package. The dev-kit's `obsidian-cli/` retrieval ladder is the read-side context-efficiency play; this is the corresponding write-side / ingestion play. Per user direction (2026-05-03): **devbox kit work takes priority; this is a follow-up only.**

---

## 24. Internal LLM shop on `npu-server` (shared, multi-purpose)

**Topic:** [[llm-shop/_summary]] · **Host:** [[host-npu-server]] · **Architecture:** [[2026-05-04_llm-shop-initial-architecture]] · **Phase 1 record:** [[2026-05-04_phase-1-installed]] · **Phase 2 design:** [[2026-05-04_phase-2-day-to-day-usage]] · **Next-steps menu:** [[2026-05-05_phase-2-next-steps]] · **Pi integration:** [[pi-dev-integration]] · **Model-routed proxy + sync:** [[2026-05-06_model-routed-proxy]]

Status (2026-05-11): Phase 2A/2A.2/2B/2C/2D.1/2D.2/2F/2G/2H + kb-deep-intake shipped. Status + Playground + Catalog + Peers at `http://npu-server.tail9b2a4e.ts.net:8080/`. OpenAI-compat at `:11434/v1` (CPU Ollama) and `:8200/v1` (iGPU SYCL 14B). `/api/proxy/chat` routes by model name. `~/llm-shop/` mirror source-controlled (commits `0eec65c` + `e62252f`).

| Phase | State |
|---|---|
| 1 — Foothold | ✅ status page, Ollama (6 models pulled, hot-swap proven), NPU (TinyLlama) |
| 2A — Multi-page dashboard | ✅ Status / Playground / Catalog / Peers w/ shared nav, `/api/proxy/chat` streaming |
| 2A.2 — Model-routed proxy + source-control sync | ✅ 2026-05-06 — see [[2026-05-06_model-routed-proxy]]. Drops `backend` field; SYCL→playground works; SSE→NDJSON adapter for llama.cpp. |
| 2B — IDE/Pi exposure | ✅ Ollama on `0.0.0.0:11434` + SYCL on `:8200/v1`; configs on `/catalog` |
| 2C — `llm-shop-delegate` subagent | ✅ at `~/.claude/agents/` |
| 2D.1 — `code-delegate` harness | ✅ `:8100`, task_type-aware system prompts |
| 2D.2 — `kb-intake` harness + `~/bin/kb-intake` CLI | ✅ shipped 2026-05-05 (URL → readability → llama3.1:8b → draft to `_research-inbox/`). Closes [[obsidian-clipper-evaluation\|§23]]. |
| 2E — Status page UX polish | ⏳ backlog (warm-up button, model live state, NDJSON log, iGPU/NPU util, runtime banner) |
| 2F — kb-todo agent | ✅ `~/bin/kb-todo-{scan,research}`, both source-controlled in `local_network_scripts/files/`. Polish backlog in [[2026-05-05_first-real-tasks-experiments]]. |
| 2G — SYCL 14B service | ✅ live on `:8200`, qwen2.5-coder:14b-instruct-sycl, ~3.4 tok/s output / 5.4 tok/s prompt on iGPU |
| kb-deep-intake module | ✅ shipped 2026-05-07; e2e validated. See [[2026-05-07_kb-deep-intake-architecture]]. |
| 2H — Overnight batch plumbing | ✅ shipped 2026-05-11. `kb-batch-{submit,pull,status}` (laptop) + `kb-batch-runner.py` + `llm-shop-kb-batch@.service` (box). Smoke: 2-URL ollama-backend run merged cleanly to `_research-inbox/`. Design: [[2026-05-07_overnight-batch-pattern]] §"Build log". |
| 3 — Federation | ⏳ deferred until ACL tags + multiple shops |

**Open work for next session:**

- [ ] **`llm-shop-sycl-7b.service`** on `:8201` (qwen2.5-coder:7b-instruct gguf). Proxy port already reserved in `SYCL_PORTS`. Need `Conflicts=llm-shop-sycl-14b.service llm-shop-sycl-8b.service` so only one runs at a time (single iGPU). Mirror the 14b unit template.
- [ ] **`llm-shop-sycl-8b.service`** on `:8202` (llama3.1:8b gguf). Same pattern as 7b. Prereq: pull/convert llama3.1:8b gguf (currently only Ollama-format on disk).
- [ ] **Phase 2E status page polish** — warm-up button, model live state, NDJSON log viewer, iGPU/NPU util banner.
- [ ] **IPEX-LLM evaluation** as faster alternative to llama.cpp+SYCL on Intel iGPU (heavier setup; should beat current ~3.4 tok/s on 14B).
- [ ] **`eval_count` cosmetic fix** in `_stream_sycl` — null on `done` events because llama.cpp's stats chunk shape doesn't always carry `usage.completion_tokens` where the adapter looks. `predicted_per_second` works.
- [ ] **Composer prompt tuning** — planner side landed 2026-05-11 (commit `7b05908`); composer-side observations (key claims sometimes echo source verbatim, occasional flat sections, off-topic placements like livekit→actuate-platform) carry forward to a future tuning pass.
- [ ] **SYCL queue-health pre-flight** — `kb-batch-doctor` or pre-submit check that detects stale clients holding the SYCL request slot. Auto-recovery now in-runner via `c186107`; pre-flight would save the K=2 trigger cost on a known-wedged queue.
- [ ] **Validate pipeline enhancements on a real batch** — 2026-05-18 shipped 5 pre-batch quality gates to `kb_deep_intake` (min-content gate in parser, topic-description map in planner, SYCL-14B relevance pre-check, post-plan substance check, submit-side URL dedup). Deployed to box; thin-page test confirmed `parser_too_thin` short-circuits at zero LLM cost. Next batch run will exercise the relevance gate (`high|medium|low`) and topic-description routing live. Code in `local_network_scripts/files/llm-shop/harnesses/kb_deep_intake/` (uncommitted as of 2026-05-18).

**Open questions inbox** (different idea — sketched 2026-05-05): [[2026-05-05_open-questions-inbox-idea]]. Schedule alongside Phase 2E.

**Deferred — needs admin help (tracked on [[host-npu-server]]):** SSH password rotation; tailnet ACL tags `tag:llm-shop`/`devbox`/`office`; tailnet HTTPS Certificates enable; push firebat pubkey to npu-server.

**Hard constraints** (don't relitigate; full detail in architecture ADR): all work in `~/llm-shop/`; tailnet-only; cgroup-RAM-capped; never starves Watchman.

---

## 25. actuate_admin schedule -> customer -> cameras cascade hook (Cohort B fix) — ARCHIVED 2026-05-07

> **Decision (2026-05-07):** no backfill, cascade hook stays flag-disabled. `actuate_admin#2406` shipped behind `AUTOPATROL_SCHEDULE_CASCADE_ENABLED=False`; standalone PR `#2405` redundant; mgmt command `#2408` paused open.
>
> Full ADR: [[2026-05-07_cohort-b-no-backfill-decision]]. Workstream archived to [[2026-05-07]] § Closed Workstreams. Re-open conditions tracked in [[autopatrol-deferred-backlog]] §"§25 Cohort B no-backfill decision".

---

## 26. Cohort F subgroup investigation + §16 hardening tail — DEFERRED 2026-05-07

> **Deferred 2026-05-07.** PR [autopatrol_onboarder#14](https://github.com/aegissystems/autopatrol_onboarder/pull/14) (Cohort F deep classifier) drafted; not blocking customer-facing work after the 2026-05-06 reframe in [[2026-05-06_cohort-f-investigation]]. All sub-items (classifier run, Snowflake export script, lifecycle/cohort dashboard signals, §16 Steps 5+6, Jira closeout) moved to [[autopatrol-deferred-backlog]] § "§26 Cohort F + §16 hardening tail". Re-open trigger: real customer-side complaint or merge of PR #14.

---

## 27. AutoPatrol — demote autopatrol-created groups to sub-groups (2026-05-05 incident) — DEFERRED 2026-05-07

> **Deferred 2026-05-07** (twice-deferred prior). The 2026-05-05 incident root cause (contract POST 100% failing for 7+d) was resolved by the same-day admin deploy that fixed the `customer_name` unique-constraint collision. The demotion is preventative for the next round. Sub-tasks moved to [[autopatrol-deferred-backlog]] § "§27 Group demotion PR 1". Re-open trigger: ops reports manual-promotion volume becoming painful, OR new contract-POST collision pattern emerges.

---

<!-- BEGIN-AUTOSYNC-JIRA -->
## Current Jira Queue (auto-synced)

**Last synced:** 2026-06-22
**Source:** `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`

This section is **fully replaced** on every sync by the `jira-sync` automation (see [[automation-jira-sync]]). Manual edits in this section will be lost — add notes against tickets in the workstream sections above instead.

### Ready to Deploy (6)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| ENG-246 | Medium | Task | actuate-instrumentation: extend to better support performance instrumentation *(tracked in §30)* |
| ENG-282 | Medium | Task | Custom-branch lifecycle: branch-scoped admin endpoints + vms-connector CI/CD cleanup wiri… *(tracked in §29)* |
| ENG-136 | High | Task | PyAV upgrade 13.1 → 17.0 (nogil pixel conversion) |
| CS3-31 | Highest | Sub-task | Automatically update the reference image |
| CS3-58 | Lowest | Task | Configuration per camera |
| CS3-323 | High | Bug | Discrepancy in cam count btwn dashboard and report |

### In Progress / In Review (6)

| Ticket | Status | Priority | Type | Summary |
|--------|--------|----------|------|---------|
| ENG-300 | In Progress | Medium | Task | Watchman watch-management service: fleet & scheduling architecture design |
| ENG-352 | In Review | Medium | Task | AutoPatrol per-camera tier + crowd-not-Tier3 escalation fix |
| ENG-309 | In Progress | Medium | Task | PyAV 13.1.0 → 17 upgrade: vms-connector + watchman-internal (AmeriGas soak) |
| ENG-289 | In Progress | Medium | Task | autopatrol_onboarder: track local ops tooling + post-deploy verification |
| ENG-269 | In Progress | Medium | Task | actuate_admin: automated endpoints for deploying/managing custom branches *(tracked in §29)* |
| ENG-247 | In Progress | Medium | Task | Research: move away from raw SQL access to postgres in non-admin contexts |

### To Do (4)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| CS3-537 | High | Sub-task | Add resolved_user to each healthcheck_sites on the api/healthcheck_result/rollup/ call |
| ENG-183 | Medium | Task | S3 Cost Reduction — Ranked Action Plan |
| CS3-505 | Medium | Sub-task | add outcome to the API for CHM alerts |
| ENG-94 | Medium | Task | Deferred alerts: send without frame as fallback when cache expires |

### Open (1)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| BT-259 | Medium | Bug | "Use Motion" toggle bug |

<!-- END-AUTOSYNC-JIRA -->

---

<!-- BEGIN-TODAY-SCOPE -->
## Today's Scope (2026-06-22)

Picked via [[skill-daily-scope|/daily-scope]]. **OFFBOARDING WEEK — last day Fri 2026-06-26.** Full plan of attack: [[2026-06-22_offboarding-plan]]. Tracked in Jira: **[ENG-375](https://actuate-team.atlassian.net/browse/ENG-375)** (epic) + ENG-376…382 (WS-A…E), all assigned to Mark, closes Fri. Line items close via [[skill-daily-wrap|/daily-wrap]] at EOD.

> **Guiding principle:** Mark's access dies Friday EOD. Re-home anything that authenticates as Mark, mirror anything on a personal account, write down anything only in Mark's head. Order by *"breaks silently when Mark leaves."* Effort split: land cheap PRs today, then all-in on handoff/persistence (no Envera cutover, no new code).
> **Health (06-22 cache):** RED but chronic — `billing_unbilled`=2510, `no_patrols`=33, OOM offender connector-44712=23, `cost_s3_tier3`=$202/day. Nothing new-critical; not blocking offboarding work.

- [ ] **Push markkb 11 commits** — last push 2026-05-22; a month of KB work is unpushed and only on Mark's laptop + personal `actuateMark` remote. Push first thing — no-brainer. *(Plan WS-B)*
- [ ] **Kick off firebat identity re-home (external asks)** — has lead time, needs other people. Raise Monday AM: (1) Tailscale admin reassign `mork-firebat` + npu-server device ownership off `mark@`; (2) org GitHub machine account / PAT to replace personal `actuateMark` gh auth; (3) team AWS IAM identity for the `dashboard-check` profile. *(Plan WS-A — critical path)*
- [ ] **Land cheap MERGEABLE PRs + freeze** — onboarder #14/#15/#16 (ENG-289); admin #2506 (⚠️ admin main = prod; re-run `makemigrations --check`); commit the squash-body CI-skip skill fix; triage actuate-libraries main orphan tests. Then freeze code. *(Plan WS-0)*

**This week (sequenced in plan):**

- **WS-A** finish identity re-home + verify every timer runs green (Tue).
- **WS-B** privacy-scrub + mirror markkb & claude-config to aegissystems org (Wed).
- **WS-C** Confluence handoff page + reassign all open Jira/PRs + Envera cutover runbook (Tue–Fri).
- **WS-D** firebat / npu-server / dashboard operating runbooks (Wed–Fri).
- **WS-E** decommission + teammate-vantage verification + dead-man's checklist (Fri).

**Frozen / handed off (not finishing personally):**

- **Envera TLS hardening + cutover** — hand off with exact runbook (scale master→0, rearch up, 60s queue retention, poll queue `envera_id`). *(was 🔝; frozen per offboarding effort split)*
- **PR #91** v5 split-intruder decision; **§18** VPA-floor PR; **§14** midnight arm-miss race; **§5** fleet-arch PoC pick — reassign via WS-C.

<!-- END-TODAY-SCOPE -->

<!-- BEGIN-MORNING-FOLLOWUPS -->
## Morning Follow-Ups (for 2026-05-22)

Time-bound checks seeded by [[skill-daily-wrap|/daily-wrap]] and consumed by the morning ritual ([[skill-daily-scope|/daily-scope]] or a future `/morning`). Each item is tagged with how it should be handled:

- **exec** — scriptable; the morning ritual runs it automatically during health fan-out and reports the result
- **verify** — needs user eyeballs on something specific; surfaced as a briefing line
- **decide** — requires a decision that should shape today's scope before picks

Consumed items get `[x]` and **immediately move to that day's daily note's `## Closed Sub-items` section** (rolling-forward convention 2026-04-27). Items not acted on roll over with a `*(rolled YYYY-MM-DD)*` qualifier.

> **Sweep history (2026-05-22):** 15 OBE items ticked + swept into [[2026-05-22#Closed-Sub-items]]. The rolled-forward set below was filtered against today's "Tracked as relevant" block in `## Today's Scope` — three items that already live there (rolling-restart, ghost cronjob, AP signal redesign) are not duplicated here. Previous swept dates' bullet history lives in their respective daily notes.

### Seeded for 2026-05-28 (PyAV-17 overnight soak) — swept to [[2026-05-28#Closed-Sub-items]]

### Seeded for 2026-05-23

- [ ] **verify**: vms-connector PR [#1711](https://github.com/aegissystems/vms-connector/pull/1711) T+24h post-merge soak (merged 2026-05-22 18:00 UTC, commit `8cd265c8f`). Expect `end_patrol succeeded on attempt 1/3` count climbing linearly; zero `attempt N/3 non-ok` / `raised` / `exhausted 3 attempts`; SMTP FDMD `warm-started motion detector from clip` still firing; `empty_metrics_dict` WARN active. Also check feature-branch-tag pod drain (`s3alerts` 6→0, `featvch-multi-frame-quality-sampling` 1→0) — once both clear, kubernetes-deployments [PR #392](https://github.com/aegissystems/kubernetes-deployments/pull/392) hold can release. *(seeded 2026-05-22 for 2026-05-23)*
- [ ] **decide**: PR #91 hand-review (in Today's Scope deferred line). Untouched 2026-05-22. *(seeded 2026-05-22 for 2026-05-23)*

### Seeded for next week (2026-05-26 / 2026-05-27)

- [ ] **investigate**: **Why does the NAT Instance Proxy hang?** Tonight was the only documented hang but it was zombied for 12h with no obvious trigger. CPU was 0.17% (no exhaustion), NetworkOut was 0 (couldn't have been congestion), instance had been up since 2023-03-01 (1135 days — possibly an uptime-related kernel issue). Check OS-level logs after a future hang (or rebuild on a newer Amazon Linux AMI + apply current kernel patches). Consider replacing the t3.micro NAT-instance pattern entirely. Driving incident: [[2026-05-24_genesis-no-alerts-milestone-token-rejection]]. *(seeded 2026-05-24)*



- [ ] **decide**: **Wire PagerDuty for AWS CloudWatch alarms** — CloudWatch `DjangoQ CPU High` alarm fired 2026-05-23 00:01 UTC via SNS topics `customer-warnings` + `Engineering-Alarms` (us-west-2, acct 388576304176) → email-only. No PagerDuty integration. Wiring path: create a PD service for "Actuate infra"; copy the Events API v2 integration URL; subscribe the SNS topic to that URL (HTTPS subscription, raw delivery off). ~15-30 min job. Apply to both SNS topics. Investigation context for the alarm that surfaced this gap: [[2026-05-22_djangoq-cpu-spike-v8-rollback-verify-scan]] (incident: an engineer fired `find_v8_sites.sh` with `xargs -P 16 aws s3 cp` in the `admin-scripts` screen on the prod admin EC2 box to verify intruder-v8 → intruder rollback completion across 28k connector settings; load avg hit 19.6 on an 8-vCPU box; renice +19 + ionice idle applied to recover; scan completed with zero v8 matches — rollback was clean).

- [ ] **decide**: **Prevent future "ad-hoc scan pegs the admin box" incidents** — driving incident 2026-05-22 `DjangoQ CPU High` (above). Today's lesson: a single engineer's parallel-subprocess scan saturated the prod admin web tier for 1-2h. Saturday evening saved us (2 requests in 3h on the AdminUIHttps ALB) but the same pattern hitting a weekday morning would burn user-facing latency hard. Possible prevention surfaces (decide which to invest in):
  1. **Tooling layer:** sanctioned helper script for bulk-S3-scan use cases — boto3 in-process with shared client + connection pool, not subprocess `aws cli -P N`. ~half-day to write + document.
  2. **Operational policy:** "admin-scripts screen on prod EC2 is for surgical commands only; bulk work goes on a separate utility box." Document in a connecting README or repo CLAUDE.md.
  3. **Infra layer:** move admin web tier off the single EC2 box onto ECS/EKS behind autoscaling. Bigger lift but eliminates whole class of "one big task pegs the box" risks. Probably overlaps with the §5 Fleet Architecture rethink.
  4. **Observability layer:** CloudWatch alarm on EC2 CPU is too late — fires after sustained 99%. Add a process-class alarm or NR infra agent on `i-035d255c2c64bb324` (currently has no NR instrumentation; only the EKS DjangoQ pods are in NR) so we get richer signals + faster page.
  5. **NR instrumentation gap:** today's recovery check tried to verify admin web latency via NR and discovered the EC2 admin host has no NR agent / no gunicorn log forwarding. Adding either would have shaved the verification time tonight from "look at ALB CloudWatch metrics manually" to "one NRQL query." Standalone follow-up regardless of the prevention decision above. *(seeded 2026-05-22 for next-week pickup)* *(seeded 2026-05-22 for next-week pickup)*

### Seeded for 2026-05-22

- [ ] **decide**: [connector_deployer#160](https://github.com/aegissystems/connector_deployer/issues/160) — orphan container cleanup. Issue still OPEN; 2 orphans observed (`51c72148`, `798e6dde`). Scope: decide approach (Option 1 recommended), draft the scan. *(rolled 2026-04-25 → 2026-04-27 → 2026-04-28 → 2026-05-22)*
- [ ] **exec**: Paste Jira ticket draft for **Immix zombie-tenant API contract violations** into AUTO project. Full draft at [[2026-04-29_immix-zombie-tenants]]. Pairs with the broader [[mark-todos#comprehensive-immix-tenant-failure-census]] expansion. *(rolled 2026-04-30 → 2026-05-01 → 2026-05-22)*
- [ ] **decide**: Cascade-disable propagation hooks — schedule → customer → site → cameras (per [[2026-04-30_admin-propagation-handoff]] + line 852). Partial overlap with §29 deploy-lifecycle work but cascade-policy is a distinct admin-side concern. Promote to active scope when the §29 staging promotion lands. *(rolled 2026-04-30 → 2026-05-01 → 2026-05-22)*
- [ ] **decide**: Recalibrate `connector_no_patrols_to_run_24h` thresholds — gated on PR #1662 reaching **prod** (currently in rearch via PR #1660; prod cut TBD). *(rolled 2026-04-30 → 2026-05-01 → 2026-05-22)*
- [ ] **exec**: File follow-up issue in vms-connector for direct unit tests on `connector_factories/shared/cleanup_emitter.py` (167 LOC, broad `except Exception`, zero direct tests). Tests should assert: emit fires under terminal exits, suppressed for pending/transient, no-op when env flag off, no-op when `schedule_id` empty. Surfaced in PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) review 2026-05-01. *(rolled 2026-05-01 → 2026-05-22)*
- [ ] **exec**: File follow-up issue (or one-line PR) for explicit `boto3.client("sqs", region_name=...)` in `cleanup_emitter.py:87` so a region-mismatched stage pod surfaces a distinguishable warning instead of opaque `NonExistentQueue`. Surfaced in PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) review 2026-05-01. *(rolled 2026-05-01 → 2026-05-22)*
- [ ] **exec**: KB synthesis closing the loop on YAM motion-bridge removal landing in connector — one-line update under `topics/vms-connector` YAM polygon-hint workstream noting PR #1660 closed the connector-side loop. Per global CLAUDE.md "After Work: Log to KB." *(rolled 2026-05-01 → 2026-05-22)*
- [ ] **exec**: §3 cleanup-Lambda correctness verify pass across the Immix-state matrix (Immix-Deleted / Immix-Suspended / Paused / genuine-offline). See §3 "Open work" — still the active path on that workstream. *(rolled 2026-05-07 → 2026-05-22)*

<!-- END-MORNING-FOLLOWUPS -->

---

## Discipline

- Update this note at the end of each working session where one of these workstreams moved.
- **Closed sub-items don't accumulate here.** When a `[x]` happens inside a §N workstream, the bullet moves into that day's daily note (`topics/personal-notes/notes/daily/YYYY-MM-DD.md`) under `## Closed Sub-items`. [[skill-daily-wrap|/daily-wrap]] Step 2.7 enforces this; the global `## Task Completion Ritual` instructs same-day distribution.
- **Never delete history.** Closed sub-items persist forever in their close-day daily note. Whole closed workstreams (§N) move to `## Closed Workstreams` in that day's note + a pointer row lands in this file's `## Archive` table. Pre-2026-04-27 history is preserved in `_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md`.
- When a new high-level TODO appears, add it via [[skill-todos-add|/todos-add]] — don't let work accumulate in chat-only form.
- Periodic audit (~weekly) via [[skill-todos-audit|/todos-audit]] — catches stale workstreams, orphaned Jira tickets, untracked branches, priority drift.
- Cross-repo opportunity sweep via [[skill-repo-scan|/repo-scan]] — surfaces high-impact + low-hanging-fruit GitHub issues that aren't assigned to Mark.
- **Weekly KB-tooling health check** via `~/bin/kb-tools-health` (or `ssh mork-firebat 'systemctl --user list-timers kb-*'`) — verifies the two firebat-side daily systemd timers are alive and converging:
  - `kb-relink.timer` (03:00 UTC daily) — Passes 1+2+3: wikilinks, tags, bare-topic rewrites
  - `kb-incoming-refresh.timer` (03:30 UTC daily) — Pass 4: backlink snapshot to frontmatter
  Healthy = both fired within last 36h AND recent runs show `wikilink_proposals/tag_proposals/incoming_updates` trending toward 0 (steady-state KB). If STALE: check `journalctl --user -u kb-relink -u kb-incoming-refresh` on firebat for failures, or that `~/.local/skills/kb-relink/relink.py` is current. See [[2026-05-01_context-efficient-kb-retrieval]] for the architecture this maintains.
- **Items in "Not-Yet-Prioritized" are not tracked in Jira** — if one becomes urgent, create a ticket and promote to a §N workstream.
- **Daily-note `topics:` + `workstreams:` frontmatter is the cross-reference primary key.** `grep -l "topic: autopatrol" topics/personal-notes/notes/daily/*.md` answers "what days touched X". Tag rigorously.

## Archive

Pointer table for fully-completed workstreams. Full content lives in the daily note linked on each row.

| Closed | Workstream | Daily note |
|--------|-----------|------------|
| 2026-04-23 | §1 Inference API v5 — finish for testing | [[2026-04-23]] |
| 2026-04-23 | §9-old AutoPatrol Alarm & Dashboard System (superseded by cross-repo §9) | [[2026-04-23]] |
| 2026-04-27 | §13 Subagent + cron MCP-bypass auth flow | [[2026-04-27]] |
| 2026-05-04 | §21 VCH SIGTERM billing-event fix (#1667/#1668) — verify + harden post-deploy | [[2026-05-04]] |
| 2026-05-04 | §16 Tenant-status sync gap — cascade-disable suspended tenants from cleanup Lambda | [[2026-05-04]] |
| 2026-05-04 | §22 Staging VCH startup crash (`KeyError: 'monitoring'`) | [[2026-05-04]] |
| 2026-05-07 | §25 actuate_admin schedule→customer cascade (Cohort B) — decided no backfill | [[2026-05-07]] |
| 2026-05-08 | §8 Multi-agent / multi-model setup for KB source research — subsumed by §24 LLM shop | [[2026-05-08]] |

## Related

- [[personal-notes/_summary|Personal Notes topic]]
- [[team-structure/_summary|Team Structure topic]]
- [[engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle|Feature Development Lifecycle]]
- [[agents-catalog]] — which agents help with which workstream
- [[automation-jira-sync]] — the daily job that refreshes the "Current Jira Queue" section
- Skills: [[skill-daily-scope|/daily-scope]], [[skill-daily-wrap|/daily-wrap]], [[skill-todos-audit|/todos-audit]], [[skill-todos-add|/todos-add]], [[skill-repo-scan|/repo-scan]]
- Pre-cleanup snapshot: `_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md`
