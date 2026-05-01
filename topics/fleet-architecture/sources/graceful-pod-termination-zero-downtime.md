---
title: "Source: Graceful Pod Termination & Zero-Downtime Deployments"
type: source
topic: fleet-architecture
tags: [source, kubernetes, graceful-shutdown, sigterm, prestop, termination-grace-period, zero-downtime, stateful, checkpoint]
url: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination
ingested: 2026-04-21
author: kb-bot
---

# Graceful Pod Termination & Zero-Downtime Deployments

## Termination sequence (exact ordering)

1. **Endpoint removal** (~0–100 ms, asynchronous) — EndpointSlice controller removes pod IP. Not synchronous with SIGTERM; this is the root cause of the classic in-flight traffic loss race.
2. **preStop hook** (if defined) — runs before SIGTERM. Budget comes from `terminationGracePeriodSeconds`. Use for: readiness-probe flip, connection drain window, state checkpoint.
3. **SIGTERM** — sent after preStop completes (or immediately if no preStop). App must handle and initiate cleanup.
4. **Grace period expires → SIGKILL** — whatever remains of `terminationGracePeriodSeconds` after preStop.

**Key formula:** `terminationGracePeriodSeconds = preStop_duration + app_shutdown_budget + 5–10s buffer`. Default 30 s is almost always too short for stateful workers.

## The endpoint-removal race condition

Because endpoint removal is async, a request can arrive after SIGTERM is already in flight. The production fix is a preStop `sleep` (typically 5–15 s) that gives the load balancer time to drain before the app processes shutdown. This is not a hack — it is the documented pattern.

## Stateful handoff pattern

For workers that must checkpoint before death (tracker snapshot, window state):

1. preStop flips readiness probe to failing → stops new traffic.
2. preStop sleeps for LB drain window (~10–15 s).
3. SIGTERM received; app flushes in-flight frames, writes snapshot to Redis/DynamoDB.
4. App exits cleanly; kubelet confirms exit before `terminationGracePeriodSeconds` elapses.

**Failure mode:** if the checkpoint write exceeds the remaining grace period, SIGKILL fires and the snapshot is lost — exactly the tracker-resume gap the graceful-failover design is trying to eliminate. `terminationGracePeriodSeconds` must be sized for worst-case snapshot write time (Redis AOF flush latency + network).

## Production configuration notes

- `maxUnavailable: 0` + `maxSurge: 1` in rolling-update strategy ensures no downtime during deploys.
- `terminationGracePeriodSeconds: 120` is reasonable for stateful fleet pods (60s drain + 45s checkpoint budget + 15s buffer).
- Kubernetes 1.27+ transitions deleted pods to `Failed`/`Succeeded` before API deletion — controllers watching pod status can observe final state.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Pipeline worker still monolithic; graceful shutdown applies to puller and alert pods. Puller preStop should drain VMS connections before SIGTERM reaches pipeline path.
- **B — Stage Fleets**: Each stage pod needs its own preStop tuned to its statefulness. Observer+filter pod holds tracker state — full checkpoint protocol applies. Motion and inference-coord pods are largely stateless; short drain only.
- **C — Camera-Worker**: Most important proposal for this pattern. Rolling updates must drain camera assignments before termination. Proposal note explicitly calls out "drain worker by reassigning its cameras first, then terminate." preStop hook should signal assignment controller and wait for drain acknowledgement.
- **D — Event-Driven**: Observer pod needs checkpoint. S3 frame refs are durable by design — partial-processing frames are recoverable without checkpoint. Simpler shutdown story than B/C/E for the non-observer stages.
- **E — Hybrid Sidecar**: Detection core StatefulSet pods hold the fullest state (tracker + window + inference buffers). These pods have the longest required grace period. Smart puller preStop is simpler — drain VMS connections, no checkpoint needed (FDMD state is ephemeral).

## Source
https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination
