---
title: "Source: Pod Disruption Budgets"
type: source
topic: fleet-architecture
tags: [source, kubernetes, pdb, disruption, availability, maintenance, zero-downtime]
url: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
ingested: 2026-04-21
author: kb-bot
---

# Pod Disruption Budgets

PodDisruptionBudgets (PDBs) constrain **voluntary disruptions** — node drains, cluster upgrades, autoscaler scale-downs — to enforce minimum availability guarantees during maintenance operations.

**Voluntary vs. involuntary disruptions:** PDBs apply to voluntary disruptions (node drain, `kubectl drain`, admin-initiated evictions). They do NOT prevent involuntary disruptions (hardware failure, OOM kill, kernel panic). Involuntary disruptions count against the PDB budget but cannot be blocked.

**Core PDB fields:**
- `minAvailable` — minimum pods that must remain running during any voluntary disruption.
- `maxUnavailable` — maximum pods that may be simultaneously unavailable.
- `unhealthyPodEvictionPolicy: AlwaysAllow` — allows drain to proceed by evicting stuck/unhealthy pods rather than blocking indefinitely. **Set this in production**; default (`IfHealthyBudget`) causes drains to stall on crashed pods.

**Critical gotcha — what PDBs do NOT cover:**
1. Direct `kubectl delete pod` or `kubectl delete deployment` — bypasses the Eviction API entirely; PDB is not consulted.
2. Rolling updates in Deployments/StatefulSets — workload's own `maxUnavailable` governs, not the PDB.
3. Involuntary node loss — pods are disrupted regardless of PDB.

PDBs are enforced only by tools that use the Kubernetes Eviction API (`kubectl drain`, cluster autoscaler, Karpenter node consolidation).

**For stateless stage workers** (Deployment-based): PDBs are a clean fit. A 3-replica fleet with `minAvailable: 2` survives any single-node drain without service interruption. Straightforward and recommended for all Deployment fleets.

**For stateful per-camera workers** (StatefulSet-based): PDBs help but are insufficient alone. StatefulSet rolling updates do not respect the PDB — they are governed by `spec.updateStrategy.rollingUpdate.maxUnavailable`. To prevent mid-upgrade camera outages, set `maxUnavailable: 0` in the StatefulSet spec (force surge-style updates) **and** set a PDB for drain protection. The combination covers both voluntary drain and rolling upgrade scenarios.

**"No site goes dark" guarantee:** A per-site or per-camera-group PDB with `minAvailable: 1` ensures at least one worker remains live during node maintenance. Combined with topology spread constraints (cross-zone placement), this provides both maintenance-time and node-failure availability.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Alert dispatch and puller fleets both benefit from PDBs. Pipeline workers are 1-per-site, so a PDB of `minAvailable: 1` effectively blocks all drain on that site's node — a meaningful operational constraint to document.
- **B — Stage Fleets**: Each stage fleet needs its own PDB. The observer+filter fleet (tracker state) is the most critical: `minAvailable` must be sized so no camera group loses all its observers simultaneously during drain.
- **C — Camera-Worker**: PDB on the worker Deployment ensures camera-to-pod ratio stays bounded during maintenance. The assignment controller's rolling-update drain logic (proposal C open item) is the complement — graceful reassignment before termination, then PDB prevents premature eviction.
- **D — Event-Driven**: NATS JetStream StatefulSet needs a PDB preventing simultaneous loss of more than 1 replica (a 3-node cluster tolerates 1 loss; `maxUnavailable: 1`). Detector/observer Deployments need standard PDBs for processing continuity.
- **E — Hybrid Sidecar**: Most directly applicable. Detection core is a StatefulSet — the combination of `maxUnavailable: 0` in StatefulSet spec plus a PDB is the mechanism for the "no site goes dark" guarantee stated in the proposal. Smart puller fleet uses a standard Deployment PDB.

## Source
https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
