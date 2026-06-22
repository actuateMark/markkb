---
title: Fleet Architecture Redesign
type: summary
topic: fleet-architecture
tags: [architecture, fleet, kubernetes, redesign, microservices, connector, scaling]
created: 2026-04-16
updated: 2026-06-01
author: kb-bot
---

# Fleet Architecture Redesign

Planning, evaluation, and prototyping work for moving the [[vms-connector|VMS Connector]] off its current **site-per-pod monolith** toward a **fleet-based multi-deployment architecture**. Each fleet (puller, inference, observer, alert, etc.) scales independently on Kubernetes and isolates failures.

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

## Cloud Video Analytics v10 Platform Reference (2026-06-01)

Received external architecture proposal: **Cloud Video Analytics Platform v10** — a fully designed, multi-tenant SaaS for ~100k cameras (us-west-2, cloud-only, no edge). **This is a forward-looking reference architecture, not a fleet proposal; see below for how it relates to A–E.**

Key contributions to the fleet-arch design space:
- **Validates Redis Streams** (frame-bus pattern) at scale; specifies JPEG settings + motion-polygon payload
- **Introduces detector-router** (NEW component): routes per-(camera, product) state to decoder pools, realizes cost savings
- **Two-stage scheduler-service** resolution (lifecycle → product activation) with sparse rule storage + 5-level precedence
- **Site-state-service as v1 core** (not premium): real-time per-site rollups + LLM tools
- **Observability split** (NR + ClickHouse): saves $50-100k/mo at scale
- **2026 silicon roster:** Graviton4, Inf2, G6e, G7e Blackwell (new Feb 2026), Trn2

Start here: [[2026-06-01_v10-cloud-platform-vs-fleet-proposals]] — situates v10 against proposals A–E. Then read:
- [[2026-06-01_cloud-video-analytics-platform-v10|v10 source architecture note]]
- [[2026-06-01_v10-scheduler-and-state-resolution|Deep dive: scheduler + per-camera-per-product state]]
- **IMPORTANT:** [[2026-06-01_terminology-conflict-watchman-ambiguity|Watchman terminology conflict flag]] — v10 defines [[watchman-repo|Watchman]] as on-prem product, KB defines as cloud. Requires clarification.

## Watch Management Service & Watchman MVP Slim Connector (2026-05-28 / 2026-06-01 — Watchman integration)

The fleet-arch redesign is now part of the **[[watchman-repo|Watchman]]** umbrella. New cross-cutting design: every proposal needs a **[[watch-entity|Watch]] Management Service** that owns [[watch-entity|Watch]] lifecycle (setup/teardown, [[healthchecks]], arm/disarm). Also: new **[[watchman-repo|Watchman]] MVP Slim Connector** — a minimal [[rtsp-deep-dive|RTSP]]→inference→Watchman-services path built to feed the cloud platform as an alternative to the full monolith. Start here:

- **[[2026-06-01_adr-watchman-mvp-slim-connector|Watchman MVP Slim Connector Design]]** (2026-06-01) — **fresh entrypoint for cloud [[watchman-repo|Watchman]] platform:** [[rtsp-deep-dive|RTSP]]→inference→sink with motion toggle and confidence+zone filtering. No window/billing/blacklist overhead. Architecture enables growth into Proposals A & E via pluggable `WatchmanSink` interface. **Confirmed:** modern `actuate-inference-client`, HTTP POST default, per-camera motion OFF by default. **Open:** event schema, inference API surface, repo location, config delivery model.
- [[2026-05-28_fleet-rearch-briefing-overview]] — **5-minute briefing.** TL;DR + proposal one-paragraphs + decisions needed.
- [[2026-05-28_watch-management-service-design]] — master design: constellation baseline, 10 cross-cutting constraints, 18-touchpoint catalog, three cardinality options.
- Per-proposal addenda: `2026-05-28_watch-management-proposal-{a,b,c,d,e,b-prime}.md`
- [[2026-05-29_watchman-prds-summary]] — PRD v2 + Agent Specs digest (Operating Modes orthogonal to [[watch-entity|Watch]]; Site Supervisor / Patrol / Connectivity agents; Kafka bus; direct-to-operator escalation).
- [[2026-05-29_site-supervisor-vs-watch-manager]] — first-order decision: how Site Supervisor Agent and the manager relate.
- [[2026-05-29_watch-manager-observability]] — metrics, traces, audit log, SLOs.
- [[2026-05-29_watch-manager-migration-plan]] — 5-phase cutover from Django-Q.
- [[2026-05-29_watch-manager-failure-modes]] — partition behavior + invariants.
- [[2026-05-29_ait-watch-manager-integration]] — AIT/brain-in-jar testing + instrumentation hooks.
- [[2026-05-29_watchman-judge-backend-io-contract]] — alert ingest + disposition wire-protocol analysis.
- [[2026-05-29_watchman-judge-immix-integration]] — Immix integration factored separately.
- Concept anchors: [[manager-touchpoint-catalog]], [[cardinality-decision]], [[watch-entity]], [[calendar-set]].

## Cross-Cutting Designs

| Document | Purpose |
|----------|---------|
| [[2026-04-16_graceful-failover-design]] | Tracker + window checkpointing for graceful worker failover |
| [[2026-04-16_frame-transport-comparison]] | Redis Streams vs NATS vs SNS/SQS vs S3-refs |
| [[2026-04-16_evaluation-rubric]] | Scoring criteria and weights for the PoC competition |
| [[k8s-controller-selection-guide]] | Deployment vs StatefulSet vs DaemonSet per fleet workload |
| [[k8s-placement-primitives]] | TSC + pod-affinity + PDB co-design (and deadlock-avoidance rules) |
| [[pod-termination-sequence]] | preStop / SIGTERM / SIGKILL handshake; enables tracker-snapshot handoff |
| [[scaling-layer-taxonomy]] | HPA + VPA + Karpenter layer interaction per fleet |
| [[vpa-bimodal-workload-limitation]] | ENG-78 root cause — why the monolith pipeline pod over-provisions |

## Cross-Plan Considerations (apply to multiple proposals)

| Document | Cross-cutting concern |
|----------|-----------------------|
| [[2026-04-16_frame-transport-comparison]] | How frames move between services — Redis / NATS / S3 / SQS tradeoffs + AWS-EKS deployment specifics |
| [[2026-04-16_graceful-failover-design]] | Tracker + window checkpointing for graceful worker failover |
| [[inference-api-interaction]] | Placement of `AsyncInferencePool` and AIMD per proposal |
| [[library-decomposition-required]] | What changes in the 41-package `actuate-libraries` monorepo per proposal |
| [[observability-and-tracing]] | NR / OTel requirements; when distributed tracing becomes mandatory |
| *Design-for-monitoring (added 2026-04-23)* | Every proposal (A–E) must include a **"Monitoring & Alarms" subsection** answering: what behavioral signals prove this proposal is working in prod, what goes on the cross-repo dashboard, what are the acceptance criteria for a rollout. Add as a scoring dimension in [[2026-04-16_evaluation-rubric]]. Triggered by the 2026-04-23 onboarder silent-failure post-mortem; tracked cross-repo as [[mark-todos]] §9. |
| [[downstream-consumer-impact]] | How [[watchman-repo|Watchman]], AutoPatrol, CHM, and alert integrations are affected |
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
- 2026-06-01 — v10 cloud platform reference received; incorporates and validates several proposal patterns
- Next — (short term) update proposals B–E with v10 insights (detector-router, two-stage resolution, sparse rules); (medium term) build targeted PoCs, score via [[2026-04-16_evaluation-rubric]], write selection synthesis

## v10-Informed Updates to Proposals (Short Term)

Before PoC selection, proposals B–E should incorporate v10 insights. See [[2026-06-01_v10-cloud-platform-vs-fleet-proposals#Recommendations for Proposal Updates]]:

1. **Add detector-router** as a cost-control component (routes per-product frames to detector pools)
2. **Adopt two-stage resolution** (lifecycle + product) in all scheduler-service designs
3. **Standardize precedence stack** (override > panel > camera > site > tenant) across all proposals
4. **Document sparse rule storage** with concrete v10 config examples

## Alternative approaches (reference)

- [[2026-04-17_preliminary-pilot-option]] — optional preliminary-pilot phase that stubs all 5 proposals in a shared harness before committing to targeted PoCs. Forward-looking reference; not currently committed to but available if targeted-PoC sequencing needs revisiting.

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
- [[knowledgebase/topics/software-architecture/_summary]] — governance and enforcement (post-selection scope)
- [[infrastructure/_summary]] — K8s, VPA, deployment pipelines
- [[actuate-libraries/_summary]] — pipeline libraries that may need decoupling
- [[aws-cost/_summary]] — cost as a scoring axis on the proposals; S3 Intelligent-Tiering + Glacier Deep Archive source notes moved there 2026-04-27
