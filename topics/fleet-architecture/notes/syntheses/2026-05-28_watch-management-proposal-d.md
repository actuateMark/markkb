---
title: Watch Manager — Proposal D (Event-Driven Pipeline) Addendum
author: kb-bot
created: 2026-05-28
updated: 2026-05-28
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, proposal-d, manager-service]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-04-16_proposal-d-event-driven]]"
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
incoming_updated: 2026-05-29
---

# Watch Manager — Proposal D (Event-Driven Pipeline) Addendum

Master: [[2026-05-28_watch-management-service-design]]. Proposal: [[2026-04-16_proposal-d-event-driven]].

## Proposal D in one paragraph

Pod per pipeline stage (Puller+FDMD, Detector, Observer+stateful, Alert), Deployments scaled on NATS JetStream consumer-lag. Frames in S3/MinIO (1h TTL); envelopes in NATS JetStream (durable until ACKed); tracker state in Observer fleet snapshotted to Redis. **No coordinator** — JetStream's own broker is the closest thing. "ENG-96 not fixed by default" (`proposal-d-event-driven.md:172`).

## Where the manager lands

**Cardinality recommendation: fleet-singleton.** Same situation as B: no per-Watch or per-site anchor in the topology. The manager must be cluster-scoped.

A wrinkle specific to D: the manager could ride JetStream itself. **Per-Watch JetStream subjects** are viable — `watch.{tenant}.{watch_id}` subject per [[watch-entity|Watch]], with arm/disarm directives, transition events, and pipeline envelopes all multiplexed on the subject. This gives near-per-Watch isolation in the message bus without per-Watch K8s resources. The manager remains a singleton but publishes to per-Watch subjects.

Per-Watch (as K8s objects) is wrong: stage fleets aren't per-Watch.
Per-site is wrong: sites aren't a topology unit.

## What's net-new vs. leveraging existing

Like B, D has no built-in controller — the manager is **mostly net-new** but with one large benefit: JetStream gives the manager free durable messaging. Mapping touchpoints:

- T1, T2, T3, T5: manager owns [[watch-entity|Watch]]+CalendarSet+ManualOverride domain. Publishes [[watch-entity|Watch]] state to a `watches.state` JetStream subject; stage fleets subscribe.
- T6: no per-Watch Deployments; the manager mutates [[watch-entity|Watch]] state published to JetStream, stage fleets read.
- T7 VCH/AP: similar to C's option (b) — VCH/AP become specially-typed envelopes injected into JetStream by the manager rather than separate CronJobs. The Puller+FDMD fleet picks up "vch envelope" and routes it like a normal frame, except detector + observer + alert see the `vch` flag and emit billing only. **This is the cleanest VCH model of any proposal** — VCH stops being a separate runtime concern entirely.
- T10, T16: reconcile loop reads from K8s API + JetStream consumer state. The manager's own state can live in JetStream KV (built-in HA).
- T17: `site_product_ended` is already a JetStream-publishable event — manager subscribes natively.
- T18: audit log is just another JetStream subject; routed to ClickHouse via a sink consumer.

The deeper question: **does the manager need a K8s-side actor at all in D?** If all arm/disarm flows through JetStream and stage fleets reconcile their work based on subject membership, the manager may never need to call `kubectl`. K8s objects (the stage-fleet Deployments) are static — they exist regardless of arming state. Arming becomes purely a message-bus concern.

## ENG-96 race

**Fixed by manager addition** — same as B. Manager is single source of truth; stage fleets read armed-state from manager-published state, not from local schedule eval.

## Sharding interplay

D has no explicit [[sharding]] — stage fleets autoscale on lag. Pod fork-safety doesn't apply because stage-fleet pods don't fork in the connector sense. The manager publishes once; consumers handle their own delivery.

## Fit verdict

**Strong fit for the manager — and D's "manager is just a JetStream publisher" model is the cleanest reconciler design of any proposal.** The downside is migration: D itself is a complete rewrite; the manager is bundled into that rewrite cost. Per-Watch JetStream subjects + manager-as-publisher is genuinely elegant if you're willing to commit to NATS as the central nervous system.

## Alternative if poor fit

If NATS JetStream is rejected (operational unfamiliarity, vendor risk), the manager design degrades to B's "fleet-singleton with separate state store" model. The manager works fine; the message-bus elegance is lost. At that point B and D become structurally similar from the manager's perspective and proposal choice should be made on data-plane grounds (NATS vs. Kafka vs. Redis Streams).
