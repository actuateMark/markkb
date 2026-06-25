---
title: "Proposal D — Event-Driven Pipeline"
type: synthesis
topic: fleet-architecture
tags: [proposal, fleet, event-driven, nats, jetstream, s3, minio]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
outgoing:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/customer-site-connectivity.md
  - topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_frame-transport-comparison.md
  - topics/fleet-architecture/notes/syntheses/2026-04-17_preliminary-pilot-option.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/_overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/reading-list.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming:
  - topics/fleet-architecture/notes/concepts/customer-site-connectivity.md
  - topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_frame-transport-comparison.md
  - topics/fleet-architecture/notes/syntheses/2026-04-17_preliminary-pilot-option.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/_overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/notes/syntheses/2026-05-05_fleet-architecture-workstream-context.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-proposal-d.md
incoming_updated: 2026-06-25
---

# Proposal D — Event-Driven Pipeline

**Core idea:** Fully event-driven architecture. NATS JetStream between stages, S3/MinIO for frame storage (reference pattern, not raw bytes on the bus). Motion gating at the puller saves 60-80% downstream. Filter chain split: stateless filters in detector, stateful in observer.

> **Pilot realization (2026-05-01):** see [[2026-05-01_ephemeral-run-pilot/paradigm-d]] for how a 24h-bounded ephemeral run lands on this paradigm — runs as JetStream subject lifecycles with TTL, no per-run pods, queryable status via consumer-state APIs.

## Architecture sketch

```
┌────────┐    JetStream (ref)     ┌──────────┐    JetStream (ref)     ┌────────────┐    JetStream    ┌──────────────┐
│ Puller │────(s3_key + meta)───> │ Detector │ ──(s3_key+detections)> │  Observer  │ ──(events)────> │ Alert Dispatch│
│ + FDMD │                        │ (YOLO +  │                        │ + stateful │                 │   Fleet       │
└────────┘                        │stateless │                        │   filters  │                 └──────────────┘
     │                            │ filters) │                        └────────────┘
     │ (writes JPEG)              └──────────┘                              │
     ▼                                 │                                    ▼
 ┌────────┐                            │ (pulls JPEG by key)         WindowIdsV2 + Tracker snapshots
 │ MinIO  │ <──────────────────────────┘
 │(cluster)│                           (S3 GET by key)
 └────────┘
```

## Frame Transport (AWS/EKS Mechanics)

- **Transport:** **NATS JetStream for envelopes + S3 for frame bytes (reference pattern)**
- **NATS deployment:** in-cluster StatefulSet, 3-5 replicas across AZs, JetStream file storage on EBS gp3. NATS is not AWS-managed — we own the ops. A [[pod-disruption-budgets|PDB]] with `maxUnavailable: 1` is mandatory for safe cluster upgrades — JetStream's RAFT quorum is N/2+1, so an uncoordinated node-drain could evict two replicas simultaneously and stall all writes until rebalance. See [[2026-04-16_frame-transport-comparison]].
- **Frame store — S3 Express One Zone (per AZ):** single-AZ low-latency bucket (~10 ms PUT/GET, ~50% cost of S3 Standard). **One bucket per AZ.** Access via **VPC gateway endpoint** → zero cross-AZ transfer cost for PUT/GET.
  - Alternative: in-cluster MinIO (lower latency, heavy ops) — rejected in favor of S3 Express unless benchmarks force a change.
- **Payload split:**
  - **S3 object:** JPEG bytes; key pattern `frame/{yyyy}/{mm}/{dd}/{hh}/{camera_id}/{frame_id}.jpg`; 1-hour lifecycle rule
  - **NATS envelope:** `{s3_key, camera_id, timestamp, frame_id, fdmd_result}` — ~200 bytes
- **Cross-AZ cost:**
  - Frame PUT/GET via VPC gateway endpoint: **free**
  - NATS inter-replica traffic: chargeable, but small (envelopes only)
  - **Critical gotcha:** if a puller in AZ `a` writes to a bucket in AZ `b`, you pay cross-AZ AND get higher latency. Puller→bucket pinning via topology hints is mandatory.
- **PUT operation cost — the real number:** at 32k cams × 3 FPS = 96k PUT/s × 86400 = 8.3 B PUT/day × $0.00025/1000 = **~$60k/mo** raw. Mitigation: batch 5-10 frames per PUT → ~$6-12k/mo. Batching adds up to 3-4 s latency; acceptable for non-motion-gated frames.
- **Site connectivity:** puller fleet exclusively owns VMS connections — same story as B. See [[customer-site-connectivity]]. **Still unresolved** — pending deploy-repo deep dive.
- **Frame durability:** S3 frames survive puller/detector crashes for the 1-hour lifecycle window; NATS JetStream persists envelopes until ACKed. **More durable than Redis Streams** — this is a D advantage.

## Scaling model

| Fleet | Scales by | Signal |
|-------|-----------|--------|
| Puller+FDMD | camera count | CPU (motion detection) |
| Detector | motion-filtered frame rate | **NATS consumer-lag** (External metric) |
| Observer+stateful | detection event rate | **NATS consumer-lag** or memory (tracker state) |
| Alert dispatch | SQS depth | downstream |
| MinIO | storage throughput | I/O |

**HPA signal — NATS consumer-lag:** detector + observer fleets scale on JetStream consumer-lag (exported as a Prometheus External metric) rather than CPU. Durable queue-depth is a more accurate leading indicator than CPU for this topology — a detector blocked on a GPU-bound inference call is CPU-light but queue-building, and CPU-based HPA would under-provision the fleet. Same signal for observer when tracker writes back-pressure against Redis.

## State & failover

- **Tracker state:** in observer fleet, per-camera. Uses [[2026-04-16_graceful-failover-design|failover design]] with Redis snapshots.
- **Frame durability:** frames live in MinIO for ~60 s TTL. Detector or observer restart can re-fetch from object storage. More durable than Redis Streams (which drop on broker restart).
- **NATS JetStream persistence:** messages persist until ACKed; survives broker restart.

## Puller pool strategy

**Family-specialized pools.** FDMD runs per-puller, needs CPU tuning per VMS family (e.g., Milestone frames arrive at different rates than ONVIF). One deployment per family.

## Failure modes

| Failure | Blast radius |
|---------|--------------|
| Puller pod crash | N cameras (HPA replaces in ~10 s) |
| Detector crash | Queue buffers; frames sit in NATS until drained |
| Observer crash | Tracker state for N cameras; resumed from snapshot |
| Alert dispatch crash | SQS buffers |
| NATS broker crash | Staged recovery; JetStream persistence recovers |
| MinIO crash | **New SPOF** — frames undeliverable until cluster heals |

## Cost model

- **Change from today:** **~neutral** at current scale; **-5 to -15%** at 10× due to stage right-sizing and motion-gating.
- **Added cost:** MinIO cluster (storage + compute + ops), NATS cluster, inter-service network.
- **Savings:** FDMD motion-gate drops 60-80% of frames before inference. At 32K cameras, this is the biggest single cost lever in any proposal.
- **MinIO throughput requirement:** ~450 MB/s sustained at current fleet; scales to 4.5 GB/s at 10×. Feasible with a properly-sized cluster.

## Reused primitives

- `S3DAO` for frame object I/O (works against MinIO with S3-compatible API)
- `WindowIdsDAO` for windows
- `SQSDAO` for alert SQS
- Inference API unchanged

## New primitives required

- **NATS client wrapper** (no existing use)
- **MinIO cluster deployment** (new infra)
- **Frame reference protocol** — publish `{s3_key, camera_id, timestamp, fdmd_result}` envelope, consumer GETs by key
- **FDMD-in-puller** — currently in pipeline; move to puller
- **Filter chain split** — stateless filters move into detector fleet, stateful filters remain with observer
- **Distributed tracing** (OTel) — required for 4-service debugging
- **Lifecycle policy** on MinIO bucket — auto-delete frames after TTL
- **Tracker snapshot serializer** (see [[tracker-snapshot-schema]])

## Targeted PoC spec

**Scope:** NATS JetStream + S3 reference pattern. Motion-gated puller with FDMD at the edge. Measure MinIO write throughput under load.

**PoC path:** `/home/mork/work/fleet-poc-d/`

**What to build:**
- Puller with FDMD + MinIO upload + NATS publish
- Detector stub that consumes NATS, GETs from MinIO, fake-inferences, publishes onward
- MinIO single-node (or 3-node) with ~10 GB storage
- NATS single-node with JetStream enabled

**Benchmarks to collect:**
- MinIO write throughput under 100-camera simulated load
- End-to-end latency: camera → detector ingestion (includes PUT+GET overhead)
- Motion-gate reduction rate (should be 60-80% of frames dropped at puller)
- Cost projection at 10× fleet (MinIO storage, network, compute)
- MinIO behavior under node failure

**Invalidation criteria:**
- End-to-end p95 > 500 ms
- MinIO throughput cap < 450 MB/s at projected load
- Storage cost at 10× fleet > Redis Streams equivalent in [[2026-04-16_proposal-b-stage-fleets|B]]

**Estimated PoC effort:** 3-4 weeks.

## Open questions

- **MinIO vs S3 native**: in-cluster MinIO is lower-latency but adds ops burden. S3 native costs more but is managed. Trade-off needs a real cost model.
- **Filter chain split boundaries**: StationaryFilter is stateful (needs observer state), IOU is stateless (depends only on current frame). IgnoreZones is stateless. Confirm each filter's state dependency before the split.
- **FDMD cost at the edge**: FDMD currently runs on CPU. Puller pods are small — can they absorb per-camera FDMD cost? Measure in PoC.
- **JetStream vs raw NATS**: JetStream adds durability but costs CPU. Do we need it for frame refs (frames are already in MinIO) or just for alerts?

## Cross-System Touchpoints

Cross-cutting considerations (shared notes):

- [[inference-api-interaction]] — inference happens in detector fleet (similar to B); AIMD pool-per-detector-pod vs centralized is open.
- [[library-decomposition-required]] — high churn: filter chain split (like B) + new `actuate-nats-jetstream`, `actuate-s3-frame-ref`, `actuate-fdmd-puller` libraries.
- [[observability-and-tracing]] — **distributed tracing mandatory.** Traces must span NATS publish/subscribe AND S3 PUT/GET. New metric types for S3 cost visibility.
- [[downstream-consumer-impact]] — **clip storage location change** may affect [[watchman-repo|Watchman]] (frame-URL construction). Must audit downstream code that constructs S3 URLs.
- [[config-and-schedule-propagation]] — same concerns as B; ENG-96 not fixed by default.
- [[memory-and-fork-safety]] — fork safety eliminated; S3 reference pattern keeps in-cluster memory low but adds S3 GET cost to decode path.
- [[customer-site-connectivity]] — puller fleet owns VMS connections; clean tunnel story.

### Related KB topics touched

- [[actuate-libraries/notes/concepts/filter-architecture]] — same stateless/stateful formalization as B
- [[actuate-libraries/_summary]] — `actuate-daos` S3DAO extended for S3 Express One Zone; useful beyond this proposal
- [[vms-connector/notes/syntheses/performance-optimization-landscape]] — FDMD-at-the-edge was listed as a proposed motion-detection optimization; this proposal moves it to production
- [[camera-health-monitoring/_summary]] — CHM's scene-change could potentially reuse the extracted FDMD primitive
- [[infrastructure/_summary]] — MinIO-or-S3-Express is net-new infra; affects Terraform/[[argocd|ArgoCD]] footprint

### Enhancement opportunities identified

- **S3-Express-per-AZ pattern as a general recipe.** If D wins, this pattern could benefit [[watchman-repo|Watchman]] and AutoPatrol too — they generate ephemeral frames as well.
- **Formalize `actuate-s3-frame-ref` as a reusable primitive.** Even non-D proposals could use it for clip-generation at lower cost.
- **Clip-URL abstraction.** Build a `frame_ref` type that encodes `{bucket, key, region, az}` — decouples consumers from storage location. Useful regardless of D winning.
- **Drive the `actuate-otel-instrumentation` library forward** — same dependency as B, pays for itself.

## Score estimate (pre-PoC)

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 10 | Every stage scales independently |
| Cost reduction | 6 | Neutral at 1×, -10% at 10× |
| Failure isolation | 8 | MinIO is a new SPOF (offsetting gain) |
| Operational simplicity | 2 | 4 service types + NATS + MinIO + tracing |
| Migration risk | 2 | 20-29 week timeline; filter chain split is invasive |
| Failover quality | 9 | Full design applies; MinIO adds durability |

Weighted: `(10×0.35)+(6×0.20)+(8×0.15)+(2×0.15)+(2×0.10)+(9×0.05) = 6.85 / 10`

Strong on scalability, severely hurt by ops complexity. MinIO in particular is the biggest drag. Reconsider if we can use S3 native instead of MinIO (lower ops, higher cost).
