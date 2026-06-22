---
title: "Proposal A — Minimal Split (Extract the Edges)"
type: synthesis
topic: fleet-architecture
tags: [proposal, fleet, minimal-split, redis-streams, incremental]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/customer-site-connectivity.md
  - topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_frame-transport-comparison.md
  - topics/fleet-architecture/notes/syntheses/2026-04-17_preliminary-pilot-option.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-05-05_fleet-architecture-workstream-context.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-proposal-a.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
incoming_updated: 2026-06-02
---

# Proposal A — Minimal Split

> ## 📝 Status note (2026-04-22)
>
> A's 2026-04-16 weighted score of **4.25/10** sits well below the contender pack (C/D/E in the 6.85–8.05 range; B at 7.25). Today's corrections (NR reversal on non-eventful ratio, real CE data showing S3 is 14.9% of $2.67M/year total cloud spend, EC2 compute at 55.4%) don't change A's score on any axis — the "no structural savings" (Cost 3/10) and "same pipeline bottleneck" (Scalability 3/10) profile is unaffected.
>
> A remains open as a fallback option — cheap to keep alive on paper, non-zero PoC-fail-back value if C/D/E hit invalidation in PoC. No park clock. Revisit only when PoC outcomes are in.

**Core idea:** Extract **puller** and **alert sender** as separate fleets. Pipeline workers remain 1-per-site, but read frames from Redis Streams and publish alerts to the sender fleet. The battle-tested pipeline code is untouched.

## Architecture sketch

```
┌──────────────┐      Redis Streams       ┌─────────────────┐      SNS      ┌─────────────────┐
│ Puller Fleet │ ───(1 stream/camera)────> │ Pipeline Worker │  ───(event)──> │ Alert Dispatch  │
│ (per-camera) │                           │  (1 per site)   │                │     Fleet       │
└──────────────┘                           └─────────────────┘                └─────────────────┘
       ▲                                            │                                  │
       │                                            │ (writes windows)                 │
       │                                            ▼                                  ▼
       │                                     DynamoDB WindowIdsV2                  SQS FIFO
       │                                                                           (existing)
       └──── assignment: today's config + camera_config lookup ──────────────────────────
```

## Frame Transport (AWS/EKS Mechanics)

- **Transport:** Redis Streams, 1 hop (puller → pipeline worker)
- **Redis deployment:** ElastiCache for Redis, cluster mode enabled, 3 shards × 2 replicas multi-AZ. TLS + auth token from Secrets Manager. See [[2026-04-16_frame-transport-comparison]] for the full deployment spec.
- **Stream key:** `frame:cam:{camera_id}` — one stream per camera, MAXLEN ~100
- **Payload:** raw JPEG bytes in `frame_bytes` field; metadata (`timestamp`, `frame_id`, `camera_id`) in adjacent fields
- **Consumer group:** `pipeline-{site_id}` — preserves per-site FIFO because one pipeline worker reads the group
- **Cross-AZ cost:** puller and pipeline-worker **must** share AZ with the ElastiCache primary for the camera's shard. Use topology-aware hints + [[pod-topology-spread-constraints|pod topology spread constraints]] (`topologyKey: topology.kubernetes.io/zone`, `whenUnsatisfiable: ScheduleAnyway` to avoid wedging on capacity). Uncontrolled, cross-AZ transfer at current scale is ~$100k/mo (see [[2026-04-16_frame-transport-comparison]]).
- **Site connectivity:** puller fleet owns VMS connections. Per-site auth/tunnel state lives in puller pods. If sites use WireGuard, see [[customer-site-connectivity]] — puller pods may need tunnel termination locally OR a centralized tunnel fleet. **Unresolved** — pending `kubernetes-deployments` deep dive.
- **Failure:** AOF persistence with `appendfsync everysec` → ~1 s loss window on Redis failover. Acceptable for ephemeral frames; tracker state in pipeline worker is unaffected.

## Scaling model

| Fleet | Scales by | Bottleneck |
|-------|-----------|-----------|
| Puller | HPA on per-pod camera count | Network I/O, VMS connections |
| Pipeline | **Still 1-per-site** — no change | GIL, inference latency, same as today |
| Alert dispatch | HPA on SQS depth | Downstream monitoring center throughput |

**Weakness:** Pipeline worker remains the scaling unit for detection. [[sharding|Sharding]] inside pipeline workers persists. Partial fix only.

## State & failover

- **Tracker/window state:** unchanged — lives in pipeline worker. Same failover semantics as today (2-30 s gap on pipeline crash).
- **[[2026-04-16_graceful-failover-design|Graceful failover design]] does not apply** to this proposal. This is a direct hit on the interview requirement.
- To retrofit failover later, we'd need to add tracker snapshotting to the pipeline worker (independent of this proposal).

## Puller pool strategy

**Family-specialized pools.** One deployment per VMS family (Milestone, Genetec, ONVIF, ExacqVision, etc.). Smaller images, family-specific tuning (e.g., Milestone's SDK threading model differs from ONVIF's [[rtsp-deep-dive|RTSP]]). Pool count: ~6-8 families across 19+ VMS types.

Rationale: incremental — we can extract one puller family at a time, leaving others on the monolith path during migration.

## Failure modes

| Failure | Blast radius |
|---------|--------------|
| Puller pod crash | 8-12 cameras (that pod's assignment) until HPA replaces |
| Pipeline worker crash | **Entire site dark** (unchanged from today) |
| Redis broker crash | All frames paused until broker recovers; pipeline workers pause |
| Alert dispatch crash | Alert delays but pipeline continues; SQS buffers |

## Cost model

- **Change from today:** +10-15%.
- **Added cost:** Redis cluster (~40 GB RAM), extra puller pod count.
- **Savings:** minor — puller extraction lets its pods be smaller, but pipeline worker sizing is unchanged.
- **At 10× fleet:** scales linearly with current pain points still present. Doesn't solve VPA over-provisioning.

## Reused primitives

- Existing `ConnectorSQSDAO` for alert-side queue integration
- Existing `WindowIdsDAO` / DynamoDB for window state
- Existing pipeline code runs unchanged inside pipeline worker

## New primitives required

- **Redis client wrapper** (no existing Redis use — [[blacklist-filter-locality|verified]])
- **Frame producer** that reads camera config, connects to VMS, writes JPEG bytes to `camera:{id}` stream
- **Frame consumer shim** injected into pipeline worker's camera class replacing its internal frame source
- **Puller/pipeline sync protocol** — consumer-group IDs, offset management, MAXLEN trimming

## Targeted PoC spec

**Scope:** Redis Streams frame transport between one extracted puller pod and one pipeline worker.

**PoC path:** `/home/mork/work/fleet-poc-a/`

**What to build:**
- Puller that pulls from one real camera ([[rtsp-deep-dive|RTSP]] is easiest), encodes JPEG, XADDs to a stream
- Pipeline-worker shim that reads with XREADGROUP and injects frames into an otherwise-normal pipeline
- Redis: single-node, AOF on, MAXLEN ~100

**Benchmarks to collect:**
- Per-frame end-to-end latency (puller capture → pipeline ingestion) p50/p95/p99
- CPU cost of XADD + XREADGROUP per frame
- Memory footprint of Redis at steady state
- Throughput ceiling: how many cameras can one puller pod handle?

**Invalidation criteria:** if per-hop latency p95 exceeds 100 ms, or Redis CPU scales worse than linearly with frame rate, the approach is probably not viable.

**Estimated PoC effort:** 1-2 weeks.

## Open questions

- What's the actual CPU cost of JPEG-encode-plus-XADD per frame? Today the encode is in the pipeline; moving it into the puller may shift the GIL contention pattern rather than eliminate it.
- Does the pipeline worker's `AsyncInferencePool` need any changes? (Probably not — inference is unrelated to frame source.)
- How do we handle a camera whose puller is in a different AZ than its pipeline worker? Cross-AZ Redis reads add latency and cost.

## Cross-System Touchpoints

Cross-cutting considerations that apply to this proposal (see shared notes for deep treatment):

- [[inference-api-interaction]] — pipeline worker keeps its per-pod `AsyncInferencePool`; no change to AIMD.
- [[library-decomposition-required]] — only leaf-library touches; smallest blast radius of any proposal.
- [[observability-and-tracing]] — 2 new service types; optional distributed tracing (single hop).
- [[downstream-consumer-impact]] — zero customer-visible change if executed cleanly; [[watchman-repo|Watchman]]/AutoPatrol contracts unchanged.
- [[config-and-schedule-propagation]] — **ENG-96 not fixed** — schedule eval stays per-pipeline-worker.
- [[memory-and-fork-safety]] — fork safety story unchanged (pipeline worker still shards internally).
- [[customer-site-connectivity]] — puller fleet owns VMS connections + tunnels; pipeline workers untouched by site network.

### Related KB topics touched

- [[vms-connector/notes/concepts/connector-factory]] — `generate_site()` factory pattern needs to be parameterized for the extracted puller path (non-trivial refactor even in this "minimal" proposal)
- [[actuate-libraries/notes/entities/actuate-alarm-senders]] — 27-sender library operates from the extracted alert fleet; MultiAlertSender orchestrator unchanged
- [[actuate-platform/notes/concepts/sns-sqs-fanout-pattern]] — unchanged; alert fleet is the SNS publisher
- [[infrastructure/notes/concepts/vpa-behavior]] — pipeline worker remains VPA'd; ENG-78 not solved

### Enhancement opportunities identified

- **Reorganize `connector_factories/` into a runtime registry** while extracting pullers. Today factory logic is intertwined with deployment wiring; cleaning up here unlocks downstream proposals (C's universal image, E's smart puller).
- **Create `actuate-redis-streams` library** as a shared new primitive — used in A, also needed by B, C, E. Build it once here.
- **Consolidate alert senders behind a common SQS-FIFO contract.** While we're extracting the alert fleet, formalize the event-envelope schema to prevent the silent-drift risk flagged in [[downstream-consumer-impact]].
- **Per-puller-family deployment** enables blue-green per-integration — a quality-of-life win that doesn't exist today.

## Score estimate (pre-PoC)

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 3 | Only puller and alert scale; pipeline still site-pod |
| Cost reduction | 3 | +10-15% at best, no structural savings |
| Failure isolation | 4 | Puller/alert isolated; pipeline still site-scoped |
| Operational simplicity | 6 | 2 new service types + Redis |
| Migration risk | 9 | Lowest-risk — pipeline unchanged |
| Failover quality | 4 | Baseline |

Weighted: `(3×0.35)+(3×0.20)+(4×0.15)+(6×0.15)+(9×0.10)+(4×0.05) = 4.25 / 10`

Beats today's baseline (~3.20) but loses badly on the primary criterion. Keep as a fallback/contingency if more ambitious proposals fail.
