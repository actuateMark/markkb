---
title: "Frame Transport Comparison — Redis Streams vs NATS vs SQS vs S3-refs"
type: synthesis
topic: fleet-architecture
tags: [redis, nats, sqs, s3, transport, message-bus, fleet]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/customer-site-connectivity.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-01
---

# Frame Transport Comparison

Four of the five candidate architectures ([[2026-04-16_proposal-a-minimal-split|A]], [[2026-04-16_proposal-b-stage-fleets|B]], [[2026-04-16_proposal-d-event-driven|D]], [[2026-04-16_proposal-e-hybrid-sidecar|E]]) move frames between pods at least once. The transport choice materially affects throughput, cost, ops burden, and failure modes. This document picks a default and documents the tradeoffs.

## Workload characteristics

- **Frame size:** JPEG-encoded, 150-500 KB typical, outliers up to 2 MB
- **Rate per camera:** 3 FPS processed (15-30 FPS inbound, motion-gated downstream in E)
- **Target fleet:** design for 10× today (elasticity goal)
- **Ordering:** per-camera FIFO matters; cross-camera ordering does not
- **Durability:** frames are **ephemeral** — losing ~5s of frames on a transport outage is tolerable (tracker re-establishes, see [[2026-04-16_graceful-failover-design]])
- **Backpressure:** critical — a slow consumer should slow the producer, not silently drop

## At-a-glance

| Transport | Frame-in-message | Frame-by-reference | Existing codebase use |
|-----------|-------------------|-------------------|-----------------------|
| Redis Streams | ✅ best-fit | optional | ❌ no Redis client in codebase |
| NATS JetStream | limited (1MB default msg) | ✅ best-fit | ❌ |
| SNS/SQS | ❌ (256 KB cap) | ✅ | ✅ SQSDAO, ConnectorSQSDAO already present |
| Kafka | ✅ | ✅ | ❌ |
| S3 (reference pattern) | n/a (storage, not bus) | ✅ | ✅ S3DAO present |

## Detailed comparison

### Redis Streams

- **Throughput:** very high. A single Redis instance can sustain 10k+ XADD/s at our frame sizes; cluster scales horizontally.
- **Latency:** sub-ms round-trip within the same AZ.
- **Ordering:** per-stream FIFO. Use one stream per camera (or one per shard).
- **Backpressure:** natural via consumer lag. `MAXLEN ~ N` keeps stream bounded.
- **Durability:** AOF writes are per-op; risk of ~1s loss on crash with default config. Acceptable for ephemeral frames.
- **Cost:** moderate. Memory-bound — at 32K cameras × 500 KB × MAXLEN 10 = ~160 GB RAM cluster. Can trim with JPEG quality or MAXLEN tuning.
- **Ops burden:** **new infra**. No existing Redis client in codebase (verified). Adds a cluster to manage + a new client dependency.
- **Good fit for:** A, B (per-hop transport), E (puller→core).

### NATS JetStream

- **Throughput:** very high; designed for message-oriented workloads.
- **Latency:** sub-ms.
- **Ordering:** per-subject FIFO; good semantics.
- **Default max message size:** **1 MB** — can raise, but frames are a poor fit for on-the-wire payloads.
- **Reference pattern:** NATS + S3 (publish the S3 key, fetch frame on consumer) is the idiomatic way. That's exactly the [[2026-04-16_proposal-d-event-driven|D]] design.
- **Backpressure:** supports flow control via consumer max-in-flight.
- **Cost:** moderate infra (StatefulSet), but S3 GETs become the real cost driver in the reference pattern.
- **Ops burden:** new infra, new client. NATS is simpler to run than Kafka but more involved than Redis.
- **Good fit for:** D (with S3 refs).

### SNS/SQS

- **Throughput:** SQS standard is unlimited; FIFO caps at 300 msg/s per group (3000 with batching).
- **Message size cap:** **256 KB** — too small for frame-in-message. Extended Client Library pushes to S3 for ≥256 KB, which is itself the reference pattern.
- **Latency:** 10-50 ms typical — higher than Redis/NATS, not ideal for frame-rate transport.
- **Backpressure:** consumer-pull model; natural.
- **Cost:** usage-priced. At 32K cameras × 3 FPS = 96K msg/s — $$ adds up, and FIFO throughput requires careful group-key design.
- **Ops burden:** **zero new infra** — already used for motion signals and alert dispatch. Existing `SQSDAO` / `ConnectorSQSDAO` in `actuate-daos` / `connector_factories/shared/sqs_dao.py`.
- **Good fit for:** low-rate control-plane messages (alert dispatch, camera assignment changes). **Poor fit** for frame-rate transport.

### Kafka

- **Throughput:** excellent.
- **Latency:** ~5-20 ms typical.
- **Ordering:** per-partition.
- **Durability:** very high.
- **Cost:** expensive to run (Zookeeper/KRaft, broker nodes, storage).
- **Ops burden:** high. No existing Kafka use. Overkill for ephemeral frames.
- **Conclusion:** rejected — Redis Streams and NATS give us the same properties with less ops.

### S3 reference pattern (frame-by-reference)

- Publisher writes JPEG to S3 with a short-TTL key; consumer receives a lightweight pointer message over any bus and GETs the object.
- **Pro:** decouples storage from bus; existing `S3DAO` (`actuate-libraries/actuate-daos/src/actuate_daos/s3.py`) works.
- **Con:** S3 PUT+GET latency ~20-50 ms adds up over multiple hops. Needs lifecycle rules to evict ephemeral frames (~1 hour TTL).
- **Con:** S3 ingestion throughput scales with prefix — need prefix partitioning to hit ~450 MB/s sustained.
- **Alternative:** MinIO in-cluster (much lower latency, but adds ops burden).

## Recommendation by proposal

| Proposal | Transport | Rationale |
|----------|-----------|-----------|
| A — Minimal Split | Redis Streams (1 hop, extracted puller → pipeline worker) | Lowest latency, smallest infra footprint for a single hop |
| B — Stage Fleets | Redis Streams (4 hops) | Consistent. MAXLEN trimming bounds cost. |
| C — Camera-Worker | **None** (frames stay in-process; cameras pinned to workers) | Eliminating transport is the whole value proposition |
| D — Event-Driven | NATS JetStream + S3 reference pattern | Decouples storage from bus; native-fit |
| E — Hybrid Sidecar | Redis Streams (motion-filtered only, 1 hop) | 60-80% of frames already dropped; low volume |

## What the PoCs must measure

- **Per-hop latency p50/p95/p99** under steady-state load
- **Consumer CPU cost** per frame (serialization + transport overhead)
- **Backpressure behavior** — what happens when a consumer is slow?
- **Recovery** — does the stream survive a broker restart cleanly?
- **Cost model** — projected at 1× and 10× current fleet

## AWS/EKS deployment specifics

We run EKS in a single region. Every transport option has AWS-native deployment choices that dominate the cost and ops calculus.

### Cross-AZ data transfer — the dominant cost

**AWS charges `$0.01/GB` for intra-region cross-AZ traffic** — each direction. At current scale:

| Fleet size | Frame data rate | Monthly cross-AZ cost (if 100% cross-AZ) |
|-----------|-----------------|-----------------------------------------|
| Today (32k cams × 3 FPS × 400 KB) | ~38 GB/s | **~$100k/mo** if every hop crosses AZs |
| 10× fleet | ~380 GB/s | ~$1M/mo |

This is the single biggest hidden cost. Mitigations:
- **Zone-aware routing** — pair producers and consumers in the same AZ using pod topology spread constraints + topology-aware service routing
- **Motion gating before transport** (proposals D, E) — drops 60-80% of frames before they cross the wire
- **VPC gateway endpoints for S3** (proposal D) — S3 traffic routed via gateway endpoint is **free** within region; this is why S3-ref pattern has a hidden cost advantage
- **Single-AZ placement for ephemeral transport** — accept reduced HA for a specific fleet in exchange for zero cross-AZ cost; viable for frame streams that can tolerate ~5s loss on AZ failure

### Redis deployment: ElastiCache vs self-managed

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **ElastiCache for Redis** (cluster mode, multi-AZ with automatic failover) | Managed, TLS, IAM auth via Secrets Manager, AZ-aware primaries, VPC-peered with EKS | Pay-per-node, limited control over Redis config, cross-AZ replication traffic is chargeable | **Recommended** — ops savings outweigh cost premium |
| **Bitnami Redis Helm** (in-cluster StatefulSet on EBS gp3) | Lower latency (pod-to-pod within AZ), no ElastiCache markup | We own the failover/backup story; operational toil | Skip unless ElastiCache proves unviable |

**Cluster mode [[sharding]] strategy:** shard by `camera_id` hash. A single site's cameras spread across shards, so no site dominates a single shard. Stream keys: `frame:cam:{camera_id}` — one stream per camera.

**AUTH:** token in AWS Secrets Manager, injected via ExternalSecrets or CSI driver. TLS in transit mandatory.

**Persistence:** AOF with `appendfsync everysec` — ~1s write loss window on node failover. Acceptable for ephemeral frames.

**Memory sizing example:** 32k cameras × 400 KB × MAXLEN 10 = ~130 GB working set. With replica and overhead, budget ~200 GB across cluster. At 10× fleet, this becomes a cost driver — MAXLEN tuning is critical.

### NATS + S3 reference pattern (proposal D)

NATS is **not** AWS-managed. Options:
- **In-cluster NATS StatefulSet** with JetStream on EBS gp3 — 3-5 replicas across AZs — we own the ops
- **AWS MQ for RabbitMQ** as an alternative to NATS (managed, but different protocol — requires proposal rework)
- **Amazon MSK (Kafka)** as a heavier alternative — managed, but even more complex

**Recommendation for D:** in-cluster NATS StatefulSet with JetStream file storage. Cluster-internal only, no cross-region.

**S3 frame store — use S3 Express One Zone:**
- Standard S3: high-latency (50ms+), high durability, cross-AZ replication baked in
- **S3 Express One Zone:** single-AZ, ~10ms latency, **50% cheaper** than Standard, ideal for ≤1hr lifecycle frames
- Access via VPC gateway endpoint → **zero cross-AZ cost** for PUT/GET
- Cost model at 32k cams × 3 FPS × 400 KB:
  - Storage (1hr lifecycle): ~140 GB at rest = ~$22/mo storage
  - PUT operations: 96k/s × 86400 = 8.3B/day × $0.00025/1000 = **~$60k/mo** — **the real cost**
  - Mitigation: batch 10 frames per PUT = 10× reduction

**Critical gotcha:** S3 Express is **per-AZ** — if the puller is in us-east-1a and the bucket is in us-east-1b, you get cross-AZ costs AND higher latency. Must provision a bucket per AZ and route pullers to same-AZ bucket.

### SNS/SQS (proposals A, C, E for alerts; never for frames)

- SQS message size cap is 256 KB — cannot carry raw JPEG. Extended Client library pushes to S3.
- SNS→SQS fanout for alert distribution is already how we work — no change
- Cost: SQS is ~$0.40 per million requests; alert volumes are low enough this doesn't move the needle
- Cross-AZ: SQS is regional; no AZ cost concerns

### DynamoDB (for tracker snapshots alternative)

- Tracker snapshots can live in DynamoDB instead of Redis — lossier latency (~10ms) but higher durability
- Cost at 32k cams × 1 Hz writes: ~32k WCU = ~$6k/mo on-demand
- VPC gateway endpoint available — no cross-AZ concerns
- Already in use via `WindowIdsDAO` — zero new client code

## Network path: frame bytes pod-to-pod

Given VPC CNI (AWS default for EKS), pod-to-pod within a node is via `veth` pairs (userspace), across nodes it's ENI-to-ENI (userspace + kernel). Cross-AZ adds VPC backbone routing (~1-2 ms).

- **Same-node pod-to-pod:** ~50 μs latency, free
- **Same-AZ pod-to-pod:** ~0.5 ms, free
- **Cross-AZ pod-to-pod:** ~1-2 ms, **$0.01/GB each way**
- **Pod-to-ElastiCache (same AZ):** ~1 ms
- **Pod-to-ElastiCache (cross-AZ):** ~2 ms + cost
- **Pod-to-S3 via VPC gateway endpoint:** ~5-20 ms, **free**
- **Pod-to-S3 via NAT:** ~5-20 ms, $0.045/GB NAT + $0.01/GB data (avoid)

## Topology rules (enforced via pod affinity + constraints)

For any proposal that transports frames over the network:

1. **Zone-aware pod scheduling** — `topology.kubernetes.io/zone` label on pods; matched producer/consumer pairs share a zone via [[pod-affinity-anti-affinity]] + topology-spread (`whenUnsatisfiable: ScheduleAnyway`, not `DoNotSchedule` — the latter wedges the scheduler under capacity pressure and is almost never what you want for cost-driven topology hints)
2. **Topology-aware routing** — `service.kubernetes.io/topology-aware-hints: auto` on services so pods preferentially hit same-AZ backends
3. **Pod anti-affinity** across zones for HA, but with topology spread constraint `whenUnsatisfiable: ScheduleAnyway` so we don't wedge on capacity
4. **ElastiCache primary locality** — pin a primary per AZ where practical; replicas across AZs for durability

## Recommendation by proposal (updated with AWS specifics)

| Proposal | Transport | AWS deployment |
|----------|-----------|----------------|
| A — Minimal Split | Redis Streams (1 hop) | ElastiCache cluster mode, 3 shards × 2 replicas, multi-AZ |
| B — Stage Fleets | Redis Streams (4 hops) | ElastiCache cluster mode, 6-10 shards × 2 replicas, **zone-aware routing mandatory** |
| C — Camera-Worker | **None** (in-process); Redis for control plane only | ElastiCache t-series small instance for leases + snapshots |
| D — Event-Driven | NATS in-cluster + S3 Express One Zone per AZ | NATS StatefulSet on EBS gp3, S3 Express bucket per AZ + VPC gateway endpoint |
| E — Hybrid Sidecar | Redis Streams (motion-filtered, 1 hop) | ElastiCache cluster mode, 3 shards × 2 replicas, stream-per-camera-group |

## Open questions

- Redis cluster [[sharding]] strategy if we pick Redis: by `camera_id` hash (spreads sites across shards, avoids hot keys if a few sites dominate).
- Do we need TLS between pods and ElastiCache? **Yes** — we're on a shared VPC with other workloads. 10-15% CPU overhead is acceptable.
- S3 Express per-AZ proliferation — if we have cameras across 3 AZs we need 3 buckets with lifecycle rules. Confirm we can script this cleanly via Terraform.
- Multi-region — out of scope. All fleet infra is single-region per cluster.
