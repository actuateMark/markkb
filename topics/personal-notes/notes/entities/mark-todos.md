---
title: "Mark's High-Level TODOs"
type: entity
topic: personal-notes
tags: [todos, mark, work-plan, priorities, personal]
created: 2026-04-16
updated: 2026-05-11
author: kb-bot
last_wrap: 2026-05-08
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

### Review + PoC selection

- [x] **Handoff #4** ✅ Done 2026-05-11 — Added M&A + B&R dimensions; reallocated weights (IS 35→30, Cost 20→17.5, FI 15→12.5; both new dims 5% each). Rescored A-E with new dimensions: E 7.775 (lead narrowed to 0.375), C 7.40 (unchanged — most rubric-robust), B 6.875 (−0.375), D 6.40 (−0.45), A 4.90 (+0.45). PoC-1=E PoC-2=C recommendation preserved. Synthesis: [[2026-05-11_rubric-monitoring-billing-dimensions]].
- [x] **Handoff #5a** ✅ Done 2026-05-11 — Added 10 fleet reading-list items across K8s Multi-Deployment (Jobs/Indexed), Workflow Orchestration (new "API Gateway → Lambda → K8s" section), Contract & Schema Governance (new section for Pydantic v2 + schema canary), Coordinator / Lease Mechanisms (new section for gRPC + Raft + lease-churn), NATS JetStream-as-blob annotation, PyAV GIL, Spot economics. Item 9 (Connascence) moved to software-arch reading-list. See [[fleet-architecture/reading-list]].
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

- [x] **Handoff #6** ✅ Done 2026-05-11 — Spec landed at [[2026-05-11_enforcement-as-proposal-scorer]]. Per-proposal target import-linter contracts (A: low ~10-50 violations, B: high ~200-500+, C: moderate ~50-150, D: highest ~400-1000+, E: moderate ~50-150). Violation-count → Migration-Risk bracket mapping (0-25→10, 26-75→8, 76-150→6, 151-300→4, 301-600→2, 600+→0). Billing-emit-site fitness functions defined (centralization + idempotency-reach checks; will need pytest sibling for AST checks import-linter can't express). Dual-use angle: pre-PoC scorer + post-PoC enforcer.
- [x] **Handoff #7** ✅ Done 2026-05-11 — Enforcement collector ships. import-linter `>=2.0` added as dep; 5 per-proposal `.ini` contracts under `data/proposal-contracts/`; collector at `src/software_arch_sketches/enforcement/rules.py` subprocess-invokes lint-imports + counts `(l.N)` edges. Real run: A=30 (MR 8/10), B=203 (4/10), C=169 (4/10), D=202 (4/10), E=30 (8/10). **2 real findings vs human estimates**: C harder than thought (−2pt MR — connector_factories hub-coupling is the cost driver), D easier than thought (+2pt — complexity lives in infra not imports). E's lead over C in composite widens from 0.375 → **0.675**. Rubric synthesis updated with collector MR addendum. Findings: [[2026-05-11_sketch-findings-enforcement]]. Dual-use: contracts → CI gate post-PoC selection.
- [x] **Handoff #5b** ✅ Done 2026-05-11 — Added 3 software-arch items + connascence (moved from fleet): tach-vs-import-linter benchmark goes under Fitness Functions; ODD/PRR new section "Operational Readiness & Observability-Driven Development"; migration-safety new section "Migration-Safety Patterns" (strangler fig, feature-flag-driven migrations, multi-quarter migration discipline). See [[software-architecture/reading-list]].
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
  - [x] **Threshold recalibration against 7d distribution** — DONE 2026-05-07. Reframed handoff's red/yellow split into regression-vs-debt taxonomy: 3 regression signals (ci_failure 15/30, mtm 1/3, open_prs_age 15/60) keep red as alarm; 5 debt signals (todo, radon, ruff, stale_branches, vulture) drop red entirely — yellow only as leaderboard. 21% flip rate, 3 legit reds today (ailink CI 35%, inference-api 714d PR, watchman 3.17d MTM).
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

- [ ] **Promote stage → rearchitecture** via standard release-train PR after stage soak clean. **Pulled into 2026-05-07 Today's Scope** — bundle naturally with PR #1679 territory or open a discrete fix-only PR. [Closed sub-items: PR #1671 opened + merged to stage 2026-05-05 — see [[2026-05-05]] § Closed Sub-items.]
- [ ] **Site-side investigation (post-merge)** — once noise is bounded, look at WARNING-level body previews. If a specific HTTP status / body shape recurs (503, rate-limit, relay-resetting empty), file a separate issue with upstream-firmware vs network-LB classification.

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
  - [x] **NF2 — Promote `reconcile_cameras.py` to a Tier-1 dashboard signal** ✅ DEPLOYED 2026-05-11. Tier-1 on Firebat (daily 04:00 PT timer), 3 signals enabled in signals.json. First real run: `production_missing_subscription.cameras=2024` → RED (value-add demo working). Deploy codified at `local_network_scripts/phase-16-billing-reconcile.sh` (re-runnable, idempotent). *(billing/_todos NF2)*
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

## 29. Internal-test deploy lane — custom-branch wiring via admin API

**Priority:** This-week-or-next (planning) — not active today.
**Status:** Idea captured 2026-05-11 during the AutoPatrol queue-routing drill. Needs design before any code.

### The problem

Today, untested dev branches must be promoted to `stage` to be exercised against any real workload, which pollutes stage with churn and means every stage→rearch promotion drags along revertible-but-noisy iterations (see the #1681 → #1686 → #1687 → #1688 chain). We need an internal-test lane that lets us point selected sites (Alibi, Securitas trial, internal eval) at a custom branch image *without* touching stage.

### Design surface

- **Admin-side wiring:** how to configure a custom branch (image tag) at the site / customer level. Likely via a new field on the connector deploy config, exposed through an admin API endpoint.
- **API automation:** so we can flip a cohort of sites onto a branch and back without manual DB edits. Idempotent endpoint + audit log.
- **Cohort definition:** what's the "internal-test cohort" canonically? Lead-implied (today's `lead_implies_dev` heuristic), explicit opt-in flag, or both?
- **Deploy interaction:** ArgoCD / connector_deployer needs to honor the per-site image-tag override. Today the deploy chain is per-cluster, not per-site — this is the heaviest lift.
- **Cleanup discipline:** stale custom-branch assignments must auto-expire (e.g., 7d TTL) or the cohort drifts off latest-known-good.

### Why now

Surfaced by the 2026-05-11 AP signal investigation — the `lead_implies_dev` queue heuristic is *already* doing 80% of this routing for the SQS layer (Alibi's patrols land on dev queue, dev pod processes them on dev image tag `1.0.1-dev`). A formal internal-test lane would generalize that into a first-class lever for the connector image itself, with safety rails.

### Open work

- [ ] **Design synthesis** — write the ADR-style note covering admin model, API surface, deploy-chain integration, cohort semantics, TTL/cleanup. Lives in `topics/actuate-platform/notes/syntheses/{date}_internal-test-deploy-lane.md` once drafted.
- [ ] **Stakeholder ping** — connector_deployer owner + admin-side owner for buy-in on the deploy-chain change before scoping further.
- [ ] **Prototype scope** — proposed phasing (admin schema first, then API, then deploy override, then cohort opt-in).

### Related

- §3 / §27 (AutoPatrol routing) — the SQS-side precedent for cohort-based dev routing
- §5 (Fleet Architecture) — any fleet redesign must accommodate per-site image-tag overrides
- §28 (Billing Pipeline) — internal-test traffic must NOT pollute billing-emit counts; cohort opt-in needs a billing-suppression switch
- Existing `lead_implies_dev` heuristic at `actuate-libraries/actuate-config/.../patrol_config.py:31-34` — first place a generalized opt-in flag would replace

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
- [⏳] **First real SYCL batch in flight** — run-id `2026-05-11T1506Z-video-processing-001`, 10 URLs (moviepy, aiortc, Av1an, mediamtx, janus, pion/webrtc, livekit, restreamer, live555, go2rtc). SYCL healthy at 3.32 tok/s post-restart (root cause of prior degradation: stuck May-7 curl client wedging the queue). ETA ~5.8 hr wallclock. Pull when DONE, review drafts.
- [ ] **Composer prompt tuning** — planner side landed 2026-05-11 (commit `7b05908`); composer-side observations (key claims sometimes echo source verbatim, occasional flat sections) carry forward to a tuning pass post-overnight.
- [ ] **SYCL queue-health pre-flight** — add a `kb-batch-doctor` or pre-submit check that detects stale clients holding the SYCL request slot (today's 4-day-old curl wedged the queue invisibly). Either kill-stale-or-warn at submit time, OR a periodic Tier-1 systemd timer.

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

**Last synced:** 2026-05-11
**Source:** `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`

This section is **fully replaced** on every sync by the `jira-sync` automation (see [[automation-jira-sync]]). Manual edits in this section will be lost — add notes against tickets in the workstream sections above instead.

### Ready to Deploy (4)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| CS3-430 | Medium | Sub-task | Account for dummy incident type in CHM API |
| CS3-31 | Highest | Sub-task | Automatically update the reference image |
| CS3-58 | Lowest | Task | Configuration per camera |
| CS3-323 | High | Bug | Discrepancy in cam count btwn dashboard and report |

### In Progress / In Review (3)

| Ticket | Status | Priority | Type | Summary |
|--------|--------|----------|------|---------|
| ENG-198 | In Progress | Medium | Bug | AutoPatrol modelless patrol: signal-flow fixes + investigation |
| ENG-219 | In Progress | Medium | Task | Local GPU agent / GPU server R&amp;D box setup |
| ENG-217 | In Progress | Medium | Task | AutoPatrol "no-schedule" cascade cleanup (~350 cams) + Cohort F deep classifier |

### To Do (4)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| ENG-136 | High | Task | PyAV upgrade 13.1 → 17.0 (nogil pixel conversion) |
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
## Today's Scope (2026-05-11)

Picked via [[skill-daily-scope|/daily-scope]]. Line items close via [[skill-daily-wrap|/daily-wrap]] at end-of-day — closed items get a summary in the daily note, not deleted here.

**Morning context:** Friday's deferred PR [#1688](https://github.com/aegissystems/vms-connector/pull/1688) (stage→rearch, bundles #1684 line-crossing libs + 10 other PRs) is **cleared for merge**: zero weekend stage drift (tip `6d95785d`), targeted re-soak via `nrql-investigator` confirmed line-crossing bundle GREEN on stage — ERROR rate down 50-58%, per-pod alarm rate down ~46% (expected parked-vehicle suppression), zero pod restarts/OOMKills, no new error classes. CI 4 SUCCESS. Mechanical blocker: `REVIEW_REQUIRED`. Morning fan-out also surfaced a **prod-side AutoPatrol RED**: `autopatrol-server` prod is starved (0 SQS msg/24h+) while `autopatrol-server-dev` is consuming the prod queue (2.5k log lines / 6h: SQS receives, S3 uploads, Immix 200s). Queue-routing config drift — not stage-correlated, but blast radius unknown (dev pod may be writing to dev-tier infra for prod patrols). Picked into today.

**Active picks:**

- [ ] **Ship PR #1688** — **MERGED 2026-05-11T18:55:37Z, commit `f4ccd2296322`.** APPROVED by Zack, all checks green pre-merge. **POST-MERGE INCIDENT:** the draft squash body I generated leaked CI-skip-directive token text inside instructional prose. GitHub Actions parsed it as a directive and skipped all push-triggered workflows on `rearchitecture` (build, reset-stage, sonar). Recovered the build via `gh workflow run rearch.yml --ref rearchitecture` (workflow_dispatch). The other two lack `workflow_dispatch` triggers — separate follow-up needed (empty push, or add the trigger). Rule enshrined: new feedback memory `feedback_ci_skip_tokens_anywhere.md` + strengthened global CLAUDE.md Git Safety section. Post-merge release-chain-watcher launched as background agent. Tier-1 systemd soak on Firebat will be stood up once build completes. Closes [§20](#20-dw_url_up-empty-body-errors--fleet-wide-dw-auth-endpoint-flake) fully on clean rearch soak. Handoff: [[2026-05-07_handoff-pr-1681-promotion]].
- [ ] **Follow-up: rearch.yml + reset-stage-after-merge + sonar re-trigger** — `reset-stage-after-merge.yml` and `sonar.yml` are missing `workflow_dispatch` triggers, so they can't be manually re-fired for the f4ccd2296322 commit. Options: (a) push an empty commit to rearchitecture (risky — alters tip), (b) add `workflow_dispatch:` triggers in a follow-up PR (preferred), (c) accept the gap until next rearch push. Recommend (b).
- [x] **AutoPatrol queue-routing investigation** — RESOLVED, no outage. Root cause: legacy `lead_implies_dev` fallback in [actuate-config/patrol_config.py:31-34](https://github.com/aegissystems/actuate-libraries/blob/main/actuate-config/src/actuate_config/connector/patrol/patrol_config.py#L31) routes any customer with "actuate" in `lead` to the dev queue. Only AP-running tenant right now is Alibi (`47dc2c1f-...`, sites 35830/35832) → all 52 patrols/6h route to dev → autopatrol-server-dev (imageTag `1.0.1-dev`, DEV=true) consumes them correctly. autopatrol-server prod (`0.1.25`) is idle because no GA-tier customer is on AP yet. Dashboard `autopatrol_sqs_messages` polls only prod queue → false-RED. Real fix is signal redesign — moved to **AutoPatrol signal redesign** below.
- [ ] **AutoPatrol signal redesign** *(post-#1688)* — Split into two signals: `autopatrol_sqs_messages_dev` (polls dev container) + `autopatrol_sqs_messages_prod` (polls prod container, threshold normalized against expected-prod-routed-patrol count — when expected=0, suppress RED). Updates: `~/.claude/skills/dashboard-check/config/signals.json` + `~/bin/autopatrol-overnight-check.sh` (source at `/home/mork/work/local_network_scripts/files/`).
- [ ] **Review/merge PR #2389** — actuate_admin draft (`audit_autopatrol_state` mgmt command). Read diff, push from draft, merge to `staging`, wait for Staging CI, eventually flow through release-train to `main` then prod. Then `kubectl exec` on prod admin → run command → paste cohort sizes back into [[2026-04-30_autopatrol-state-audit]]. Carry-forward from 2026-05-01 follow-up.
- [ ] **IAM access-denied triage** — Dashboard RED: `iam_access_denied_cluster_wide` shows `camera-admin-staging=12, microservice=9`. Pull last 24h denials via NRQL or CloudWatch, identify role/policy gap, file ticket or fix in `kubernetes-deployments`. Single-pass triage, not a full project.

**Tracked as relevant (carry-forward):**

- **§5 Run Service sub-project** — 6 docs drafted; top blockers: vestigial customer-fields, image `validate` subcommand status, sensitivity preset numeric calibration. Forward context.
- **§18 fleet memory-limit drift** — handed off to infra team; follow up later in week to confirm VPA floor restoration landed. **Not our task today.**
- **§24 LLM shop** — Phase 2A.2 shipped 2026-05-06; forward context.
- **AUTO-351 BB push to prod** (§2c) — Ready-to-Deploy, Brad-assigned.
- **§16 lifecycle log silence debug** + **Immix zombie-tenants Jira draft** — in [[autopatrol-deferred-backlog]].
- **vms-connector#1656 streamId-null patrol-alert** (§2d.2) — Unassigned.

**Surface (camera-ui audit-flag):** Login.tsx — runbook landed via [[2026-04-30_camera-ui-login-tsx-audit-flag]] should retire; carrying.
**Surface (jira-sync):** stale (`Last synced: 2026-05-07`); refresh after the AP drill.
**Surface (orphan branches):** `vms-connector@stage-to-rearch-2026-05-08-billing` (current — keep till #1688 merges), other orphans unchanged.

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

- [ ] **verify**: vms-connector PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) post-merge soak (merged 2026-05-01T14:28:26Z, commit `73fd3bf` to `rearchitecture`). **Autonomous Tier-1 monitoring in place:** `~/bin/pr-1660-soak-check` on Firebat with 4 systemd one-shots (T+6h 20:30Z today, T+8h 22:30Z today, T+18h 12:00Z 2026-05-02, T+24h 14:30Z 2026-05-02). Verdicts auto-append to daily notes under `## PR #1660 Post-Merge Monitoring`. RED runs surface via `systemctl --user --failed`. Source-controlled at `local_network_scripts/files/pr-1660-soak-*`. **Manual fan-out below is now redundant** unless an autonomous run goes RED. Bundled 6 commits: AP cleanup connector emit (#1657), stream_id null guard (#1659), VCH `no_patrols` drop (#1662), YAM polygon hints (#1655), pullers stable bump (#1661), BT-949 pano-split IZ fix. Verification fan-out:
  1. **YAM emit (1h post-deploy first, 24h confirm):** any YAM-eligible site emits `motion_polygons` WKT to slicing server, no `motion_mask`-related `AttributeError` in connector logs. NRQL: `SELECT count(*) FROM Log WHERE container_name LIKE '%connector%' AND message LIKE '%motion_mask%' AND level = 'ERROR' SINCE 24 hours ago` — expect 0.
  2. **VCH `no_patrols` traffic drop (24h):** cleanup-Lambda `integration=vch reason=no_patrols` event count drops to near-zero for Vendor.Actuate.Prod. Unblocks `decide: Recalibrate connector_no_patrols_to_run_24h thresholds` once landed in prod (not just rearchitecture).
  3. **stream_id null guard (24h):** no `raise_patrol_alert` handler errors with null `stream_id`. Spot-check: `SELECT count(*) FROM Log WHERE message LIKE '%raise_patrol_alert%' AND message LIKE '%null%' SINCE 24 hours ago`.
  4. **AP cleanup connector emit (24h):** SQS `autopatrol_stale_schedule_cleanup_dev.fifo` (or prod equivalent) receives messages from connector terminal exits at expected rate. Cross-check against cleanup-Lambda invocation count.
  5. **BT-949 pano-split IZ fix (multi-day watch):** TJ Hamilton Cars M5/M7/M19 false-positive vehicle alerts trend down vs 7-day baseline. Manual spot-check needed on a pano clip with aspect > 2.0 and a drawn vehicle IZ.
  6. **Connector-pod error baseline (24h):** total connector-pod errors flat or improved vs prior 24h. Use `/post-deploy-monitor` if it's been retrofitted to take a merge timestamp.
- [ ] **exec**: File follow-up issue in vms-connector for direct unit tests on `connector_factories/shared/cleanup_emitter.py` (167 LOC, broad `except Exception`, zero direct tests). Tests should assert: emit fires under terminal exits, suppressed for pending/transient, no-op when env flag off, no-op when `schedule_id` empty. Surfaced in PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) review 2026-05-01. *(seeded 2026-05-01 for 2026-05-02)*
- [ ] **exec**: File follow-up issue (or one-line PR) for explicit `boto3.client("sqs", region_name=...)` in `cleanup_emitter.py:87` so a region-mismatched stage pod surfaces a distinguishable warning instead of opaque `NonExistentQueue`. Surfaced in PR [#1660](https://github.com/aegissystems/vms-connector/pull/1660) review 2026-05-01. *(seeded 2026-05-01 for 2026-05-02)*
- [ ] **exec**: KB synthesis closing the loop on YAM motion-bridge removal landing in connector — one-line update under `topics/vms-connector` YAM polygon-hint workstream noting PR #1660 closes the connector-side loop. Per global CLAUDE.md "After Work: Log to KB." *(seeded 2026-05-01 for 2026-05-02)*

### Seeded for 2026-05-03

- [ ] **verify**: §21 — VCH SIGTERM billing-event fix (PR [#1667](https://github.com/aegissystems/vms-connector/pull/1667), merged 2026-05-02 to stage). 36h soak window: by Sunday afternoon there should be multiple SIGTERM'd VCH cronjob pods in the 24h window — confirm each emitted `site_product_ended` events (pre-fix: zero). Run the four NRQL queries in §21 via `nrql-investigator`. If green: comment on PR, close issue [#1666](https://github.com/aegissystems/vms-connector/issues/1666), promote to rearch (separate stage→rearch PR opened from this same session). If red: pull pre/post comparison, figure out what the fix missed. *(seeded 2026-05-02 for 2026-05-03)*

### Seeded for 2026-05-04

- [x] **investigate**: §22 — staging VCH `KeyError: 'monitoring'` startup crash → **picked into 2026-05-04 Today's Scope**. *(seeded 2026-05-03 for 2026-05-04; ran 2026-05-04 — promoted)*
- [x] **harden**: rotate the Firebat box's user account / SSH password → **picked into 2026-05-04 Today's Scope**. *(seeded 2026-05-03 for 2026-05-04; ran 2026-05-04 — promoted)*

### Seeded for 2026-05-07

- [ ] **verify**: vms-connector PR [#1679](https://github.com/aegissystems/vms-connector/pull/1679) post-merge soak — gated on user merge. Watch `succeeded on stream_id candidate #N` (iteration safety net firing) and `raise_patrol_alert ... failed` (regression) on `:rearchitecture` images for 24h post-merge. Stage validation already proved `stream_ids=[...]` history accumulation is firing (9 events in 30 min) and 0 raise failures; rearch should mirror. **PULLED INTO TODAY'S SCOPE 2026-05-07.** *(seeded 2026-05-06 for 2026-05-07)*
- [x] **decide**: Send the Immix `StreamFinished` inquiry — **DONE 2026-05-06 evening (sent).** Standing follow-up watch for Immix response per the inquiry's post-response branching plan in [[2026-05-06_immix-streamfinished-inquiry]]. *(seeded 2026-05-06 for 2026-05-07; done 2026-05-06)*
- [ ] **verify**: Confirm patrol-A188AC1E-style runs on `:rearchitecture` are succeeding without the silent-400 failure mode. Spot-check via `SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND container_image LIKE '%:rearchitecture%' AND message LIKE '%raise_patrol_alert%' AND message LIKE '%failed%' SINCE 24 hours ago` — expect 0. **Folded into PR #1679 soak** above. *(seeded 2026-05-06 for 2026-05-07)*
- [ ] **exec**: §3 cleanup-Lambda correctness verify pass across Immix-state matrix — see Today's Scope. *(seeded 2026-05-07 for 2026-05-07)*
- [ ] **exec**: fleet_error_top15 triage — see Today's Scope. *(seeded 2026-05-07 for 2026-05-07)*

### Seeded for 2026-05-06 (or later evening when #2406 lands)

- [x] **DECIDED 2026-05-07 — NO BACKFILL.** §25 Cohort B one-time backfill is no longer REQUIRED. Decision documented in [[2026-05-07_cohort-b-no-backfill-decision]]; cascade hook stays flag-disabled. Re-open conditions tracked in [[autopatrol-deferred-backlog]]. *(seeded 2026-05-05; decided 2026-05-07)*

### Seeded for 2026-05-11

- [x] **verify**: vms-connector PR [#1688](https://github.com/aegissystems/vms-connector/pull/1688) stage tip + re-soak before merge — **GREEN.** Zero weekend drift on stage (tip `6d95785d` matches Friday capture). Targeted re-soak of the #1684/#345 line-crossing bundle via `nrql-investigator`: ERROR rate down 50-58% post-merge (1744 → ~770/24h), per-pod alarm rate down ~46% (expected parked-vehicle suppression, not over-suppressed — volume non-zero), zero pod restarts/OOMKills, no new error classes referencing `actuate_filters`/`actuate_connector_observers`/`line_crossing`. PR status: OPEN, MERGEABLE/BLOCKED, `REVIEW_REQUIRED`, 4 CI checks SUCCESS. Mechanical blocker only: reviewer approval. *(seeded 2026-05-08; ran 2026-05-11)*

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
