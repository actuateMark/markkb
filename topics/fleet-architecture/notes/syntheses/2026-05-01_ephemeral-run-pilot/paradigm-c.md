---
title: "Run Service — Paradigm C (Camera-Worker)"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, pilot, paradigm-c, camera-worker, k8s-jobs, ephemeral-runs, bin-packing]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: drafting
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/api-contract.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-e.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/translation-layer.md
incoming_updated: 2026-05-27
---

# Run Service — Paradigm C (Camera-Worker)

> **Reading note:** Scores in this document are **ephemeral-lens only**. Final paradigm selection combines them with a separate persistent-mode score — see [[_overview]] for the dual-rubric framing. The chosen paradigm has to serve **both** `mode: ephemeral` and `mode: persistent` runs through the **same primitives** (no parallel implementations); the pilot stress-tests this directly.

**Core insight:** An ephemeral run is conceptually a **temporary lease** on a set of cameras within the worker fleet — exactly what [[2026-04-16_proposal-c-camera-worker|Proposal C's assignment controller]] manages at steady state. The pilot doesn't need a new pattern; it just sets a TTL on the lease and lets the controller handle drain on expiry.

This is the cleanest mapping of the three paradigms because C already owns camera-to-worker assignment as a first-class primitive. An ephemeral run becomes a request to "assign these cameras to the fleet with a deadline; tear down when TTL fires."

## Natural fit for ephemeral runs

Proposal C's foundational unit is the **camera assignment** — a binding between a camera and a worker pod, held as a TTL-based lease in Redis or etcd. Steady-state operation assigns cameras to workers for indefinite duration (or until manual reassignment); camera lifetime is decoupled from pod lifetime because state lives in Redis snapshots.

An ephemeral run flips the TTL from "infinite" to "24 hours max." The assignment controller **already knows how to**:
- Pick idle workers (or scale up via Karpenter if needed)
- Write leases with TTL
- Detect lease expiry and revoke the assignment
- Drain the camera (stop pulling, flush in-flight detections)
- Free the worker's capacity for other cameras

This is **not a new workload pattern**; it's the existing pattern with a bounded lifetime. Paradigm D (Event-Driven) and E (Hybrid Sidecar) both need new concepts (Jobs, sidecars, event brokers, stream persistence); Paradigm C just needs to parameterize an existing concept.

## What gets created on `POST /runs`

### Lambda → Assignment Intent

1. Caller invokes `POST /v1/runs` with `RunSpec.v1` (mode, cameras, products, alerts, duration).
2. Lambda authenticates + rate-limits (per [[api-contract]]).
3. Lambda translates spec → complete `settings.json` (per [[translation-layer]]).
4. Lambda spawns init container with connector image to validate the settings.json (exits 0 = valid).
5. Lambda writes an **assignment intent** record to the assignment controller's backing store (Redis or etcd):

```
assignment-intent:<run_id> = {
  run_id: string,
  tenant_id: string,
  created_at: ISO8601,
  expires_at: ISO8601,  // now + duration_seconds
  cameras: [
    { camera_id, site_id, settings_fragment }  // per-camera config snippet
  ],
  alert_config: { ... }  // inline alert recipients
}
```

TTL on the Redis key = `duration_seconds`. Controller reconciliation loop picks up the intent immediately.

### Controller Assignment & Worker Binding

1. Assignment controller's leader sees the intent and runs bin-packing: "Which worker(s) can take these cameras?"
2. If capacity exists: write camera leases atomically (one lease per camera, same `expires_at` as the intent).
3. If no capacity: trigger Karpenter to scale up. Poll until ready, then write leases.
4. Workers pull their assignments from Redis and start pipelines (same mechanism as steady-state).

**Key difference from paradigm D/E:** No K8s Job or Pod per run. The assignment is the unit of work; the worker pods are long-lived. This is the bin-packing win — an ephemeral run doesn't add a pod, it just adds load to an existing worker's assignment list.

## K8s manifest sketch

The ephemeral run lands in the existing worker fleet, not a separate job cluster.

### What does NOT happen:
- No `apiVersion: batch/v1, kind: Job` per run
- No per-run pod creation
- No new workload controller (Jobs, StatefulSets, etc.)

### What does happen:
1. Workers are already deployed as a [[k8s-controller-selection-guide|Deployment]] (stateless, long-lived, managed by Karpenter).
2. Each worker periodically polls the assignment controller for its camera list.
3. On assignment delta, worker starts/stops camera pipelines in-process (no pod churn).
4. Karpenter consolidation may reclaim empty workers post-drain if the pool is over-provisioned.

### Manifest example:
```yaml
# Existing, unchanged
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ephemeral-workers
spec:
  replicas: 3  # scaled by HPA on aggregate load
  selector:
    matchLabels:
      app: vms-connector-worker
  template:
    metadata:
      labels:
        app: vms-connector-worker
      annotations:
        karpenter.sh/capacity-type: spot  # can be spot-eligible
    spec:
      containers:
      - name: worker
        image: actuate-vms-connector:latest
        env:
        - name: ASSIGNMENT_CONTROLLER_URL
          value: "redis://assignment-controller:6379"
        - name: DEPLOYMENT_MODE
          value: "camera-worker"

# No per-run objects. Ephemeral state lives in Redis.
```

The **only ephemeral artifact** is the Redis assignment intent record (written by Lambda, TTL-expired by Redis).

## Alert flow under finite TTL

Alerts emit from workers via the existing alert-sender, unchanged. The TTL constraint shapes the cleanup:

1. Worker receives an assignment (or multiple, bin-packed).
2. Worker streams the camera, runs detection, sends real-time alerts to recipients (email, SMS, integrations) — all via existing `actuate-alarm-senders`.
3. Alerts fire **directly to recipients**, not routed back through the API. This is a key difference from paradigm D/E — the alert is the primary status channel, not a secondary artifact.
4. When `expires_at` approaches, the controller sends a "drain" signal to the worker.
5. Worker gracefully stops pulling new frames and flushes in-flight detections through the alert pipeline.
6. `terminationGracePeriodSeconds` (e.g., 30s) allows in-flight detections to finish and alert-sender to deliver the final batch.
7. Worker revokes the lease on disconnect; assignment controller picks up the revocation and may reassign the cameras to another worker (if the run is still active — this shouldn't happen in practice, but the protocol is symmetric).

**Failure case:** If a detection fires 1 second before TTL, the alert goes out. If TTL fires before the alert-sender batch flushes (unlikely but possible under heavy load), the last batch of events is lost — this is an acceptable trade-off for the simplicity of a TTL-bounded model. Caller can retry at a lower threshold if needed.

## Status flow back to caller

The [[api-contract]] defines `GET /v1/runs/{id}` for poll-based status. Paradigm C's status reader is minimal:

1. Lambda (or a dedicated status-read function) queries the assignment controller's store:
   - Does the assignment intent exist? (If not, run has expired.)
   - What is the assignment's current state? (Pending, active, draining, expired.)
   - Per-camera counters: frames processed, detections, alerts sent.

2. Worker pods emit metrics to the assignment controller (one-per-second snapshots):
   ```
   assignment-metrics:<run_id>:<camera_id> = {
     frames_processed: int,
     detections_count: int,
     alerts_sent: int,
     last_seen_at: ISO8601,
   }
   ```
   These are transient and cleaned up automatically when the run expires.

3. Status response to caller:
   ```json
   {
     "run_id": "eph_a3k7qz",
     "status": "active",  // or "expired", "drained"
     "expires_at": "2026-05-02T14:00:00Z",
     "cameras": [
       {
         "camera_id": "cam_123",
         "frames_processed": 45000,
         "detections": 123,
         "alerts_sent": 12
       }
     ],
     "timeline": {
       "created_at": "2026-05-01T14:00:00Z",
       "drained_at": null  // filled on drain
     }
   }
   ```

Real-time alerts are the primary feedback channel; polling is for run lifecycle only. This aligns with the [[_overview|pilot scope]]: "real-time alerts are the primary channel."

## Tear-down cleanliness

TTL-driven termination is the cleanest of the 3 paradigms because no pod reclamation happens:

1. Redis TTL fires on the assignment intent and all camera leases.
2. Controller detects lease expiry (leases are gone, intent is gone).
3. Worker detects missing lease (heartbeat fails or explicit revocation).
4. Worker drains the camera (stops pulling, flushes buffer).
5. No pod termination, no SIGTERM, no PVC cleanup.
6. Worker keeps running with a smaller assignment list.
7. If the worker fleet is now over-provisioned, Karpenter can consolidate empty pods in its next reconciliation cycle (minutes later).

**Vs paradigm D/E:**
- **Paradigm D (Event-Driven):** Job's `activeDeadlineSeconds` fires; K8s kills the pod; PVC must be explicitly cleaned up; Karpenter consolidates the freed node.
- **Paradigm E (Sidecar):** Detection core StatefulSet pod is terminated; sidecar shuts down; PVC orphan retention policy must be set; consolidation happens later.
- **Paradigm C:** Lease expires in Redis; worker self-drains; pod keeps running; no K8s reclamation events; consolidation is opportunistic.

Paradigm C's worst case is a "zombie assignment" where the controller crashes and workers keep pulling. But this is bounded by the Redis TTL — at worst 24 hours of wasted compute. Paradigm D/E can leak pods if the Job/StatefulSet controller crashes.

## Cold-start latency

Depends entirely on worker pool capacity:

### Warm pool (capacity available):
- Lambda writes assignment intent: ~50ms
- Controller picks assignment and writes leases: ~100ms
- Worker polls assignment updates (typically every 5s): ~1-5s (depends on poll frequency)
- Worker starts pipeline for the camera: ~2-3s
- **Total: 5-10 seconds.** API returns `run_id` immediately after Lambda write (~100ms); worker startup is asynchronous.

### Cold pool (no capacity):
- Same as above, but Karpenter must provision an EC2 instance (~60-120s per instance).
- Controller waits for HPA or Karpenter to bring a worker online.
- **Total: 60-120 seconds.**

### Mitigations:
1. Keep a small "ephemeral runway" of warm workers dedicated to trial runs (2-3 pods, low resource cost).
2. Predictive scaling: if `POST /runs` request volume is bursty, pre-warm workers during known peak windows.
3. Accept the cold start for the first run; subsequent runs during the same warm-pool window are <10s.

**Verdict:** Cold-start latency is acceptable for a trial/demo product. A caller doesn't expect sub-1s API response; they expect the run to start within a minute.

## Per-run cost

Paradigm C scores best on cost among the 3 because workers are **bin-packed**:

- 1 camera for 1 hour ≈ fractional worker-hour (~2-5% of a m5.large depending on resolution/FPS)
- Cost is amortized across all concurrent runs and production sites the worker fleet serves
- Worker fleet runs 24/7 for production site pods anyway, so ephemeral runs are **pure incremental load**
- Spot eligibility applies (from [[2026-04-16_proposal-c-camera-worker|parent proposal]]): Spot interruption on a worker drops 1-2 frames per camera (tracker snapshots at 1 Hz), mitigated by `karpenter.sh/do-not-disrupt` annotation
- No per-run pod overhead

**Comparison:**
- **Paradigm D:** 1 camera × 1 hour = 1 dedicated EC2 instance (or fractional if multiple runs overlap). Spot eligible but still ~$0.04 per run.
- **Paradigm E:** 1 camera = 1 detection core pod (persistent) + 1 puller sidecar. Slightly better than D due to sidecar sharing, but still not bin-packed.
- **Paradigm C:** 1 camera = fractional worker-hour, shared with 10-50 other concurrent runs. Cost per camera is 0.5-1 cent per hour.

**Implication:** Paradigm C can offer ephemeral trials at scale without flinching at the per-call cost.

## Failure recovery (within 24h)

If a worker dies mid-run:

1. Worker stops sending heartbeats (lease renewal fails).
2. Assignment controller detects lease timeout (~5-10s).
3. Controller reassigns the camera to a different worker (or spins up a new one if all are overloaded).
4. New worker pulls the camera's last tracker snapshot from Redis (written at 1 Hz by the old worker).
5. New worker resumes from the snapshot, losing at most 1 detection cycle (~1 second of video).
6. Caller observes a brief gap in the `frames_processed` counter; nothing leaks to the API surface (the run is still active, the counter just paused for a moment).

This is **C's strongest story** — failure recovery is fully automated at the controller level. No caller intervention needed. Paradigm D/E require polling a Job status or handling StatefulSet pod churn.

## Implementation cost (if C already exists)

If Proposal C is built as a fleet, the ephemeral pilot is a **thin add-on**:

1. New `assignment-intent` schema in controller's Redis/etcd key space.
2. TTL handling in controller's reconciliation loop (should be trivial — write `EXPIRE` on lease).
3. Status-read Lambda (simple key lookups in Redis).
4. Metrics aggregation in the assignment controller (optional; can ship v1 without per-camera metrics).

**Estimated effort:** 1-2 weeks if C already exists.

### Pre-requisite (the big one):
**Proposal C must be built first.** This is the largest pre-req of the 3 paradigms. Paradigm C as a pilot is feasible only if the assignment controller + camera-worker fleet is on the roadmap. If C doesn't exist, the effort becomes:
- Build the assignment controller + worker fleets (13-20 weeks per [[2026-04-16_proposal-c-camera-worker]]).
- Then add ephemeral run hooks (1-2 weeks).
- **Total: 14-22 weeks.** Not a candidate for a short-cycle pilot.

**Strategic question:** Is the ephemeral pilot being used to **validate** that we should build C, or is it a **secondary** use case for an already-committed C rollout? If the former, paradigm C is too expensive as a pilot vehicle. If the latter, C makes the pilot nearly free.

## Architectural fit

Paradigm C maps **almost exactly** to the ephemeral-run model:
- `camera assignment` = `run` (conceptually)
- `TTL on lease` = `max 24h` (natural)
- `worker pool` = `compute substrate` (reuses existing)
- `drain on expiry` = `run lifecycle` (symmetric)

The data model alignment is strong, which is why implementation cost is low. No awkward impedance mismatches between "caller API" and "cluster mechanics."

**The risk:** "We built Proposal C just to support ephemeral runs." The pilot should **prove that C is a good design for steady-state production**, not vice versa. Evaluate the pilot results carefully:
- Does the controller scale cleanly to 1000+ cameras (not just 50)?
- Does bin-packing actually reduce cost at 24/7 production scale?
- Are there failure modes (e.g., controller leader election hang, Redis snapshot corruption) that only surface under long-term running?

An ephemeral pilot provides signal on cold-start, cost, and burst behavior; it does NOT provide signal on multi-month stability. Budget for a longer steady-state production trial before declaring C viable.

## What the pilot proves about C

If paradigm C is selected for the pilot, the pilot tests:

1. **Bin-packing efficiency under burst load** — 10-100 small ephemeral runs stacked on production site pods in the same fleet. Does churn hurt production latency?
2. **Controller scalability** — Assignment ops/sec under high churn (10s of `POST /runs` per minute, all with different TTLs). Does the controller keep up?
3. **Spot interruption tolerance** — Worker dies mid-assignment (Spot reclamation). Does reassignment + snapshot recovery actually work? How many events are lost?
4. **Karpenter scaling cadence** — Does consolidation kick in fast enough to avoid stranded over-provisioning? Or do we accumulate empty workers?
5. **Alert reliability under TTL** — Do detections firing close to expiry actually send alerts, or does the drain/SIGTERM race cause loss?

## Scoring against the rubric

Using the [[_overview|ephemeral-run pilot evaluation rubric]]:

| Dimension | Score | Justification |
|-----------|------:|---|
| **Cold-start latency** (20%) | 8 | 5-10s warm pool, 60-120s cold. Acceptable for a trial product. Warm-runway mitigation can push toward 5s. |
| **Per-run cost** (20%) | 10 | Bin-packing = fractional worker-hour. Lowest of 3 paradigms. |
| **Tear-down cleanliness** (15%) | 9 | TTL expiry + worker self-drain. No pod reclamation events. Cleanest of 3. |
| **Alert latency under TTL** (15%) | 8 | Alerts fire immediately from workers. Close-to-expiry edge case (race between detection and drain) is rare and acceptable. |
| **Failure recovery** (10%) | 9 | Fully automated at controller level. Snapshot recovery from Redis. No caller intervention. Strongest of 3. |
| **Implementation cost** (10%) | 2 | Requires building Proposal C first (13-20 weeks). Pilot add-on is cheap (~1-2 weeks), but base cost is high. OR if C already exists: 10/10. |
| **Architectural fit** (10%) | 10 | 1:1 mapping of lease → run. Data model alignment is ideal. |

**Composite (weighted):** `(8×0.20)+(10×0.20)+(9×0.15)+(8×0.15)+(9×0.10)+(2×0.10)+(10×0.10) = 1.6 + 2.0 + 1.35 + 1.2 + 0.9 + 0.2 + 1.0 = 8.25 / 10`

**Caveat:** The "implementation cost" dimension dominates. If C is already on the roadmap, the score is closer to 9.5/10. If C is contingent on the ephemeral pilot's success, the score drops to 7/10 (high upfront sunk cost for an uncertain bet).

## Open questions / follow-ups

1. **Controller churn tolerance** — Is the C controller designed to handle 10+ assignment changes per second, or is it tuned for steady-state (1 change per minute)? Ephemeral runs are bursty; the pilot will expose controller bottlenecks fast.

2. **Minimum viable C stub** — What's the smallest subset of C that unblocks the ephemeral pilot? Can we ship an MVP with:
   - Single-threaded controller (no HA standby)?
   - Redis only (no etcd)?
   - Simple FIFO bin-packing (not best-fit)?
   - No metrics collection (only run status)?

3. **Per-tenant capacity limits** — How do capacity caps (e.g., "tenant A can use max 10 cameras at once") map onto a shared worker pool? Does the controller have quota enforcement?

4. **Multi-tenant isolation in shared workers** — At pilot scale (small trials), risk is low. But at 100+ concurrent ephemeral runs from different tenants in the same worker: is this a security concern? Can one tenant's pipeline spy on another's tracker state or alert config?

5. **Upgrade safety during active runs** — If we roll out a new connector image while ephemeral runs are active, do running workers stay on the old image (safest), or do they upgrade in-place (loses tracker state)? For C, the answer is "workers stay on old image; new workers use new image; old cameras eventually drain and reassign to new workers." Confirm this is the desired behavior.

6. **Snapshot serialization format** — Tracker snapshots are sent to Redis at 1 Hz. What happens if the snapshot schema changes (e.g., tracker adds a new field)? Are old snapshots forward-compatible when loaded into a new worker image?

## Cross-references

- Parent proposal: [[2026-04-16_proposal-c-camera-worker]]
- Pilot overview: [[_overview]]
- API contract: [[api-contract]]
- Translation layer: [[translation-layer]]
- Verification: [[blacklist-filter-locality]] (enables per-camera split)
- Controller selection: [[k8s-controller-selection-guide]]
- Sibling paradigms: [[paradigm-d]], [[paradigm-e]]
- Failure & recovery: [[2026-04-16_graceful-failover-design]]
- Tracker state: [[tracker-snapshot-schema]]
- Connectivity: [[customer-site-connectivity]]
- Alert routing: `[[actuate-libraries/notes/entities/actuate-alarm-senders]]`
