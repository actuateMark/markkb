---
title: "Proposal B — Stage Fleets (Pipeline as Microservices)"
type: synthesis
topic: fleet-architecture
tags: [proposal, fleet, stage-fleets, microservices, redis-streams]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/blacklist-filter-locality.md
  - topics/fleet-architecture/notes/concepts/customer-site-connectivity.md
  - topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_frame-transport-comparison.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-17_preliminary-pilot-option.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/reading-list.md
incoming_updated: 2026-05-01
---

# Proposal B — Stage Fleets

> ## 📝 Status note (2026-04-22)
>
> **B's 2026-04-16 score of 7.25/10 stands as originally documented. B remains a viable-but-operationally-complex proposal, not closed.**
>
> Context: an earlier 2026-04-22 design-delta synthesis (`topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md`) claimed B's score was "invalidated" under a converging frame-storage design (in-cluster blob + conditional S3 promotion). That invalidation claim was itself invalidated later the same day by a corrected NR query (see the design-delta synthesis's AMENDMENT banner for details) — the true non-eventful-window ratio is ~31% rather than the >99% first reported, which reduces the conditional-promotion cost lever from >50× to ~1.45×.
>
> **Net effect:** B's original score analysis stands. B-prime (a 2026-04-22 variant explored in response to the flawed invalidation claim) was formally closed at 6.25/10 — see `topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md`.
>
> The **fleet-coordinator unification question** (see `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md`) that surfaced during B-prime's synthesis DOES apply to B structurally if it were to grow a coordinator-adjacent service — but B as originally scoped doesn't have one, so the question is non-binding for B's current form.

**Core idea:** Every stage is its own fleet. Pullers, motion workers, inference coordinators, observer workers, alert workers. Redis Streams between every stage. Maximum independent scalability per-stage.

## Architecture sketch

```
┌────────┐  stream  ┌────────┐  stream  ┌────────────┐  stream  ┌────────────┐  SNS  ┌────────────┐
│ Puller │  ───────>│ Motion │ ───────> │ Inference  │ ───────> │ Observer + │ ────> │ Alert      │
│ Fleet  │          │ Fleet  │          │ Coord Fleet│          │ Filter     │       │ Dispatch   │
└────────┘          └────────┘          └────────────┘          │ Fleet      │       └────────────┘
    ▲                                        │                   └────────────┘
    │                                        ▼                          │
    │                                  Inference API                    ▼
    │                                                             WindowIdsV2 (DDB)
    │                                                             Tracker snapshots (Redis)
    └── Assignment / Camera Registry (new central service) ─────────────────
```

## Frame Transport (AWS/EKS Mechanics)

- **Transport:** Redis Streams, **4 hops** (puller → motion → inference-coord → observer+filter), plus SNS for observer → alert
- **Redis deployment:** ElastiCache for Redis, cluster mode, 6-10 shards × 2 replicas multi-AZ. Sized for 4× the data volume of A. See [[2026-04-16_frame-transport-comparison]].
- **Stream keys (4 per camera):** `raw:cam:{id}`, `motion:cam:{id}`, `inference:cam:{id}`, `observed:cam:{id}`
- **Payload:**
  - `raw` — JPEG bytes
  - `motion` — JPEG bytes + motion regions (annotated, not filtered)
  - `inference` — JPEG bytes + detection boxes (Protobuf)
  - `observed` — detection events (no frame bytes)
- **Consumer groups:** `motion`, `inference`, `observer` — each stage has a consumer group across its fleet
- **Cross-AZ cost — CRITICAL:** 4 hops multiplies cross-AZ risk 4×. **Zone-aware routing mandatory.** Pod placement: [[pod-topology-spread-constraints|topology-spread]] with `topologyKey: topology.kubernetes.io/zone` + `whenUnsatisfiable: ScheduleAnyway` keeps a camera's 4-pod chain colocated in one AZ — the right tool here, NOT O(n²) pairwise [[pod-affinity-anti-affinity]] across stages (that path wedges the scheduler). Uncontrolled, projected cost at current scale: **~$400k/mo** (see [[2026-04-16_frame-transport-comparison]]).
- **Site connectivity:** puller fleet exclusively owns VMS connections — downstream fleets never touch the customer network. This is the cleanest of the proposals wrt the [[customer-site-connectivity|connectivity topology]] concern. **Still unresolved** — pending `kubernetes-deployments` deep dive to confirm tunnel termination patterns.
- **Tracing:** every stream entry includes an OTel span ID; required for 4-hop debuggability

## Scaling model

| Fleet | Scales by | Signal |
|-------|-----------|--------|
| Puller | camera count | network I/O |
| Motion | frame rate | CPU |
| Inference Coord | inference RPS | async queue depth (existing AIMD) |
| Observer+Filter | detection event rate | memory + CPU |
| Alert Dispatch | SQS depth | downstream throughput |

Every stage scales to its own bottleneck. Maximum elasticity.

**HPA tuning pitfalls in a 4-hop chain:** each stage's scale-down pulse can trigger a cascade through the pipeline. Per-fleet HPA `behavior.scaleDown.selectPolicy: Min` with `stabilizationWindowSeconds: 300` dampens chain-reaction thrash — the window's long enough to ride out transient queue spikes but short enough to still yield elasticity. **Spot viability:** Motion + InferenceCoord are stateless and Spot-eligible; **Observer is not** — tracker snapshot cadence (1 Hz) plus preStop drain must complete within `terminationGracePeriodSeconds`, and Spot's 2-minute warning is cutting it close under load. Use On-Demand-only NodePool for Observer; Spot + `karpenter.sh/do-not-disrupt` annotation on mid-window pods for the rest.

## State & failover

- **Tracker state:** lives in observer+filter fleet. Camera-partitioned. Uses [[2026-04-16_graceful-failover-design|Graceful failover design]] in full — Redis snapshots every 1 s.
- **Window state:** written to `WindowIdsV2` by observer+filter fleet. No change to existing DAO.
- **In-flight frames:** ephemeral in streams. A broker restart loses up to MAXLEN frames per camera; acceptable.

## Puller pool strategy

**Adapter-specialized pools.** One pool per VMS adapter (ONVIF, Milestone, Genetec, Exacq, Avigilon, etc.). Rationale: at this scale of decomposition, isolating blast radius by adapter is cheap and matches the "every stage has its own fleet" philosophy.

## Failure modes

| Failure | Blast radius |
|---------|--------------|
| Puller pod crash | N cameras (assignment-dependent) |
| Motion pod crash | N cameras worth of motion work; redistributes |
| Inference coord crash | Inference backpressure; frames queue in motion→inference stream |
| Observer pod crash | Tracker state for N cameras; resumed from snapshot (RPO ≤1 s) |
| Alert dispatch crash | Alert delays; SQS buffers |
| Redis broker crash | All streams paused; workers idle until recovery |

## Cost model

- **Change from today:** +15-25% at current scale; **break-even at 3-5× fleet** due to stage-right-sizing.
- **Added cost:** 5 service types instead of 1; Redis cluster (~180 GB RAM at 10× scale); distributed tracing infra (OTel collectors).
- **Savings at 10×:** substantial — each stage right-sized for its bottleneck; no [[sharding]] overhead.

## Reused primitives

- `WindowIdsDAO` / DynamoDB for window state
- `S3DAO` for alert clip uploads (unchanged)
- Existing inference API
- Existing SQS alert path

## New primitives required

- Redis client wrapper (no existing use)
- Tracker snapshot serializer (see [[tracker-snapshot-schema]])
- Camera assignment controller (who owns which camera in which fleet)
- Distributed tracing (OTel) — required for debuggability with 5 service types
- Inter-stage schema contracts (protobuf or similar)
- Filter chain split: stateless filters move to observer fleet, stateful filters stay there too (current architecture already supports this via `ObservableManager`)

## Targeted PoC spec

**Scope:** 4-hop pipeline (puller → motion → inference coord → observer) with OTel distributed tracing. Measure end-to-end latency and debugging burden.

**PoC path:** `/home/mork/work/fleet-poc-b/`

**What to build:**
- Minimal versions of each of the 4 service types
- Redis Streams between each hop
- OTel tracing instrumentation on every stage
- Tempo or Jaeger backend to visualize traces

**Benchmarks to collect:**
- End-to-end frame latency p50/p95/p99
- Per-hop latency breakdown
- Operator "time to diagnose" for a seeded bug in the observer (UX measurement)
- CPU/memory footprint per service at steady state

**Invalidation criteria:**
- End-to-end p95 > 500 ms (frames too stale for real-time detection)
- Debugging a seeded bug takes >30 min with distributed tracing enabled

**Estimated PoC effort:** 3-4 weeks (highest of the five).

## Open questions

- **Filter chain splitting**: some filters (StationaryFilter) need frame context and observer state. Can they genuinely move into the observer fleet cleanly, or do we need a hybrid split?
- **Inference coord vs direct inference**: is the coord layer even necessary, or do observer workers call inference directly? AIMD congestion control is the main reason for consolidation.
- **Multi-fleet schema evolution**: when we bump `WindowDataPacket` fields, do all 5 services have to deploy in lockstep?

## Cross-System Touchpoints

Cross-cutting considerations (shared notes):

- [[inference-api-interaction]] — open question: dedicated inference-coord fleet or per-observer-pod `AsyncInferencePool`? AIMD convergence is the deciding factor.
- [[library-decomposition-required]] — **highest churn of any proposal.** Filter chain split, pipeline runtime extraction, new OTel library. Touches `actuate-pipeline`, `actuate-filters`, `actuate-connector-observers` — the most-depended-on packages.
- [[observability-and-tracing]] — **distributed tracing mandatory** (4-hop pipeline is undebuggable without it). Major cookbook rewrite in [[new-relic/notes/concepts/nr-connector-query-cookbook]].
- [[downstream-consumer-impact]] — CHM healthcheck pipeline mapping to stages is non-obvious — needs design work. [[watchman-repo|Watchman]] and alert integration contracts preserved.
- [[config-and-schedule-propagation]] — config pulls spread across 5 fleets; staleness widens. ENG-96 not fixed by default — needs explicit design (add a config/schedule service).
- [[memory-and-fork-safety]] — fork safety eliminated; observer fleet is memory-bound (per-camera tracker). Per-hop memcpy cost measurable.
- [[customer-site-connectivity]] — tunnels localized in puller fleet (clean).

### Related KB topics touched

- [[actuate-libraries/notes/concepts/filter-architecture]] — needs update to formalize stateless-vs-stateful taxonomy before the split
- [[actuate-libraries/notes/concepts/dependency-graph]] — major restructuring; pipeline and filters become multi-package instead of one
- [[vms-connector/notes/concepts/inference-pool]] — relocation (pod vs coord fleet) is an open design decision
- [[vms-connector/notes/concepts/memory-management]] — stage pods each need jemalloc `LD_PRELOAD` (boilerplate multiplied 5×)
- [[camera-health-monitoring/_summary]] — healthcheck pipeline may need its own shorter path through the fleets
- [[infrastructure/notes/concepts/vpa-behavior]] — every fleet gets its own VPA; sizing per-stage rather than per-site is the point

### Enhancement opportunities identified

- **Add an `is_stateless` class-attribute to every filter** + a fitness function to enforce placement. This is a pre-cursor to B/D but is valuable even if neither ships — self-documenting code.
- **Extract `actuate-otel-instrumentation` as a reusable library.** Span IDs in log lines helps every service regardless of which proposal wins. Worth building now.
- **Build a "fleet-health" NR dashboard** ([[2026-04-16_code-health-dashboard]] style) — per-fleet panels, stream-lag panels, per-hop latency heatmaps. Essential for B; useful for all.
- **Tooling for cross-service schema evolution.** When `WindowDataPacket` or similar fields change, we can't tolerate lockstep deploys of 5 services. Adopt envelope-versioning + backwards-compat rules.

## Score estimate (pre-PoC)

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 10 | Every stage is its own fleet |
| Cost reduction | 6 | Break-even to -10% at 10× scale |
| Failure isolation | 9 | Per-stage, per-camera blast radius |
| Operational simplicity | 3 | 5 service types + distributed tracing + Redis |
| Migration risk | 3 | 24-32 week timeline; high code churn |
| Failover quality | 9 | Full design applies |

Weighted: `(10×0.35)+(6×0.20)+(9×0.15)+(3×0.15)+(3×0.10)+(9×0.05) = 7.25 / 10`

Strongest on primary criterion. Loses on ops complexity and migration risk. The PoC's debuggability measurement is the key gate.
