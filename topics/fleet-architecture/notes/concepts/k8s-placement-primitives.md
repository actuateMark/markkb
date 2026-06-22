---
title: "K8s Placement & Availability Primitives"
type: concept
topic: fleet-architecture
tags: [kubernetes, scheduling, placement, topology, affinity, pdb, availability, fleet-design]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/concepts/pod-termination-sequence.md
  - topics/fleet-architecture/notes/concepts/scaling-layer-taxonomy.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_graceful-failover-design.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-e.md
  - topics/fleet-architecture/reading-list.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
incoming_updated: 2026-05-27
---

# K8s Placement & Availability Primitives

The three mechanisms that together express "where pods land" and "minimum availability guarantees" in K8s. They are always co-designed — reasoning about any one in isolation misses the deadlock risks. This note is the pre-implementation checklist for whichever fleet proposal is selected.

Distilled from [[pod-topology-spread-constraints]] + [[pod-affinity-anti-affinity]] + [[pod-disruption-budgets]].

## The Three Primitives

| Primitive | Purpose | Complexity | Deadlock risk |
|---|---|---|---|
| **Topology Spread Constraints (TSC)** | Even-distribute pods across failure domains (zone, node) | O(n) | Yes with `DoNotSchedule` + tight `maxSkew` under partial capacity |
| **Pod Affinity / Anti-Affinity** | Co-locate / repel pods based on other pods' labels | O(n²) | Yes with `requiredDuringSchedulingIgnoredDuringExecution` if replicas > domains |
| **Pod Disruption Budget (PDB)** | Constrain voluntary disruptions to maintain min availability | N/A (eviction-time) | Yes — can block drain indefinitely if `unhealthyPodEvictionPolicy` is default |

## When to use which

- **Spread workloads across zones/nodes** → TSC. At >100 nodes, always prefer TSC over pairwise anti-affinity (O(n) vs O(n²)).
- **Co-locate pod X with pod Y (same node or AZ)** → pod affinity with `topologyKey`. No TSC equivalent exists for this.
- **Prevent mass eviction during node drain** → PDB. Only mechanism that gates voluntary disruptions via the Eviction API.

## Production-safe defaults

**Stateless stage fleet (Deployment):**
- TSC: `maxSkew: 1`, `topologyKey: topology.kubernetes.io/zone`, `whenUnsatisfiable: ScheduleAnyway`
- Second TSC at node level: `topologyKey: kubernetes.io/hostname`, `DoNotSchedule` (strict node spread)
- PDB: `minAvailable: max(1, replicas-1)` (i.e. tolerate 1 simultaneous drain)
- `unhealthyPodEvictionPolicy: AlwaysAllow`

**Stateful per-camera fleet (StatefulSet):**
- TSC: `maxSkew: 1`, `topologyKey: topology.kubernetes.io/zone`, `minDomains: 3`, `DoNotSchedule` (strict cross-zone)
- StatefulSet `updateStrategy.rollingUpdate.maxUnavailable: 0` (surge-style updates)
- PDB: `minAvailable: 1` for drain protection
- Pod affinity to paired sidecar if co-location required ([[2026-04-16_proposal-e-hybrid-sidecar]])

## Deadlock-avoidance rules

1. **Never pair `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity with replica count > domain count.** Pods go `Pending` forever.
2. **Never pair `DoNotSchedule` TSC with `minDomains` exceeding cluster's actual zones.** Same failure mode.
3. **Always set `unhealthyPodEvictionPolicy: AlwaysAllow` on PDBs in production.** Default (`IfHealthyBudget`) causes drains to stall on crashed pods.
4. **Rebalancing is scheduling-time only.** TSC does not rebalance running pods — only a rolling update triggers new placement. Plan for this in capacity-change playbooks.

## What PDBs do NOT cover

- Direct `kubectl delete pod` (bypasses Eviction API)
- Rolling updates in Deployments/StatefulSets (workload's own `maxUnavailable` governs)
- Involuntary node loss (hardware failure, OOM kill, kernel panic)

## Per-proposal application

- **A**: TSC on puller fleet for cross-AZ redistribution. PDB on alert fleet. Pipeline-worker PDB is a tradeoff (`minAvailable: 1` on a 1-per-site fleet effectively blocks node drain for that site's node).
- **B**: Per-stage TSC composing zone-level `ScheduleAnyway` with node-level `DoNotSchedule`. PDB per stage fleet. Cross-AZ cost control requires zone-locality between pipeline-chained stages.
- **C**: Node-level TSC on the worker pool (no two workers per node). Zone-level TSC `minDomains: 3` for cross-zone distribution. PDB + assignment-controller drain logic are complements.
- **D**: NATS JetStream StatefulSet needs TSC + PDB (`maxUnavailable: 1`) for safe 3-node cluster upgrades. Stateless fleets (detector, observer) follow B's pattern.
- **E**: Detection core StatefulSet with `minDomains: 3` TSC + `maxUnavailable: 0` StatefulSet spec + PDB `minAvailable: 1`. Smart-puller-to-core pod affinity at zone level ([[pod-affinity-anti-affinity]]). This is the most complex placement story of any proposal.

## Related

- [[pod-topology-spread-constraints]], [[pod-affinity-anti-affinity]], [[pod-disruption-budgets]] — primary sources
- [[pod-termination-sequence]] — PDB + graceful shutdown are the two operational primitives for "no site goes dark"
- [[2026-04-16_graceful-failover-design]] — PDB is required alongside snapshot design for C/E failover
