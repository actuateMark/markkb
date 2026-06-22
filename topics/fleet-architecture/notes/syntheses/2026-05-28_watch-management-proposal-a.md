---
title: Watch Manager — Proposal A (Minimal Split) Addendum
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, proposal-a, manager-service]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-04-16_proposal-a-minimal-split]]"
incoming:
  - topics/fleet-architecture/notes/concepts/cardinality-decision.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/personal-notes/notes/daily/2026-05-28.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
incoming_updated: 2026-05-30
---

# Watch Manager — Proposal A (Minimal Split) Addendum

Master: [[2026-05-28_watch-management-service-design]]. Proposal: [[2026-04-16_proposal-a-minimal-split]].

## Proposal A in one paragraph

Per-family puller pods, **per-site pipeline worker** (unchanged from today), pod-fleet alert dispatch. State stays in-pod for the pipeline worker; ephemeral frames in Redis Streams; windows in DDB WindowIdsV2. **No coordinator.** Schedules and config flow the same way they do today.

## Where the manager lands

**Cardinality recommendation: per-site supervisor.** The per-site pipeline worker is the unit-of-deployment and the only natural anchor; the proposal kills neither it nor today's K8s shape (one Deployment per customer). A per-site manager sidecars or sits next to the pipeline worker, owning that worker's lifecycle + its associated VCH/AP CronJobs.

Per-Watch is wrong for A: the proposal preserves "one pod handles all of a customer's products," and Watches share the pod — a 1:1 supervisor would multiply pods without changing the data plane.

Fleet-singleton is wrong for A: A's value proposition is *minimal* change. Bolting on a cluster-wide controller while keeping the rest static is the worst of both worlds — you take the migration cost of (B/D)-class manager without any of (C/E/B′)-class data-plane payoff.

## What's net-new vs. leveraging existing

A has nothing pre-built to absorb. The manager is **net-new but contained**: a per-site controller (one Deployment per customer or a sidecar container in the pipeline worker pod) replacing:

- `ConnectorController.start_connector / stop_connector` (T6)
- `AutoPatrolSchedule.deploy/undeploy` and `Healthcheck.handle_healthcheck_cronjob` (T7)
- The `schedule_processor → schedule_deployer → connector_deployer` chain (T8, T10)

Touchpoints that don't need rebuild because A doesn't change the data plane: T2 (manual override), T4 (image tag), T12 (wait-for-ready), T13 (graceful teardown), T15 (don't double-fire Immix calls).

## ENG-96 race

**Not fixed by Proposal A.** A keeps per-pod schedule reads (`proposal-a-minimal-split.md:146`); the manager would still race the per-site pipeline worker unless arming evaluation moves into the manager. **Manager addition forces a fix** — once the manager exists, the pipeline worker reads "armed" from the manager (or from a single coordinated state row) instead of recomputing locally. This is the strongest reason to add the manager *within* Proposal A even though A itself doesn't ask for one.

## Sharding interplay

A retains `ChunkedSiteManager` semantics. A per-site manager pushes arm/disarm signals to the pipeline worker; the worker fans out to its forked shards via shared memory or settings-file-replacement-then-SIGHUP. The manager NEVER injects threads pre-fork (constraint #2).

## Fit verdict

**Workable but underwhelming.** A per-site manager fixes ENG-96 and unifies the three current actuators (admin Django-Q chain + connector_deployer + VCH/AP CronJob owners), but Proposal A's small data-plane delta means most of the manager's machinery is paying for itself only on the schedule/lifecycle side. If the team picks A, the manager work is still worth doing — but it doesn't buy as much per dollar as it does in C/E/B′.

## Alternative if poor fit

If the appetite for net-new components inside A is low, a **degenerate manager** is acceptable: a thin replacement for `schedule_processor` + `schedule_deployer` that owns the django-q chain rewrite without becoming a per-site daemon. This loses T10 (reconcile-loop / observed-state-as-truth) and most of T16 (periodic K8s resync) but keeps T1, T2, T6, T7, T8. It's the "scheduler stands up *one thing*" goal at a reduced scope — the one thing is a cron call into the new scheduler service, which then does the connector_deployer dance.
