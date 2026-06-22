---
title: Watch Manager — Proposal B′ (Stateless with Blob Coordinator) Addendum
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, proposal-b-prime, manager-service]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-04-22_proposal-b-prime-stateless-with-coordinator]]"
  - "[[2026-04-22_fleet-coordinator-api-sketch]]"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-failure-modes.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_site-supervisor-vs-watch-manager.md
incoming_updated: 2026-05-30
---

# Watch Manager — Proposal B′ (Stateless with Blob Coordinator) Addendum

Master: [[2026-05-28_watch-management-service-design]]. Proposal: [[2026-04-22_proposal-b-prime-stateless-with-coordinator]].

## Proposal B′ in one paragraph

Same five stage-fleet pods as B, plus a **3-replica Blob Coordinator StatefulSet** with etcd-Raft. Per-window JPEG blobs on node-local tmpfs of the owning motion pod; lease metadata in Coordinator raft state; tracker in Observer (Redis snapshots). The Coordinator was scoped narrowly to blob lifecycle, but Open Question 6 (`proposal-b-prime-stateless-with-coordinator.md:189`) explicitly asks "should it also absorb camera-assignment (C's controller) and schedule eval (E's site-context)?" The [[2026-04-22_fleet-coordinator-api-sketch]] answers yes — a unified FleetCoordinator with 15 RPCs spanning Assignments / Schedules / Config / Outcomes.

## Where the manager lands

**Cardinality recommendation: fleet-singleton — the manager IS the FleetCoordinator (Blob Coordinator + C's assignment + E's schedule eval, unified).** B′'s own open questions point this way; the API sketch is the contract.

## What's net-new vs. leveraging existing

**Most architecturally elegant of any proposal.** The Coordinator's Raft state machine + etcd-style API natively gives:

- HA + leader election (better than C's single Assignment Controller with a hot standby)
- Strong consistency on [[watch-entity|Watch]] state (no read-write races — unlike today's Redis MotionStatus)
- [[watch-entity|Watch]] API natively (FleetCoordinator.[[watch-entity|Watch]] RPC streams state changes — perfect for stage fleets / pods that need to react to arm/disarm)
- Linearizable schedule re-derivation across DST boundaries (T3 becomes a Raft-replicated state transition)
- Lease semantics already in place for blobs — extend to [[watch-entity|Watch]] leases (a [[watch-entity|Watch]] "leased" to a Detection Core means that Core is the authoritative runner for it)

Extensions on top of the existing Coordinator scope:

- Schedule data model ([[watch-entity|Watch]] + CalendarSet + ManualOverride) added to the Coordinator's state machine.
- Schedule-eval logic added to Coordinator tick (e.g. 30–60s reconcile pass over CalendarSets + Watches → desired armed states).
- Assignments domain (C's bin-packing or E's camera-group ordinal mapping — either works).
- Outcomes domain (T17 billing-event subscription) — Coordinator observes SQS to confirm assignments ran.

Touchpoints absorbed: T1, T2, T3, T5, T6 (no per-Watch K8s objects — workloads exist independently and read [[watch-entity|Watch]] state from Coordinator), T8, T10, T11, T16, T17, T18.

## ENG-96 race

**Fixed by design + made provably correct by Raft.** Unlike Option B's runner-tick model (where multiple tick instances could in theory race), the Raft-replicated tick is linearizable. The brainstorm's Option B premise ("desired state is a pure function of current time + DB state") becomes mathematically clean.

## Sharding interplay

B′'s stage fleets read [[watch-entity|Watch]] state via Coordinator.[[watch-entity|Watch]] RPC streams. The 3-replica StatefulSet handles HA via Raft; followers serve read-only watches, leader handles writes. Pod fork-safety doesn't apply at the manager layer (Coordinator is its own StatefulSet).

## Fit verdict

**Tied with C and E for best fit, with the strongest correctness story of the three.** B′ is the most over-engineered choice — but for a security product where missed arms have legal consequences, "over-engineered" may be the appropriate engineering posture. The Raft state machine gives strong-consistency guarantees that C's standby-failover and E's centralized-but-single-replica designs don't.

The cost is operational: running an etcd-Raft StatefulSet adds an SRE skill requirement and a failure mode (split-brain on network partition) that C/E don't have. Whether that's worth it depends on the org's appetite for Raft operations.

## Alternative if poor fit

If Raft operations are deemed too expensive, **fall back to C** — the Assignment Controller pattern is the cheapest cardinality with the same logical surface as the FleetCoordinator. You lose strong-consistency on [[watch-entity|Watch]] transitions and have to accept the single-controller-with-standby HA model, but the manager design otherwise translates 1:1.

## Cross-reference

The [[2026-04-22_fleet-coordinator-api-sketch]] 15-RPC specification IS the manager-service contract for this proposal. Treat it as the authoritative manager-service API surface; this addendum just adds [[watch-entity|Watch]] domain semantics on top.
