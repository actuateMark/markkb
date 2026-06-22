---
title: Watch Manager — Proposal E (Hybrid Sidecar) Addendum
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, proposal-e, manager-service]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-04-16_proposal-e-hybrid-sidecar]]"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
incoming_updated: 2026-05-29
---

# Watch Manager — Proposal E (Hybrid Sidecar) Addendum

Master: [[2026-05-28_watch-management-service-design]]. Proposal: [[2026-04-16_proposal-e-hybrid-sidecar]].

## Proposal E in one paragraph

Smart Puller pods (per-family) + **Detection Core StatefulSet pod per camera-group** (10–50 cameras) + Alert Dispatch pods. State in StatefulSet pod memory, Redis snapshots. **Has a coordinator — Site Context Service** owning config, camera registry, and **centralized schedule eval** (`proposal-e-hybrid-sidecar.md:28,47-49,165`). "Site Context Service IS the ENG-96 fix" (`:166`).

## Where the manager lands

**Cardinality recommendation: fleet-singleton — the manager IS the Site Context Service.** Like Proposal C, this proposal already half-builds the manager; don't add a second controller, extend the one already proposed.

Per-Watch is wrong: too granular for E's camera-group topology.
Per-site is plausible (the Site Context Service is "site-scoped" in name) but the proposal's own design is a centralized service, not one per site — the "Site" in "Site Context" is the scoping of data, not the deployment cardinality.

## What's net-new vs. leveraging existing

**Most pre-built of any proposal.** Site Context Service already owns:

- Config + camera registry (T1, T4, T5 — [[watch-entity|Watch]] directives become first-class entries in the registry)
- Centralized schedule eval (T3 explicitly named)
- Camera-group assignment to Detection Core StatefulSet pods (T6, T11 implicit)

Extensions needed:

- **T2 manual-override entity** with `expires_at NOT NULL` — promote from today's Redis fields.
- **T7 VCH/AP CronJobs** — the proposal mentions "Smart Pullers handle pulling," but doesn't specify whether VCH/AP run on the existing pullers or separately. Cleanest answer parallel to C/D: VCH/AP become Watch-typed assignments from Site Context to Smart Pullers; no separate CronJobs.
- **T9 graceful arm/disarm via `replicas: 0/1`** — Detection Core StatefulSet pods are ordinal-managed; arming a [[watch-entity|Watch]] means assigning it to an existing StatefulSet ordinal, not creating a new pod. Disarm means removing the assignment, not scaling down.
- **T17 billing-event subscription** — Site Context observes `site_product_ended` from Detection Core to confirm runs.

## ENG-96 race

**Fixed by design.** The proposal explicitly calls out centralized schedule eval as the ENG-96 fix (`:166`). The manager extension just formalizes the schedule data model (replacing ScheduleV2 + FlexSchedule + Calendar with [[watch-entity|Watch]] + CalendarSet + ManualOverride).

## Sharding interplay

E uses StatefulSet ordinals as the [[sharding]] unit. The Detection Core StatefulSet pods get assignments from Site Context Service; pods don't fork in the connector sense (the StatefulSet handles per-camera-group isolation by pod boundary, not by `multiprocessing.Process`). Arm/disarm reaches pods via Site Context push (gRPC stream, etcd [[watch-entity|watch]], or NATS) and is honored without re-fork concerns.

## Fit verdict

**Tied with C for best fit.** The manager IS Site Context Service. The proposal explicitly puts schedule eval inside this service. The extensions are small and well-scoped: manual override, VCH/AP-as-assignments, billing-event subscription.

Comparison vs. C:

- C's Assignment Controller bin-packs cameras across customers; E's Site Context Service preserves site-grouping.
- C is more aggressive about retiring per-site identity; E retains it.
- For the manager's purposes, both work equally well — the manager design is identical, only the unit being assigned differs (camera in C, camera-group in E).

The choice between C and E for *manager fit* alone is a wash. The data-plane tradeoffs (bin-packing efficiency vs. per-site isolation) should drive the proposal selection.

## Alternative if poor fit

N/A — if E is rejected, the manager design is fine elsewhere. Manager fit is not a reason to reject E.
