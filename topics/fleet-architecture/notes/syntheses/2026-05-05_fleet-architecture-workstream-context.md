---
title: "Fleet Architecture — workstream context (factored from mark-todos §5)"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, mark-todos-factored]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_claude-context-optimization.md
  - topics/personal-notes/notes/concepts/2026-05-11_pre-impl-research-priority-reorder.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-29
---

Factored out of mark-todos §5 on 2026-05-05 to keep the live workstream tracker lean. See [[mark-todos]] §5 for active checkboxes.

## Status snapshot

- **Priority:** this-week
- **Tickets:** *(pre-ticket — captured in [[fleet-architecture/_summary|fleet-architecture]] topic syntheses)*
- **Status:** review phase — formal A-E re-score landed 2026-04-22; PoC selection next

## Sub-project: Run Service (2026-05-01)

**Permanent control plane** for [[vms-connector|VMS connector]] workloads, parallel to admin-api site provisioning. API-Gateway-fronted; serves both `mode: ephemeral` (≤24h, first delivery vehicle) and `mode: persistent` (open-ended, canonical onboarding for new customers) on the same `RunSpec.v1` surface. Paradigm choice (C, D, or E) must serve both modes through same primitives. See [[2026-05-01_ephemeral-run-pilot/_overview|run service overview]]. (Folder name still says "ephemeral-run-pilot" — rename pending finalization of project name.)

**Drafted to date** — initial 6-doc groundwork + dual-mode framing + permanent-control-plane reframe + full spec scope (products + sensitivity presets + alert plumbing) + DetectionEvent.v1. Closed sub-items swept to [[2026-05-01]] §"Closed Sub-items" by `/daily-wrap` 2026-05-01.

The active follow-ups (paradigm scoring, translator + spec, API contract, operational + infrastructure) remain in [[mark-todos]] §5 as live `[ ]` checkboxes — keep them there for working-set visibility, not duplicated here.

## Proposals (rescored 2026-04-22)

- [[2026-04-16_proposal-a-minimal-split|A — Minimal split]] (rescore: 4.45)
- [[2026-04-16_proposal-b-stage-fleets|B — Stage fleets]] (rescore: 7.25)
- [[2026-04-16_proposal-c-camera-worker|C — Camera worker]] (rescore: 7.55, PoC-2)
- [[2026-04-16_proposal-d-event-driven|D — Event-driven]] (rescore: 6.85)
- [[2026-04-16_proposal-e-hybrid-sidecar|E — Hybrid sidecar]] (rescore: 8.00, PoC-1)
- [[2026-04-22_proposal-b-prime-stateless-with-coordinator|B-prime — CLOSED 2026-04-22]] (6.25; archived [[2026-04-22]])

The PoC plan is **PoC-1: E (Hybrid sidecar)**, **PoC-2: C (Camera worker)** as runner-up. See [[2026-04-22_fleet-proposal-rescore-with-delta]] for the rescore methodology and addendum.

## Pre-PoC investigation: Tier3 replication driver

$44k/year, 11.1% of S3 spend, 72.9M requests. Investigation steps:

a. S3 Storage Lens or bucket-lifecycle policy audit
b. Per-bucket Tier3 breakdown via CUR + Athena if it's worth the setup
c. CloudTrail dive for `PutBucketLifecycleConfiguration` + `PutBucketReplication` recent events

## Open architectural questions

- Whether [[2026-04-16_graceful-failover-design|graceful failover]] and [[2026-04-16_frame-transport-comparison|frame transport]] should become ADRs
- Whether the chosen paradigm must serve both ephemeral and persistent modes with the same primitives (no parallel implementations) or whether bimodal config is acceptable

## Relevant KB

- [[fleet-architecture/_summary|fleet-architecture topic]]
- [[2026-04-16_evaluation-rubric|evaluation rubric]]
- [[2026-04-22_fleet-proposal-rescore-with-delta|formal rescore + addendum]]
- [[2026-04-22_fleet-coordinator-api-sketch|coordinator unification API sketch]]
- [[2026-04-16_graceful-failover-design]]
- [[2026-04-16_frame-transport-comparison]]
- [[adr-writing-guide]] — if any proposal graduates to an ADR
