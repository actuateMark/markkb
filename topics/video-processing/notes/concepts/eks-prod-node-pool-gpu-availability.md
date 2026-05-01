---
title: "EKS Prod Node-Pool GPU Availability (Connector cluster snapshot)"
type: concept
topic: video-processing
tags: [eks, karpenter, gpu, nvidia, node-pool, infrastructure, follow-up, snapshot]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# EKS Prod Node-Pool GPU Availability (Connector cluster snapshot)

Snapshot of node-pool composition on the prod connector cluster (`Connector-EKS` / `inference-eks-Ny9n`, account 388576304176, us-west-2) as of 2026-04-27. Feeds [[gpu-substrate-and-fleet-placement]] (preliminary, in flight).

## Summary

The prod connector cluster **does have GPU and Inferentia node pools defined and serviceable today** (G4dn / G5 / G6 / G6e for NVIDIA via `gpu-spegel-green`; inf2 via `inf2-spegel-blue`), with both `nvidia-device-plugin` and `neuron-device-plugin` enabled cluster-wide. **However, no `vms-connector` pods land on them.** The connector pod template targets only the `multi-az` CPU pools (Graviton + 7th-gen x86) via `nodeSelector: workload.actuate.ai/connector=true`, and connector pods do not declare an `nvidia.com/gpu` toleration. GPU nodes in this cluster exist for ML inference workloads (`ds-model-prod` namespace, Inferentia for multimodel + intruder; the GPU pool is currently lightly used and there is a dormant Kyverno mutate policy hinting at a one-off `connector-705-fs-251-*` GPU experiment).

## Node-pool inventory

All pools are Karpenter-managed (`karpenter.sh/v1` `NodePool`, AMI source `karpenter.k8s.aws/v1` `EC2NodeClass`). No legacy Provisioner CRDs remain. There are also two static EKS managed node groups (`services-ng-blue` SPOT, `services-ng-green` ON_DEMAND, `BOTTLEROCKET_x86_64`, `c7i/c7a/m7i/m7a/c6i/c6a/m6i/m6a 2xlarge`) tainted `CriticalAddonsOnly=true` for system addons — not workload-relevant.

| NodePool | Arch | Instance families | Capacity | GPU/Accel | Key labels | Taints |
|---|---|---|---|---|---|---|
| `multi-az-public-bottlerocket` (w=50) | amd64+arm64 | m8g/c8g/r8g/m8gd/c8gd/r8gd/r8gn/c8gn/i8g/x8g + m7i/m7a/c7i/c7a/r7i/r7a | spot+on-demand, all 4 AZs | none | `actuate.ai/multi-az=true`, `subnets=public` | `multi-az=true:NoSchedule` |
| `multi-az-private-bottlerocket` (w=50) | amd64+arm64 | same as above | spot+on-demand, all 4 AZs | none | `subnets=private` | `multi-az=true:NoSchedule` |
| `multi-az-public-connector-bottlerocket` + 12 per-AZ shards (w=40-48) | amd64+arm64 | m8g/r8g/m8gd/r8gd/r8gn/i8g/x8g + m7i/m7a/c7i/c7a/r7i/r7a | spot, per-AZ CPU-limited (128/192/256/384/512) | none | `workload.actuate.ai/connector=true` | `multi-az=true:NoSchedule` |
| `multi-az-private-connector-bottlerocket` (w=40) | amd64+arm64 | same | spot+on-demand, us-west-2d | none | `subnets=private`, `workload.actuate.ai/connector=true` | `multi-az=true:NoSchedule` |
| `multi-az-*-longrunning-bottlerocket` | amd64+arm64 | (similar 7th/8th gen) | mixed | none | `nodegroup-type=longrunning` | `actuate.ai/longrunning=true` |
| `multi-az-*-tasks-bottlerocket` | amd64+arm64 | similar | mixed | none | `nodegroup-type=tasks` | `actuate.ai/tasks=true` |
| `x86-public-bottlerocket` / `x86-private-bottlerocket` (w=10) | amd64 only | m7i/m7a/c7i/c7a/r7i/r7a | spot+on-demand, us-west-2d | none | `nodegroup-type=x86-public/private` | (public adds `NAT=false`) |
| `x86-public-chm-*` / `x86-private-chm-*` | amd64 | same | same | none | `nodegroup-type=x86-*-chm` | `actuate.ai/tasks=true` (+`NAT=false` public) |
| **`gpu-spegel-green`** (w=10) | **amd64** | **g6e, g6, g5, g4dn, p2, p3** | **spot+on-demand, all 4 AZs** | **NVIDIA** (label `nvidia.com/gpu: present`) | `nodegroup-type=gpu-spegel-green` | **`nvidia.com/gpu=present:NoSchedule`** |
| **`inf2-spegel-blue`** (+ `inf2-spegel-spot-blue` w=20) | amd64 | inf2 (xlarge/8xlarge/24xlarge/48xlarge) | spot+on-demand, all 4 AZs | **AWS Neuron** | `nodegroup-type=inf2-spegel-blue` | **`aws.amazon.com/neuron=inf2-spegel-blue:NoSchedule`** |
| `github-actions` | arm64+amd64 (8th/7th gen Graviton + x86) | many | spot, short-lived (24h expire) | none | `node-role.actuate.ai/github-actions` | runner-only |

Karpenter `expireAfter: 72h` on all workload pools. Consolidation policy `WhenEmptyOrUnderutilized` with 30s settle.

## GPU posture today

GPU is **available but unused for connector workloads**. Concrete evidence:

- **NodePool**: `gpu-spegel-green` allows G4dn/G5/G6/G6e/P2/P3 on AL2023 NVIDIA AMI (`amazon-eks-node-al2023-x86_64-nvidia-1.32-v*`). xlarge through 16xlarge sizes. CPU manager `static`, topology manager `single-numa-node`. Pre-pulls Spegel + EKS networking images via userdata.
- **Device plugin**: `nvidiaDevicePlugin: enabled: true` (Argo app `nvidia-device-plugin`). `neuronDevicePlugin: enabled: true` (the `neuron/` chart deploys `k8s-neuron-device-plugin`).
- **Today's GPU consumers**: cluster-values.yaml shows only the inference stack uses Inferentia (`nodeSelector: nodegroupType: inf2-spegel-blue`, `tolerations: aws.amazon.com/neuron=inf2-spegel-blue`) for `ds-model-prod` multimodel + intruder. **Nothing currently targets `gpu-spegel-green` in production.** The only reference is a fully-commented-out Kyverno policy (`deployments/cluster-services/kyverno-policies/gpu-connector/gpu-connector.yaml`) that would have mutated `connector-705-fs-251-*` pods onto the GPU pool with `nvidia.com/gpu: 1` resource limit and a special `connectors_gpu:featureoptimized-connector` image — disabled.
- **NVIDIA Container Toolkit**: not explicitly named, but `amazon-eks-node-al2023-x86_64-nvidia-*` AMIs ship with the toolkit pre-installed. No `gpu-operator` deployment seen — Argo manages the simpler `nvidia-device-plugin` chart only.

So the cluster is GPU-capable, not GPU-utilising for the connector. From the connector-fleet perspective this is effectively **CPU-only today** — proposals that depend on GPU offload need to assume that any cost / capacity headroom on GPU nodes is currently zero.

## Karpenter version & shape

Modern stack:
- CRDs: `karpenter.sh/v1` (NodePool) and `karpenter.k8s.aws/v1` (EC2NodeClass) — current generation, **not** legacy `Provisioner`/`AWSNodeTemplate`.
- Cluster version: EKS 1.33 (per terragrunt input; AMIs pinned to 1.32 in nodeclasses, suggests a recent or in-progress upgrade).
- AMI families: `Bottlerocket` for all CPU pools (alias `bottlerocket@latest`), `AL2023` only for the GPU and inf2 pools (forced by the NVIDIA / Neuron AMI variants).
- Per-AZ + per-CPU-cap NodePool [[sharding]] (`-usw2a-0`/`1`/`2`/`3`/empty) is a hand-rolled spread mechanism — multiple pools at decreasing weights and increasing `limits.cpu` to bias placement toward smaller, more-spread shards first. This pattern only exists for the connector workload.

## Connector pod placement constraints

From `connector_deployer/src/yaml/deployment.py` (template variables `$(SUBNETS)`, `$(ARCHITECTURE)`, `$(NODEGROUP_TYPE)` filled at deploy time — see [[connector-deployer]] flow):

```yaml
nodeSelector:
  actuate.ai/multi-az: "true"
  actuate.ai/subnets: $(SUBNETS)         # public | private
  kubernetes.io/arch: $(ARCHITECTURE)    # arm64 | amd64
  actuate.ai/nodegroup-type: $(NODEGROUP_TYPE)
  workload.actuate.ai/connector: "true"
tolerations:
  - key: multi-az
    value: "true"
    effect: NoSchedule
```

Resource request: `cpu: 3` / `memory: 4Gi` (limit `6Gi`). Default image is `arm_connector:latest`. Connector pods **only land on `multi-az-*-connector-*` shards** — no GPU toleration, no Inferentia toleration, no anti-affinity on the GPU label. That's the locked-in placement contract today.

## What this means for fleet-architecture proposals C/D/E

(Pulling forward from [[gpu-substrate-and-fleet-placement]]; details still in flight, but the substrate constraints are now concrete.)

- **Proposal C / D / E that assume GPU-accelerated decode in the connector pod**: not free. Requires (a) adding `nvidia.com/gpu: 1` to the connector container's `resources.limits`, (b) tolerating `nvidia.com/gpu=present:NoSchedule`, (c) flipping `nodeSelector` to `actuate.ai/nodegroup-type: gpu-spegel-green`, and (d) building a CUDA-aware connector image (the dormant Kyverno policy already defines an ECR repo `connectors_gpu:featureoptimized-connector` — likely a stalled experiment we can resurrect).
- **Capacity**: the GPU pool has no hard limit set at the NodePool level (unlike the CPU connector shards which cap at 128/192/256/384/512 cpu per shard) — so spinning up GPU nodes is gated by EC2 spot/on-demand availability, not by cluster config. Cost-per-pod jumps significantly (G5.xlarge ~$1/hr vs c7i.xlarge ~$0.17/hr); GPU-substrate proposals must include a per-camera attach ratio analysis.
- **Multi-AZ placement of GPU**: `gpu-spegel-green` allows all four us-west-2 AZs, unlike the connector shards which heavily favour 2a/2b/2c with smaller pools and fall back to 2d on the private side. A GPU-bearing connector pod would lose the per-AZ shard weighting and need its own [[sharding]] scheme.
- **EU parity**: prod EU (`inference-eks-Xp5O`) has the same template structure (gpu-spegel-green exists there too), so any GPU substrate decision can be rolled out symmetrically. Verification not done in this snapshot — flagged below.

## Open questions / verification still needed

- **Live node count** on `gpu-spegel-green` in prod US right now (declared, not necessarily provisioned). Run `kubectl get nodes -l actuate.ai/nodegroup-type=gpu-spegel-green` against `Connector-EKS`.
- **Live consumers** of `gpu-spegel-green` — any PodDisruptionBudgets / DaemonSets there beyond `nvidia-device-plugin`? Confirms whether the pool is genuinely empty or has hidden tenants.
- **Hardware-decode capability per instance family**: G4dn = T4 ([[hardware-accelerated-codecs|NVENC]]/[[hardware-accelerated-codecs|NVDEC]], [[h264-deep-dive|H264]]/[[h265-hevc-deep-dive|H265]]), G5 = A10G (also [[av1-vp9-future|AV1]] decode), G6/G6e = L4/L40S (full [[av1-vp9-future|AV1]] + H266). This intersects with [[ffmpeg-hardware-acceleration]] / [[hardware-accelerated-codecs]] for the codec coverage table.
- **Kyverno `gpu-connector` policy provenance**: who authored it, when, and what was the experimental result? It's the only artifact suggesting GPU-connector has ever been attempted — finding the matching ticket would short-circuit a lot of proposal-C planning.
- **EU symmetry confirmation**: read `inference-eks-Xp5O/gpu-spegel-nodepool-green.yaml` and confirm AMI / sizes / AZs match.
- **GPU AMI version drift**: `amazon-eks-node-al2023-x86_64-nvidia-1.32-v*` is pinned to 1.32 while the cluster declares 1.33 in terragrunt — this works (kubelet skew tolerated) but is a follow-up.

Cross-references: [[gpu-substrate-and-fleet-placement]], [[hardware-accelerated-codecs]], [[ffmpeg-hardware-acceleration]], [[infrastructure/_summary]], [[fleet-architecture/_summary]], [[k8s-placement-primitives]], [[scaling-layer-taxonomy]], [[connector-docker-system-deps]] (peer follow-up).
