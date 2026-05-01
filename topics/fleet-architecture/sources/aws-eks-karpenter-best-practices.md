---
title: "Source: AWS EKS Best Practices — Karpenter (Compute & Autoscaling)"
type: source
topic: fleet-architecture
tags: [source, kubernetes, autoscaling, karpenter, eks, aws, best-practices, spot, irsa, nodepool]
url: https://aws.github.io/aws-eks-best-practices/karpenter/
ingested: 2026-04-21
author: kb-bot
---

# AWS EKS Best Practices — Karpenter (Compute & Autoscaling)

AWS's production guidance for running Karpenter on EKS. Picks up directly from the `ds-terraform-eks-v2` infrastructure baseline and addresses operational patterns not covered in the upstream Karpenter docs.

## Controller Placement

Run Karpenter controllers on **EKS Fargate or a dedicated managed node group** — never on Karpenter-managed nodes. This is a hard requirement: if Karpenter terminates the node running its own controller during consolidation, the cluster loses its autoscaler. The `ds-terraform-eks-v2` Terraform module must include a Fargate profile or a separate fixed node group for Karpenter.

## Private Cluster Requirements

Private EKS clusters (like the Connector-EKS cluster) require additional **VPC endpoints** beyond standard EKS networking:
- **AWS STS endpoint** — IRSA credential retrieval for Karpenter's IAM role
- **SSM Parameter Store endpoint** — Launch Template and AMI discovery
- Without the Price List Query API endpoint, instance pricing data becomes stale and is only refreshed on Karpenter upgrades — affects Spot selection quality.

## NodePool Design

**Mutual exclusivity is critical.** Overlapping NodePools (same labels, no taints) cause non-deterministic pool selection. Use taints for GPU-bound or workload-specialised pools. Recommended pattern for the connector fleet:
- One NodePool per fleet type (puller, worker/observer, alert) with dedicated taints
- Per-NodePool CPU/memory **limits** — no global limit exists in Karpenter. Without limits, a bug or traffic spike can provision unbounded nodes.
- TTL-based node expiration (`expireAfter`) for rolling AMI/security updates without manual drains.

## Spot Strategy

- Allow the broadest instance type list compatible with workload requirements — wider pools reduce interruption probability via **Price Capacity Optimized** allocation.
- Configure an **SQS interruption queue** for proactive drain (Karpenter handles the 2-minute warning, drains the node, and provisions a replacement before termination).
- Avoid over-restricting to a single instance family (e.g., only `c6i`) — this is the most common cause of Spot capacity errors at scale.

## Resource Request Accuracy

Karpenter's consolidation bin-packing and its node-type selection both depend on **accurate pod resource requests**. Over-requesting wastes capacity; under-requesting causes OOM on consolidation. Recommendation: set `LimitRange` defaults per namespace to prevent unbounded consumption. For the connector fleet, per-camera CPU/memory requests need empirical calibration (PoC phase) before enabling aggressive consolidation.

## High-Availability Patterns

Standard EKS HA patterns apply on top of Karpenter:
- **Topology spread constraints** across AZs for all stateless fleets
- **PodDisruptionBudgets** on all fleets with `minAvailable ≥ 1` to prevent simultaneous Karpenter-driven evictions
- **CoreDNS lameduck duration** — Karpenter's rapid node cycling can expose DNS routing bugs; set `lameduck` on CoreDNS to prevent queries routing to terminating pods.

## Cost Monitoring

CloudWatch metric filters + billing alarms per NodePool. AWS Cost Anomaly Detection recommended. Without per-NodePool limits and alarms, a misconfigured HPA (e.g., `maxReplicas: 10000`) can silently inflate the cluster to multi-thousands of nodes.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Karpenter best practices apply but with low complexity — one NodePool for the monolith pods, one for alert pods. IRSA and VPC endpoint requirements apply to the existing cluster regardless.
- **B — Stage Fleets**: Five NodePools, one per fleet type. Mutual-exclusivity via taints is essential — otherwise the scheduler non-deterministically places motion pods on memory-optimised observer nodes and vice versa. Per-pool limits are a critical cost guard at B's operational complexity level.
- **C — Camera-Worker Fleet**: Single worker NodePool — the simplest Karpenter configuration of any proposal. Consolidation maps cleanly to camera-packing. Per-NodePool limit acts as a natural camera-count ceiling (safety valve during assignment-controller bugs).
- **D — Event-Driven Pipeline**: Same multi-NodePool pattern as B. S3 Express One Zone + VPC gateway endpoint is already aligned with the private-cluster VPC endpoint guidance. Detector fleet may benefit from inference-optimised instance types (c6i.2xlarge) in a dedicated NodePool.
- **E — Hybrid Sidecar**: Smart Puller NodePool (Spot-eligible, broad instance family). Detection Core NodePool (On-Demand or On-Demand-preferred — StatefulSet with live tracker state should not be spot-interrupted without `do-not-disrupt`; IRSA snapshot-to-Redis before drain is the mitigation). Alert Dispatch NodePool (Spot-eligible).

## Source
https://aws.github.io/aws-eks-best-practices/karpenter/
