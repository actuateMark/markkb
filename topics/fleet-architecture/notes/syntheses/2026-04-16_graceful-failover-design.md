---
title: "Graceful Failover Design — Tracker and Window Checkpointing"
type: synthesis
topic: fleet-architecture
tags: [failover, checkpointing, state, botsort, windows, resume, high-availability, dynamodb]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/k8s-placement-primitives.md
  - topics/fleet-architecture/notes/concepts/pod-termination-sequence.md
  - topics/fleet-architecture/notes/concepts/tracker-snapshot-schema.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_frame-transport-comparison.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
incoming_updated: 2026-05-01
---

# Graceful Failover Design

The interview locked in **graceful failover** as a requirement for the fleet redesign: on stateful-worker death, the replacement must resume in-flight tracking and detection windows without a 2-30 s gap. This document defines the design, shared by proposals B/C/D/E. (Proposal A keeps state in the pipeline monolith — its failover semantics are identical to today.)

## Requirement

**RPO (Recovery Point Objective): ≤1 second of lost tracker state per camera.**
**RTO (Recovery Time Objective): ≤5 seconds from pod death to resumed processing on a new pod.**

Below those bounds, cold-start is acceptable — running for ~60 s with a stale snapshot causes more false positives than helpful resume.

## What needs to survive a worker restart

| State | Today's location | Snapshot source |
|-------|-----------------|-----------------|
| BoTSORT tracker (per camera) | In-process, `ObservableManager` | **New** — see [[tracker-snapshot-schema]] |
| Detection windows (per camera) | `WindowDataPacket`, DynamoDB `WindowIdsV2` | **Exists** — `WindowIdsDAO` already persists |
| Pipeline step state | Mostly stateless | N/A |
| `StationaryFilter` cooldowns | In-process | Accept cold-start (short-lived, ~5 s) |
| Camera assignment | Today: config+schedule | Assignment controller (proposals C/E) holds authoritative state |
| In-flight alerts | SQS FIFO queues | **Exists** — SQS durability covers this |

## Snapshot approach

Use a **coalesced 1-second write cadence per camera**, combined with event-driven writes on window open/close:

- Every 1 s, worker writes `tracker:{camera_id}` snapshot to the state store
- On window open/close, worker writes window state via existing `WindowIdsDAO` (no change)
- Writes are **idempotent** — same key, latest value wins
- Writes are **fire-and-forget** from the hot path; failures logged but don't block the pipeline

See [[tracker-snapshot-schema]] for the tracker payload format.

## Storage options

| Store | Latency | Durability | Cost at 32K cams (1 Hz) | Existing use |
|-------|---------|-----------|------------------------|--------------|
| **Redis with AOF** | <5 ms | ~1 s window on broker crash | Moderate (~160 GB RAM if we co-locate tracker + frame-stream) | None — new infra |
| **DynamoDB (extend WindowIdsV2)** | ~10 ms | High (multi-AZ) | Higher (32K WCU sustained) | `WindowIdsDAO` pattern |
| **S3 partitioned prefix** | ~50 ms | Highest | Low but too slow for 1 Hz | `S3DAO` exists |

**Recommendation: Redis for tracker snapshots, DynamoDB for windows (no change).** This keeps the hot, high-cadence path in memory and the durable, lower-cadence path in an existing service.

**Dual-write during bed-in:** For the first 2 weeks in production, dual-write tracker snapshots to Redis + DynamoDB. If Redis has any pathology, we can failover the read path to DynamoDB without losing state. Disable DynamoDB dual-write after that period.

## Resume protocol

When a new pod claims camera `C`:

1. Read `tracker:C` from Redis
2. If key is missing or `captured_at` is older than 60 s → cold-start (no resume)
3. Otherwise: reconstruct `BoTSORT` from camera config + injected STrack state (see [[tracker-snapshot-schema]])
4. Read latest open windows from `WindowIdsDAO.get_open_windows(camera_id=C)`
5. Rehydrate `SlidingWindowStep` state with those windows
6. Begin pulling frames; skip the first inference result (warm-up)

Total time: dominated by pod-boot — the actual read+rehydrate is <50 ms per camera. Realistically covered by the existing "new pod comes up, picks up assignment, begins processing" path.

## Snapshot cadence tradeoff

| Cadence | RPO | Write load (32K cams) | Verdict |
|---------|-----|----------------------|---------|
| Per-frame (3 Hz) | frame-perfect | 96k writes/s | Rejected — cost prohibitive |
| Per-second | ≤1 s | 32k writes/s | **Chosen** — tolerable load, good RPO |
| Per-window (2-30 s) | 2-30 s | ~1k writes/s | Too coarse for tracker, fine for windows |

## Failure modes

### Redis cluster down
- **Symptom:** tracker snapshots fail to write; window writes continue via DynamoDB.
- **Behavior:** workers keep running with in-memory state (same as today). On pod death during this window, replacement cold-starts.
- **Mitigation:** Redis HA (sentinel or cluster mode). This is acceptable degradation — we lose the graceful-failover *property* but not *availability*.

### Stale snapshot replayed (worker resumed from snapshot >60 s old)
- **Symptom:** tracks drift, false positives spike.
- **Behavior:** 60 s TTL prevents this. On cold-start we accept the tracking gap.
- **Mitigation:** alarm if cold-start rate > baseline.

### Snapshot corruption / schema mismatch
- **Symptom:** resume fails to decode.
- **Behavior:** fall back to cold-start (log WARNING with camera_id).
- **Mitigation:** schema version in snapshot header (see [[tracker-snapshot-schema]]); workers refuse to decode unknown versions.

### Concurrent writes (old and new workers overlap during handoff)
- **Symptom:** last write wins.
- **Behavior:** old worker's final write may be newer than new worker's first read. Acceptable — the new worker's resume will be at most 1 s stale.
- **Mitigation:** assignment controller (proposals C/E) ensures at most one worker owns a camera at a time. For B/D, use conditional writes (compare-and-set on `owner_id`) if needed.

## K8s Mechanics

The snapshot cadence only works if the K8s-level shutdown sequence cooperates with it. See [[graceful-pod-termination-zero-downtime]] + [[pod-termination-sequence]] for the full flow: PreStop hook → SIGTERM → grace period → SIGKILL.

**Concrete cadence bound:** `terminationGracePeriodSeconds` must be ≥ (preStop drain + snapshot write latency + buffer). SIGKILL is the hard bound on the 1-second snapshot cadence — any snapshot in flight when SIGKILL fires is lost, silently. Rough sizing:

- preStop drain (stop claiming new frames, flush in-flight): ~1-2 s
- Snapshot write latency: p99 ~10-50 ms × cameras-in-pod; under load outliers can reach 100-200 ms
- Buffer for slow Redis under load: ~1-2 s
- **Typical value: 10-30 s per pod**

If pods routinely cold-start on upgrade, the first suspect is a grace period too short to complete the final snapshot cycle — not the snapshot logic itself.

## K8s Availability Primitives

Pod-level availability during voluntary disruptions (node upgrades, autoscaler scale-down, manual drains) depends on:

- [[pod-disruption-budgets]] — `minAvailable` or `maxUnavailable` policy keeps a quorum up during evictions. `unhealthyPodEvictionPolicy: AlwaysAllow` (K8s 1.27+) prevents an unready pod from blocking the Eviction API indefinitely, which is the usual cause of "stuck node drain" outages.
- [[k8s-placement-primitives]] — topology-spread with `whenUnsatisfiable: ScheduleAnyway` + AZ anti-affinity so a single-AZ failure doesn't take all replicas and so capacity pressure doesn't wedge the scheduler.

Together these keep RTO ≤5 s during voluntary disruptions — most pods never actually die; replacements come up in-zone with low-latency snapshot access.

## What this doesn't solve

- **Network partition:** if new and old workers can't see each other and both write to Redis, the last write wins. Combined with assignment-controller leases, probability is low; we accept the residual risk.
- **Multi-region HA:** out of scope — this design is single-region per cluster.
- **Alert de-duplication across resume:** if the old worker emitted an alert milliseconds before dying, and the new worker resumes before that alert is processed downstream, we may get a duplicate. Alert dispatch (SNS → SQS FIFO) already has deduplication semantics; rely on that.

## PoC demands

For any proposal whose PoC exercises this design (C, E primarily):

- Kill the worker mid-processing and measure: seconds-to-resume, frames lost, tracks lost, false-positive/false-negative delta vs a non-failed run
- Compare cold-start RPO (today's behavior) against snapshot-resume RPO
- Benchmark Redis cluster load at current scale and at 10×
