---
title: "Source: Pod Affinity & Anti-Affinity (Assigning Pods to Nodes)"
type: source
topic: fleet-architecture
tags: [source, kubernetes, scheduling, affinity, anti-affinity, topology-spread, node-affinity]
url: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
ingested: 2026-04-21
author: kb-bot
---

# Pod Affinity & Anti-Affinity (Assigning Pods to Nodes)

## Core mechanisms

Kubernetes offers four co-location and placement mechanisms in rough order of expressiveness: `nodeSelector` (deprecated for complex use, AND-only), **node affinity** (preferred replacement — operators `In/NotIn/Exists/Gt/Lt`, OR across `nodeSelectorTerms`, AND within `matchExpressions`), **pod affinity / anti-affinity** (co-locate or repel based on other pods), and **topology spread constraints** (modern even-distribution primitive).

## Required vs Preferred

Both node and pod affinity come in two variants:

- `requiredDuringSchedulingIgnoredDuringExecution` — hard constraint; pod enters `Pending` indefinitely if unmet. Use only for true hard requirements (GPU, data residency).
- `preferredDuringSchedulingIgnoredDuringExecution` — soft; scheduler tries but falls back. Weights 1–100 are additive. Non-deterministic across scheduler versions.

**Critical gotcha:** "IgnoredDuringExecution" means node-label changes after scheduling are not enforced — a pod already running on a node that loses its label stays there.

## Pod affinity vs topology spread

Pod affinity/anti-affinity is **O(n²)** at scheduling time. For clusters beyond ~100 nodes, prefer **topology spread constraints** (O(n)), which express max-skew across a topology key with `DoNotSchedule` (hard) or `ScheduleAnyway` (soft) unsatisfiability policy. `maxSkew: 1` with `ScheduleAnyway` is the production-safe default — hard spread can deadlock if capacity is tight.

## Key production gotchas

1. Required anti-affinity can make pods permanently unschedulable if replica count exceeds node/zone count. Always use soft anti-affinity with weight tiers.
2. `nodeSelector` + `nodeAffinity` are AND'd if both present — don't mix.
3. Pod affinity uses `topologyKey: kubernetes.io/hostname` (same node) or `topology.kubernetes.io/zone` (same AZ). Missing node labels silently break pod-affinity constraints.
4. Topology spread with `DoNotSchedule` and a tight `maxSkew` is a scheduling deadlock risk under partial capacity; always pair with monitoring.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Pod affinity can co-locate puller pods with the pipeline-worker pod on the same node to keep frame transport latency low. Node affinity useful for pinning pipeline workers to memory-optimized node pools.
- **B — Stage Fleets**: Zone-affinity across all 4 stage pods is mandatory to avoid cross-AZ cost (~$400k/mo at scale). Topology spread constraints with `topologyKey: topology.kubernetes.io/zone` and `ScheduleAnyway` are the implementation vehicle. Mentioned explicitly in `2026-04-16_proposal-b-stage-fleets.md`.
- **C — Camera-Worker**: Topology spread to distribute generic workers evenly across nodes; pod anti-affinity to prevent two GPU-heavy workers from landing on the same node. No co-location requirement.
- **D — Event-Driven**: Similar to B — zone-affinity per-stage to minimize cross-AZ S3/NATS traffic. Puller-to-detector affinity less critical (S3 decouples them).
- **E — Hybrid Sidecar**: Most complex affinity story. Smart puller pods need pod-affinity to their paired detection-core StatefulSet pod in the same AZ (mentioned in proposal note). Detection core StatefulSet uses stable pod identities — pair with `podAffinity` on `topologyKey: topology.kubernetes.io/zone` to keep camera-group streams local.

## Source
https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/
