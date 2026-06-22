---
title: "Pod Termination Sequence & Stateful Checkpoint Handshake"
type: concept
topic: fleet-architecture
tags: [kubernetes, graceful-shutdown, sigterm, prestop, checkpoint, stateful, tracker-snapshot]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md
  - topics/fleet-architecture/notes/concepts/k8s-placement-primitives.md
  - topics/fleet-architecture/notes/concepts/tracker-snapshot-schema.md
  - topics/fleet-architecture/notes/concepts/vpa-bimodal-workload-limitation.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_graceful-failover-design.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/_overview.md
incoming_updated: 2026-05-27
---

# Pod Termination Sequence & Stateful Checkpoint Handshake

The exact K8s pod-termination timing, the endpoint-removal race, and the preStop pattern for stateful-worker checkpoint-before-death. This is the concrete K8s mechanism that makes any "snapshot-on-shutdown" tracker-resume design implementable.

Primary source: [[graceful-pod-termination-zero-downtime]].

## Exact Termination Sequence

1. **Endpoint removal** (async, 0-100 ms) — EndpointSlice controller removes pod IP from the Service's endpoint list. **Not** synchronous with SIGTERM — this is the root cause of the in-flight-traffic-loss race.
2. **preStop hook** (if defined) — runs before SIGTERM. Budget comes from `terminationGracePeriodSeconds`.
3. **SIGTERM** — sent after preStop completes (or immediately if no preStop).
4. **Grace period expires → SIGKILL** — whatever remains of `terminationGracePeriodSeconds`.

**Key formula:**
```
terminationGracePeriodSeconds = preStop_duration + app_shutdown_budget + 5-10s buffer
```

Default 30 s is almost always too short for stateful workers. `120 s` is a reasonable starting point (60s drain + 45s checkpoint budget + 15s buffer).

## The Endpoint-Removal Race

Because endpoint removal is async with SIGTERM, a request can arrive after SIGTERM is in flight. The documented fix is a preStop `sleep 5-15s` that gives the load balancer time to drain before the app processes shutdown. **This is not a hack — it is the official pattern.**

## Stateful Handoff Pattern (Tracker Snapshot)

For workers that must checkpoint tracker state before death:

1. **preStop**: flip readiness probe to failing → stops new traffic arriving.
2. **preStop**: `sleep` for LB drain window (~10-15 s).
3. **preStop exits → SIGTERM**: app flushes in-flight frames, writes snapshot to Redis/DynamoDB.
4. **App exits**: kubelet confirms exit before `terminationGracePeriodSeconds` elapses.

**Failure mode — SIGKILL eats the snapshot:** if the checkpoint write exceeds the remaining grace period, SIGKILL fires and the snapshot is lost. This is exactly the tracker-resume gap [[2026-04-16_graceful-failover-design]] is trying to eliminate. `terminationGracePeriodSeconds` must be sized for worst-case snapshot write time (Redis AOF flush latency + network).

## The 1-Second Snapshot Cadence Constraint

[[tracker-snapshot-schema]] proposes a 1-second snapshot cadence. The SIGKILL deadline is the hard bound on this: if snapshot write latency P99 approaches `terminationGracePeriodSeconds - preStop_sleep`, cadence must widen (because worst-case pre-kill snapshot delta can never exceed grace period minus preStop budget).

**Action:** benchmark Redis AOF flush P99 under production-like camera load before finalizing snapshot cadence vs grace-period sizing.

## Production Configuration

- `maxUnavailable: 0` + `maxSurge: 1` in rolling-update strategy for stateless fleets → zero-downtime deploys.
- `terminationGracePeriodSeconds: 120` for stateful fleet pods; measure P99 snapshot latency and bump if needed.
- K8s 1.27+ transitions deleted pods to `Failed`/`Succeeded` before API deletion — controllers watching pod status observe final state.

## Per-proposal applicability

- **A**: Applies to puller + alert pods (pipeline pod stays monolithic; in-place restart).
- **B**: Each stage pod needs preStop tuned to its statefulness. Observer+filter is highest-stakes (tracker state); motion and inference-coord are largely stateless.
- **C**: Most important proposal for this pattern. Rolling updates must drain camera assignments before termination — "drain worker by reassigning its cameras first" is the assignment-controller's preStop signal.
- **D**: S3 frame refs are durable by design — partial-processing frames recoverable without checkpoint. Simpler shutdown story except for observer.
- **E**: Detection core holds fullest state (tracker + window + inference buffers); longest required grace period.

## Related

- [[graceful-pod-termination-zero-downtime]] — primary source
- [[tracker-snapshot-schema]] — cadence constraint derived here
- [[2026-04-16_graceful-failover-design]] — snapshot-before-death protocol this pattern implements
- [[k8s-placement-primitives]] — PDB complements graceful shutdown (prevents mass drain that overwhelms grace period)
- [[k8s-controller-selection-guide]] — StatefulSet upgrade behavior relies on this handshake
