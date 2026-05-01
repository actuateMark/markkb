---
title: "EKS Storage Cost-Opt — Actuate Applicability"
type: concept
topic: aws-cost
tags: [aws, eks, ebs, efs, snapshots, applicability, cost-optimization]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/syntheses/2026-04-27_aws-cost-topic-spinoff.md
  - topics/aws-cost/notes/syntheses/2026-04-28_s3-cost-reduction-action-plan.md
  - topics/aws-cost/sources/2026-04-27_eks-cost-opt-storage.md
  - topics/personal-notes/notes/daily/2026-04-27.md
incoming_updated: 2026-05-01
---

# EKS Storage Cost-Opt — Actuate Applicability

Per-recommendation mapping of [[2026-04-27_eks-cost-opt-storage]] to Actuate's actual EKS fleet posture. Recommendations not relevant to us (FSx Lustre, FSx ONTAP, etc.) are dropped.

## Active opportunities

| Recommendation | Actuate state | Effort | Estimated lever |
|---|---|---|---|
| **gp2 → gp3 migration** | Unaudited; default volume class on the connector pods + supporting infrastructure not yet inventoried. | Medium — needs an audit pass + EBS CSI driver migration. EKS v1.31+ supports VolumeAttributesClass for in-place. | Up to **20% of EBS spend**. EBS spend itself unquantified — surfaces only as a CE line item. Audit first. |
| **EBS snapshot lifecycle (DLM)** | No DLM today; manual snapshot management. | Small — declarative DLM policy via Terraform. | Low-but-cumulative; depends on snapshot retention practices today. |
| **Dangling EBS volume scan** | No ongoing audit. Trusted Advisor available; Popeye not deployed. | Tiny — one-shot Trusted Advisor check, then a recurring `/cost-check` recipe. | Variable; wins are historic-orphan-driven, not steady-state. |
| **Compute Optimizer review** | Not currently consulted. | Tiny — read-only AWS console. | Recommendations only; intersects with VPA over-provisioning (ENG-78). |
| **Right-size volumes (start small, grow)** | Default sizes used; no dynamic-grow strategy. | Medium — needs CSI driver tuning + monitoring before relying on grow-on-demand. | Variable. |
| **Container image: distroless / multi-stage** | Some images already optimized; per-image audit needed (vms-connector, [[ds-server-container]], multiple variants). | Per-image judgment call. | Layer-storage savings; small per-image but compounding across ~15 repos. |

## Less-active or N/A

- **EFS Infrequent-Access tiering** — EFS surface in our fleet TBD; if minimal, low-priority. Audit + decide.
- **EFS Intelligent-Tiering** — same.
- **EFS One-Zone tiers** — same.
- **FSx for Lustre** — not used.
- **FSx for NetApp ONTAP** — not used.
- **`io2` block express** — overkill for our workloads.
- **Velero with TTL flags** — not currently used; DLM is the more direct path for our EBS workloads.
- **kubelet GC tuning** — defaults likely fine; revisit only if image-store pressure surfaces.

## Recommended next actions (low → high friction)

1. **Audit EBS volume types** — count of gp2 vs gp3 across the fleet. One-shot via `aws ec2 describe-volumes --filters Name=tag:cluster,Values=Connector-EKS --query 'Volumes[].[VolumeId,VolumeType,Size]'` (or analogous query). Output: number/percent on gp2.
2. **Trusted Advisor cost-optimization scan** — read-only console action; produces a list of dangling/under-utilized volumes.
3. **Run AWS Compute Optimizer on the EBS dimension** — 14d data already in CW; recommendations come "for free."
4. **DLM policy** — pick a reasonable default snapshot retention (e.g., 7 daily, 4 weekly, 12 monthly) + apply to volumes tagged for snapshotting.
5. **gp2 → gp3 migration plan** — once the audit is done, write a phased migration. EKS v1.31+ in-place via VolumeAttributesClass is the path; older clusters need volume-modify + restart.

## Notable gaps in the AWS doc (vs our actual cost picture)

- **No S3 guidance.** Most of our cost-opt headroom is S3-side (~$398k/yr S3 vs unquantified EBS). Covered separately under [[2026-04-27_s3-cost-optimization]] et al.
- **No specific guidance on per-deployment VPA over-provisioning** — that's a Kubernetes-side problem (ENG-78) the doc doesn't touch.
- **No guidance on inference-side storage** (model weights, inference cache) — relevant to [[ds-server-container]].

## Related

- [[2026-04-27_eks-cost-opt-storage]] — source
- [[cost-architecture]] — Actuate's cost layers
- [[2026-04-23_s3-tier3-cost-investigation]] — the S3 cost picture (separate track)
- [[infrastructure/_summary]]
