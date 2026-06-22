---
title: Watch Manager — Proposal C (Camera-Worker Fleet) Addendum
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, proposal-c, manager-service]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-04-16_proposal-c-camera-worker]]"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-backend-io-contract.md
incoming_updated: 2026-05-30
---

# Watch Manager — Proposal C (Camera-Worker Fleet) Addendum

Master: [[2026-05-28_watch-management-service-design]]. Proposal: [[2026-04-16_proposal-c-camera-worker]].

## Proposal C in one paragraph

Generic camera-worker pods, each bin-packed with cameras across multiple customer sites by an **Assignment Controller** (singleton + HA standby). Workers run full pipeline per camera; tracker state in pod memory, snapshotted to Redis at 1 Hz. Camera→worker mapping is TTL-leased. The Assignment Controller "naturally owns schedule context; camera assignment includes armed-state snapshot" — fixes ENG-96 by design (`proposal-c-camera-worker.md:159`).

## Where the manager lands

**Cardinality recommendation: fleet-singleton — the Assignment Controller IS the manager.** Don't add a second controller; extend the existing one. The proposal's open questions already anticipate this absorption.

Per-Watch is wrong: workers aren't per-Watch.
Per-site is wrong: sites aren't a deployment unit; one worker handles cameras from multiple sites.

## What's net-new vs. leveraging existing

**Manager is mostly built — extend, don't recreate.** Assignment Controller already owns:

- Camera→worker assignment (subsumes T1, T5 once [[watch-entity|Watch]] becomes a first-class assignment input)
- TTL leases + worker lifecycle (subsumes T10, T16 reconciler shape, T13 graceful teardown via drain)
- "Armed-state snapshot included in camera assignment" — the manager's source-of-truth role for arming is already in the proposal

What needs to be added on top:

- **T2 manual-override entity** with `expires_at NOT NULL` (replaces today's Redis MotionStatus debounce).
- **T3 DST/day-boundary schedule re-derivation** — currently described as "Assignment Controller naturally owns schedule context" but the schedule-eval mechanics need to be specified. The brainstorm's Option B runner pattern (~30–60s tick, pure function evaluation) maps directly.
- **T7 VCH/AP CronJobs** — Proposal C doesn't address these. Options: (a) Assignment Controller emits VCH/AP CronJobs per `(camera, product)` [[watch-entity|Watch]]; (b) VCH/AP become "ephemeral assignments" — the Controller assigns "health-check this camera for 2s" as a special assignment type, no CronJob needed. (b) is more aligned with C's bin-packing philosophy and avoids the K8s CronJob fleet management problem.
- **T17 billing-event subscription** — the Controller needs to observe SQS `site_product_ended` to confirm assignments actually ran for billing accuracy.
- **T11 K8s gateway decision** — does the Controller talk K8s API directly to manage worker Deployments, or does it call `connector_deployer`? Cleanest answer: Controller talks K8s directly; deployer is retired (its responsibilities reduce to "ensure the worker StatefulSet exists" which Helm/[[argocd|ArgoCD]] already does).

## ENG-96 race

**Fixed by design.** Per the proposal: armed-state is snapshot into the assignment; workers don't recompute schedule locally. Manager extension formalizes this (T5).

## Sharding interplay

C dissolves the per-site [[sharding]] model entirely — bin-packing IS the [[sharding]] mechanism, and the Controller is the only thing that needs to know assignments. No fork-safety concern for the manager (the Controller is its own pod). Workers themselves may still fork internally for their per-camera pipelines; arm/disarm signals reach them via the existing assignment-update push (NATS / etcd [[watch-entity|watch]] / gRPC stream from Controller).

## Fit verdict

**Best fit of any proposal.** The manager IS the Assignment Controller with three extensions (manual-override entity, schedule re-derivation, VCH/AP as ephemeral assignments). The proposal's own open questions are exactly the manager design questions. No "should we add a manager" conflict — the proposal already has one.

## Alternative if poor fit

N/A — if C is rejected, it's rejected for reasons other than the manager (bin-packing complexity, worker rebalancing storm risk, Redis snapshot cost). The manager itself is well-served by C.
