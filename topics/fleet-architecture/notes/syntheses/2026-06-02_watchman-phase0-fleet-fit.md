---
title: "Watchman Phase 0 — Fleet-Architecture Fit & Phased Build Plan"
author: kb-bot
created: 2026-06-02
updated: 2026-06-02
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, phase-0, puller-fleet, bin-packing, redis-streams, watch-management-service, greenfield, planning]
related:
  - "[[topics/fleet-architecture/_summary]]"
  - "[[topics/watchman/_summary]]"
  - "[[2026-06-01_adr-watchman-mvp-slim-connector]]"
  - "[[2026-06-01_v10-cloud-platform-vs-fleet-proposals]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-29_watchman-judge-backend-io-contract]]"
  - "[[2026-04-22_fleet-proposal-rescore-with-delta]]"
  - "[[2026-06-02_frontend-sketch-ui]]"
---

# Watchman Phase 0 — Fleet-Architecture Fit & Phased Build Plan

> Planning-session output, 2026-06-02. Answers the question: **which fleet-architecture proposal best fits a clean, greenfield Phase-0 Watchman product, and which should it be scaffolded to grow into?** Companion to the cataloged [[2026-06-02_frontend-sketch-ui|frontend sketch]].

## Phase 0 — the stated shape

A **full fleet** (independently-scaling K8s deployments), scoped to the **[[watchman-repo|Watchman]]** product only, built **greenfield** with no obligation to today's [[vms-connector|connector]] (it may stand alone as a product forever, or absorb full connector functionality later). Constraints (decided this session):

- **RTSP-only** ingest.
- **Per-camera runs; no `site` abstraction** — Watch ≈ `(camera, product)` for Phase 0.
- **Simple scheduling**, owned by a real (if minimal) Watch Management Service — *not* a throwaway stub.
- **Uniform, bin-packed puller pods** — same pod size across the whole fleet (k8s-ops simplicity is the explicit driver). `cameras_per_puller` is the one knob.
- **[[redis-streams|Redis Streams]]** for the puller→pipeline frame hop (decided over Kinesis — matches A/B/E + the [[2026-06-01_cloud-video-analytics-platform-v10|v10]] frame-bus; TTL auto-expiry, consumer-group FIFO, cheaper at fleet scale).
- **Motion gating present but default-OFF** (per-camera toggle, pluggable — matches the [[2026-06-01_adr-watchman-mvp-slim-connector|Slim Connector ADR]]).
- **Trimmed pipeline** (confidence + zone-polygon filter only — no window / billing / blacklist) emitting alerts to the rest of Watchman.
- **Low cost.**

### Topology

```
[ Watch Management Service ]  fleet-singleton reconciler (the FleetCoordinator)
   owns Watch lifecycle, camera→puller bin-pack assignment, arm/disarm enable-gate
        │ desired-state (which cameras armed, which puller owns them)
        ▼
[ Puller fleet ]      uniform pods, N RTSP cameras bin-packed each, motion toggle (off)
        │  Redis Streams  (one stream per camera; TTL; consumer-group FIFO)
        ▼
[ Detection fleet ]   STATELESS + uniform: inference (actuate-inference-client)
        │              + confidence/zone filter. NO window/tracker state.
        ▼
[ Alert-dispatch fleet ]  WatchmanSink → SQS  (Judge I/O contract schema)
        ▼
   Watchman Judge / Assessment loop  → SNS fan-out → operator UI / audit / Immix
```

## Fit analysis — proposals against *these* constraints

Scored against Phase-0's actual requirements, not the original ephemeral-run rubric.

| Proposal | Separate puller fleet | Per-camera / site-agnostic | Uniform bin-packed pods | Low cost | Verdict |
|---|---|---|---|---|---|
| **A — Minimal Split** | ✅ puller+alert split | ❌ pipeline stays **per-site monolith** | partial | +10–15% | Transport *shape* fits; cardinality is exactly what we're shedding. Fallback (rescore 4.45). |
| **C — Camera-Worker** | ❌ worker = puller **+** inference in one pod | ✅ cameras bin-packed regardless of site | ✅ (its thesis) | ✅ −15–30% | Right *packing & cardinality*, wrong *split*. Contradicts the separate-puller + Redis requirement. |
| **E — Hybrid Sidecar** | ✅ puller → core → alert dispatch | ◑ camera-*group* affinity | ◑ pullers family-specialized (6–8 VMS) | ✅ −20–40% | **The drawn topology.** Top rescore (7.85). Simplifies cleanly under RTSP-only/per-camera. |
| **[[2026-06-01_cloud-video-analytics-platform-v10\|v10 platform]]** | ✅ ingest vs detector pools | ✅ per-(camera,product) | ✅ | ✅ at scale | The **grow-into target**, not the Phase-0 build. |

## Recommendation

**Phase 0 = "E's split, C's packing."** Build **Proposal E's three-fleet topology** (smart-puller → Redis → trimmed detection → alert-dispatch), borrowing the two **C** properties that Phase-0's constraints unlock:

1. **C's uniform bin-packing for the puller tier.** E normally specializes pullers into 6–8 VMS families; RTSP-only means **one family → genuinely uniform pods** — exactly the "same pod size across the whole fleet" requirement. The WMS bin-packs `N` cameras per puller.
2. **C's site-agnostic, per-camera assignment.** Dropping `site` lets cameras pack onto any pod with no affinity, removing E's camera-group affinity complexity.

**Phase-0 simplification that makes both fleets uniform.** Because the trimmed pipeline drops windowing/tracking/observers, the **detection fleet is stateless** — it consumes a Redis consumer-group and scales on lag, no camera affinity, no StatefulSet. So **both** puller and detection fleets are uniform, horizontally-scalable Deployments. The statefulness (tracker/observer/window) is precisely what gets *re-added* when growing into E proper — it is not removed, it is *deferred*.

**Why not the others, concisely:**
- **Not A** — A's defining choice (keep the pipeline a per-site monolith) is the exact thing being shed. Only A's puller→Redis→pipeline *hop* survives, and E already has it. A stays a paper fallback.
- **Not pure C** — cheapest and matches "ignore site / per-camera / uniform pods," but it **collapses pull+inference into one pod**, killing the separate uniform puller fleet and the Redis hop. We take C's *packing discipline*, not its *monolithic worker*.
- **E is already the documented growth target** of the [[2026-06-01_adr-watchman-mvp-slim-connector|Slim Connector ADR]] — the `WatchmanSink` is named there as "the extraction point in Proposal A *and* Proposal E." Phase 0 makes that extraction real on day one.

**One-line answer:** best fit for Phase 0 is **E (simplified)**; the plan to scaffold *into* is **[[2026-06-01_cloud-video-analytics-platform-v10|v10]], reached through E** — with **C** contributing bin-packing discipline for the uniform puller fleet, not its architecture.

## The grow-into path is monotonic (nothing is thrown away)

```
Phase 0  (E-slim: uniform RTSP pullers + Redis + STATELESS trimmed detection + alert dispatch + WMS)
   │  + re-add VMS puller families, motion-gate tuning, stateful detection core (tracker/observer/window), camera-group affinity
   ▼
Proposal E proper  (full hybrid sidecar, multi-protocol)
   │  + detector-router (per-product fanout), two-stage scheduler-service,
   │    site-state-service, multi-tenancy, ClickHouse observability split
   ▼
v10 Cloud Platform  ("move the whole system onto this", ~100k cameras)
```

**Three seams committed in Phase 0 make this free:**
- **Redis Streams** = v10's frame-bus primitive (same shard-by-camera, TTL, lo-res JPEG payload).
- **`WatchmanSink` interface** = A/E alert-extraction point *and* v10's event-bus seam. `HttpWatchmanSink` (MVP) → SQS Judge contract → `KafkaWatchmanSink` (v10 inter-agent bus).
- **WMS = FleetCoordinator** = C's Assignment Controller ∪ E's Site Context Service (per [[2026-05-28_watch-management-service-design]], the 15-RPC [[2026-04-22_fleet-coordinator-api-sketch|FleetCoordinator]] covers C+E+B′ with zero gaps). Grows into v10's two-stage scheduler-service.

**Deferred cleanly (not designed around):** the full `Watch`/`CalendarSet` model, per-product detector-routing, multi-protocol pullers, stateful detection, multi-tenancy.

### Greenfield kills the migration tax

The [[2026-05-28_watch-management-service-design|WMS design]] carries a 5-phase Django-Q→manager migration and 10 legacy constraints (ScheduleV2, `connector_deployer` create/delete arm, Redis `MotionStatus` debounce, etc.). **None of that applies to a greenfield Watchman fleet** — the WMS is built directly in its target form: a **K8s-native fleet-singleton reconciler** with arm/disarm via `replicas`/enable-gate (constraint T9 by construction, not by migration), observed-state-is-truth reconcile loop (T10/T16), and a clean per-camera Watch model. This is a major argument for building Phase 0 greenfield: the manager is born in the shape every proposal eventually wants.

## Emit contract — what the trimmed pipeline sends to "the rest of Watchman"

Per [[2026-05-29_watchman-judge-backend-io-contract]], the alert-dispatch fleet publishes metadata-only messages (frames stay in S3) to SQS, consumed by the Watchman Judge/Assessment loop, which fans out via SNS to operator UI / audit / Immix. Phase-0 `WatchmanSink` emits the input schema:

`alert_id` · `camera_id` · `alert_ts` (ISO-8601 UTC) · **`product`** (not `yolo_class`) · `confidence` · `bbox` (pin `xywh` vs `xyxy` against `actuate-pipeline-objects`) · `s3_prefix` · `schema_version` · **`watch_id`** · **`run_id`**.

Arming enforcement is upstream: disarmed Watches emit no alerts (WMS gates them), so the Judge needs no `armed` field. Transport is **SQS for Phase 0**; the PRD's Kafka inter-agent bus is the v10-era swap behind the same sink interface (open platform decision, not a Phase-0 blocker).

## Phased build plan

New **standalone repo** (greenfield; `uv`-managed; depends on `actuate-inference-client`, puller/sender library patterns; free of `SiteManager`/Factory/billing/window/blacklist).

| Milestone | Deliverable | Proves |
|---|---|---|
| **M0 — Repo + skeleton** | New repo, `pyproject.toml` (uv), CI, three base images (uniform puller / stateless detection / WMS), library deps wired. | Build & deploy substrate. |
| **M1 — Single-camera vertical slice** | 1 puller (1 RTSP cam) → Redis → 1 detection pod → inference → `HttpWatchmanSink` → mock Judge (stdout). | The end-to-end seam (graduates the "CSV-in/stdout-out POC" of the Judge contract). |
| **M2 — Bin-packed puller fleet** | WMS bin-packs `N` cameras across uniform puller pods; `cameras_per_puller` knob; HPA on puller count; one Redis stream per camera. | Uniform-pod fleet + the core ops-simplicity claim. |
| **M3 — Trimmed detection fleet + real emit** | Confidence + zone-polygon filter; real Judge-contract schema to SQS; stand up SQS + stub Judge consumer; stateless detection scaling on consumer-group lag. | The "alerts for the rest of Watchman" boundary. |
| **M4 — Watch Management Service** | Fleet-singleton reconciler: Watch lifecycle, arm/disarm enable-gate, observed-state reconcile loop; simple per-camera schedule growing toward `calendar_set`; motion toggle plumbed (default OFF). | The control plane in target FleetCoordinator form. |
| **M5 — Observability + hardening + cost** | NR/ClickHouse audit, `run_id`/`watch_id` propagation, graceful teardown, PDB + topology-spread for uniform pods, **measured cost/frames/inference** to feed the §5 PoC pick. | Production-readiness + the low-cost validation with real numbers. |

## Open decisions (carry into build)

1. **Repo name** — e.g. `watchman-fleet` vs `watchman-connector`. (Slim Connector ADR also left repo location open.)
2. **Detection cardinality** — confirmed *stateless + bin-packed* for Phase 0 (above); revisit when window/tracker state returns under E.
3. **WMS state store** — Postgres vs Redis vs manager-private; greenfield lets us pick clean (no admin-Postgres legacy).
4. **Schedule model depth in Phase 0** — minimal per-camera arm/disarm now vs partial `calendar_set` from the start (user leans toward "more than a stub").
5. **`bbox` orientation** (`xywh` vs `xyxy`) + `schema_version` mismatch policy — settle against `actuate-pipeline-objects`.
6. **ClickHouse in Phase 0** or log-stub until v10-era.
7. **SQS now / Kafka later** behind `WatchmanSink` — confirmed direction; track Kafka as the v10 platform swap.

## Cross-references

- [[2026-06-02_frontend-sketch-ui]] — the cataloged look-and-feel prototype this plans the backend for
- [[2026-06-01_adr-watchman-mvp-slim-connector]] — the slim ingest entrypoint this generalizes into a full fleet
- [[2026-06-01_v10-cloud-platform-vs-fleet-proposals]] / [[2026-06-01_cloud-video-analytics-platform-v10]] — the grow-into target
- [[2026-05-28_watch-management-service-design]] — WMS/FleetCoordinator baseline (greenfield skips its migration phases)
- [[2026-05-29_watchman-judge-backend-io-contract]] — the alert emit contract
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — E 7.85 > C 7.40 rescore
- [[2026-04-16_proposal-e-hybrid-sidecar]], [[2026-04-16_proposal-c-camera-worker]], [[2026-04-16_proposal-a-minimal-split]]
