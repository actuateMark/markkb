---
title: "Proposal E — Hybrid Sidecar"
type: synthesis
topic: fleet-architecture
tags: [proposal, fleet, hybrid, sidecar, smart-puller, detection-core, statefulset]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Proposal E — Hybrid Sidecar

**Core idea:** Three fleets cut at the **natural stateless/stateful boundary**:
1. **Smart Puller Fleet** — pulls frames AND runs FDMD motion detection locally. Only motion-detected frames (20-40%) forwarded.
2. **Detection Core Fleet** — StatefulSet with **camera affinity**. Runs inference, full filter chain, and observers in-process (the 12-library critical path stays together).
3. **Site Context Service** — centralized config, camera registry, schedule evaluation (fixes ENG-96).
4. **Alert Dispatch Service** — consumes events via SNS, routes to existing SQS FIFO queues (fixes ENG-66).

Sometimes described as 3-4 fleets; the site context service is small enough that some treat it as a library rather than a fleet.

## Architecture sketch

```
┌───────────────┐    Redis Streams     ┌───────────────────┐      SNS     ┌──────────────┐
│ Smart Puller  │─(motion-gated only)─>│  Detection Core   │ ──(events)─> │ Alert Dispatch│
│    Fleet      │                      │  Fleet (StateSet) │              │    Fleet      │
│ + FDMD inline │                      │  camera affinity  │              └──────────────┘
└───────────────┘                      └───────────────────┘                    │
        │                                      │  │                             ▼
        │                                      │  │                         SQS FIFO
        │ reads config                         │  │ reads config            (existing)
        ▼                                      ▼  ▼
    ┌─────────────────────────────────────────────────┐
    │   Site Context Service (config, registry,       │
    │   centralized schedule eval — fixes ENG-96)     │
    └─────────────────────────────────────────────────┘
                         │
                         ▼                          Tracker snapshots → Redis
                    Admin API                       Windows → DynamoDB WindowIdsV2
```

## Frame Transport (AWS/EKS Mechanics)

- **Transport:** Redis Streams, 1 hop, **motion-filtered frames only** (20-40% of raw frame volume)
- **Redis deployment:** ElastiCache for Redis, cluster mode, 3 shards × 2 replicas multi-AZ. Sized smaller than A's because motion-gating drops most frames before they cross the wire. See [[2026-04-16_frame-transport-comparison]].
- **Stream key:** `motion-frame:group:{camera_group_id}` — **one stream per camera-group** (not per camera). A detection core pod owns a camera group (10-50 cameras) and reads that one stream. Fewer streams → less metadata overhead → cheaper cluster.
- **Payload:** motion-filtered JPEG bytes + motion regions + camera_id (envelope format). No raw frames transit the bus — FDMD drops them at the puller.
- **Cross-AZ cost:** frame volume is 20-40% of raw, so worst-case cross-AZ is ~$30k/mo at current scale (vs A's ~$100k). **Zone-aware routing still recommended:** pair smart-puller pods and their camera-group's detection-core pod in same AZ via topology spread + affinity.
- **Detection core locality:** StatefulSet with camera-affinity — a given camera-group maps to a specific pod. Smart pullers for that group route to that pod's same-AZ replica preferentially. Failover moves the camera-group to another AZ only on pod death.
- **Alert emission:** detection core → SNS → SQS FIFO (existing path, unchanged, solves ENG-66 by being its own fleet)
- **Site connectivity:** smart puller fleet owns VMS connections AND runs FDMD locally — clean tunnel story (tunnels terminate in puller pods, same as A/B/D). See [[customer-site-connectivity]]. **Still unresolved** — pending deploy-repo deep dive.
- **FDMD state locality:** motion detection state stays with the puller owning a camera. Reassignment of a camera between pullers triggers motion-model cold-start (seconds). Acceptable.

## Scaling model

| Fleet | Scales by | Signal |
|-------|-----------|--------|
| Smart Puller | camera count | CPU (FDMD dominates) |
| Detection Core | camera-group count (post-motion-filter rate) | memory + CPU |
| Site Context | ~stateless | HPA on RPS |
| Alert Dispatch | event rate | SQS depth |

**Sidecar detail:** the detection core is a StatefulSet with camera-affinity — one pod owns a group of 10-50 cameras. Promotion/demotion happens via site context service assignment. Cameras in a pod share resources (inference pool, observer pool) — preserves today's efficiencies.

## State & failover

- **Tracker state:** in detection core. Uses [[2026-04-16_graceful-failover-design|failover design]] with Redis snapshots.
- **Window state:** existing `WindowIdsDAO`.
- **ENG-96 fix:** schedule eval moves from distributed (per-pipeline-worker) to centralized (site context service). No more race conditions.
- **ENG-66 fix:** alert dispatch is its own fleet; thundering herd on event listeners becomes a separate bounded fleet with HPA.

## Puller pool strategy

**Family-specialized pools.** FDMD tuning per VMS family; smart pullers need to own both the VMS connection lifecycle and motion detection, so family isolation is natural. Expected ~6-8 pools.

## Failure modes

| Failure | Blast radius |
|---------|--------------|
| Smart puller crash | N cameras (HPA replaces; tracker unaffected) |
| Detection core crash | N cameras worth of tracker state; resumed from snapshot (RPO ≤1 s) |
| Site context crash | HA standby takes over; running detection cores keep their last-known state |
| Alert dispatch crash | SQS buffers events |
| Redis crash | Tracker snapshots fail; workers run on in-memory state until recovery |

## Cost model

- **Change from today:** **-20% to -40%.**
- **Why savings:**
  1. FDMD at the edge drops 60-80% of frames before any inference or pipeline work
  2. VPA fix — smart puller is steady-load; detection core is bursty (fixes ENG-78)
  3. No sharding overhead — detection core pods are sized for camera-groups, not sites
  4. Alert dispatch right-sized separately
- **Added cost:** 3-4 service types; Redis cluster for motion-filtered frames + tracker snapshots.

## Reused primitives

- Existing pipeline code lives in detection core (filters, observers, AsyncInferencePool)
- `WindowIdsDAO`, `S3DAO`, `SQSDAO` unchanged
- FDMD currently in `actuate-pipeline`; extract to puller

## New primitives required

- **Redis client wrapper**
- **FDMD-in-puller** library
- **Camera-affinity scheduler** (StatefulSet + site context service assignment API)
- **Site context service** — new small service with config + schedule + camera registry
- **Tracker snapshot serializer** (see [[tracker-snapshot-schema]])
- **Motion-filtered frame protocol** — envelope with camera_id, timestamp, motion regions, JPEG bytes

## Targeted PoC spec

**Scope:** Smart puller with in-process FDMD + stateful detection core with camera-affinity StatefulSet. Measure motion-filter reduction rate (target: 60-80% frame drop).

**PoC path:** `/home/mork/work/fleet-poc-e/`

**What to build:**
- Smart puller: one real camera, FDMD inline, Redis Stream publish of motion-filtered frames
- Detection core: minimal pipeline running YOLO + StationaryFilter + SlidingWindow + alert emission, consuming from Redis
- Site context service stub: hardcoded assignments
- Redis single-node

**Benchmarks to collect:**
- Motion-filter drop rate (critical — if <60%, the cost case weakens significantly)
- End-to-end latency from camera pull to alert emission
- FDMD CPU cost per frame inside puller
- Detection core memory footprint per camera at steady state
- Tracker snapshot write cost per camera per second

**Invalidation criteria:**
- Motion-filter drop rate < 50% (cost case collapses)
- End-to-end p95 > 300 ms
- FDMD cost makes smart puller CPU dominate over inference savings

**Estimated PoC effort:** 2-3 weeks.

## Open questions

- **FDMD quality:** moving FDMD to the puller means each puller has its own motion model state. Currently FDMD has some per-camera learning; confirm nothing breaks when running in a smaller, potentially-restarted process.
- **Camera-group sizing:** what's the optimal group-per-core-pod? 10? 50? 100? PoC should inform.
- **StatefulSet upgrade behavior:** how does a rolling update of detection cores interact with tracker snapshotting? Worst case: 10% of cameras are mid-upgrade at any moment.
- **ENG-96 fix correctness:** moving schedule eval to a central service must preserve existing semantics. Need a parallel-run validation phase.

## Cross-System Touchpoints

Cross-cutting considerations (shared notes):

- [[inference-api-interaction]] — detection core StatefulSet holds `AsyncInferencePool` per camera group — larger pools, better AIMD convergence than site-per-pod.
- [[library-decomposition-required]] — moderate: extract FDMD from `actuate-pipeline` into standalone `actuate-fdmd`; new `actuate-site-context` service + client; `actuate-redis-streams`. Filter chain stays intact — low risk.
- [[observability-and-tracing]] — tracing strongly recommended (3 hops). Log scope by `camera_group_id`. Motion-drop-rate metric is the single most important KPI for this proposal.
- [[downstream-consumer-impact]] — **cleanest downstream story** — Watchman/AutoPatrol/alert integrations see no contract change. Smart puller handles AutoPatrol's patrol alongside FDMD.
- [[config-and-schedule-propagation]] — **Site Context Service IS the ENG-96 fix.** Centralized schedule eval + camera registry + config cache. This is a material advantage; document the properties in [[config-and-schedule-propagation]] as prescriptive.
- [[memory-and-fork-safety]] — fork safety eliminated; detection core preserves today's in-process memory efficiencies (PooledTTLImageCache, jemalloc) for the heavy work.
- [[customer-site-connectivity]] — smart puller fleet owns VMS connections + tunnels; detection core untouched by site network.

### Related KB topics touched

- [[vms-connector/_summary]] — ENG-96, ENG-66, ENG-78 all have a direct fix in this proposal; summary should be updated post-selection
- [[camera-health-monitoring/_summary]] — **FDMD primitive is reusable** — CHM's scene-change detector could consume it, eliminating duplication
- [[actuate-libraries/_summary]] — `actuate-fdmd` becomes a new top-level library; document its API and model state management
- [[admin-api/_summary]] — site-context service is a new reader of admin-api; standardize the hot-path config read pattern
- [[infrastructure/_summary]] — adds site-context service to ArgoCD + VPA list; fewer VPA woes overall because pods are shape-consistent
- [[vms-connector/notes/syntheses/performance-optimization-landscape]] — motion detection section gets promoted from "proposed optimization" to "core architecture"

### Enhancement opportunities identified

- **CHM reuse of FDMD.** Scene-change detection is motion detection with different thresholds. Build `actuate-fdmd` with a clean API so CHM can consume it; saves duplicated work in [[camera-health-monitoring/_summary]].
- **Site Context Service as a broader config abstraction.** Today's `actuate-config` reads settings.json; site-context could become the standard read-path for ALL hot-path config, not just the connector. Watchman and AutoPatrol could consume it too.
- **ENG-96 fix is generalizable** — centralizing schedule eval in site-context is the actual fix. Document it separately so even if E loses the bake-off, the fix pattern is KB'd.
- **Thundering-herd KPI in ENG-66** — alert dispatch fleet HPA signal should be SQS depth or enqueue rate. Once measured, build an autoscale target that wasn't possible before.
- **Camera-group sizing as a per-customer tunable.** Pods own 10-50 cameras; larger sites want bigger groups, smaller sites want smaller groups to limit blast radius. Surface this in admin-api config.

## Score estimate (pre-PoC)

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 8 | 3-4 fleets scale independently (less than B's 5, more than C's 1) |
| Cost reduction | 10 | -20 to -40% |
| Failure isolation | 8 | Per-fleet, per-camera-group blast radius |
| Operational simplicity | 6 | 3-4 service types + Redis (less than B, more than C) |
| Migration risk | 7 | 14-20 weeks; filter chain stays intact — lowest risk among the ambitious options |
| Failover quality | 9 | Full design applies |

Weighted: `(8×0.35)+(10×0.20)+(8×0.15)+(6×0.15)+(7×0.10)+(9×0.05) = 8.05 / 10`

**Highest composite estimate.** E balances primary criterion (scalability) with cost savings, preserves the battle-tested pipeline core, addresses three known pain points directly (ENG-78, ENG-96, ENG-66), and has moderate ops complexity. The PoC's drop-rate measurement is the linchpin — if motion-filtering doesn't deliver 60%+ reduction, the cost case weakens and B or C become more attractive.
