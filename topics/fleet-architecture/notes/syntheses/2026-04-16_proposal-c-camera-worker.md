---
title: "Proposal C — Camera-Worker Fleet"
type: synthesis
topic: fleet-architecture
tags: [proposal, fleet, camera-worker, bin-packing, assignment-controller, autopatrol]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/notes/concepts/blacklist-filter-locality.md
  - topics/fleet-architecture/notes/concepts/customer-site-connectivity.md
  - topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md
  - topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md
  - topics/fleet-architecture/notes/syntheses/2026-04-17_preliminary-pilot-option.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/_overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
incoming_updated: 2026-06-25
---

# Proposal C — Camera-Worker Fleet

**Core idea:** Generic worker pods run the **full pipeline per camera**. Cameras from *any* site are bin-packed into workers dynamically. An assignment controller manages camera→worker mapping. No frame transport over the network.

This was the proposal whose viability hinged on whether `BlacklistFilter` is per-camera or per-site. [[blacklist-filter-locality|Verified per-camera]] — so C is fully viable.

## Architecture sketch

```
┌──────────────────────────┐
│   Assignment Controller  │ ── etcd/Redis (camera ownership leases) ──┐
│ (singleton + HA standby) │                                           │
└──────────────────────────┘                                           │
         │                                                             │
         │ camera assignments                                          │
         ▼                                                             ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐        Redis (leases + snapshots)
│  Worker Pod  │   │  Worker Pod  │   │  Worker Pod  │ ...
│  N cameras,  │   │  N cameras,  │   │  N cameras,  │
│ full pipeline│   │ full pipeline│   │ full pipeline│
└──────────────┘   └──────────────┘   └──────────────┘
       │                                      │
       ▼                                      ▼
     Inference API                      SNS → SQS (alerts, existing)
                                        DynamoDB WindowIdsV2
```

## Frame Transport (AWS/EKS Mechanics)

- **Transport for frames:** **none** — frames stay in-process inside the worker pod. This is the central value proposition of proposal C.
- **Control plane (Redis for leases + tracker snapshots):** ElastiCache small instance (`cache.t4g.small` or similar), single-digit shard count. Low-volume — assignments change at human-scale cadence, tracker snapshots at 1 Hz per camera. See [[2026-04-16_frame-transport-comparison]] for deployment details.
- **Alert emission:** SNS → SQS FIFO (existing pattern, unchanged)
- **Cross-AZ cost:** negligible for frames (nothing crosses the wire). Redis cross-AZ is small (~32k writes/s × 200 B snapshot envelope). Cost is dominated by the **lack** of cross-AZ frame traffic — this is where C's cost advantage over B/D/E comes from.
- **Site connectivity — CRITICAL CONSTRAINT:** because cameras can reassign across workers at any moment, **every worker must be able to route to every camera's VMS**. If a meaningful fraction of sites use WireGuard or per-site VPNs, this forces one of:
  1. Every worker pod terminates every tunnel (infeasible)
  2. Centralized tunnel fleet with pod-level SNAT (new failure domain + operational complexity)
  3. Assignment constraint: `camera X only assignable to workers in tunnel-class Y` — erodes bin-packing freedom
  See [[customer-site-connectivity]]. **Blocker: pending `kubernetes-deployments` deep dive** — if >20% of sites use WireGuard, proposal C needs a serious design revision around tunnels before PoC.
- **VMS connection lifecycle:** worker opens connection on assignment, closes on deassignment. Re-auth cost per reassignment must be measured in PoC.

## Scaling model

| Fleet | Scales by | Signal |
|-------|-----------|--------|
| Worker pool | total camera count | aggregate CPU/memory; HPA on a per-pod camera-count target |
| Assignment controller | single leader + HA standby | camera churn rate (rarely grows) |

Scaling lever: **camera count per pod**. Tune once, adjust via ConfigMap. Elasticity goal is met — same architecture from 100 cameras to 100,000.

**Spot viability:** worker pods snapshot tracker state to Redis at 1 Hz and can cold-resume on a new pod within RTO. Spot's ~2-minute interruption warning costs at most 1–2 tracker frames per camera (worst case a single snapshot cycle). `karpenter.sh/do-not-disrupt` annotation on pods mid-heavy-processing handles the edge cases; default pool can be Spot-eligible. This is where C's cost advantage compounds — Spot + bin-packing + no frame transport all stack.

## State & failover

- **Tracker state:** per-camera, lives in the worker pod. Uses [[2026-04-16_graceful-failover-design|failover design]] with Redis snapshots every 1 s.
- **Worker death:** assignment controller detects missing lease, reassigns camera to another worker, new worker resumes from Redis snapshot.
- **Rolling updates:** drain worker by reassigning its cameras first, then terminate. Zero-downtime if done cleanly.

## Puller pool strategy

**Universal image (embedded).** Each worker bundles all 19+ VMS adapters (current monolith does this anyway). A worker can be assigned any camera regardless of VMS type. Simplest scheduling, largest image.

Alternative if image size becomes problematic: **worker classes by VMS family** (workers labeled `vms-class: milestone|onvif|genetec|...`) with assignment controller respecting class constraints. Defer to post-PoC.

## Failure modes

| Failure | Blast radius |
|---------|--------------|
| Worker pod crash | N cameras (N = per-pod assignment) across all sites |
| Assignment controller crash | No new assignments until HA standby takes over (~5 s); running workers unaffected |
| Redis (leases + snapshots) crash | Lease expiry pauses new assignments; running workers keep their cameras |
| Split-brain (network partition) | Lease TTL expires, new worker claims cameras; old worker loses lease on reconnect |

## Cost model

- **Change from today:** **-15% to -30%.**
- **Why savings:**
  1. No [[sharding]] overhead — cameras bin-packed into workers efficiently rather than site-shaped pods
  2. No per-site VPA over-provisioning — a generic worker pool has smoother load
  3. No duplicated [[inference-pool|inference pool]] per shard (one pool per worker instead of one per shard within a site-pod)
- **Added cost:** assignment controller (small) + Redis cluster for leases+snapshots.

## Reused primitives

- Full existing pipeline code runs in workers (no rewrite)
- `WindowIdsDAO`, `S3DAO`, `SQSDAO` unchanged
- Existing `AsyncInferencePool`, filter chain, observers all in-process

## New primitives required

- **Assignment controller** — leader-elected service that decides camera→worker mapping using bin-packing heuristics
- **Camera lease protocol** — workers hold a TTL-based lease on each camera; lease renewal is the liveness signal
- **Redis client wrapper** (for leases + tracker snapshots)
- **Worker assignment SDK** — worker lib that subscribes to assignment updates and spins up/down per-camera pipelines
- **Rolling-update drain logic** — controller handles pod termination gracefully; standard K8s pattern is [[pod-disruption-budgets|PDB]] + Eviction API (assignment controller drains cameras off a pod *before* the eviction API fires SIGTERM, using PDB to keep the fleet-wide quorum safe)
- **Tracker snapshot serializer** (see [[tracker-snapshot-schema]])

## Targeted PoC spec

**Scope:** Assignment controller + bin-packing algorithm. Simulate 100 cameras across 10 workers with rolling updates. Measure reassignment churn.

**PoC path:** `/home/mork/work/fleet-poc-c/`

**What to build:**
- Assignment controller with leader election (use Kubernetes leader election lease)
- Simple bin-packing: sort cameras by weight (descending), assign to least-loaded worker
- Lease-based liveness protocol
- Simulated workers (no real pipeline — just track "I own N cameras" and emit heartbeats)
- Rolling update harness (kill worker, measure reassignment time and churn)

**Benchmarks to collect:**
- Camera reassignment latency on worker death (RTO component)
- Churn: how many cameras move during a rolling update of all workers?
- Controller CPU/memory at 1000, 10000 cameras
- Split-brain behavior under injected network partition

**Invalidation criteria:**
- Reassignment latency > 10 s (breaks RTO requirement)
- Churn > 20% of cameras during a rolling update (excessive tracker cold-starts)

**Estimated PoC effort:** 2-3 weeks.

## Open questions

- **Bin-packing weights:** cameras vary in cost (FPS, resolution, motion rate). Can we cheaply estimate weight from config, or do we need observed load telemetry?
- **Stateful upgrade strategy:** when worker image upgrades, do cameras reassign (tracker cold-start) or can we hot-swap tracker state? For now, accept cold-start during upgrades.
- **Assignment controller HA:** single-leader + hot standby via Kubernetes lease is simplest; confirm no single-leader bottleneck at 10× fleet.
- **Adapter loading:** if we go universal-image, startup time may suffer loading all 19+ adapters lazily. Measure in PoC.

## Cross-System Touchpoints

Cross-cutting considerations (shared notes):

- [[inference-api-interaction]] — worker holds its own `AsyncInferencePool`; pool count scales with worker count rather than site count. May improve AIMD convergence (fewer, larger pools).
- [[library-decomposition-required]] — low library churn (pipeline stays in-process). Biggest new work: `actuate-assignment-controller` + `actuate-assignment-client`.
- [[observability-and-tracing]] — logs re-key from `site_id` to `worker_id` + `camera_id`. Cookbook rewrite needed in [[new-relic/notes/concepts/nr-connector-query-cookbook]].
- [[downstream-consumer-impact]] — **AutoPatrol session state** is the biggest risk — session assumptions may break on camera reassignment. Needs audit before PoC.
- [[config-and-schedule-propagation]] — **fixes ENG-96 by design** — assignment controller naturally owns schedule context; camera assignment includes armed-state snapshot.
- [[memory-and-fork-safety]] — **fork safety eliminated.** Today's multiprocessing [[sharding]] complexity becomes dead code. Worth celebrating.
- [[customer-site-connectivity]] — **the biggest open risk for this proposal.** If sites use per-site WireGuard tunnels, universal worker routing breaks. Blocked on deploy-repo deep dive.

### Related KB topics touched

- [[vms-connector/notes/concepts/memory-management]] — post-fork jemalloc re-enablement dance becomes obsolete; simplification win
- [[vms-connector/notes/concepts/connector-factory]] — factories load lazily on assignment instead of eagerly on site launch
- [[infrastructure/notes/concepts/vpa-behavior]] — VPA continues to apply but smoother load (no burst/steady mixing) → fixes ENG-78 partially
- [[knowledgebase/topics/autopatrol/_summary]] — AutoPatrol is the tricky consumer; session migration must be designed
- [[camera-health-monitoring/_summary]] — per-camera scene-change state is safe with reassignment (already camera-scoped)
- [[actuate-libraries/notes/entities/actuate-alarm-senders]] — alerts emit from worker pods; contract unchanged

### Enhancement opportunities identified

- **Make the assignment controller a general platform primitive.** AutoPatrol (patrol scheduling) and CHM (health-probe scheduling) have similar "assign work to pods" problems — a shared primitive would consolidate three controllers into one.
- **Delete the multiprocessing [[sharding]] code after C stabilizes.** `ChunkedSiteManager`, post-fork dance, and the [[sharding]] PR history are all mechanisms for a problem C removes. Pre-migration KB note: [[vms-connector/notes/concepts/memory-management]] gets an update.
- **Formalize a "lazy adapter loader" pattern** — universal image loads VMS adapters on first assignment. Pattern reusable elsewhere.
- **Universal image size optimization.** 1.5+ GB image is slow to pull; investigate multi-stage builds and layer sharing across integration families.
- **Schedule service spins off from the assignment controller.** Fixing ENG-96 structurally in this proposal — do it deliberately, document in [[config-and-schedule-propagation]].

## Score estimate (pre-PoC)

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 6 | Scales by camera-count, not per-stage — but elasticity goal is met |
| Cost reduction | 10 | -15 to -30% projected |
| Failure isolation | 8 | Per-worker, ~N cameras across sites |
| Operational simplicity | 7 | 1 worker type + controller + Redis |
| Migration risk | 6 | 13-20 weeks; universal image is the biggest risk |
| Failover quality | 9 | Full design applies |

Weighted: `(6×0.35)+(10×0.20)+(8×0.15)+(7×0.15)+(6×0.10)+(9×0.05) = 7.40 / 10`

Very close to B on composite. C wins on cost, B wins on per-stage scaling. The trade-off: B has more knobs, C has one knob (per-worker camera count).
