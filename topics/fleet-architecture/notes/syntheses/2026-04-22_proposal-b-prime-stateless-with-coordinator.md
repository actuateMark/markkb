---
title: "Proposal B-prime — Stage Fleets with Blob Coordinator"
type: synthesis
topic: fleet-architecture
tags: [proposal, fleet, stage-fleets, coordinator, b-prime, conditional-promotion, in-cluster-blob]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
incoming:
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Proposal B-prime — Stage Fleets with Blob Coordinator

> ## 🔒 CLOSEOUT BANNER (2026-04-22)
>
> **Status: formally closed. Parked as examined-and-closed reference artifact. Not a PoC candidate.**
>
> This synthesis exists to answer the question "does B-prime earn its seat alongside C and E?" The answer is no.
>
> **Score (pre-PoC): 6.25/10** — below B's 7.25 and well below E's 8.05. Key axes: ops simplicity 2, migration risk 2 (worst in the family), failure isolation degraded by a node-local tmpfs blob-durability gap C and E don't have.
>
> **Closure reasons:**
> 1. **Re-solves E's problem with more moving parts.** The Blob Coordinator is structurally similar to E's Site Context Service; the differentiation evaporates under honest review.
> 2. **Correctness regression vs C/E** — node-local tmpfs blob durability estimated at ~6 lost clips/day fleet-wide. Small in absolute terms but a net regression vs today's S3-durable storage.
> 3. **"Stateless stages" claim becomes marketing** once the coordinator is added. Either the coordinator holds lifecycle state (and stages aren't truly stateless), or it doesn't (and the architecture is wrong).
> 4. **Cost premise weakened further by 2026-04-22 NR reversal.** B-prime's cost-side argument rested on the conditional-promotion-at-window-close direction saving >50×. Corrected data (see `topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md` amendment): real S3 API-call reduction is ~1.45× because most windows (~69%) ARE detection-positive. B-prime's ops burden is indefensible for a ~31% PUT savings when E delivers similar savings via simpler motion-gating-at-puller.
>
> **Re-examination trigger:** only if E's PoC fails on motion-drop-rate (<50% FDMD filter effectiveness) or on detection-core-StatefulSet operational load. Until then, this synthesis is historical.
>
> **Surviving insight (NOT closed):** the **fleet-coordinator unification question** surfaced during this synthesis — do C + E + B-prime's control-plane services collapse into one primitive? That question survives the closure of B-prime itself and is tracked at `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md`. It's a structural question about control-plane consolidation and is independent of the cost-claim reversal.
>
> — End closeout banner —

## Motivation

The 2026-04-22 frame-storage design-delta ([[2026-04-22_frame-storage-design-deltas]]) found the in-cluster-blob + conditional-promotion direction a natural fit for C and E and an awkward fit for B. B's per-hop JPEG-in-stream transport structurally conflicts with "accumulate a window's frames until outcome is known, then drop or promote." The delta's §B left an open question: *"Should B be re-scoped as B-prime with an explicit blob-holding stage?"*

B-prime is the synthesis that answers that question. The load-bearing test: can "every stage is its own fleet" be preserved by introducing a **lightweight Blob Coordinator service** that owns per-window blob lifecycle across hops — stage pods stay stateless while the coordinator tracks which pod owns each window's accumulating bytes? If yes and the benefit differentiates B-prime from [[2026-04-16_proposal-e-hybrid-sidecar|E]], B-prime earns its seat; otherwise this synthesis formally closes it in favor of E.

## Core idea

Every stage is its own fleet (as in B). Frames still flow stage-to-stage via Redis Streams. A new **Blob Coordinator service**, tangent to the hot path, owns per-window blob lifecycle: which pod currently holds the window's accumulating JPEGs, when the window closes, whether the blob promotes to S3 or drops. Stages remain pod-interchangeable Deployments; the coordinator is the only new stateful piece added to B.

## Architecture sketch

```
┌────────┐  stream  ┌────────┐  stream  ┌────────────┐  stream  ┌──────────┐  SNS  ┌──────────┐
│ Puller │────────> │ Motion │────────> │ Inference  │────────> │ Observer │─────> │  Alert   │
│ Fleet  │          │ Fleet  │          │ Coord Fleet│          │  Fleet   │       │ Dispatch │
└────────┘          └────────┘          └────────────┘          └──────────┘       └──────────┘
                       │ ▲                                           │
                       │ │ blob owner: motion pod (one per window,   │
                       │ │   picked via consistent-hash at handoff)  │
                       │ │                                           │
                       │ │   on window-close event:                  │
                       │ │   observer → coordinator → decide drop/   │
                       │ │   promote → motion pod encodes + S3 PUT   │
                       ▼ │                                           ▼
                ┌─────────────────────┐◀───────── window-close ──────┘
                │  Blob Coordinator   │
                │  (3-replica StSet,  │    holds per-window lease:
                │   etcd/Raft)        │    {window_id, owner_pod, AZ, byte_count}
                └─────────────────────┘

Blob bytes: EmptyDir tmpfs on the motion pod that owns the window.
Redis Streams carry frame-refs {cam_id, window_id, frame_seq, owner_pod}, NOT JPEGs.
```

The coordinator is **not in the hot path of frame bytes** — it sits in the control plane mediating window-close → encode → promote. Frame bytes stay pinned in the owner pod's tmpfs; streams carry envelopes only.

## Frame Transport (AWS/EKS Mechanics)

B-prime **inverts** B's transport model. Under B, every hop serialized JPEG bytes onto the next stream. Under B-prime, the puller writes once to node-local tmpfs inside the motion pod sticky for this window; every subsequent hop carries references only.

- **Transport:** Redis Streams, 4 hops, **frame-ref envelopes** (`{cam_id, window_id, frame_seq, blob_owner_pod, capture_ts, OTel-span}`). `motion` adds motion regions; `inference` adds detection boxes; `observed` adds the `window_close` marker.
- **Blob owner pod:** one motion pod per window. Selected at puller→motion handoff by consistent-hash over `{cam_id, window_id}` filtered by the coordinator's view of healthy motion pods in the puller's AZ. The motion pod's EmptyDir tmpfs (`medium: Memory`, Karpenter-selected `m5d`/`m6id` family with node-local NVMe spillover) accumulates JPEGs keyed by `(window_id, frame_seq)`.
- **Why motion, not observer:** the delta's Option B1 (observer as owner) collapses to E. Option B2 (inference-coord) owns inference budget, not window state. Motion is the structural choice that preserves B's stateless-stage philosophy most cleanly — motion pods fan-out widely, and consistent-hashing across the motion fleet replicates B's "stage interchangeability" promise even while one motion pod happens to hold one window's bytes.
- **Redis deployment:** ElastiCache cluster mode, **3-4 shards × 2 replicas** — smaller than B's 6-10 shards because streams now carry envelopes (~200 B) instead of JPEGs (~400 KB). Memory footprint for stream storage drops ~2000×.
- **Cross-AZ cost:** frame bytes never leave the motion pod's node. Streams carry envelopes only. **Cross-AZ cost drops from B's projected ~$400k/mo to ~$5-10k/mo.** This is B-prime's most compelling improvement over B.
- **Zone-aware routing becomes mandatory-for-correctness**, not just cost — observer's window-close signal must route to the same AZ as the blob-owning motion pod.
- **Site connectivity:** puller fleet exclusively owns VMS connections (unchanged from B).

**Blob size per window:** 3 FPS × 10 frames × 150 KB ≈ **4.5 MB per open window per camera**. At 32k cameras × ~20% open-window concurrency: ~29 GB fleet-wide, consistent-hashed across ~200 motion pods = ~145 MB tmpfs per pod. Fits comfortably on `m5d.xlarge` (16 GB RAM).

## Blob Coordinator service

**Controller choice:** **3-replica StatefulSet with Raft-based replicated state** (practical route: use `etcd` as the substrate rather than hand-rolling Raft). Per [[k8s-controller-selection-guide]], stateful workloads with leader election and replicated commit logs belong on StatefulSet. Not Deployment (no stable ordinals/DNS for Raft peers). Not a singleton + lease standby — on failover the standby has nowhere to reconstruct blob-ownership state from without either replaying all Redis open-window envelopes or polling every motion pod. Raft sidesteps this: followers already hold the state, failover is sub-second.

**API surface (minimal):**
- `RegisterBlobOwner(cam_id, window_id, owner_pod, AZ) → lease_token, TTL`
- `RenewBlobLease(lease_token) → ok` (motion pod heartbeats every 10 s)
- `LookupBlobOwner(cam_id, window_id) → owner_pod, AZ` (observer calls on window close)
- `CloseWindow(cam_id, window_id, outcome={drop|promote}) → ack`
- `OnOwnerFailure(cam_id, window_id) → (replacement_pod | accept_loss)` (coordinator-internal, triggers on lease TTL expiry)

**HA story:** 3 replicas, Raft quorum for writes, PDB `minAvailable: 2`. TSC with `topology.kubernetes.io/zone`, `minDomains: 3`, `DoNotSchedule` per [[k8s-placement-primitives]] — one replica per AZ, any single AZ loss preserves quorum.

**Coordinator crash:** single-replica loss is invisible. Quorum loss (2+ replicas) puts the coordinator in read-only degraded mode; motion pods continue accumulating blobs locally, close events queue, and on recovery the queue drains normally. Worst-case RTO ~30-60 s; in-flight windows delayed, not lost.

## Scaling model

| Fleet | Scales by | Signal |
|-------|-----------|--------|
| Puller | camera count | network I/O |
| Motion | frame rate | CPU + tmpfs occupancy |
| Inference Coord | inference RPS | async queue depth (AIMD) |
| Observer+Filter | detection event rate | memory + CPU |
| Alert Dispatch | SQS depth | downstream throughput |
| **Blob Coordinator** | **open-window count** | **Raft log rate (minimal CPU)** |

Coordinator RPS at 32k cameras: ~1k RPS register/close + ~3k RPS heartbeats. Easy for a 3-replica StatefulSet.

**Spot viability:** Motion pods no longer Spot-eligible — they hold blob state, and a 2-min warning may not cover encode completion. Motion moves to On-Demand (erodes one of B's cost stories); Puller/InferenceCoord/AlertDispatch remain Spot-eligible.

## State & failover

**Owner pod crash mid-window:** lease TTL expires (~20 s), coordinator selects a replacement motion pod for forward-going frames; previously-accumulated frames are lost. If the window was detection-positive and already pending close, the detection fires with a missing clip — an unavoidable correctness hit. Estimated fleet-wide loss: ~6 windows/day (200-pod motion fleet × weekly MTBF × 20% open-window concurrency). **Materially worse than C/E**, where window state is pinned to a stateful pod from open to close with a designed snapshot-resume path.

## Puller pool strategy

Same as B — adapter-specialized pools per VMS family. Coordinator's consistent-hash operates on motion pods only; puller fleet structure unchanged.

## Failure modes

| Failure | Blast radius |
|---------|--------------|
| Puller pod crash | N cameras (assignment-dependent) |
| **Motion pod crash** | **N cameras × open-window loss** — pre-close windows lose accumulated frames; forward-going frames reassigned |
| Inference coord crash | Inference backpressure; frames queue |
| Observer pod crash | Tracker state resumed from snapshot (RPO ≤1 s). Blobs stay pinned at motion pod. |
| Alert dispatch crash | SQS buffers |
| Redis broker crash | Streams paused; workers idle until recovery |
| **Coordinator quorum loss** | Register/close ops block; in-flight blobs accumulate locally; RTO 30-60 s |
| **Node-level loss (motion pod's node)** | All windows on that node lost (tmpfs not replicated) |

The node-level-loss row is B-prime's structural weakness. Blob durability is tied to node availability, which is worse than C/E where the blob owner is stateful and its failover is well-designed.

## Cost model

- **Frame-transport savings vs B:** massive. Streams carry ~200 B envelopes instead of ~400 KB JPEGs. Redis cluster drops 6-10 → 3-4 shards. Cross-AZ transfer: ~$400k/mo (uncontrolled) → ~$5-10k/mo.
- **S3 API savings vs B:** same 22 → 0/2 per window as other delta-adopting proposals.
- **Coordinator cost:** 3-replica StatefulSet on small instances, ~$200/mo.
- **Motion-fleet cost:** up ~15-25% vs B (tmpfs blobs + On-Demand-only).
- **Net vs current:** comparable to or slightly better than B's original cost profile (-5 to +10%); delta closes B's cost gap.
- **Net vs E:** similar cost profile. E has fewer fleets (3-4 vs 6) and lower coordination overhead, but compositionally close.

The coordinator-complexity tax is real but bounded — comparable to adding a small `etcd` cluster. The question is not "is B-prime viable" but "does it differentiate from E."

## Reused primitives

`WindowIdsDAO`, `S3DAO` (1 PUT per eventful window now), existing inference API, SQS alert path, OTel tracing, Redis Streams client — all inherited from B.

## New primitives required

Everything B required, plus:

- **Blob Coordinator service** (3-replica StatefulSet on etcd) + client library
- **Blob-lifecycle protocol** (register/renew/lookup/close)
- **Node-local tmpfs blob store** — motion pod EmptyDir on `m5d`/`m6id` Karpenter NodePool with NVMe spillover
- **Frame-ref envelope schema** — replaces JPEG-in-stream payload
- **Consistent-hash motion-pod selection** in puller
- **[[pyav-entity|PyAV]] in-process window encoder** — runs in motion pod on window close
- **Blob-owner lease renewal** (10 s heartbeat)
- **Coordinator Raft observability** — NR dashboard + blob-loss-rate panel

## Targeted PoC spec

**Scope:** Motion-pod tmpfs blob accumulation + Blob Coordinator (3-replica on `etcd` substrate) + observer window-close signal + coordinator-driven encode-and-promote. Measure blob durability under chaos and operator time-to-diagnose a lost-window bug.

**PoC path:** `/home/mork/work/fleet-poc-b-prime/`

**Build:** minimal puller/motion/inference-coord/observer; coordinator on etcd (skip hand-rolled Raft); envelope-only Redis Streams; [[pyav-entity|PyAV]] encode in motion pod; OTel end-to-end; chaos harness killing motion pods and coordinator replicas.

**Benchmarks:** blob-loss rate under normal ops (target <0.1%) and under 10% pod-churn/hr (target <5%); e2e frame latency p95 (<500 ms); coordinator RPS headroom at 10× fleet; operator diagnosis time for seeded missing-clip bug; tmpfs occupancy per motion pod.

**Invalidation criteria:** blob-loss >1% normal / >10% chaos; p95 >500 ms; diagnosis time >30 min with tracing; coordinator ops burden ends up above E's (B-prime fails to differentiate).

**Estimated PoC effort:** 4-5 weeks (highest in the family — coordinator + chaos harness on top of B's baseline).

## Open questions

1. **Does the coordinator collapse into E's site-context-service?** E's site-context-service owns config, camera registry, and schedule eval. B-prime's coordinator owns blob lifecycle. Both are small services adjacent to a fleet of workers. Combined, B-prime's control-plane shape matches E's almost exactly — the only remaining difference is "stage pods stateless" vs "detection-core stateful." Is that load-bearing enough to justify a separate proposal? (See Score estimate.)
2. **Motion pod as blob owner — HPA stability.** Scale-down kills motion pods holding open-window blobs. A drain protocol (motion pod refuses exit until windows close or reassign) starts looking like a StatefulSet — further erosion of the stateless premise.
3. **Node-local tmpfs durability.** Node drain = blob loss. Does `karpenter.sh/do-not-disrupt` suffice, or do we need cross-node replication (collapses B-prime toward D's JetStream approach)?
4. **[[pyav-entity|PyAV]] encode in motion pod — CPU fit.** Motion pod CPU is sized for motion detection. Window-close encode adds bursty CPU; does VPA cope, or does this reintroduce the [[vpa-bimodal-workload-limitation]] issue in a new fleet?
5. **Consistent-hash stability under rolling motion-fleet updates.** Hash ring shifts during rollout; in-flight windows migrate (complex) or abandon (blob loss).
6. **Coordinator as a shared cluster primitive.** If built for blob lifecycle, should it also absorb camera-assignment (C's controller) and schedule eval (E's site-context)? One stateful service replacing three.
7. **Is B-prime's "each stage scales independently" ever a real production signal vs. E's combined detection core?** Motion is lightweight CPU; bundling into detection core (E) is not known to be a scalability problem.
8. **Schema evolution across 6 services.** B already had this for 5; B-prime adds a 6th.

## Cross-System Touchpoints

- [[inference-api-interaction]] — unchanged from B.
- [[library-decomposition-required]] — **highest churn of any proposal**, higher than B (adds coordinator library + envelope schema + client).
- [[observability-and-tracing]] — distributed tracing mandatory (4 hops + coordinator). Coordinator health + blob-loss-rate panel + Raft metrics are new asks.
- [[downstream-consumer-impact]] — `/create-video` retires (shared with all delta-adopting proposals).
- [[config-and-schedule-propagation]] — coordinator could absorb schedule eval (ENG-96 fix); otherwise unresolved as in B.
- [[memory-and-fork-safety]] — fork safety eliminated; **new tmpfs pressure on motion pods**; jemalloc boilerplate × 6.
- [[customer-site-connectivity]] — tunnels localized in puller fleet (unchanged from B/E).

### Related KB topics touched

- [[vms-connector/notes/concepts/memory-management]] — motion pods carry tmpfs blobs; jemalloc + tmpfs interaction needs testing
- [[infrastructure/notes/concepts/vpa-behavior]] — motion fleet VPA profile becomes bimodal (motion-detect + encode bursts)
- [[k8s-controller-selection-guide]] — coordinator is the cleanest StatefulSet-with-Raft example in the family
- [[k8s-placement-primitives]] — coordinator placement is the most complex in the family (3-AZ mandatory)

### Enhancement opportunities identified

- **Unified control-plane primitive.** A shared "fleet-coordinator" absorbing blob lifecycle (B-prime) + camera assignment (C) + schedule eval / site-context (E) would consolidate three partially-overlapping control-plane services.
- **Consistent-hash stability pattern** is reusable for any fleet with "pick a pod, stick with it" semantics.
- **Tmpfs-backed node-local blob** — if validated, composes into C and E for NVMe spillover.

## Score estimate (pre-PoC)

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 9 | Each stage still its own fleet; motion scaling is now tmpfs-bounded (below B's 10). |
| Cost reduction | 7 | Frame-transport collapses vs B; coordinator + On-Demand motion offset some gains. |
| Failure isolation | 7 | Stage isolation preserved, but tmpfs node-loss adds a correctness gap C/E lack. |
| Operational simplicity | 2 | 6 service types + Raft + chaos testing + tracing. Worst in family. |
| Migration risk | 2 | 28-36 weeks; highest code churn. |
| Failover quality | 7 | Observer snapshot design applies; coordinator Raft HA; but node-loss blob-loss is unique to B-prime. |

Weighted: `(9×0.35)+(7×0.20)+(7×0.15)+(2×0.15)+(2×0.10)+(7×0.05) = 6.25 / 10`

**B-prime scores below B's 7.25 and well below E's 8.05.** Honest analysis:

- **Frame-transport is genuinely better than B.** Cross-AZ cost drops ~40×. This is the unambiguous win.
- **Coordinator-complexity tax is severe.** Operational simplicity 3 → 2; migration risk 3 → 2.
- **New correctness gap vs C/E.** Node-local tmpfs blob loss on node failure is a real failure mode C/E don't share — C/E's blob is co-resident with the stateful pod that also owns window state, so node loss collapses into pod death with well-designed snapshot-resume.
- **Differentiator from E is thin.** B-prime's coordinator + stateless-motion-fleet is structurally close to E's site-context-service + stateful detection-core. The only material difference is "motion in its own fleet" vs "motion bundled in detection core" — but motion is lightweight CPU, and bundling it (E) is not a known scalability problem. B-prime's coordinator re-creates with extra machinery what E gets for free from its StatefulSet.

**Verdict: B-prime does not earn its seat as a PoC candidate.** Its one win is overshadowed by (1) re-solving E's problem with more moving parts, (2) a correctness regression vs C/E, (3) bottom-of-family ops simplicity, (4) a "stateless stages" claim that is marketing-level once the coordinator is added.

**Recommend: park B-prime as an "examined and closed" reference artifact.** If E's PoC fails on its primary axis (motion-filter drop rate or detection-core StatefulSet ops load), re-examine B-prime as a fallback. Until then, E is the better PoC investment.

## Related

- [[2026-04-16_proposal-b-stage-fleets]] — original B
- [[2026-04-22_frame-storage-design-deltas]] — delta synthesis that raised the "should B-prime exist?" question
- [[frame-storage-current-state]] §§11-12 — cost insight and converging design
- [[2026-04-16_frame-transport-comparison]] — transport deployment tradeoffs
- [[2026-04-16_proposal-c-camera-worker]] — assignment-controller contrast
- [[2026-04-16_proposal-e-hybrid-sidecar]] — site-context-service contrast; the pattern B-prime converges toward
- [[2026-04-16_evaluation-rubric]] — scoring framework
- [[k8s-controller-selection-guide]] — StatefulSet-with-Raft rationale
- [[k8s-placement-primitives]] — 3-AZ coordinator placement
- [[pod-termination-sequence]] — motion-pod drain protocol
- [[2026-04-16_graceful-failover-design]] — observer snapshot design
- [[vpa-bimodal-workload-limitation]] — motion-fleet encode-burst risk
- [[memory-and-fork-safety]] — tmpfs blob profile
- [[customer-site-connectivity]], [[inference-api-interaction]], [[library-decomposition-required]], [[observability-and-tracing]], [[downstream-consumer-impact]], [[config-and-schedule-propagation]], [[tracker-snapshot-schema]]
