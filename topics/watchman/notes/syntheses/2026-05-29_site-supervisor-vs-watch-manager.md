---
title: Site Supervisor Agent vs. Watch Management Service — Relationship Decision
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: watchman
type: synthesis
tags: [watchman, fleet-architecture, manager-service, site-supervisor, agent-architecture]
related:
  - "[[topics/watchman/_summary]]"
  - "[[2026-05-29_watchman-prds-summary]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watch-management-service-index]]"
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/482344961"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/watchman/_summary.md
  - topics/watchman/notes/concepts/watch-entity.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-backend-io-contract.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-prds-summary.md
incoming_updated: 2026-05-30
---

# Site Supervisor Agent vs. Watch Management Service — Relationship Decision

## Why this note exists

Reading the [[2026-05-29_watchman-prds-summary|Watchman PRDs]] surfaced an unresolved first-order design decision: **the Site Supervisor Agent (PROD-147) and the [[watch-entity|Watch]] Management Service we've been designing have overlapping scope.** Neither the May 28 syntheses nor the PRDs name this conflict. This note pins it down, lays out three resolution options, and recommends one.

## The overlap

| Dimension | Site Supervisor Agent (PROD-147) | [[watch-entity|Watch]] Management Service (May 28 design) |
|---|---|---|
| Shape | Continuous daemon | Continuous daemon (Option B runner) |
| Scope | Per-site (one per customer site, conceptually) | Per-proposal — per-site, per-Watch, or fleet-singleton |
| Owns | Mode state machine (Patrol ↔ Active), agent coordinator, resource allocator | [[watch-entity|Watch]] lifecycle, K8s primitives, schedule eval, manual override |
| Triggers on | Live events (precursor/threat fires), agent outputs | Calendar tick + manual override + arm/disarm directive |
| Mutates | Detection pod resource allocation, agent invocation | K8s Deployments / VPAs / CronJobs, manager state |
| State store | Redis (per-spec) + DynamoDB (rhythm/timeline) | Manager-pick: Postgres / Redis / Raft (per [[2026-05-28_watch-management-service-design]] open Q1) |
| Bus | Kafka | TBD — SQS today, Kafka under [[watchman-repo|Watchman]] |

Both daemons need to know:
- What Watches exist at a site
- Which cameras are in each [[watch-entity|Watch]]
- What products are configured per [[watch-entity|Watch]]
- What the current armed-state is
- What's happening in real-time (events, transitions)

Both daemons mutate connector behavior — Site Supervisor via "bump FPS during Active mode," [[watch-entity|Watch]] Manager via "arm or disarm [[watch-entity|Watch]] X." If they're separate daemons, they race to mutate the same pod.

## Three resolution options

### Option I — Single daemon (manager IS the Site Supervisor substrate)

The [[watch-entity|Watch]] Management Service is the runtime; the Site Supervisor Agent is a *layer of behavior* inside it. Mode state machine lives in manager state; mode transitions are reconcile-loop outcomes; "bump FPS on mode change" is a mutation issued by the manager's actuator path. Other agents (Patrol, Threat, Assessment, etc.) remain separate; the manager is the single per-site authority over the data plane.

**Pros.** No race. One pod per site. One reconcile loop. Single audit trail. Schedule + mode + manual override evaluated in one place. Maps cleanly to proposals C/E/B′ where the manager is already a fleet-singleton/coordinator.

**Cons.** The Site Supervisor's mode-derivation logic is event-driven (consumes precursor/threat fires from Kafka); the manager's schedule-derivation is time-driven (tick + DB read). Forcing both into one daemon couples their failure modes — a Kafka partition that blocks mode derivation also blocks schedule eval, even though schedule eval doesn't need Kafka. Also blurs ownership; harder to staff.

### Option II — Two daemons, manager is upstream (Site Supervisor is a tenant)

[[watch-entity|Watch]] Management Service publishes armed-state + [[watch-entity|Watch]] config; Site Supervisor Agent reads from it, runs its mode state machine, and issues *its own* mutations to the data plane. Manager owns "is this [[watch-entity|Watch]] armed?"; Site Supervisor owns "given armed Watches, what mode is this site in and how should we allocate resources?"

**Pros.** Clean separation of concerns: schedule/lifecycle vs. event-driven orchestration. Each can fail independently. Manager's failure mode is "armed states stop transitioning"; Site Supervisor's failure mode is "mode stays in Patrol" — both degrade gracefully. Maps to today's connector-deployer pattern (admin owns schedule, deployer owns K8s) — [[watchman-repo|Watchman]] generalizes that split.

**Cons.** Two daemons both mutate the connector pod (manager via K8s, Site Supervisor via runtime config). Need a contract — e.g. manager owns cold-start / scale / arm boundary; Site Supervisor owns hot-reconfigure of an already-armed pod. Defining the contract is hard. Race conditions on overlapping mutations need an explicit precedence rule.

### Option III — Two daemons, peers sharing state

Both read from a shared state store; neither is upstream. Coordination via explicit locks or CRDT-style merge. Each daemon claims a non-overlapping subset of mutations (e.g. manager owns Deployments + CronJobs; Site Supervisor owns ConfigMap updates only).

**Pros.** Maximum independence; either can be rewritten without touching the other.

**Cons.** Coordination is fragile (shared-state races); needs strong consensus or external lock service. Two-daemon teamwork mistakes show up as silent inconsistencies. Probably needs Raft (push everyone toward [[2026-05-28_watch-management-proposal-b-prime|Proposal B′]]'s FleetCoordinator).

## Recommendation — Option II, with manager as authoritative source-of-truth for armed-state

**Pin the boundary at "armed-state vs. resource allocation."** The [[watch-entity|Watch]] Management Service owns:
- [[watch-entity|Watch]] definition and lifecycle
- Schedule evaluation + manual override
- K8s primitive create/delete (Deployments, CronJobs)
- Cold-start arm and disarm
- The `site_product_*` billing-event observation

The Site Supervisor Agent reads armed-state from the manager (subscribe to manager's transitions topic) and owns:
- Mode state machine (Patrol ↔ Active)
- Per-mode resource allocation (FPS bumps, agent invocation)
- Hot-reconfigure of already-armed pods (constraint #3 relaxation lives here)
- Per-mode agent coordination (Patrol Agent invocation, Assessment Agent triggering)

**Contract pinning rules:**
1. Site Supervisor can hot-reconfigure an armed pod but **cannot** arm or disarm a [[watch-entity|Watch]] directly — it goes through the manager.
2. Manager **cannot** mutate runtime FPS or pod resource limits — it issues create/delete, not patches.
3. Both write structured audit events to a shared transitions topic for downstream observability.
4. Manager → Site Supervisor is push (manager publishes armed-state changes to Kafka); Site Supervisor → manager is pull (Site Supervisor queries manager state, doesn't issue commands).

This boundary maps cleanly onto today's admin-vs-deployer split: admin owns "should this site be running"; deployer owns "make K8s match." [[watchman-repo|Watchman]] generalizes the split with Site Supervisor adding a mode-aware runtime layer.

## What this means per fleet-arch proposal

| Proposal | Site Supervisor placement | Manager placement |
|---|---|---|
| A | Per-site sidecar to the pipeline worker | Per-site (sibling sidecar) |
| B | Fleet-singleton with per-site tenancy | Fleet-singleton (the "Camera Registry" gap) |
| C | Per-site tenant inside the Assignment Controller's worker | Fleet-singleton (Assignment Controller extended) |
| D | Fleet-singleton consumer subscribing to per-Watch JetStream subjects | Fleet-singleton publisher |
| E | Per-camera-group tenant inside the Detection Core StatefulSet | Fleet-singleton (Site Context Service extended) |
| B′ | Per-site tenant inside the FleetCoordinator's RPC API | Fleet-singleton (Coordinator absorbed) |

Pattern: **Site Supervisor is per-site in scope; manager is fleet-wide. They run on different cardinalities.** Update each addendum to reflect this.

## Open follow-ups

1. **Hot-reconfigure mechanism** — the connector has no settings-reload path today. Adding one is a significant change; should be a separate workstream (target ticket: TBD). See [[2026-05-28_watch-management-service-design]] constraint #3.
2. **Transitions topic schema** — what does the manager publish on Kafka? Suggested: `{watch_id, from, to, cause, now, idempotency_key}`. Land in [[2026-05-29_watch-manager-observability]].
3. **Mode-change billing impact** — does a mode flip count as a new run for `site_product_*` purposes? If yes, billing semantics need a "mode_run_id" alongside the current run identification.
4. **Failure correlation** — if manager partitions from Kafka, Site Supervisor can't see [[watch-entity|Watch]] changes. Document under [[2026-05-29_watch-manager-failure-modes]].
5. **Code home for Site Supervisor** — fresh repo, extend `Watchman/api.py`, or live inside the same manager codebase under Option II? See [[2026-05-29_watchman-prds-summary]] for repo state.
