---
title: Watch Manager — Proposal B (Stage Fleets) Addendum
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, proposal-b, manager-service]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-04-16_proposal-b-stage-fleets]]"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
incoming_updated: 2026-05-29
---

# Watch Manager — Proposal B (Stage Fleets) Addendum

Master: [[2026-05-28_watch-management-service-design]]. Proposal: [[2026-04-16_proposal-b-stage-fleets]].

## Proposal B in one paragraph

Five pipeline stage fleets (Puller, Motion, Inference-Coord, Observer+Filter, Alert), each a Deployment. Tracker/window state in the Observer fleet pod memory, snapshotted to Redis every 1s; windows to DDB. **No coordinator** — the diagram has a "Camera Registry (new central service)" placeholder (`proposal-b-stage-fleets.md:49`) but it's undeveloped. Config and schedule pulls "spread across 5 fleets; staleness widens. ENG-96 not fixed by default — needs explicit design (add a config/schedule service)" (`:162`).

## Where the manager lands

**Cardinality recommendation: fleet-singleton controller.** B has no per-site or per-Watch anchor — the data plane is stage-fleeted, sites no longer exist as a topology unit. A fleet-singleton (K8s operator pattern or leader-elected Deployment) is the only cardinality that maps. The "Camera Registry" placeholder is exactly where the manager slots in.

Per-Watch is wrong: B has no per-Watch resource to bind to.
Per-site is wrong: sites aren't a topology unit anymore; there's no per-site pod to attach a manager to.

## What's net-new vs. leveraging existing

The "Camera Registry" placeholder needs full design anyway, so the manager **becomes** the Camera Registry. Naming: rename the placeholder to `WatchCoordinator` or `FleetManager`. Responsibilities — every touchpoint from the master:

- T1, T2, T3, T5 (state surface): the manager owns [[watch-entity|Watch]]+CalendarSet+ManualOverride domain entirely. Admin becomes a thin CRUD facade.
- T6: no per-Watch Deployments to manage — instead the manager publishes [[watch-entity|Watch]] state to each stage fleet (via Kafka/NATS topic or a shared etcd key range).
- T7: VCH/AP — open question. B's stage-fleet decomposition doesn't naturally accommodate "run a one-shot health check on a single camera." Two options: (a) keep VCH/AP as separate CronJobs orchestrated by the manager, (b) absorb VCH into the Motion+Inference fleets as an explicit "healthcheck [[watch-entity|Watch]] type." (b) is cleaner; (a) is closer to today.
- T10, T16: reconcile loop becomes critical — five stage fleets each have their own opinions about who's running.

## ENG-96 race

**Fixed by manager addition.** Each stage fleet reads desired armed state from the manager (single source of truth), eliminating the per-pod schedule race. The manager's own clock + DST handling replaces `schedules_redeploy` and `was_redeployed_today`.

## Sharding interplay

[[sharding|Sharding]] is *implicit* in B — the stage fleets autoscale on metric/lag-based HPA, no explicit shard concept. The manager publishes [[watch-entity|Watch]] state at the camera ID level; each stage fleet consumer reads only the cameras assigned to its current Pods. No fork-safety concern because the stage-fleet pods don't fork in the connector sense.

## Fit verdict

**Manager is essential, not optional.** B is unworkable for arming without a fleet-singleton coordinator — the proposal's own evaluation rubric flags this (`proposal-b-stage-fleets.md:162`). Adding the manager is the same project as filling in the "Camera Registry" gap. The good news: B + manager + the [[2026-04-22_fleet-coordinator-api-sketch]] 15-RPC contract becomes equivalent to B′ in everything but the blob-lifecycle dimension.

## Alternative if poor fit

If a fleet-singleton is too risky (blast radius, HA complexity), B is probably the wrong proposal — its stage-fleet topology *demands* coordination. The next-cheapest variant is to back into Proposal A's per-site model (collapse the five stage fleets into one site pod) which is what Proposal A already is. Said another way: if you reject the manager in B, you reject B.
