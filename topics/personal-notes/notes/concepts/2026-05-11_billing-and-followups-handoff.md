---
title: "Handoff: billing topic landing + fleet/software-arch follow-ups (2026-05-11)"
type: concept
topic: personal-notes
tags: [handoff, billing, fleet-architecture, software-architecture, session-boundary, next-session]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Handoff: billing topic landing + fleet/software-arch follow-ups

Read this, then [[billing/_summary|billing topic summary]], then [[billing/_todos|billing topic todos]]. This handoff is the entry point for the next session.

## Why this exists

Session 2026-05-11 was scoped to **stand up a customer-billing topic in the KB** (parallel to `aws-cost`), anchored on the PR-#1675 → #1688 connector firefight + Cohort F investigation. That scope landed. But the originating prompt was multi-part: (a) reading-list additions for fleet + software-arch, (b) `_summary` + rubric updates with monitoring + billing dimensions, (c) enforcement-sketch-as-proposal-scorer spec, plus a sketch extension and a reeval scan. Those carried over.

This handoff captures **what's done, what's next, and the context the next session needs to pick up without re-reading the whole transcript**.

## What was completed this session (2026-05-11)

### Billing topic stood up

| Artifact | Path |
|---|---|
| Topic root | [[billing/_summary]] |
| Reading list seed | [[billing/reading-list]] |
| Founding post-mortem | [[2026-05-11_billing-pain-post-mortem]] |
| Events catalog (the artifact whose absence cost the firefight) | [[billing-events-catalog]] |
| Topic todo list (6 categories, 25 items) | [[billing/_todos]] |

### Tag retrofit pass — 12 notes now tagged `billing`

Across vms-connector / autopatrol / admin-api / actuate-libraries. Specifically: handoff-pr-1681, autopatrol-deferred-backlog, queue-consumer, admin-schedule-cascade-design, cohort-f3a-deactivate-runbook, cohort-b-no-backfill-decision, cohort-b-backfill-runbook, silent-cameras-diagnosis (×2), data-model-cascade-semantics, autopatrol-cleanup-lambda, actuate-queue-consumer. Cleaned up duplicate `immix` tags in three files as a side-effect.

### mark-todos §28 added

[[mark-todos]] §28 "Customer Billing Pipeline — tighten + self-right" is the loose-link header. Highest-priority items (T1, R1, R2, S1, C1) surfaced inline with `(billing/_todos T1)` annotations. Topic `_todos.md` remains source-of-truth; §28 references, doesn't duplicate.

## Locked-in answers from session 2026-05-11

These were asked and answered at the end of session 2026-05-11. Captured here so the next session doesn't re-litigate.

| Q | Answer | Adjustment applied |
|---|---|---|
| Snowflake DDL access for billing tables? | None currently. If critical, file a Jira ticket with thorough hows/whys. | [[billing/_todos]] C2 expanded with Jira-ticket spec (body + acceptance + project hint). To-do is "file the ticket"; data-team response is the blocker after that. |
| Cohort F tracker handoff (`cohort_f_tracker.json`)? | Our part is done. Mark off our plate. | [[billing/_todos]] R2 marked **OUR PART DONE**; post-mortem table row updated. Data team owns ongoing; we re-engage only if escalated back. |
| Extend post-mortem backwards through alibi billing-profile redesign? | No — alibi is old news, not relevant to current issues. | Post-mortem scope stays anchored at the PR-#1675 → #1688 connector firefight. Alibi remains cross-referenced as foundational primitive but not in the firefight narrative. |
| R1 dashboard surface — operational dashboard, separate dashboard, or sales-dashboard integration? | **Separate billing dashboard**, sketched locally first, future integration with `https://sales-dashboard.internal.actuateui.net/`. Sales-dashboard deploy-repo unknown. | [[billing/_todos]] R1 surface decision added; new [[billing/_todos]] C6 created: "Locate the sales-dashboard deployment repo." |

## Highest-priority next move

**R1 — Admin↔emit billing-reconciliation dashboard signal.** This is the post-mortem's headline action item. Cohort F's drift duration is unknown — we cannot say how long we were under-billing 642 cameras. Until we have continuous reconciliation, the next gap class will surface manually, weeks late.

This eclipses every other follow-up on the list, including the fleet-decision research from session 2026-05-11. Recommend it gets a discrete §N or stays under §28 as the first active sub-item on next session.

## Ordered next-session priorities

The carry-over from session 2026-05-11, reordered for the post-mortem-shifted picture:

| # | Item | Why now | Entry point | Status (2026-05-11 close) |
|---|------|---------|-------------|---|
| 1 | **R1 dashboard spec** | Closes the unknown-drift-window risk; post-mortem headline | [[billing/_todos]] R1 | ✅ **DONE** — spec at [[2026-05-11_billing-reconciliation-dashboard-design]]; superseded by NF2 (operational impl) |
| 2 | **C2 Jira ticket for Snowflake DDL** | Unblocks C5, T2, T3, T4, R2 closure. Cheap, file-and-forget | [[billing/_todos]] C2 | ✅ **DONE** — filed as ENG-242, then *closed Done* same day after [[sales-dashboard-repo]] + [[actuate-bi-repo]] surfaced the answers |
| 3 | **Reeval scan** — pre-implementation research priority order | Billing is the new hot path. The session 2026-05-11 fleet pre-impl list (NR FDMD query, WireGuard inventory, PyAV GIL, etc.) needs reordering against billing items | Session 2026-05-11 last summary + [[2026-04-22_fleet-proposal-rescore-with-delta]] open questions | ✅ **DONE** — [[2026-05-11_pre-impl-research-priority-reorder]]; top 2 promoted to mark-todos §28 |
| 4 | **(b) Fleet rubric: add Monitoring & Alarms + Billing & Reconciliation dimensions** | Promised in 2026-04-23 `_summary` update; never landed. Both dimensions now relevant | [[2026-04-16_evaluation-rubric]] | ✅ **DONE** — [[2026-05-11_rubric-monitoring-billing-dimensions]] (weights rebalanced, 5 proposals rescored, ranking preserved with narrower lead) |
| 5 | **(a) Reading-list additions to fleet + software-arch** | 10-13 items I listed in session 2026-05-11. Several are billing-adjacent (event-sourcing, idempotency, reconciliation) — coordinate with [[billing/reading-list]] | [[fleet-architecture/reading-list]], [[software-architecture/reading-list]] | ✅ **DONE** — 10 fleet items added (3 new sections created), 4 software-arch items added (2 new sections), Connascence moved fleet → software-arch |
| 6 | **(c) Enforcement-sketch-as-proposal-scorer spec** | Quantitative Migration Risk axis for fleet rubric. Also gets billing-emit-site fitness functions per [[billing/_todos]] C1 | [[2026-04-16_architecture-enforcement]] | ✅ **DONE** — [[2026-05-11_enforcement-as-proposal-scorer]] (per-proposal target topologies, violation-bracket mapping, dual-use angle, billing fitness functions) |
| 7 | **Sketch extension** — Enforcement collector beyond stub | Operationalizes #6 against vms-connector | `/home/mork/work/software-arch-sketches/src/software_arch_sketches/enforcement/` | ⏳ Pending — only remaining handoff item; code work (next session per §"Net outcome" below) |
| 8 | **C6 — Locate sales-dashboard deployment repo** | Enables eventual R1 integration. LOW priority but small effort | [[billing/_todos]] C6 | ✅ **DONE** — by side-effect of #2 closure ([[sales-dashboard-repo]] entity note) |

## Net outcome of 2026-05-11 session

**Closed beyond the original handoff (emergent during 2026-05-11):**
- Snowflake-side Tier-1 reconciliation signal DEPLOYED on Firebat (NF2) — daily timer, 3 dashboard signals, first run flagged 2,024 production cameras missing Ordway subscription (vs Feb 2026 baseline of 803).
- Five new billing-topic follow-ups (NF1-NF8 in [[billing/_todos]]) captured.
- ENG-242 filed and closed same-day (data-team off the hook).
- Three new KB entities: [[snowflake-billing-tables]], [[sales-dashboard-repo]], [[actuate-bi-repo]].

**Still owed (handoff item #7 only):**
- Item 7 (enforcement collector code in `/home/mork/work/software-arch-sketches/`) is the only remaining handoff item. Spec for it lives at [[2026-05-11_enforcement-as-proposal-scorer]]; implementation is mechanical from there. Recommended for fresh session — code work benefits from a clean window.

## Per-item context

### 1. R1 dashboard spec

**Scope:** design (not implement) the continuous admin↔emit reconciliation signal. Output: a concept note at `topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md` answering:

- **Data source** — NRQL (cheap, instant, doesn't need Snowflake access) or Snowflake (richer joins but blocked on C2 Jira). Strong recommendation: NRQL-first for the SQS-side, joined against admin DB via a periodic Lambda or laptop cron.
- **Query shape** — left-side: `admin: count(Camera.is_deleted=False AND Customer.active=True) × products`. Right-side: `count(distinct (admin_camera_id, product) emitting `_ended` in trailing 24h)` from `event_queue_analytics.fifo` logs. Delta = drift.
- **Surface** — separate billing dashboard. Local first (laptop/Firebat dashboard collector), future integration with `https://sales-dashboard.internal.actuateui.net/`.
- **Alert thresholds** — start at 5% gap; tighten as gaps close. Per-cohort breakdown when the alert fires (gap rows tractable for an operator).
- **Cadence** — daily.

**Files to read first:**
- [[2026-05-11_billing-pain-post-mortem]] — context
- [[billing-events-catalog]] — what `_ended` looks like; `act_a` discriminator semantics
- [[2026-05-06_cohort-f-investigation]] — methodology blueprint (NR query against `event_queue_analytics.fifo`)
- [[2026-04-30_data-model-cascade-semantics]] — admin source-of-truth state model
- [[dashboard-check]] skill config — `~/.claude/skills/dashboard-check/config/signals.json` for the existing dashboard signal pattern
- [[autopatrol-deferred-backlog]] "Cohort dashboard signals" — adjacent prior art

**Blockers:** none for the design. Implementation later may chain on C2 Jira (Snowflake side) or C6 (sales-dashboard integration), but the local sketch can start today.

### 2. C2 Jira ticket for Snowflake DDL

**Scope:** file the ticket with the body spec already drafted in [[billing/_todos]] C2. Project: TBD — probably data-eng or platform; pick whichever has the queue_consumer/Snowflake pipeline owner.

**Drafted ticket body content:**
- **Why:** link to [[2026-05-11_billing-pain-post-mortem]] and [[billing-events-catalog]]
- **What we believe:** reverse-engineered schema in the catalog
- **What we'd do with it:** close C2; unblock R1 query design; validate T2/T3/T4
- **Acceptance:** `notes/entities/snowflake-billing-tables.md` (per C5) written from authoritative source
- **Context co-location:** link to `cohort_f_tracker.json`

**Files to read first:** [[billing-events-catalog]], [[billing/_todos]] C2.

### 3. Reeval scan

**Scope:** revisit the session 2026-05-11 ordered list of pre-implementation research items, accounting for billing as the new top-priority class. Items from last session:

| Session-2026-05-11 item | Hours | Could flip E→C? | Still top? |
|---|---:|:---:|:---:|
| NR query: actual FDMD drop rate fleet-wide | 2 | Yes | Was #1 — now likely #4 behind R1, C2, S1 |
| WireGuard/tunnel inventory | 1d | Yes (flips C unviable) | Was #2 — still important but billing precedes |
| PyAV GIL budget measurement at frame rate | 0.5d | Partially | Was #3 — same |
| Confirm `connector validate` subcommand exists | 0.25h | No | Was #4 — same |
| Lease-churn benchmark | 0.5d | No | Was #5 — same |
| Tier3 replication investigation | 1h | No | Was #6 — same |

**Output:** updated ordered list in a concept note or directly into the next-session daily; promote top 2-3 to mark-todos. Surface this in `/daily-scope` as the basis for the day's picks.

### 4. (b) Fleet rubric: Monitoring + Billing dimensions

**Scope:** add two new dimensions to [[2026-04-16_evaluation-rubric]] and rescore the 5 proposals.

- **Monitoring & Alarms** dimension — promised in 2026-04-23 `_summary` update; never landed. Each proposal must articulate: what behavioral signals prove it works in prod; what goes on the operational dashboard; what acceptance criteria gate rollout.
- **Billing & Reconciliation** dimension — new (raised this session). Each proposal must articulate: how billing-emit invariants are preserved across the restructure; what new emit sites are needed; how reconciliation works in the new shape.

**Weight reallocation:** current weights sum to 100%. Both new dimensions need ~10% each. Candidate redistribution:

| Dimension | Current | Proposed |
|---|---:|---:|
| Independent scalability | 35% | 30% |
| Cost reduction | 20% | 17.5% |
| Failure isolation | 15% | 12.5% |
| Operational simplicity | 15% | 15% |
| Migration risk | 10% | 10% |
| Failover quality | 5% | 5% |
| **Monitoring & Alarms (NEW)** | — | **5%** |
| **Billing & Reconciliation (NEW)** | — | **5%** |

(Subject to revision; the redistribution should be a brief design decision in the next session.)

**Expected impact:** Proposal B (4-hop transport) likely worst on billing reconciliation because emit-site multiplicity grows. C (camera-worker) and E (hybrid sidecar) keep emission in roughly one place — probably fine. D (event-driven with S3-ref) needs the most design work to preserve billing semantics. Recompute composites; possible ranking change at the E/C margin.

**Files to read first:** [[2026-04-16_evaluation-rubric]], [[2026-04-22_fleet-proposal-rescore-with-delta]], [[billing-events-catalog]] §"Lifecycle invariants."

### 5. (a) Reading-list additions

**Scope:** add the 10-13 items I listed in session 2026-05-11 to [[fleet-architecture/reading-list]] and [[software-architecture/reading-list]]. List repeats here for completeness:

Fleet:
1. K8s Job lifecycle / `activeDeadlineSeconds` / Indexed Jobs
2. API Gateway → Lambda → K8s orchestration patterns
3. Pydantic v2 contract evolution + OpenAPI generation
4. Schema canary / contract testing (translator ↔ connector validate)
5. gRPC service design + Raft/etcd leader election in Python
6. Spot instances + ephemeral worker economics
7. PyAV / encoder GIL budget benchmarks
8. NATS JetStream as ephemeral blob store (promote from Chunk 9)
9. Connascence framework
10. Lease-churn benchmarking for multi-tenant coordinators

Software-arch:
11. Architecture conformance benchmarks (tach vs import-linter)
12. Observability-driven development / production readiness reviews
13. Migration-safety patterns at scale

**Coordinate with [[billing/reading-list]]:** several entries (event-sourcing, idempotency, reconciliation patterns, Snowpipe) overlap. Add cross-references rather than duplicating.

### 6. (c) Enforcement-sketch-as-proposal-scorer spec

**Scope:** specify how the enforcement sketch becomes a quantitative input to the fleet rubric's Migration Risk axis. Output: a concept note at `topics/software-architecture/notes/concepts/2026-05-XX_enforcement-as-proposal-scorer.md`.

**Approach:**
- For each fleet proposal (A-E), write a set of import-linter rules describing its **target** layer structure (e.g., for E: `core_pod ↛ puller`, `sidecar ↛ core_pod_internals`).
- Run those rules against the **current** vms-connector codebase.
- Output: violation-count-per-proposal. Higher count = higher Migration Risk.
- Also: identify the 3 F-ranked complexity hotspots from session 2026-05-11's metrics sketch findings (`AnalyticsSiteManager._log_memory_breakdown`, `factory.generate_site`, `run_multi_bridge_test`). Map them to each proposal's fleet-boundary disruption.

**Billing emit-site fitness function (new, from [[billing/_todos]] C1):**
- No emit outside `connector_factories/shared/billing_emit.py`.
- Idempotency guard reached on every emit path.
- New emit sites must update [[billing-events-catalog]] (enforced at PR-review level, but a static-analysis check could attempt this too).

### 7. Sketch extension proper

**Scope:** turn the enforcement sketch from stub into working collector. Wire to the spec in #6.

**Files to touch:**
- `/home/mork/work/software-arch-sketches/src/software_arch_sketches/enforcement/__init__.py`
- (probably new) `/home/mork/work/software-arch-sketches/src/software_arch_sketches/enforcement/collector.py`
- `/home/mork/work/software-arch-sketches/Makefile` — `make enforce` target already exists; just needs the impl

**Acceptance:**
- `make enforce` runs against vms-connector, produces `data/violations.json` with per-proposal violation counts.
- Dashboard sketch can read it (already wired in stub).
- KB findings note at `topics/software-architecture/notes/concepts/2026-05-XX_sketch-findings-enforcement.md` mirroring the metrics-collector findings note pattern.

### 8. C6 — Locate sales-dashboard deployment repo

**Scope:** find the repo that deploys `https://sales-dashboard.internal.actuateui.net/`. Document in [[billing/_todos]] C6's target concept note.

**Approach:**
- Check page source / build artifacts for repo footprint.
- Grep `/home/mork/work/` for `sales-dashboard` or `internal.actuateui.net`.
- Ask whoever owns the dashboard surface (likely platform / front-end channel).

LOW priority — only matters when R1 is ready for integration. Could defer.

## Cross-references

### Topic anchors (the durable artifacts this session produced)

- [[billing/_summary]]
- [[billing/_todos]]
- [[2026-05-11_billing-pain-post-mortem]]
- [[billing-events-catalog]]
- [[billing/reading-list]]

### Related KB

- [[aws-cost/_summary]] — sibling topic (infra cost vs customer revenue)
- [[autopatrol/_summary]] — largest emit source + cohort-investigation history
- [[fleet-architecture/_summary]] — fleet redesign that must preserve billing emission
- [[software-architecture/_summary]] — enforcement / dashboard sketches that will absorb billing signals
- [[operational-health/_summary]] — adjacent dashboard topic
- [[autopatrol-deferred-backlog]] — sibling backlog with overlapping items
- [[2026-04-30_data-model-cascade-semantics]] — primary source for billing self-righting items (S1-S4)
- [[autopatrol-cleanup-lambda]] — the existing self-righting prototype to copy
- [[2026-05-06_cohort-f-investigation]] — the audit that drove this whole arc
- [[2026-05-07_handoff-pr-1681-promotion]] — promotion-chain context for PR #1688

### Mark-todos hooks

- [[mark-todos]] §28 — billing parent workstream (loose-link to topic todos)
- [[mark-todos]] §5 — fleet architecture (gets monitoring + billing dimensions on rubric)
- [[mark-todos]] §6 — software architecture sketches (gets enforcement extension + billing-emit fitness function)
- [[mark-todos]] §9 — operational dashboard (separate from billing dashboard but cross-link)
- [[mark-todos]] §3 — cleanup-Lambda (the self-righting prototype)

## Discipline note

This handoff is the entry-point for **one** next session. If multiple sessions intervene before the carry-over items land, append updates to this file with date headers rather than rewriting. When all 8 items are addressed (or sunsetted), this handoff retires — close with a `## Status: COMPLETE` banner and link to the closing artifacts.
