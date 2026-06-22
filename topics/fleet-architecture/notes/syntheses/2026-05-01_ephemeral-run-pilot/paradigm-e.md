---
title: "Run Service — Paradigm E (Hybrid Sidecar)"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, pilot, paradigm-e, hybrid-sidecar, statefulset, smart-puller, ephemeral-run, api-gateway]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: drafting
jira: ""
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/api-contract.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/translation-layer.md
incoming_updated: 2026-05-27
---

# Run Service — Paradigm E (Hybrid Sidecar)

> **Reading note:** Scores in this document are **ephemeral-lens only**. Final paradigm selection combines them with a separate persistent-mode score — see [[_overview]] for the dual-rubric framing. The chosen paradigm has to serve **both** `mode: ephemeral` and `mode: persistent` runs through the **same primitives** (no parallel implementations); the pilot stress-tests this directly.

**Context:** This note describes how the **Ephemeral Run Pilot** (a bounded-TTL, caller-supplied VMS workload) lands on **Proposal E's architecture** — the highest-scoring candidate (8.05/10) from the fleet redesign effort. The pilot tests whether E's structural complexity (3-4 fleets, StatefulSet camera affinity, motion-gated frame flow) is justified even for short-lived, finite-scale workloads.

Refer to [[2026-04-16_proposal-e-hybrid-sidecar|Proposal E]] for the full architecture; [[_overview|Ephemeral Run Pilot Overview]] for the API contract, translation layer, and evaluation rubric. This note focuses on E-specific design and implementation surface.

---

## The Fit for Ephemeral Runs

Proposal E's core strength is **independent fleet scalability via internal specialization** — Smart Puller handles frame acquisition + motion filtering; Detection Core holds full inference + tracker state; Site Context manages schedule + camera registry; Alert Dispatch consumes events asynchronously. This decomposition wins on cost (-20-40%) and failure isolation when amortized across persistent workloads at scale.

But ephemeral runs are **different**: they're bounded (24h max), typically smaller (10-100 cameras), single-user, and stateless from the admin API's perspective. The question E's pilot must answer: **does E's internal complexity justified its overhead, or does the setup cadence and multi-fleet handoff eat the savings for a 24h workload?**

Key unknowns:
1. How fast does Detection Core scale (StatefulSet ordinal increase) under HPA?
2. Do camera-affinity slot allocations under high churn (lots of runs adding/removing cameras) remain efficient?
3. Does motion-gating's cost savings actually materialize at small scale (48 cameras, 24h)?
4. Can the tracker-snapshot recovery path run cleanly under TTL drain without orphaned Redis keys?

E may "win on paper but lose for ephemeral" — or conversely, the pilot may validate that motion-filtering is E's killer feature and the internal structure is cheap insurance. The rubric (below) addresses this honestly.

---

## What Gets Created on POST /v1/runs

Caller issues:
```json
POST /v1/runs
{
  "spec": {
    "cameras": [{"vms_id": "...", "name": "..."}, ...],
    "alert_config": {...},
    "duration_hours": 6,
    "site_name": "ephemeral-run-{uuid}"
  }
}
```

Lambda response: API Gateway returns `{run_id, status, status_url}` (synchronous create; status polling thereafter).

### Backend handoff (E-specific)

1. **Lambda translates** `RunSpec.v1` → full `settings.json` (per [[translation-layer]]). Runs three-layer validation + `connector validate` init container.

2. **Lambda registers site with Site Context Service** — creates a "site" record keyed by `{run_id}` with:
   - Camera roster + VMS credentials (encrypted in Site Context's own store)
   - TTL: `now() + duration_hours + 5min buffer` (ensures graceful drain before revocation)
   - Alert config (routing rules, recipient list)
   - Schedule (if caller supplied; else "always on")

3. **Smart Puller fleet picks up the new site** — Site Context's [[watch-entity|watch]] notifications (or polling) trigger Smart Puller to:
   - Allocate a puller pod from the pool matching the VMS family
   - Open VMS tunnel; pull frames at camera's configured FPS
   - Run FDMD motion detection inline
   - Publish motion-gated frames (20-40% of raw) to Redis Streams at `motion-frame:group:{camera_group_id}`

4. **Detection Core StatefulSet routes by camera affinity** — Each frame published by Smart Puller includes `camera_id`. Detection Core's Site Context client assigns cameras to specific pods (ordinal-based):
   - **If spare slots:** reuse an existing Detection Core pod (sub-second latency)
   - **If no spare slots:** HPA triggers StatefulSet ordinal increase (1-3 min latency typical; this is the cold-start hot spot for E)
   - Affinity persists across frames — same camera always hits the same pod during the run

5. **Detection Core inference → SNS → SQS → alert-sender** — full pipeline intact (per Proposal E). Detection Core emits events to SNS; Alert Dispatch fleet consumes via SQS FIFO + sends to recipients (email/SMS/webhook).

6. **Status aggregation** — Site Context Service exposes per-run counters:
   - Frames pulled (Smart Puller counter)
   - Frames after motion gate (Smart Puller counter)
   - Detections emitted (Detection Core counter)
   - Alerts fired (Alert Dispatch counter)
   - API reader Lambda queries Site Context and returns to caller

7. **On TTL expiry** — Site Context revokes the run's site record:
   - Smart Pullers stop pulling for the run's cameras
   - Detection Core drains tracker state via snapshot-to-Redis (10-30s under load, bounded by `terminationGracePeriodSeconds`)
   - Alert Dispatch drains in-flight SQS messages (FIFO ordering ensures no loss)
   - Unused StatefulSet ordinals scale down only if post-drain Detection Core is over-provisioned (rare; unlikely for 24h bounded runs)

---

## K8s Manifest Sketch

Unlike paradigm C (Job per run) or paradigm D (per-run NATS source), E **creates no new K8s objects per run**. All workloads are fleet-level; runs exist as Site Context records + transient state in running pods.

### Per-run resources
- **Site Context record** (DynamoDB or in-process cache, depending on Site Context's backend)
  - Key: `{run_id}`
  - Attributes: camera roster, alert config, TTL, status counters, Site Context pod affinity assignments
  - TTL: application-enforced (DynamoDB TTL if using DynamoDB; custom watchdog if in-memory)

- **Detection Core ordinal scale** (StatefulSet `replicas` field increase)
  - Occurs only if `HPA.maxReplicas` permits and HPA threshold is crossed
  - Adds pods with ordinals `[current_max+1, current_max+2, ...]` via StatefulSet controller
  - Removes ordinals during drain (unlikely for bounded runs)

### Fleet-level resources (reused across all runs)
- **Smart Puller StatefulSet or Deployment** (family-pooled, Spot-eligible)
  - One pod per VMS family; cameras distributed across pods by family
  - No per-run scaling — one puller handles 10-100 concurrent cameras
  - (Alternative: one puller pod per run for full isolation, but cost-inefficient)

- **Detection Core StatefulSet** (On-Demand, not Spot)
  - Scaled by HPA based on CPU/memory + camera-affinity slot utilization
  - `partition` field in `updateStrategy.rollingUpdate` enables staged ordinal rollouts

- **Site Context Service** (stateless Service + Deployment, Spot-eligible)
  - Small footprint; routes config/schedule/registry queries
  - Load negligible (queries are per-run, not per-frame)

- **Alert Dispatch Service** (Deployment consuming SNS → SQS FIFO, Spot-eligible)
  - Reuses existing SQS FIFO queues (one per camera-group? one per site?)
  - HPA scales on SQS queue depth

---

## Alert Flow Under Finite TTL

E's alert path is the **cleanest of the 3 ephemeral paradigms** (C/D/E):

1. **Detection Core emits events to SNS** — one SNS topic per detection event type, or one per run (configurable at Lambda registration time)

2. **Alert Dispatch (dedicated fleet) consumes SNS → SQS FIFO** — SNS fan-out to SQS FIFO queues, preserving order by camera-id

3. **Alert-sender fires to recipients** — alert-sender (existing service) consumes SQS FIFO and dispatches to email/SMS/webhook. Service is decoupled from the [[vms-connector|VMS connector]]; no thundering herd.

4. **Real-time delivery** — motion-gating at Smart Puller layer means only "interesting" frames (20-40%) reach Detection Core. Detection-to-alert latency is bounded by inference path, not frame-backlog under load.

5. **TTL boundary cleanness** — on TTL expiry:
   - Detection Core stops emitting events (no new frames from Smart Puller)
   - In-flight events in SQS FIFO finish their journey (SQS retention > TTL, so no loss)
   - Caller may see a final batch of alerts for the last few seconds of camera capture
   - This is expected and acceptable

**Risk:** if Alert Dispatch or alert-sender crashes mid-run, in-flight events remain in SQS and retry indefinitely (potentially past TTL). Mitigation: set SQS message TTL or mark ephemeral-run events with a run_id so alert-sender can discard them post-expiry.

---

## Status Flow Back to Caller

Caller polls `GET /v1/runs/{run_id}/status` (async; no blocking calls per API contract). Lambda reader:

1. Queries Site Context Service for run's site record
2. Reads aggregated counters per fleet:
   - `frames_pulled` (Smart Puller counter)
   - `frames_post_motion_gate` (Smart Puller counter)
   - `detections_count` (Detection Core counter)
   - `alerts_fired` (Alert Dispatch counter)
3. Computes motion-gate drop rate, detection rate, alert rate
4. Returns status + counters to caller

**Canonical source:** Site Context Service is the authoritative run-state oracle for Paradigm E. It holds:
- Camera assignments (which Detection Core pod owns each camera)
- Live trackers (per-camera state, per pod)
- TTL + countdown
- Per-fleet counter aggregates (pulled from fleet pods, cached)

This is cleaner than C's approach (Job status field) or D's approach (NATS stream state).

---

## Tear-Down Cleanliness

At TTL expiry or manual cancellation:

1. **Site Context revokes the run's site record** — immediately stops serving it to pullers/cores

2. **Smart Puller fleet** — notices site revocation (via [[watch-entity|watch]] or next poll cycle):
   - Closes VMS tunnels for the run's cameras
   - Stops publishing to Redis Streams
   - Frees FDMD state (motion models)

3. **Detection Core drains tracker state** — per [[2026-04-16_graceful-failover-design]]:
   - Waits for in-flight frames from Smart Puller to finish (bounded by frame pull interval, typically <1s)
   - Snapshots tracker state to Redis with TTL (key: `tracker:run-{run_id}:{camera_id}`)
   - Drains observer event buffers (via `SlidingWindowBuffer.flush()`)
   - Exits within `terminationGracePeriodSeconds` (10-30s)

4. **Alert Dispatch drains SQS** — finishes consuming in-flight events from SNS/SQS within grace period

5. **StatefulSet ordinal cleanup** — ordinals added during the run scale down only if:
   - HPA detects reduced load post-drain
   - This is rare for bounded runs (unlikely enough that you may skip it and let the next run reuse hot pods)

**Orphaned Redis keys risk:** Tracker snapshot keys use a TTL; if the cleanup TTL is shorter than any other run's snapshot duration, keys may be deleted prematurely. **Mitigation:** set snapshot TTL to `run_ttl + 1h` (grace period) to ensure no collision across sequential runs.

---

## Cold-Start Latency

Realistic end-to-end latency from `POST /v1/runs` to first frame in Detection Core:

1. **Lambda registration** — translates spec, validates, registers with Site Context: 1-2s

2. **Smart Puller acquisition** — opens VMS tunnel, pulls first frame, detects motion: 2-5s (depends on camera FPS, VMS latency, FDMD warmup)

3. **Detection Core assignment** — most critical path:
   - **Best case:** existing Detection Core pod has spare camera-affinity slots. Assignment + routing: <1s
   - **Worst case:** no spare slots; HPA triggers StatefulSet ordinal increase:
     - HPA observes threshold breach: 15-30s
     - Karpenter/EKS provisions node (or reuses existing): 30-60s
     - StatefulSet schedules new ordinal: 10-30s
     - Total: 1-3 minutes
   - Realistic middle ground: 10-30s (some ordinals pre-allocated)

**Mitigation:** keep an "ephemeral runway" of 10-20% unused camera-affinity slots in Detection Core. Cost of one idle GPU pod (~$0.50/hr) is negligible against the pilot budget; latency reduction is material.

---

## Per-Run Cost

Proposal E's cost advantage (-20-40%) is **motion-gating-driven**. For an ephemeral run:

### Cost drivers
1. **Smart Puller CPU** — pulling + FDMD motion detection. Roughly proportional to raw frame count × FPS. Cost: $0.02-0.05/camera/24h (Spot-eligible; ~50% discount).

2. **Detection Core GPU** — inference on motion-gated frames only (20-40% of raw). Largest cost component. Cost: $0.20-0.40/camera/24h (On-Demand; not Spot-safe). This is where motion-gating saves the most.

3. **Site Context Service** — config/registry queries. Cost negligible ($0.001/camera/24h).

4. **Alert Dispatch** — SNS + SQS + alert-sender fire. Cost negligible ($0.001/camera/24h).

5. **Redis Streams** — motion-filtered frame transit (20-40% of raw). Cost: $0.01-0.02/camera/24h (ElastiCache on-demand).

6. **Tracker snapshot Redis** — one write per camera per inference cycle (~5-10 MB/camera/24h). Cost: $0.001-0.002/camera/24h.

### Total estimate
- **48-camera, 24h run:** $10-20 (Detection Core dominates)
- **Break-even vs C:** C is stateless (no tracker), so cheaper to scale horizontally; but E's motion gating saves 60-80% of downstream inference cost, which dominates.

### Bin-packing across runs
Cameras from multiple concurrent runs (e.g., 3 runs × 48 cameras) can share the same Detection Core pod via camera-affinity slots. No pod-per-run overhead. This is E's structural advantage for high-concurrency ephemeral scenarios.

---

## Failure Recovery (Within 24h)

E's failure recovery is strong but carries one caveat:

1. **Smart Puller dies** → another Smart Puller in the fleet picks up via Site Context's reassignment. Stateless; cold-start on replacement.
   - **Risk:** 10-30s gap in frames for the run's cameras
   - **Mitigation:** oversub Smart Puller fleet by 10-20% to absorb failures

2. **Detection Core pod dies** → StatefulSet controller reschedules the ordinal. Tracker state restores from Redis snapshot:
   - **RPO:** ≤1s (snapshot cadence matches pod preStop interval)
   - **RTO:** 30-60s (pod restart + cache warm-up)
   - **Risk:** frames lost during snapshot write + reschedule window
   - **Verified via:** [[2026-04-16_graceful-failover-design]] (proof-of-concept)

3. **Site Context dies** → HA standby takes over (leader election via etcd or Consul). Running Detection Core pods continue using last-known camera assignments.
   - **Gap:** new runs cannot be registered until Site Context recovers
   - **Mitigation:** Site Context SLA: 99.9% uptime (small service, easy to guarantee)

4. **Redis crash** → tracker snapshots fail; Detection Core workers continue on in-memory state. On next pod restart, snapshots are lost and state is cold-started.
   - **Risk:** burst of false negatives until trackers warm back up
   - **Mitigation:** Redis cluster mode with failover (3-node, multi-AZ); RTO <30s

5. **Alert Dispatch dies** → SQS FIFO buffers events. New Alert Dispatch pods resume from queue depth. No loss (SQS is durable).

**From caller's perspective:** brief gaps in alerts (30-60s during pod restart); no data loss if redundancy is configured.

---

## Implementation Cost

Prerequisite: **Proposal E's architecture must exist.** This is the main implementation burden. Ephemeral support adds moderate surface:

A. **Site Context Service enhancements**
   - Add "site with TTL" model (trivial: one extra field + background watchdog for revocation)
   - Expose counters via new `/metrics` or `/status` endpoint
   - Implementation: 1-2 engineer-weeks if Site Context already exists; 4-6 weeks from scratch

B. **Smart Puller integration**
   - Subscribe to Site Context's site-update notifications (pub-sub or polling)
   - Allocate puller from pool per VMS family
   - Implementation: 1-2 weeks (reuses existing puller code)

C. **Detection Core integration**
   - Camera-affinity assignment logic must accept dynamic sites mid-flight
   - Verify camera-group isolation (no cross-run state leakage)
   - Implementation: 1-2 weeks (routing logic already exists for persistent workloads)

D. **Lambda registration + status reader**
   - Translate `RunSpec.v1` to settings.json (per [[translation-layer]])
   - Register with Site Context, poll status, return to caller
   - Implementation: 2-3 weeks (heavy lifting is in translation-layer, shared across paradigms)

E. **Graceful shutdown + cleanup**
   - Verify tracker-snapshot cadence and Redis TTL logic (per [[2026-04-16_graceful-failover-design]])
   - Test TTL revocation pipeline end-to-end
   - Implementation: 1-2 weeks

**Total: 8-14 weeks assuming E's core architecture is already built.** If E must be built from scratch, add 14-20 weeks (the full E proposal timeline). This note assumes E exists as a deployed fleet; if it doesn't, the ephemeral pilot's timeline slips.

---

## Architectural Fit

E's internal complexity is high relative to the 24h bounded workload it's supporting. But the pilot's job is to ask: **does the complexity pay for itself?**

### Strengths E brings to ephemeral runs

1. **Motion-gating savings** — 60-80% frame drop at puller = 60-80% inference cost reduction. This is E's killer feature and scales to any fleet size.

2. **Stateful isolation** — Detection Core pods own camera-group state in-process. No shared database; local memory + Redis snapshots. Faster failover than C's shared-state model.

3. **Camera-affinity slot management** — efficient bin-packing of multiple runs across the same Detection Core pods. Amortizes setup overhead.

4. **Alert latency** — motion-gating + Alert Dispatch fleet = real-time alerts bounded by inference path, not frame queue depth.

### Weaknesses E carries for 24h workloads

1. **StatefulSet ordinal cadence** — HPA-driven scale-up takes 1-3 min. For a 24h run, setup latency is amortized; but for sub-1h runs, it's material. (Not in pilot scope; pilot is 6-24h by design.)

2. **On-Demand Detection Core cost floor** — Detection Core is not Spot-eligible. Cost floor higher than C. For small runs, this may be a regression vs stateless alternatives.

3. **Tracker-snapshot Redis overhead** — snapshot cadence + Redis I/O adds 5-10% latency per pod. For low-latency requirements (e.g., <50ms), this may be a dealbreaker.

4. **Most internal structure** — most moving parts, most failure modes, most operational surface. On-call load higher than C.

### What the pilot validates or invalidates

1. **Does motion-gating actually save 60-80%?** Measure across 48 cameras, 24h. If savings <50%, cost case weakens.

2. **Is StatefulSet ordinal scale-up fast enough?** Measure HPA response time. If >5 min, burst-load scenarios lose their advantage.

3. **Can tracker-snapshot recovery run cleanly?** Inject pod deaths; verify recovery completes within `terminationGracePeriodSeconds`. If failures > 5% loss, failover design is inadequate.

4. **Is camera-affinity slot allocation robust?** Run 10+ concurrent small runs (48 cameras each) and verify no slot conflicts or starvation.

---

## Rubric Scoring (Pilot-Specific)

Using the fleet redesign evaluation rubric ([[2026-04-16_evaluation-rubric]]) adapted for ephemeral runs:

| Dimension | Score | Justification |
|-----------|------:|---|
| **Scalability (35%)** | 7 | Motion-gating + affinity slot bin-packing scale well for multi-run concurrency. But cold-start ordinal scale (1-3 min) is a sub-hour run penalty. |
| **Cost (20%)** | 8 | Motion-gating saves 60-80% inference cost. On-Demand Detection Core is a cost floor, but amortized across 24h runs. Validate via PoC benchmark. |
| **Failure isolation (15%)** | 8 | Camera-group blast radius; alerts isolated; tracker recovery tested. Weakest point is Site Context single-pod risk. |
| **Operational simplicity (15%)** | 6 | 4 fleet types + Redis + Site Context (3+ components). Distributed tracing optional but recommended. Medium ops burden. |
| **Migration risk (10%)** | 7 | E must exist first (14-20 weeks). Ephemeral support is incremental (8-14 weeks atop E). Rollout can be opt-in feature. |
| **Failover quality (5%)** | 8 | Tracker snapshot design proven; RTO 30-60s acceptable for 24h workload. Redis recovery is weak point. |

**Weighted: `(7×0.35) + (8×0.20) + (8×0.15) + (6×0.15) + (7×0.10) + (8×0.05) = 7.35 / 10`**

E scores slightly lower for ephemeral than its persistent-workload score (8.05) due to cold-start ordinal latency. But motion-gating's cost advantage and stateful isolation lift it above C/D for bounded, multi-run scenarios.

---

## E-Specific Risks

1. **StatefulSet partition cadence** — `updateStrategy.rollingUpdate.partition` enables staged rollouts, but ordinal-add latency is untested at scale. Requires production measurement during pilot.

2. **Camera-affinity slot capacity** — under what load does a slot become full? If pods saturate faster than HPA scales, requests may back up. Define SLO: e.g., "p99 Detection Core wait time <10s".

3. **Site Context HA** — single point of failure if not replicated. Pilot assumes Site Context is run as a 3-pod Deployment with leader election. Verify failover speed (<5s).

4. **Tracker-snapshot Redis cleanup** — TTL boundaries may overlap; stale keys may linger post-run. Test cleanup discipline with extended TTL windows.

5. **Motion-gating at low FPS** — if cameras are sub-1 FPS, FDMD motion models may not train fast enough. Validate FDMD quality per camera family during PoC.

---

## Open Questions & Follow-ups

1. **HPA ordinal scale-up latency** — what's the realistic p95 ordinal-provision time on production EKS cluster under load? (Benchmark during pilot.)

2. **Camera-affinity slot capacity per pod** — under what GPU/memory load does a slot become full? (Measure via PoC [[inference-pool|inference pool]] saturation curve.)

3. **Site Context scalability** — what's the max QPS it can handle? If 10+ concurrent ephemeral runs register simultaneously, does Site Context's assignment logic stay <1s? (Load test.)

4. **Tracker-snapshot Redis overhead** — what's the per-frame latency tax? Measure e2e latency with/without snapshots. (Benchmark during pilot.)

5. **Motion-gating quality per VMS family** — FDMD parameters are family-tuned. Do ephemeral runs inherit the family's FDMD config, or do they need site-level tuning? (Verify in PoC setup.)

6. **SQS FIFO queue strategy for ephemeral runs** — one queue per run, or one per camera-group? Impacts Alert Dispatch HPA scaling and message-ordering semantics. (Design before Lambda implementation.)

---

## Cross-References

- **Parent proposal:** [[2026-04-16_proposal-e-hybrid-sidecar|Proposal E — Hybrid Sidecar]]
- **Ephemeral pilot framing:** [[_overview|Ephemeral Run Pilot Overview]], [[api-contract|API Contract]], [[translation-layer|Translation Layer]]
- **Sibling paradigms:** [[paradigm-c|Paradigm C (Camera-Worker)]], [[paradigm-d|Paradigm D (Event-Driven)]]
- **Shared design docs:** [[2026-04-16_graceful-failover-design|Graceful Failover Design]], [[tracker-snapshot-schema|Tracker Snapshot Schema]], [[2026-04-16_frame-transport-comparison|Frame Transport Comparison]]
- **K8s design:** [[k8s-controller-selection-guide|Controller Selection]], [[k8s-placement-primitives|Placement Primitives]], [[pod-termination-sequence|Pod Termination Sequence]]
- **Evaluation:** [[2026-04-16_evaluation-rubric|Evaluation Rubric]]

---

## Summary

Paradigm E for ephemeral runs is **moderate-complexity but high-reward**: motion-gating drives 60-80% cost savings, and camera-affinity slot bin-packing enables multi-run concurrency without per-run infrastructure overhead. The main risk is StatefulSet ordinal cold-start latency (1-3 min) — acceptable for 24h runs but a penalty if E must also serve sub-1h ephemeral requests.

The pilot must validate that motion-gating savings materialize at small scale, that tracker-snapshot recovery is bulletproof, and that Site Context scales to 10+ concurrent runs. If all three check out, E becomes a compelling choice even for bounded workloads; if any fail, C's simpler stateless model may prove more cost-effective.
