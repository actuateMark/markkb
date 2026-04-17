---
title: Fleet Architecture Redesign
type: summary
topic: fleet-architecture
tags: [architecture, fleet, kubernetes, redesign, microservices, connector, scaling]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Fleet Architecture Redesign

Planning, evaluation, and prototyping work for moving the VMS Connector off its current **site-per-pod monolith** toward a **fleet-based multi-deployment architecture**. Each fleet (puller, inference, observer, alert, etc.) scales independently on Kubernetes and isolates failures.

This topic is the workspace for the redesign effort — candidate architectures, cross-cutting design docs, PoC results, and the eventual selection.

## Why this exists

The connector today runs **one K8s pod per customer site** carrying the full pipeline with 30+ library deps. It shards via multiprocessing at 24 cameras (50-80% CPU overhead per shard boundary). Known pain:

- **ENG-78** — VPA over-provisions because burst+steady workloads share one pod
- **ENG-96** — schedule race conditions from distributed schedule eval
- **ENG-66** — alert-sender event-listener thundering herd
- **Any pipeline crash = whole site dark**
- **Fork-safety complexity** across a 30-library stack

See [[vms-connector/notes/syntheses/performance-optimization-landscape]] for the bottleneck map that prompted this redesign.

## Candidate Architectures

| Proposal | Core idea | Scaling unit | Timeline | Cost delta |
|----------|-----------|--------------|----------|-----------|
| [[2026-04-16_proposal-a-minimal-split\|A — Minimal Split]] | Extract puller + alerts, keep pipeline monolith | Site | 12-16 wks | +10-15% |
| [[2026-04-16_proposal-b-stage-fleets\|B — Stage Fleets]] | Every pipeline stage is its own fleet | Per-stage | 24-32 wks | +15-25% |
| [[2026-04-16_proposal-c-camera-worker\|C — Camera-Worker Fleet]] | Generic workers, cameras bin-packed across sites | Camera | 13-20 wks | -15-30% |
| [[2026-04-16_proposal-d-event-driven\|D — Event-Driven Pipeline]] | NATS JetStream + S3 frame refs | Per-stage | 20-29 wks | ~neutral |
| [[2026-04-16_proposal-e-hybrid-sidecar\|E — Hybrid Sidecar]] | Smart pullers + stateful core + async alerts | Puller=cam, Core=cam-group | 14-20 wks | -20-40% |

## Cross-Cutting Designs

| Document | Purpose |
|----------|---------|
| [[2026-04-16_graceful-failover-design]] | Tracker + window checkpointing for graceful worker failover |
| [[2026-04-16_frame-transport-comparison]] | Redis Streams vs NATS vs SNS/SQS vs S3-refs |
| [[2026-04-16_evaluation-rubric]] | Scoring criteria and weights for the PoC competition |

## Cross-Plan Considerations (apply to multiple proposals)

| Document | Cross-cutting concern |
|----------|-----------------------|
| [[2026-04-16_frame-transport-comparison]] | How frames move between services — Redis / NATS / S3 / SQS tradeoffs + AWS-EKS deployment specifics |
| [[2026-04-16_graceful-failover-design]] | Tracker + window checkpointing for graceful worker failover |
| [[inference-api-interaction]] | Placement of `AsyncInferencePool` and AIMD per proposal |
| [[library-decomposition-required]] | What changes in the 41-package `actuate-libraries` monorepo per proposal |
| [[observability-and-tracing]] | NR / OTel requirements; when distributed tracing becomes mandatory |
| [[downstream-consumer-impact]] | How Watchman, AutoPatrol, CHM, and alert integrations are affected |
| [[config-and-schedule-propagation]] | admin-api config flow + ENG-96 schedule-race fix per proposal |
| [[memory-and-fork-safety]] | jemalloc, PooledTTLImageCache, fork-safety per proposal |
| [[customer-site-connectivity]] | NAT/VPN/public/WireGuard topology — **incomplete**, blocks puller fleet design for C in particular |

## Concepts (verified findings)

| Document | What it proves |
|----------|----------------|
| [[blacklist-filter-locality]] | BlacklistFilter R-tree is per-camera, not per-site — camera splitting is safe |
| [[tracker-snapshot-schema]] | BoTSORT state is serializable; defines snapshot format |

## Open blockers (before PoC selection)

- **`kubernetes-deployments` + `connector_deployer` deep dive** — we need authoritative info on how sites are launched today and what fraction use WireGuard vs public vs NAT. This affects puller fleet design across all 5 proposals and is a potential deal-breaker for C. Queued in [[_dive-queue]].

## Decisions locked in during interview (2026-04-16)

| Question | Answer |
|----------|--------|
| Primary criterion | **Independent scalability** (secondary: cost reduction; isolation/simplicity also weighed) |
| Fleet size target | **Design for elasticity** — scale from today to 10× without re-architecture |
| Cross-camera state | **Per-camera** (verified) — splitting a site across workers is safe |
| State loss on worker death | **Need graceful failover** — snapshot + resume tracker/windows |
| Puller pool strategy | **Per-proposal sub-plan** |
| Prototype strategy | **Targeted PoCs** — build only the novel/risky piece per candidate |
| Candidate set | **All 5** — A, B, C, D, E get full treatment |

## Status

- 2026-04-16 — interview complete, all 5 proposal syntheses + cross-cutting docs drafted
- 2026-04-16 — PoCs not yet built (targeted PoC specs live in each proposal note)
- Next — build targeted PoCs, score via [[2026-04-16_evaluation-rubric]], write selection synthesis

## Pre-PoC score estimates

Rubric applied before any PoC runs. PoCs may move these numbers materially (cost and failover scores in particular are speculative until benchmarked).

| # | Proposal | Composite / 10 |
|---|----------|---------------:|
| 1 | [[2026-04-16_proposal-e-hybrid-sidecar\|E — Hybrid Sidecar]] | **8.05** |
| 2 | [[2026-04-16_proposal-c-camera-worker\|C — Camera-Worker]] | 7.40 |
| 3 | [[2026-04-16_proposal-b-stage-fleets\|B — Stage Fleets]] | 7.25 |
| 4 | [[2026-04-16_proposal-d-event-driven\|D — Event-Driven]] | 6.85 |
| 5 | [[2026-04-16_proposal-a-minimal-split\|A — Minimal Split]] | 4.25 |
| — | Today's baseline | 3.20 |

## Related Topics

- [[vms-connector/_summary]] — current architecture being redesigned
- [[software-architecture/_summary]] — governance and enforcement (post-selection scope)
- [[infrastructure/_summary]] — K8s, VPA, deployment pipelines
- [[actuate-libraries/_summary]] — pipeline libraries that may need decoupling
