---
title: "Run Service — Paradigm D (Event-Driven)"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, pilot, paradigm-d, event-driven, nats, jetstream, s3, ephemeral, dynamodb]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: drafting
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/api-contract.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-e.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/translation-layer.md
incoming_updated: 2026-05-27
---

# Run Service — Paradigm D (Event-Driven)

> **Reading note:** Scores in this document are **ephemeral-lens only**. Final paradigm selection combines them with a separate persistent-mode score — see [[_overview]] for the dual-rubric framing. The chosen paradigm has to serve **both** `mode: ephemeral` and `mode: persistent` runs through the **same primitives** (no parallel implementations); the pilot stress-tests this directly.

Ephemeral runs fit naturally into Proposal D's event-driven topology: the "run" becomes a queue lifecycle. Instead of spinning up per-run K8s Jobs, the pilot publishes camera assignments to JetStream subjects with TTL, existing fleets (pullers, detectors, observers, alert-dispatch) subscribe and drain when the subject expires. The architecture gains no new pods, but the operational model shifts from imperative (create/destroy workloads) to declarative (publish/consume events).

This note focuses on D-specific mechanics for the 24-hour ephemeral pilot. See [[_overview]] for pilot framing and evaluation rubric; [[api-contract]] for the public API shape; [[translation-layer]] for spec → settings.json translation. Read [[2026-04-16_proposal-d-event-driven]] for D's full architecture and cost model.

## Natural fit: runs as queue lifecycles

In paradigm D, a "run" has no K8s representation—no Job, no Deployment, no StatefulSet. Instead:

1. Lambda receives `POST /v1/runs/{run_id}` with `RunSpec.v1` payload
2. Lambda translates spec → settings.json, validates (three-layer per [[translation-layer]])
3. Lambda publishes camera-assignment messages to a tenant-scoped JetStream subject: `runs.{tenant}.{run_id}.cameras.{cam_id}.frames` with `Expires` set to the run's TTL (max 24h)
4. Existing puller fleet subscribes to all subjects under `runs.{tenant}.{run_id}.cameras.*`; each puller consumes assignments for cameras it pulls
5. Puller writes frames to S3, publishes frame references to `runs.{tenant}.{run_id}.detections.input`
6. Detector fleet consumes, infers, publishes detections to `runs.{tenant}.{run_id}.detections.output`
7. Observer consumes detections, runs filters, publishes alerts to `runs.{tenant}.{run_id}.alerts`
8. Alert-dispatch fleet consumes alerts, fires through alert-sender to recipients (email/SMS/integrations)
9. When `Expires` fires (24h), JetStream reclaims the subjects; all consumers auto-drain; pullers and detectors stop processing without explicit shutdown

**Architectural advantage:** The queue itself is the run's lifecycle primitive. No controller orchestrates pod creation/deletion; K8s is purely a capacity pool. Compare to paradigms C (K8s Job per run) and E (K8s Deployment per run) — D eliminates the control-plane churn.

**Caveat:** This is conceptually clean but operationally depends on JetStream's `Expires` semantics being reliable and monitored. If a subject's TTL fails to fire, the run persists indefinitely and consumes resources.

## What gets created on `POST /v1/runs`

Lambda handoff to the D fleet is minimal:

| Artifact | Ownership | Lifecycle |
|----------|-----------|-----------|
| **JetStream subjects** (4 per run) | NATS | Auto-reclaimed at TTL expiry |
| **S3 frame objects** | S3 | TTL policy (30d archive, then expire) |
| **DynamoDB run record** | Dynamo | Per [[api-contract]]: persist run metadata, status, config |
| **K8s resources** | None | Zero new pods, zero Jobs, zero Deployments |

The subjects are:
- `runs.{tenant}.{run_id}.cameras.{cam_id}.frames` — camera → frame refs (puller publishes, detector consumes)
- `runs.{tenant}.{run_id}.detections.input` — detector input queue (aggregated refs from all cameras)
- `runs.{tenant}.{run_id}.detections.output` — detector output queue (detections + frame refs)
- `runs.{tenant}.{run_id}.alerts` — alert events (observer publishes, alert-dispatch consumes)

Each subject has `Expires: {run_ttl}` set on the JetStream consumer. When the clock ticks past the expiry, the consumer's messages are reclaimed and new publishes fail with a "subject expired" error.

Lambda also writes a run record to DynamoDB with initial state `RUNNING`, config snapshot, and TTL indexed for cleanup queries.

## K8s manifest sketch

No new manifests. All existing:

| Component | Type | Count | Scaling signal |
|-----------|------|-------|-----------------|
| Puller + FDMD | Deployment | N (per site) | HPA on camera count |
| Detector | Deployment | M | HPA on JetStream consumer-lag |
| Observer + tracker | StatefulSet | K | HPA on JetStream consumer-lag or tracker memory |
| Alert-dispatch | Deployment | L | HPA on alert-event rate |
| NATS JetStream | StatefulSet | 3-5 | Fixed size; no ephemeral scaling |

NATS itself is shared infrastructure — the cluster runs continuously, not per-run. Multiple runs' subjects coexist on the same broker. The [[pod-disruption-budgets|PDB]] with `maxUnavailable: 1` ensures a rolling upgrade doesn't stall the broker's RAFT quorum (N/2+1 for N replicas).

**Key insight:** Ephemeral runs don't trigger new pod creation. They're just subjects on an existing cluster. Cold-start latency is dominated by:
- Existing pullers' latency to pick up a new subject (typically <100ms if already subscribed to the wildcard)
- First frame S3 write + publish latency (~500ms for [[rtsp-deep-dive|RTSP]] connect + first frame)
- Detector fleet latency to consume and infer (varies by GPU utilization, typically 2-5s for first detection)

If the detector fleet is scale-to-zero, HPA scale-from-zero adds 1-2 minutes (image pull + container startup + model warmup). This is a real risk for D if the fleet isn't "warm" — but that's a parameter of the **operational model** (keep detectors warm or pay cold-start penalty), not a D-specific issue.

## Alert flow under finite TTL

Alerts travel through D's existing Alert-dispatch fleet, which consumes from the run's alert subject and fires through the external alert-sender (email, SMS, third-party integrations). All recipients receive alerts **directly**, not routed through the API.

JetStream's delivery contract: at-least-once. If alert-dispatch ACKs an alert message, it has been fired (or queued for firing). If the pod crashes before ACKing, the message is redelivered to another consumer.

**TTL safety:** JetStream doesn't auto-delete a message until all consumers have ACKed it (for durable consumers). So even if an alert is in-flight when the subject's `Expires` fires:
- If it's already published and the ACK is in-flight, the message persists until ACKed
- If it's published but not yet consumed, it persists until a consumer processes + ACKs
- "Persists" means it stays in the broker's replicated log, not in NATS memory

In practice, a 24-hour TTL gives generous buffer for alerts (typically <100ms publish + consume latency). The risk of a message expiring mid-ACK is negligible unless the alert-dispatch fleet is severely backlogged (lag > hours), which would be visible on the monitoring dashboard.

## Status flow back to caller

The status reader Lambda queries JetStream consumer-state directly via the NATS client:

```go
// Pseudocode
consumer := jetstream.Consumer(ctx, "runs.{tenant}.{run_id}.detections.output")
info := consumer.Info(ctx)
// info.NumPending — messages awaiting delivery
// info.NumAckPending — messages delivered but not acked
// info.AckFloor.Stream — highest sequence acked
```

Status endpoints populate:

| Metric | Source | Meaning |
|--------|--------|---------|
| `frames_pulled` | max(frame-ref subject's published count) per camera | Frames fetched from [[rtsp-deep-dive|RTSP]] |
| `detections_made` | detection-output subject's acked count | Inferences run (per-camera summable) |
| `alerts_fired` | alert subject's acked count | Alerts sent to recipients |
| `queue_lag` | consumer-lag on each subject | Backpressure signal; indicates overload if lag grows |
| `time_to_first_detection` | timestamp diff (first frame published → first detection published) | Cold-start latency |

JetStream exposes these metrics natively via its consumer-state API, no instrumentation needed. The status reader can answer "how many frames have been processed?" and "is the detector queue backed up?" without polling counters or querying a separate metrics system.

**Observability win:** D's queueing gives status queries much higher fidelity than paradigm C (where status requires scraping Prometheus from scattered pods) or E (where state is spread across multiple components).

## Tear-down cleanliness

At TTL expiry, the NATS broker's `Expires` field on the consumer triggers a clean reclaim:

1. JetStream consumer's `MaxAge` (or `Expires`) timer fires at T = 24h
2. Broker purges the consumer's message set; new publishes to the subject fail with "subject expired"
3. All subscribers (pullers, detectors, observers, alert-dispatch) see the subscription closed
4. Workers drain naturally (no more messages to consume)
5. S3 frame objects are tagged with the run ID and a separate TTL via S3 lifecycle policy (e.g., 30 days for archival, then automatic expiry)

No Kubernetes Job cleanup needed. No pod preStop handlers. No lingering processes. The run's footprint in the cluster shrinks to zero.

**Risk: orphaned S3 objects.** If the S3 lifecycle rule is misconfigured (missing run-id tag, wrong expiry date, or not applied), frames linger and cost money. Mitigation: Lambda should tag every S3 object it writes with `run_id` and `ttl_expires_at` at upload time. A separate background Lambda (triggered by EventBridge on a daily schedule) scans S3 for orphaned frames older than 30 days and deletes them. This is a small operational tax but necessary for cost safety.

## Cold-start latency

D's cold-start is dominated by existing-fleet latency to pick up new subjects, not by pod provisioning:

- **Lambda to subject creation:** <100ms
- **Puller to first frame:** depends on [[rtsp-deep-dive|RTSP]] connection (typically 500ms-2s)
- **S3 frame ref publish latency:** ~100ms (NATS publish)
- **Detector to consumption:** <100ms if fleet is warm; 1-2 minutes if scale-to-zero
- **Inference latency:** 1-5s per frame (model-dependent)
- **First detection published:** typically 2-10s from first frame pulled

**Realistic end-to-end cold-start: 5-10s if detector fleet is warm, 1-3 minutes if waking from scale-to-zero.**

Compare to paradigm C (spin up K8s Job + pull container image + start connector: 30-60s minimum) and E (spin up Deployment + init container validation: 20-40s). D is competitive or faster **if the fleet is warm**. D's Achilles heel is the assumption that the detector fleet runs continuously; if it doesn't, D regresses to the slowest start time of the three.

This is a **parameter of the operational model**, not a D flaw. The pilot must validate whether keeping detectors warm (e.g., via a periodic no-op request to HPA) is acceptable operational overhead.

## Per-run cost

D's cost structure is sensitive to run shape:

| Component | Cost driver | Per-run impact |
|-----------|-------------|-----------------|
| **NATS bandwidth** | Message volume (frames + detections + alerts) | ~0.1-0.5% of total, negligible |
| **S3 frame storage (PUT)** | Puller frame-write rate | ~$0.00025 per 1000 PUTs; 100 cams × 3 FPS × 86400s = 25.9M PUTs/day = $6.50/day storage cost |
| **S3 frame storage (GET)** | Detector reads | ~100-500 GET/s sustained; typically 10 GET/sec × 86400 = 864k GET/day = $0.04/day read cost |
| **S3 frame object storage** | GB-days of frame objects | 100 cams × 3 FPS × 1200 bytes (JPEG) × 86400s = ~311 GB/day; at $0.023/GB/mo (~$0.00000032/GB/day in S3 Standard) = ~$0.10/day storage cost |
| **Detector GPU-seconds** | Inference time | E.g., 100 cams × 3 FPS = 259.2k inferences/day; at 100ms/inference (YOLOv5) = 25,920 GPU-seconds = ~$0.02/day (at $3/hr p3.2xlarge GPU) |
| **Observer CPU** | Filter evaluation | ~1-5 vCPU-hours/day; negligible |
| **Alert dispatch** | SMTP/SMS/API calls | Depends on alert rate; 100-1000 alerts/day = <$1 |

**Total per-run cost for a typical 24h, 100-camera run at 3 FPS: ~$7-8/day in S3 PUT + frame storage + detector GPU.** This scales linearly with frame rate and camera count.

**Cost concern: S3 frame storage is the largest variable cost.** Unlike paradigm C (where frames are discarded after inference) or E (where frames are in-memory and evicted after detection), D persists every frame to S3 for the detector fleet to access. For a busy run (motion-heavy, high frame rate), this can spiral: 100 cameras × 10 FPS × 24h = 86.4M frames = 100+ GB of frame data.

**Mitigations:**
- Aggressive S3 object lifecycle: delete frames 1-2 hours after writing (not 30 days), keeping only recent frames for replay/debugging
- Frame deduplication: if FDMD drops identical frames, puller batches 5-10 into a single S3 object, reducing PUT cost
- Lower-resolution frames for non-motion frames: puller writes thumbnails (200x200 JPEG) for FDMD-dropped frames, full-res only for motion frames

**Cost sensitivity:** D's per-run cost is **not flat** across run shapes. A quiet 24-hour run (few detections) costs ~$2-3. A busy run (heavy motion, 10 FPS) costs $50-100. This makes D less predictable than C or E, where cost is more tightly bound to inference count.

## Failure recovery (within 24h)

D's stateless design makes recovery the strongest of the three paradigms:

| Failure | Recovery |
|---------|----------|
| **Puller pod crash** | NATS message ACK fails → redelivery to another puller consumer; frames resume flowing <10s |
| **Detector crash** | Detection messages redelivered to another detector instance; queue buffers pending detections |
| **Observer crash** | **Tracker state lost** (see below); detection messages redelivered; filter evaluation resumes but without historical state |
| **Alert-dispatch crash** | Alert messages redelivered to another instance; alerts resume flowing <10s |
| **NATS broker crash** | JetStream persistence recovers; cluster reconverges (RAFT); messages persist in replicated log |
| **S3 frame corruption** | Detector can't fetch frame → error log, detection skipped, no blast radius |

**Tracker state recovery:** The observer fleet is the only stateful component (tracks moving objects per camera). On pod restart, the observer must reload tracker snapshots from Redis (per [[tracker-snapshot-schema]]). The tracker's RPO is the last snapshot time (typically every 1-5s); alerts may repeat within that window until the snapshot reloads.

This is the weak point: if the observer fleet crashes mid-run, tracker state is lost and has to be rebuilt from scratch. Compared to paradigm E (where tracker state lives in a persistent StatefulSet with local storage), D's recovery is slower but still acceptable for a 24h run.

## Implementation cost

Building ephemeral support on top of D is **small** if D's fleet already exists:

| Task | Effort | Notes |
|------|--------|-------|
| Lambda to create JetStream subjects + DynamoDB record | 2-3 days | Reuse translation-layer logic; add subject-creation API to NATS client wrapper |
| Status reader Lambda to query consumer-state | 1 day | Query NATS consumer APIs; format response per [[api-contract]] |
| S3 lifecycle policy + cleanup Lambda | 1 day | Tag frames with run ID; sweep orphaned objects daily |
| DynamoDB TTL index for stale run cleanup | 1 day | Purge old run records on schedule |
| Monitoring: JetStream subject-lag + broker health | 2-3 days | Export lag to Prometheus; alert on stale subjects or lag > threshold |
| Integration test (end-to-end with test run) | 2-3 days | Validate frame flow, detector output, alerts, TTL cleanup |

**Total: ~10-15 days.** This assumes D's core fleet (pullers, detectors, observers, alert-dispatch, NATS) is already operational.

**Pre-requisite: D must be built first.** The pilot is feasible only if D is on the roadmap and provisioned with sufficient capacity to run pilot load alongside production load. Shared NATS cluster means pilot and production subjects coexist; noisy pilot subjects could interfere with production consumers if resource limits aren't tight.

## Architectural fit

D is **the best fit for ephemeral runs by data model**:

1. **Queue as primitive:** "A run is a queue's lifecycle" is a clean abstraction. No imperative workflow controller needed.
2. **Per-camera subjects scale O(1):** Subject creation and message routing are stateless. No centralizing controller becomes a bottleneck (unlike C, where the job-manager controller must create one Job per run).
3. **Rich status observability:** JetStream consumer-state APIs expose run metrics for free.
4. **Natural failover:** Stateless components (pullers, detectors) fail over by message redelivery; no explicit recovery code needed.
5. **Replay capability:** Historical runs' subjects' messages can be replayed from JetStream's log if auditing or debugging is needed (not possible with C or E).

**Caveat:** D's architectural elegance is offset by **operational complexity**. NATS JetStream is a new operational surface: RAFT leader elections, disk pressure, rebalancing during upgrades, subject proliferation (fragmentation). The team must be comfortable debugging these failure modes.

## D-specific risks

1. **NATS JetStream operational maturity:** The team has never run NATS at scale. Failure modes (RAFT stalls, disk fill, rebalance latency) are unfamiliar. The pilot must validate that the team can operate it safely (automated monitoring, runbooks, fast recovery).

2. **S3 frame-storage cost can blow up:** Busy runs (motion-heavy, high frame rate) can generate 100+ GB of frames in 24h. Without aggressive lifecycle policies, per-run costs spike nonlinearly. The pilot must validate cost projections against real camera data.

3. **Stateless-vs-stateful filter split:** The parent proposal splits filters: stateless (IOU, IgnoreZones) in detector, stateful (StationaryFilter) in observer. This split is not intrinsic to D; it's an architectural choice that limits what filters can do. If a future filter is both stateless and state-aware, the architecture constrains implementation. The pilot doesn't need to fix this, but must flag if it becomes a blocker.

4. **Subject namespace explosion:** Every run creates 4 subjects. 1000 ephemeral runs = 4000 subjects on the broker. NATS can handle this, but subject metadata (broker-side storage, log entries) grows O(runs). The pilot must validate broker scaling assumptions.

5. **Cold-start from scale-to-zero:** If the detector fleet is scaled to zero between runs, the first run incurs 1-2 minute cold-start (HPA scale-up + image pull + model load). The pilot must confirm whether warm-fleet assumptions are realistic or if we accept this latency tax.

## What the pilot proves about D

1. **JetStream operational maturity** at pilot scale (clustering, node failure, upgrade cycles without human intervention)
2. **S3 frame-storage cost economics** under realistic camera-hours (validate the $7/day projection; identify optimization opportunities)
3. **HPA on consumer-lag responsiveness** for real-time alert latency (lag is the signal; does HPA respond fast enough to keep latency steady?)
4. **Multi-tenant subject namespace design** (can we safely isolate tenant A's subjects from tenant B's without manual broker tuning?)
5. **Subject-per-camera scaling characteristics** (does broker metadata grow unacceptably with subject count? Does msg routing slow down?)
6. **Tracker state recovery time** from snapshots (on observer restart, how long until tracker is warm again?)
7. **Cost sensitivity to run shape** (how much does cost vary between quiet and busy runs? Are mitigations effective?)

## Evaluation against the rubric

Using [[2026-04-16_evaluation-rubric]]:

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Independent scalability | 9 | All stages scale independently on consumer-lag; puller scales on camera count. Single minor caveat: alert-dispatch scales on event rate, less direct than other stages. |
| Cost reduction | 5 | Per-run cost is lower than C for quiet runs (~$2-3/day); higher for busy runs ($50-100/day). At 10× fleet, depends heavily on motion distribution — likely neutral if motion patterns don't change. |
| Failure isolation | 8 | Stateless stages fail over cleanly; tracker-state loss on observer crash is the only blast-radius item. Alerts keep flowing even during pipeline failures. |
| Operational simplicity | 3 | NATS + S3 + DynamoDB + monitoring adds significant ops surface. JetStream's RAFT, broker health, subject fragmentation are new unknowns. Distributed tracing mandatory for multi-stage debugging. |
| Migration risk | 3 | Depends on D's build timeline (not paradigm-specific). Filter-chain split is invasive; stateless/stateful split may break existing filter assumptions. Incremental rollout risky if fleet capacity is tight. |
| Failover quality | 8 | RPO ~1-5s (tracker snapshot interval); RTO ~5-10s for stateless stages, 10-30s for observer (tracker reload + catchup). Verified in chaos test (not yet done). |

**Composite (pre-pilot):** `(9×0.35) + (5×0.20) + (8×0.15) + (3×0.15) + (3×0.10) + (8×0.05) = 6.65 / 10`

This is slightly below D's pre-PoC composite (6.85 from the parent proposal) because the ephemeral pilot adds operational complexity (subject management, cost monitoring) that the general-purpose fleet doesn't need to justify. The pilot is still viable but requires strong confidence in operational readiness.

## Open questions / follow-ups

1. **JetStream capacity sizing:** How many subjects can a 3-5 node NATS cluster safely host? At 1000 concurrent ephemeral runs × 4 subjects/run, we have 4000 subjects. Is this acceptable, or do we need a separate pilot-only broker?

2. **S3 PUT cost optimization:** Batching frames into single S3 objects reduces PUT cost by 10×. Does this add acceptable latency (3-4s) to the detector's frame-fetch path? Benchmark in pilot.

3. **Detector fleet warmth assumption:** If detectors scale to zero, cold-start is 1-2 minutes. If they stay warm, operational cost is higher but cold-start is 5-10s. What's the breakeven? Can we auto-scale down but with a 5-minute grace period to catch "bursty" workloads?

4. **Tracker snapshot interval:** How frequently must observer write snapshots to Redis to keep RPO acceptable? Every 1s? Every 5s? Trade-off is CPU (write frequency) vs RPO (loss window). Benchmark in pilot.

5. **Subject namespace design:** Should we use per-run subjects (`runs.{tenant}.{run_id}.detections.output`) or per-stage subjects (`detections.output`)? Per-run isolates runs but fragments the broker; per-stage aggregates but makes per-run status queries harder. The pilot must choose and validate.

6. **Cost projections under real motion:** The pilot uses synthetic camera data. Real motion patterns may differ (fewer detections = lower cost, or more = higher). Iterate cost model post-pilot with production motion rates.

7. **Failure cascades:** If the observer crashes and tracker state is lost, can puller + detector continue? What happens to in-flight alerts? Chaos-test the cascade scenarios.

## Cross-references

- [[2026-04-16_proposal-d-event-driven|Parent proposal]] — full architecture, failure modes, PoC spec
- [[_overview|Pilot overview]] — 24h boundary, no-admin-state model, evaluation dimensions
- [[api-contract|API contract]] — RunSpec.v1, lifecycle endpoints, DetectionEvent.v1, DynamoDB schema
- [[translation-layer|Translation layer]] — spec → settings.json, three-layer validation
- [[2026-04-16_frame-transport-comparison|Frame transport comparison]] — S3 reference pattern rationale, cross-AZ cost
- [[pod-disruption-budgets|Pod disruption budgets]] — NATS StatefulSet PDB requirement
- [[tracker-snapshot-schema|Tracker snapshots]] — observer state recovery design
- [[paradigm-c|Paradigm C (Camera-worker)]] — sibling approach for comparison
- [[paradigm-e|Paradigm E (Hybrid sidecar)]] — sibling approach for comparison
