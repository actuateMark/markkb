---
title: Watch Management Service — Index (Watchman cross-ref)
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: watchman
type: synthesis
tags: [watchman, scheduling, fleet-architecture, manager-service]
related:
  - "[[topics/watchman/_summary]]"
  - "[[topics/fleet-architecture/_summary]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/personal-notes/notes/daily/2026-05-28.md
  - topics/watchman/_summary.md
  - topics/watchman/notes/syntheses/2026-05-29_site-supervisor-vs-watch-manager.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-backend-io-contract.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-prds-summary.md
incoming_updated: 2026-05-30
---

# Watch Management Service — Index (Watchman cross-ref)

This index sits inside the **[[watchman-repo|Watchman]]** topic and points outward to the cross-architecture analysis that lives under [[topics/fleet-architecture/_summary]].

## Why this is a Watchman concern

The [[watchman-repo|Watchman]] scheduling brainstorm (Confluence PM/601686018) introduces the `Watch = (site, cameras[], product)` runtime entity. The fleet-arch redesign work (proposals A–E + B′) is the **platform layer** that implements [[watch-entity|Watch]] lifecycle. The two threads must be reasoned about together — [[watchman-repo|Watchman]]'s UX/data model + the fleet rework's runtime placement.

## Read in order

1. [[2026-05-29_watchman-prds-summary]] — **Start here.** Fact-sheet of PM/478019585 (PRD v2) and PM/482344961 (Agent Specs). Establishes Operating Modes (Patrol/Active) as site-level state managed by Site Supervisor Agent, **orthogonal to [[watch-entity|Watch]] arming**; agent roster; Kafka bus; direct-to-operator escalation (not Immix); Patrol Agent replaces connector AutoPatrol.
2. [[2026-05-28_watchman-scheduling-brainstorm-correlation]] — Original [[watchman-repo|Watchman]] brainstorm correlated against the connector's current `(site, camera, product)` model. Establishes the **gap analysis**: the brainstorm references an "override-service" and "v9-v10 architecture summary" that don't exist in the KB; the connector has no arm/disarm concept; Watches project onto today's code as a predicate over `(camera, stream, feature_deployment)` tuples.
3. [[2026-05-28_watch-management-service-design]] — **Master design note.** Constellation baseline (Django-Q + ScheduleV2 + connector_deployer + in-pod lifecycle), 10 cross-cutting constraints any manager must honor (billing emission, fork-safety, no settings reload, etc.), 18-touchpoint catalog, three cardinality options. **Updated 2026-05-29** with constraint #3/#8 sunset notes and resolved Open Questions.
4. [[2026-05-29_site-supervisor-vs-watch-manager]] — First-order decision: how Site Supervisor Agent (PROD-147) and [[watch-entity|Watch]] Management Service relate. Three options; recommends Option II (manager upstream as armed-state source-of-truth, Site Supervisor as tenant for mode-aware hot-reconfigure).
5. Per-proposal addenda (one per fleet-arch proposal):
   - [[2026-05-28_watch-management-proposal-a]] — Minimal Split: per-site supervisor, net-new but contained
   - [[2026-05-28_watch-management-proposal-b]] — Stage Fleets: fleet-singleton, manager IS the "Camera Registry" placeholder
   - [[2026-05-28_watch-management-proposal-c]] — Camera-Worker: fleet-singleton, manager IS the Assignment Controller (extend, don't recreate) — **strong fit**
   - [[2026-05-28_watch-management-proposal-d]] — Event-Driven: fleet-singleton with per-Watch JetStream subjects; cleanest VCH-as-envelope model
   - [[2026-05-28_watch-management-proposal-e]] — Hybrid Sidecar: manager IS Site Context Service — **strong fit (tied with C)**
   - [[2026-05-28_watch-management-proposal-b-prime]] — Stateless w/ Coordinator: manager IS the FleetCoordinator (Raft) — **strong fit (tied), strongest correctness story**

## TL;DR fit ranking

| Proposal | Verdict | Why |
|---|---|---|
| B′ | Strong | Coordinator already proposed; Raft gives linearizable arm/disarm |
| C | Strong | Assignment Controller already proposed; manager IS it + small extensions |
| E | Strong | Site Context Service already proposed; manager IS it + small extensions |
| D | Strong (different) | Per-Watch JetStream subjects; manager is mostly a publisher; cleanest VCH model |
| B | Required | Manager is the unfilled "Camera Registry" gap; without it, B doesn't work |
| A | Workable | Per-site manager fixes ENG-96 within A's small data-plane delta; manager pays for itself less |

## Round 2 (2026-05-29) follow-up notes

- [[2026-05-29_watchman-prds-summary]] — PRD v2 + Agent Specs digest
- [[2026-05-29_site-supervisor-vs-watch-manager]] — relationship decision
- [[2026-05-29_watch-manager-observability]] — metrics, traces, audit, SLOs (covers touchpoint T18 in depth)
- [[2026-05-29_watch-manager-migration-plan]] — 5-phase cutover from Django-Q constellation
- [[2026-05-29_watch-manager-failure-modes]] — partition behavior + invariants
- [[2026-05-29_ait-watch-manager-integration]] — testing + instrumentation via AIT/brain-in-jar (10 fixtures, 12 hooks, 8 Hypothesis properties)
- [[2026-05-29_watchman-judge-backend-io-contract]] — Judge wire-protocol analysis, decisions captured, 12-item conflict register
- [[2026-05-29_watchman-judge-immix-integration]] — Immix factored out as a separate concern (not a peer of Django in fan-out)

## Open items (post-Round-2)

Resolved in Round 2:
- ~~Operating Modes vs. [[watch-entity|Watch]]~~ — orthogonal; modes are site-level Site-Supervisor state.
- ~~PRD v2 / Agent Specs unread~~ — digested in [[2026-05-29_watchman-prds-summary]].
- ~~Migration cutover~~ — see [[2026-05-29_watch-manager-migration-plan]].

Still open:
- **Hot-reconfigure mechanism** for the connector — constraint #3 relaxation. Net-new workstream.
- **Kafka adoption timeline** — bridging from today's SQS billing pipe.
- **"v9-v10 architecture summary"** — brainstorm premise still unresolved with doc author.
- **Cost model per proposal** — pod count, AWS-resource count, Raft StatefulSet vs. NATS JetStream vs. EventBridge fanout.
- **Multi-region / multi-cluster** — PRD §11 + §17 hint at AWS Local Zones + EU residency.
- **RBAC for arm/disarm** — Enterprise tier in PRD §13.

## Cross-references

- Brainstorm: [Watchman Scheduling — Brainstorm](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/601686018)
- Fleet-arch summary: [[topics/fleet-architecture/_summary]]
- FleetCoordinator API sketch: [[topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-coordinator-api-sketch]]
- [[watchman-repo|Watchman]] summary: [[topics/watchman/_summary]]
