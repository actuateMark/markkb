---
title: Manager Cardinality Decision — Per-Watch vs. Per-Site vs. Fleet-Singleton
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: fleet-architecture
type: concept
tags: [watchman, fleet-architecture, manager-service, cardinality]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[manager-touchpoint-catalog]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-migration-plan.md
incoming_updated: 2026-05-30
---

# Manager Cardinality Decision — Per-Watch vs. Per-Site vs. Fleet-Singleton

The [[watch-entity|Watch]] Management Service can run at three cardinalities. The choice is **proposal-dependent**, not universal. Each per-proposal addendum recommends one.

## Three options

### Per-Watch supervisor (1:1)

One supervisor pod per armed [[watch-entity|Watch]]. Max isolation, max K8s object count.

| Property | Per-Watch |
|---|---|
| K8s objects per [[watch-entity|Watch]] | 1 supervisor + N workloads |
| Blast radius of bug | 1 [[watch-entity|Watch]] |
| Memory floor | High (N × baseline) |
| Reconciler complexity | Low (single resource) |
| Maps to today's model | Not at all |
| Fits K8s operator pattern | Possible |
| HA story | Each pod is its own SPOF |
| Fanout to forked shards | Trivial (one supervisor per [[watch-entity|Watch]]'s pod) |
| Cold-start parallelism | Parallel (one per [[watch-entity|Watch]]) |

### Per-site supervisor

One supervisor per customer site, managing all Watches at that site.

| Property | Per-site |
|---|---|
| K8s objects per [[watch-entity|Watch]] | Shared supervisor + N workloads |
| Blast radius of bug | 1 site (many Watches) |
| Memory floor | Medium |
| Reconciler complexity | Medium |
| Maps to today's model | Yes (1 customer ≈ 1 site) |
| Fits K8s operator pattern | Possible |
| HA story | Per-site SPOF |
| Fanout to forked shards | Needs pod-internal fanout |
| Cold-start parallelism | Serial within site |

### Fleet-singleton controller

One cluster-wide controller (K8s operator-style) watches a [[watch-entity|Watch]] CRD/table and reconciles all sites.

| Property | Fleet-singleton |
|---|---|
| K8s objects per [[watch-entity|Watch]] | 0 supervisors + N workloads |
| Blast radius of bug | Whole fleet |
| Memory floor | Low |
| Reconciler complexity | High ([[sharding]], ordering, leader election) |
| Maps to today's model | No |
| Fits K8s operator pattern | Yes — natural |
| HA story | Leader election / Raft (cf. B′ Blob Coordinator) |
| Fanout to forked shards | Needs pod-internal fanout |
| Cold-start parallelism | Parallel across sites, work-queue within |

## Per-proposal recommendation

| Proposal | Recommended cardinality | Why |
|---|---|---|
| A — Minimal Split | **Per-site supervisor** | Mirrors the surviving site-pod; manager is a contained per-site addition |
| B — Stage Fleets | **Fleet-singleton** | No per-site anchor; manager fills the "Camera Registry" placeholder |
| C — Camera-Worker | **Fleet-singleton** | Manager IS the Assignment Controller (already proposed as singleton + HA standby) |
| D — Event-Driven | **Fleet-singleton + per-Watch JetStream subjects** | Singleton publisher; per-Watch isolation via message bus, not K8s |
| E — Hybrid Sidecar | **Fleet-singleton** | Manager IS Site Context Service (already proposed centralized) |
| B′ — Coordinator+Raft | **Fleet-singleton (Raft 3-replica)** | Manager absorbs Blob Coordinator into unified FleetCoordinator |

Pattern: **all proposals with built-in coordinators (C, E, B′) and all proposals without per-site anchors (B, D) land on fleet-singleton.** Only A — which preserves the per-site pipeline pod — favors per-site supervisor.

## Why per-Watch (1:1) loses every comparison

Per-Watch is theoretically the cleanest blast-radius story but loses on every other dimension:

- **K8s object count explodes** (N_Watches × supervisor pods). Fleets today have ~5k Watches at projected granularity; that's 5k extra pods doing very little each.
- **Cold-start cost** is the same per [[watch-entity|Watch]] (memory, image pull, init) regardless of work volume.
- **Cross-Watch coordination** (e.g. "this customer's billing should aggregate all their armed Watches") is harder when each [[watch-entity|Watch]]'s supervisor is isolated.
- **Reconcile loop cost** is wasted — most Watches don't transition most of the time; a singleton can amortize.

Per-Watch may make sense as a *runtime topology* (e.g. one pod per [[watch-entity|Watch]] as the workload, not the supervisor — that's a different question, covered by briefing decision #6 / [[2026-05-28_watch-management-service-design]] Open Q6). But not as a supervisor cardinality.

## Cross-references

- [[2026-05-28_watch-management-service-design]] — origin tradeoff table
- [[2026-05-28_watch-management-proposal-a]] through `proposal-b-prime` — per-proposal recommendation rationale
- [[manager-touchpoint-catalog]] — how each touchpoint scales with cardinality
- [[2026-05-29_watch-manager-failure-modes]] — F-A (crash) and F-F (split-brain) behavior per cardinality
