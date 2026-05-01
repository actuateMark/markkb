---
title: "Scaling-Layer Taxonomy (HPA + VPA + Karpenter)"
type: concept
topic: fleet-architecture
tags: [autoscaling, hpa, vpa, karpenter, scaling-layers, fleet-design, decision-framework]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/concepts/vpa-bimodal-workload-limitation.md
  - topics/fleet-architecture/reading-list.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/video-processing/notes/syntheses/gpu-substrate-and-fleet-placement.md
incoming_updated: 2026-05-01
---

# Scaling-Layer Taxonomy (HPA + VPA + Karpenter)

The three autoscaling layers relevant to the fleet redesign, how they interact, and how each proposal should engage them. Proposals B, C, D, and E all need to make this choice per fleet — a single reference prevents the decision being rediscovered per-proposal.

Sources: [[kubernetes-hpa-behavior]], [[vertical-pod-autoscaler-deep-dive]], [[karpenter-node-provisioning]], [[aws-eks-karpenter-best-practices]].

## The Three Layers

| Layer | What it tunes | Control loop latency | Failure mode |
|---|---|---|---|
| **HPA** (pod-level) | Replica count | ~15 s sync + scrape | Missing `resources.requests` → silent no-op |
| **VPA** (pod-resource) | CPU/memory requests per pod | Eviction-driven (minutes) | Bimodal workload over-provisioning ([[vpa-bimodal-workload-limitation]]) |
| **Karpenter** (node-level) | EC2 instances in cluster | Milliseconds (direct API) | Overlapping NodePools → non-deterministic scheduling |

## Interaction Rules

- **HPA + VPA on the same metric is incompatible.** VPA on memory + HPA on CPU is the only safe combo.
- **HPA buffers Karpenter provisioning latency.** Even Karpenter needs 60-90 s for a cold node to appear. HPA's `minReplicas` must carry headroom for this, or cold bursts cause a gap.
- **Karpenter consolidation can evict VPA-recommended pods.** `karpenter.sh/do-not-disrupt` annotation is required for any StatefulSet holding live state during consolidation cycles.
- **Scale-down stabilization is per-layer.** HPA has `stabilizationWindowSeconds` (bursty-workload anti-thrash lever); Karpenter has its own disruption-decision cadence.

## Per-Fleet Layer Decisions

| Fleet type | HPA | VPA | Karpenter Spot-eligible |
|---|---|---|---|
| Stateless stage (motion, inference-coord, alert) | ✅ CPU / queue-depth | ✅ Steady load, clean recommendation | ✅ |
| Stateful per-camera (observer, detection-core) | ❌ awkward w/ sticky state | ✅ but test pod-recreation impact | ❌ Use On-Demand |
| Puller fleet | 🟡 depends on proposal | ✅ steady | ✅ (stateless FDMD state) |
| NATS JetStream (D only) | ❌ StatefulSet; manual size | 🟡 memory only | ❌ cluster integrity |

## Scaling Signals Per Proposal

- **A — Minimal Split**: Low HPA benefit on the monolith (mixed burst/steady averages out); VPA remains the primary lever but ENG-78 unresolved. Karpenter benefits all fleets.
- **B — Stage Fleets**: Each stage gets independent HPA with stage-specific signal (CPU for motion, queue depth for inference, SQS depth for alert). `behavior.scaleDown.stabilizationWindowSeconds: 300` prevents chain-reaction thrash across the 4-hop pipeline. VPA cleanly per-fleet ([[vpa-bimodal-workload-limitation]]).
- **C — Camera-Worker Fleet**: Single-fleet HPA on worker pool, driven by aggregate camera count. Simplest autoscaling story of any proposal. Karpenter consolidation directly maps to camera-packing efficiency.
- **D — Event-Driven**: NATS JetStream **consumer lag** is the natural External HPA metric for Detector and Observer fleets — more accurate than CPU because NATS provides a durable queue-depth signal independent of processing speed. Motion-gating at the puller reduces downstream stage replica counts significantly.
- **E — Hybrid Sidecar**: Smart Puller fleet HPA on camera count/CPU; Detection Core = StatefulSet with camera-group affinity (HPA awkward — VPA or manual sizing appropriate). Alert Dispatch HPA on SQS depth. Best overall VPA-layer alignment.

## Production-Safe HPA Defaults

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0        # react immediately to spikes
    policies:
    - type: Percent
      value: 100
      periodSeconds: 15                  # double every 15s
  scaleDown:
    stabilizationWindowSeconds: 300      # 5-min look-back
    policies:
    - type: Percent
      value: 10
      periodSeconds: 60                  # 10%/min scale-down
    selectPolicy: Min                    # most conservative
```

Tune per-fleet burst profile; observer/alert need longer `stabilizationWindowSeconds` than motion/inference.

## Karpenter NodePool Pattern

One NodePool per fleet type, with taints for mutual exclusivity and per-pool resource limits (no global Karpenter limit exists — a misconfigured HPA with `maxReplicas: 10000` could silently inflate the cluster without these guards). See [[aws-eks-karpenter-best-practices]].

## Open Questions

- **K8s cluster version**: VPA `InPlaceOrRecreate` requires K8s 1.33+. Confirm EKS version before specifying proposals' VPA strategy.
- **Karpenter version**: `karpenter.sh/do-not-disrupt` available from v0.32. Check `ds-terraform-eks-v2` for current pin.
- **Per-proposal NodePool instance families**: not yet specified. Compute-optimized for motion/detector vs memory-optimized for observer — do this during the PoC sizing phase.

## Related

- [[kubernetes-hpa-behavior]], [[vertical-pod-autoscaler-deep-dive]], [[karpenter-node-provisioning]], [[aws-eks-karpenter-best-practices]] — primary sources
- [[vpa-bimodal-workload-limitation]] — ENG-78 root cause
- [[k8s-placement-primitives]] — placement and availability primitives that compose with scaling
- [[memory-and-fork-safety]] — [[vpa-behavior|VPA behavior]]'s interaction with fork-safety
