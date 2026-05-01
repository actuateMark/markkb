---
title: "Fleet-Coordinator API Sketch — Unification Viability Review"
type: synthesis
topic: fleet-architecture
tags: [fleet-coordinator, api-sketch, grpc, design-review, unification, synthesizer-pilot-5]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-22.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Fleet-Coordinator API Sketch — Unification Viability Review

## Motivation

`topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md` asks whether C's Assignment Controller, E's Site Context Service, and B-prime's (now closed) Blob Coordinator collapse into one primitive — a "fleet-coordinator" service — or whether the responsibilities are distinct enough to justify separate services. User decision 2026-04-22: **run this design review *before* PoC kickoff**, since the coordinator is a shared primitive in both PoC candidates (E and C) and building it twice is the waste the question exists to prevent.

Success criterion per the concept note: minimum-viable API ≤20 RPCs with consistent noun-verb structure + coherent resource model. If the API sprawls to 40+ RPCs across unrelated domains → unification is a distributed monolith and should be rejected. This sketch delivers a concrete proposal-level API and applies that test.

## Responsibility inventory

Union of responsibilities across the three coordinators:

**From C's Assignment Controller** (`topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md`):
- Assign camera → worker (bin-pack-driven; lease-based)
- Renew lease (liveness heartbeat)
- Release camera (drain-on-termination)
- Watch assignment changes (workers subscribe to own-camera set)
- Split-brain resolution (lease TTL + fencing tokens)
- Rolling-update drain (reassign cameras before pod terminates)

**From E's Site Context Service** (`topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md`):
- Assign camera-group → core-pod (StatefulSet ordinal-aware)
- Centralized schedule eval (fixes ENG-96: armed-state per schedule, time-windowed)
- Watch schedule changes (alert-dispatchers subscribe)
- Config cache (hot-path admin-api reads consolidated; camera registry)

**From B-prime's Blob Coordinator** (`topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md`, CLOSED but structurally informative):
- Per-window blob lease (which motion pod owns this window's accumulating bytes)
- Window-close outcome notification (promote-to-S3 or drop)
- Blob cleanup on drop

**Organizing into four natural categories:**

1. **Identifier-to-pod assignment** — camera / camera-group / window-blob → owner pod, TTL-leased (C, E, B-prime all need this; same shape, different resource types)
2. **Schedule + armed-state** — schedule_id → armed windows (E only; hot-path read + change watch)
3. **Config cache** — entity_type + entity_id → snapshot (E primarily; C tangentially for worker-image version info)
4. **Outcome-driven lifecycle events** — window-close outcome, camera-moved, schedule-changed (B-prime for blob; E for schedule push)

The encouraging shape: categories 1 and 4 share a lease/lifecycle pattern; categories 2 and 3 share a cache/subscribe pattern. The **underlying primitives are narrower than the use-cases suggest.**

## Resource model

Five nouns; each with fields, lifecycle states, invariants:

**`Assignment`** — resource-to-owner mapping
- Fields: `assignment_id` (UUID), `resource_type` (CAMERA | CAMERA_GROUP | WINDOW_BLOB), `resource_id` (string), `owner_pod` (k8s pod-name), `lease_expires_at` (timestamp), `state` (ASSIGNING | ASSIGNED | DRAINING | RELEASED), `generation` (monotonic int for fencing)
- Invariant: at most one ASSIGNED per `resource_id`; state transitions monotonic; `generation` strictly increasing across leases of the same resource

**`Lease`** — extensible time-bound ownership token; embedded in `Assignment`
- Fields: `holder_pod`, `expires_at`, `generation`
- Invariant: renewal extends `expires_at`; generation incremented only on transfer

**`Schedule`** — armed-state for E's time-window evaluation
- Fields: `schedule_id`, `camera_id`, `armed_windows` (list of {day_of_week, start, end, timezone}), `version` (monotonic int), `admin_pk` (upstream admin-api reference)
- Invariant: version strictly increasing; consumers filter by version to detect updates

**`ConfigSnapshot`** — hot-path admin-api cache
- Fields: `snapshot_id`, `entity_type` (SITE | CAMERA | SCHEDULE | USER), `entity_id`, `data` (bytes, JSON-encoded upstream payload), `fetched_at`, `ttl`
- Invariant: snapshots may be stale but never malformed; Watch stream pushes invalidations on upstream change

**`WindowOutcome`** — conditional-promotion signal (unified service absorbs B-prime's role)
- Fields: `window_id`, `outcome` (PROMOTE | DROP), `blob_location` (pod+path for PROMOTE), `reported_by_pod`, `reported_at`
- Invariant: one final outcome per window_id; outcome observers see at-least-once delivery

## API sketch (proto3-style pseudo-schema)

Grouped by category. **Target: ≤20 RPCs. Actual: 15 RPCs.**

```proto
service FleetCoordinator {

  // ========= Assignments (5 RPCs) =========
  // Covers C + E + B-prime identifier-to-pod mapping.

  rpc Assign(AssignRequest) returns (Assignment);
  //   AssignRequest { resource_type, resource_id, candidate_pods (optional), lease_duration }
  //   Server picks an owner via bin-packing heuristic + liveness check.

  rpc Release(ReleaseRequest) returns (Ack);
  //   ReleaseRequest { assignment_id, generation }
  //   Voluntary release, typically during pod drain.

  rpc RenewLease(RenewLeaseRequest) returns (Lease);
  //   RenewLeaseRequest { assignment_id, generation }
  //   Heartbeat; extends lease_expires_at. 409 if generation mismatch (split-brain).

  rpc DrainOwner(DrainOwnerRequest) returns (stream DrainProgress);
  //   DrainOwnerRequest { owner_pod, grace_period }
  //   Streams reassignment events as each resource moves off the draining pod.

  rpc WatchAssignments(WatchRequest) returns (stream AssignmentEvent);
  //   WatchRequest { owner_pod_filter (optional), resource_type_filter (optional), resume_from_version (optional) }
  //   Long-lived stream. Workers subscribe to own-pod events to discover new camera/group/window assignments.

  // ========= Schedules (3 RPCs) =========
  // E's schedule-eval responsibility.

  rpc GetScheduleState(GetScheduleRequest) returns (ScheduleState);
  //   GetScheduleRequest { schedule_id, at_timestamp (optional, defaults now) }
  //   Evaluated armed-state; ENG-96 fix lives here.

  rpc PutSchedule(PutScheduleRequest) returns (Ack);
  //   PutScheduleRequest { schedule }
  //   Upstream (admin-api writer) pushes updates. Coordinator rebuilds eval index.

  rpc WatchSchedule(WatchRequest) returns (stream ScheduleEvent);
  //   Camera-group pods subscribe to their schedule_ids for armed-state transitions.

  // ========= Config cache (3 RPCs) =========
  // E's hot-path admin-api read consolidation; optional use by C for worker-image pinning.

  rpc GetConfig(GetConfigRequest) returns (ConfigSnapshot);
  //   May return from local cache or trigger upstream fetch.

  rpc InvalidateConfig(InvalidateConfigRequest) returns (Ack);
  //   admin-api writer pushes invalidations; forces next GetConfig to refetch.

  rpc WatchConfig(WatchRequest) returns (stream ConfigEvent);
  //   Downstream subscribers observe config updates.

  // ========= Window outcomes (2 RPCs, used if unified absorbs B-prime's role) =========

  rpc NotifyWindowOutcome(WindowOutcomeRequest) returns (Ack);
  //   Observer-side pod signals PROMOTE or DROP on window close.
  //   Motion pod owning the blob reacts to its own subscription.

  rpc GetWindowOwner(GetWindowOwnerRequest) returns (Assignment);
  //   Cheap lookup for "who holds this window's blob?" — convenience over
  //   Watching assignments with resource_type=WINDOW_BLOB.

  // ========= Health + admin (2 RPCs) =========

  rpc Health(Empty) returns (HealthStatus);
  //   Liveness/readiness + current leader ID + replica count.

  rpc ListAssignments(ListAssignmentsRequest) returns (stream Assignment);
  //   Admin introspection / operator debugging; paginated over streaming.
}
```

**Count: 15 RPCs.** Within target. Five categories: **Assignments (5) | Schedules (3) | Config (3) | Outcomes (2) | Admin (2).**

Noun-verb consistency check: `Assign / Release / RenewLease / DrainOwner / WatchAssignments` share the Assignment noun. `GetScheduleState / PutSchedule / WatchSchedule` share Schedule. `GetConfig / InvalidateConfig / WatchConfig` share Config. `NotifyWindowOutcome / GetWindowOwner` pair on the outcome event. `Health / ListAssignments` are admin-scoped. **Structure is consistent; no RPC does multiple unrelated jobs.**

## Per-proposal coverage check

**C — Camera-Worker Fleet.** Uses: `Assign(CAMERA)`, `RenewLease`, `Release`, `WatchAssignments(owner_pod=me, resource_type=CAMERA)`, `DrainOwner(me)` on rolling update. Five of the 5 assignment RPCs. No gaps. ✅

**E — Hybrid Sidecar.** Uses: `Assign(CAMERA_GROUP)`, `RenewLease`, `Release`, `WatchAssignments(owner_pod=me)`, `GetScheduleState` on hot path, `WatchSchedule` for armed-state transitions, `GetConfig` for camera registry, `WatchConfig` for updates. Nine RPCs; all the shape E's Site Context Service needs. No gaps. ✅

**B-prime — Blob Coordinator (closed, for pattern-reference only).** Uses: `Assign(WINDOW_BLOB)`, `NotifyWindowOutcome`, `GetWindowOwner`, `WatchAssignments(resource_type=WINDOW_BLOB)`. Four RPCs. No gaps. ✅ (Parenthetical — if B-prime were reopened, the API doesn't need extension.)

**Unused by any current proposal:** zero. Every RPC earns its place against at least one use-case.

## Deployment shape

**3-replica StatefulSet** with etcd-raft library for consensus (kv-store-agnostic; could also use embedded BoltDB). Placement via `topology.kubernetes.io/zone` anti-affinity — one replica per AZ across the 3-AZ cluster. `pod-disruption-budgets` with `maxUnavailable: 1` to preserve quorum during node drains. See `[[k8s-controller-selection-guide]]` and `[[k8s-placement-primitives]]`.

**Client connection model:** gRPC streams need HTTP/2 sticky routing. ALB with gRPC target-group type; clients pick a replica and stick for stream lifetime; on leader change, streams drop and clients reconnect (acceptable — sub-second reconnect).

**State backend:** etcd-raft internal to the coordinator pods; no external etcd dependency. State footprint is small (~10K cameras × ~200 bytes = 2 MB working set; schedules + config add ~10 MB total). Easily fits in RAM.

**Scaling:** single writer (leader), 3 followers. Read-scaling via follower reads if needed post-PoC; v1 reads-through-leader simplifies consistency.

## Failure modes

- **Leader crash** → raft re-election (~1–3 s), clients see stream disconnect, reconnect picks up new leader, resume from `resume_from_version`. Assignments whose leases expired during outage get reassigned as normal. RPO = 0 (committed writes survive), RTO = reconnect latency.
- **Network partition** → minority side refuses writes; majority continues. Clients in minority zone fail-open (use last-known assignments) or fail-closed (halt) — configurable per client.
- **Lease expiry under load** → coordinator refuses renewals past grace period; assignment reverts to `RELEASED`; next `Assign` re-picks owner. Fencing token (`generation`) prevents zombie writes from old owner.
- **Config cache staleness** → short TTL + Watch-driven invalidations. If admin-api writer crashes before sending invalidation, cache serves stale data for up to TTL. Acceptable for schedule/config updates at human cadence.
- **Window-outcome lost before NotifyWindowOutcome** → at-least-once semantics on the Watch stream; motion pod treats outcome as idempotent (PROMOTE twice = same promoted clip; DROP twice = no-op).

## Verdict: coherent, unification viable

**15 RPCs, 5 resource types, consistent noun-verb structure, clean per-proposal coverage.** The API passes the ≤20-RPC test and has no single RPC doing unrelated work. The resource model fits on one diagram.

**Recommendation: apply +1 to C and E on operational-simplicity axis in the re-score** (already captured conditionally in `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md` Addendum → "Conditional scenario").

**Not a distributed monolith.** The four categories share underlying primitives (lease-based assignment, version-driven watch) without cross-coupling; removing the outcome category (if B-prime stays closed) drops 2 RPCs to 13. Removing the config cache (if we decide admin-api direct reads are fine) drops another 3 to 10. The design is modular at the API level, not just at the implementation level.

**Caveats that could break unification:**
- If multi-region / cross-cluster coordination becomes a requirement, the "single etcd-raft group" assumption falls apart; unification remains viable but deployment complexity goes up materially.
- If schedule-eval logic grows (e.g., site-level holidays, override schedules, multi-tenancy nesting) the Schedule category could spawn 5+ more RPCs and justify its own service.
- If window-outcome cardinality is too high for the coordinator (e.g., >10k events/sec fleet-wide), it may need its own event bus and the 2 RPCs become an anti-pattern.

## Implementation estimate

Go + gRPC + `go.etcd.io/raft/v3`. Ballpark:
- Coordinator service: ~2500 LoC (5 RPCs × ~200 LoC + raft glue + k8s leader-elect + Dockerfile + Helm chart)
- Per-proposal client libraries: ~1500 LoC total (SDK wrapping Watch + reconnect + generation checking)
- Tests: ~3000 LoC (failure injection is the bulk)
- **Est: 4–6 dev-weeks for v1.** Feasible before PoC kickoff if started now.

## Open questions

1. **Config cache scope** — which admin-api reads belong in the coordinator cache vs stay direct? Start narrow (camera registry + schedule only); expand only when a specific hot-path emerges.
2. **Schedule eval state** — armed-state evaluation is stateful (timezone rules, overrides). Does it live fully in the coordinator, or does the coordinator cache the output of an eval library that the admin-api also runs? Latter is safer (single source of truth), former is faster (no cross-service hop).
3. **Multi-region coordination** — if prod ever goes multi-region, is this a per-region coordinator with region-scoped resource_ids, or a single global coordinator? Decide before building, because the raft-group scope is baked into the deployment shape.
4. **Window-outcome cardinality budget** — motion pods emit one outcome per window close; fleet-wide rate is ~5.3M/day (per 2026-04-22 NR query). That's ~60/sec average. Coordinator can absorb that easily via raft, but burst rate needs measuring in PoC.
5. **Audit-log integration** — assignments, schedule changes, config invalidations should emit structured events for SOC2. Coordinator emits to a separate stream (Kafka / SNS / stdout-to-CloudWatch); decide where before v1 ships.
6. **B-prime reopen scenario** — if E's PoC fails on motion-drop-rate or detection-core ops load, B-prime becomes a re-examination candidate (per B-prime's CLOSEOUT banner). The coordinator handles B-prime's needs without modification, which is a side benefit of unification — B-prime reopen costs no additional coordinator work.

## Related

- `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md` — the framing question this sketch answers
- `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-proposal-rescore-with-delta.md` — Addendum → "Conditional scenario" row shows C/E with +0.15 each under affirmative verdict (applied now that this sketch is coherent)
- `topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md` — C's Assignment Controller spec
- `topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md` — E's Site Context Service spec
- `topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md` — B-prime's Blob Coordinator spec (CLOSED)
- `topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md` — StatefulSet vs Deployment choice
- `topics/fleet-architecture/notes/concepts/k8s-placement-primitives.md` — per-AZ placement
- `topics/personal-notes/notes/entities/mark-todos.md` §5 — fleet-architecture workstream + tracked follow-ups
