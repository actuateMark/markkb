---
title: "Source: Karpenter — Just-In-Time Node Provisioning"
type: source
topic: fleet-architecture
tags: [source, kubernetes, autoscaling, karpenter, node-provisioning, spot, consolidation, eks]
url: https://karpenter.sh/
ingested: 2026-04-21
author: kb-bot
---

# Karpenter — Just-In-Time Node Provisioning

Karpenter is a Kubernetes-native node autoscaler that **observes unschedulable pods** and provisions exactly the instance type(s) needed to satisfy their scheduling constraints — without pre-defining node groups. It then actively works to return those nodes when workloads drain, enabling tight cost control for variable-demand clusters.

## Provisioning Model

The core objects are **NodePools** (declarative constraints — instance families, zones, taints, resource limits) and **NodeClaims** (per-node requests Karpenter fulfills). When the scheduler marks pods Unschedulable, Karpenter reads their `nodeAffinity`, `topologySpreadConstraints`, and resource requests, selects a matching instance from the full EC2 catalogue, and provisions it. Retry on unavailable capacity happens **in milliseconds**, not minutes — the critical difference from Cluster Autoscaler which must iterate through fixed node groups.

## Key Advantages Over Cluster Autoscaler

| Dimension | Cluster Autoscaler | Karpenter |
|---|---|---|
| Instance selection | Fixed node group types | Any matching EC2 type |
| Capacity retry | Minutes (re-eval loop) | Milliseconds (direct API) |
| Bin-packing | Group-level | Pod-level |
| Spot handling | Manual group diversification | Native interruption + re-provision |
| Consolidation | No | Yes — replaces under-utilised nodes |

## Disruption Strategies

Karpenter runs four disruption modes: **consolidation** (remove empty or under-utilised nodes by bin-packing survivors onto fewer), **drift** (replace nodes whose spec diverges from current NodePool), **expiration** (TTL-based rotation for security/patching), and **interruption** (proactive spot-termination drain via SQS). `PodDisruptionBudgets` and the `karpenter.sh/do-not-disrupt` pod annotation are the guardrails that prevent disruption of stateful workloads mid-processing.

## Spot Instance Handling

Karpenter uses **Price Capacity Optimized** allocation across a diversified instance pool. The wider the allowed instance family list in a NodePool, the lower the interruption probability. Interruption events (2-minute warning via EC2 metadata + SQS) trigger proactive node drain before termination. For video-processing bursty loads, Spot is viable for stateless stages (puller/motion/detector) but should not be used for stateful observer pods holding live tracker state.

## Applicability to Bursty Video-Processing Loads

Karpenter's just-in-time provisioning is well-matched to bursty camera fleets: camera counts can surge (new customer onboarding, seasonal events) and the cluster should absorb that without pre-warmed spare capacity. Consolidation recovers cost during off-hours when motion rates drop and fewer inference pods are needed. The key constraint is **provisioning latency**: even Karpenter needs 60-90 s for a cold node to appear. Pod-level HPA must buffer that gap with `minReplicas` headroom, or a **warm-pool / pending-pod pre-provisioning** strategy is needed.

## Production Gotchas

- Deploy Karpenter controllers on Fargate or a dedicated non-Karpenter node group — never on nodes it manages (circular dependency on crash).
- Overlapping NodePools degrade scheduling predictability (random pool selection). Use taints or label selectors to make pools mutually exclusive.
- NodePool resource limits are per-pool, not global — set explicit CPU/memory caps per pool or unexpected spend can compound.
- `karpenter.sh/do-not-disrupt` is essential for any StatefulSet that holds camera tracker state during consolidation cycles.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Karpenter is beneficial but not transformative — today's site-pod shape is already coarse-grained. Consolidation savings are modest.
- **B — Stage Fleets**: High value. Five separate fleets with different burst profiles — Karpenter can right-size node types per fleet (compute-optimised for motion, memory-optimised for observer). Spot viable for stateless stages (motion, inference-coord).
- **C — Camera-Worker Fleet**: High value. Worker fleet is a single homogeneous pool; Karpenter consolidation directly maps to camera-packing efficiency. Spot viable for worker pods since tracker state snapshots to Redis before eviction.
- **D — Event-Driven Pipeline**: Same as B — per-stage fleets benefit from per-fleet NodePool tuning. Detector fleet is GPU-adjacent (inference-heavy); Karpenter can select inference-optimised instance types (c6i, m6i) on demand.
- **E — Hybrid Sidecar**: Smart Puller fleet (stateless) — Spot eligible. Detection Core (StatefulSet, sticky camera-group state) — `do-not-disrupt` annotation required; Spot risk higher here. Alert Dispatch — Spot eligible.

## Source
https://karpenter.sh/
