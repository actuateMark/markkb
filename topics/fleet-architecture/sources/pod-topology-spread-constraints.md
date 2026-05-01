---
title: "Source: Pod Topology Spread Constraints"
type: source
topic: fleet-architecture
tags: [source, kubernetes, topology, scheduling, placement, zones, failover]
url: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
ingested: 2026-04-21
author: kb-bot
---

# Pod Topology Spread Constraints

Topology Spread Constraints (TSC) provide declarative control over pod distribution across failure domains — zones, nodes, racks — at scheduling time. They replace the more expensive O(n²) pod anti-affinity pattern for spreading workloads.

**Core fields:**
- `maxSkew` — maximum permitted difference in pod count between the most-loaded and least-loaded domain. With `DoNotSchedule`, the scheduler rejects pods that would exceed the skew; with `ScheduleAnyway`, it biases toward lower-skew domains but still schedules.
- `topologyKey` — node label defining a domain boundary (e.g., `topology.kubernetes.io/zone`, `kubernetes.io/hostname`).
- `minDomains` (GA in K8s 1.30) — minimum eligible domains required. If fewer domains exist than `minDomains`, the scheduler treats the global minimum as 0, enabling strict spread enforcement even with few replicas. Risk: pods stall if fewer zones are available than specified.
- `whenUnsatisfiable` — `DoNotSchedule` (hard constraint) vs `ScheduleAnyway` (soft preference).
- `nodeAffinityPolicy` / `nodeTaintsPolicy` (beta 1.26, GA 1.34) — control whether affinity/taint-excluded nodes count toward domain totals. Set to `Honor` when camera workers require GPU-tainted nodes to prevent skew miscalculation.
- `matchLabelKeys` (beta 1.27, GA 1.34) — merges per-revision Deployment labels into the selector automatically; avoids manual label updates across rolling updates.

**Critical production gotcha:** constraints apply **only at scheduling time**. Existing unbalanced pods are not rebalanced. Rebalancing requires a rolling update to trigger new ReplicaSet pod placement.

**Stateful camera workers** (per-camera or per-camera-group): use `minDomains: 3` + `DoNotSchedule` at zone level to guarantee cross-zone redundancy even at low replica counts. This is the primary failover guarantee for proposals C and E.

**Stateless stage processors**: combine zone-level `ScheduleAnyway` (allow mild imbalance for throughput) with node-level `DoNotSchedule` (strict spread for node-failure recovery). Composing two constraints — one per `topologyKey` — is supported and recommended.

**Comparison to pod anti-affinity**: TSC is O(n) at scheduling vs O(n²) for pairwise anti-affinity. For fleets with hundreds of pods, TSC is the correct tool.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Puller pods benefit from zone-level TSC to avoid co-locating all pullers for a camera group in one AZ. The proposal already notes topology-aware hints are needed for cross-AZ Redis cost control — TSC is the mechanism.
- **B — Stage Fleets**: Each of B's 5 stage fleets needs independent TSC configuration. The critical constraint is keeping a camera's chain (puller → motion → inference → observer) in the same AZ; per-stage TSC with `topologyKey: topology.kubernetes.io/zone` and `ScheduleAnyway` achieves this without hard blocking.
- **C — Camera-Worker**: TSC on `kubernetes.io/hostname` ensures camera workers spread across nodes (no two workers on the same node), limiting blast radius per node failure. Zone-level TSC with `minDomains: 3` enforces cross-zone distribution of the worker pool.
- **D — Event-Driven**: The NATS JetStream StatefulSet needs TSC to spread its 3-5 replicas across zones. Detector and observer fleets use TSC for node-level spread identical to B's processing tiers.
- **E — Hybrid Sidecar**: Directly cited in the proposal — topology spread constraints pair with affinity to keep smart puller and its camera-group's detection core pod in the same AZ. `minDomains: 3` on the detection core StatefulSet is the concrete failover mechanism this proposal requires.

## Source
https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/
