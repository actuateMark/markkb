---
title: "AWS EKS Best Practices — Storage Cost Optimization"
type: source
topic: aws-cost
tags: [aws, eks, ebs, efs, fsx, snapshots, cost-optimization, source]
url: "https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt-storage.html"
ingested: 2026-04-27
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# AWS EKS Best Practices — Storage Cost Optimization

Source: <https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt-storage.html>

The EKS team's recommended storage cost-optimization playbook. Covers EBS, EFS, FSx for Lustre, FSx for NetApp ONTAP, snapshots, and container images. **Notable gap:** no in-depth S3 guidance — it treats S3 only as a complementary tier for FSx for Lustre. For S3-specific guidance, see [[2026-04-27_s3-cost-optimization]] and the Storage Lens / Intelligent-Tiering / Lifecycle source notes.

## Recommendations

### EBS

- **Use gp3 as default** — 20% lower cost than gp2; supports independent IOPS/throughput scaling without provisioning extra capacity.
- **Right-size volumes** — start small, grow via the EBS CSI driver as needed. Avoid over-provisioning IOPS.
- **`io2` block express** only for high-perf needs (SAP HANA-class workloads, up to 256k IOPS).
- **Clean up dangling volumes** — Trusted Advisor's cost-optimization checks or Popeye OSS scanner.

### EFS

- **Lifecycle policy → Infrequent Access** — files not accessed for 7-90 days move automatically. Up to 92% cheaper than Standard.
- **Intelligent-Tiering** — auto-optimizes placement across classes.
- **One-Zone tiers** — for non-critical, single-AZ workloads.

### FSx for Lustre

- **Scratch deployment** for ephemeral workloads (no replication).
- **Persistent deployment** for long-term — SSD or HDD per latency vs throughput need.
- **LZ4 compression** — lossless, applies to new writes.
- **Link to S3** — lazy-load datasets from S3, return results, delete the Lustre fs.

### FSx for NetApp ONTAP

- **Capacity-pool tier** for infrequent data; auto-scaling.
- **Compression + dedup** via FabricPool's auto-tiering.

### Snapshots

- **Data Lifecycle Manager (DLM)** — automate EBS snapshot creation/retention/deletion.
- **Or Velero with TTL flags** — Kubernetes-native alternative.
- **Incremental snapshots** by default (only changed blocks billed).

### Container images

- **Distroless or scratch base images** — reduce host storage + attack surface.
- **Multi-stage Docker builds** — exclude unneeded layers from the final image.
- **Tune kubelet GC** — defaults: 5-min image cleanup, 1-min container cleanup.

## Operator Action Table

| Action | Current → Target | Tool |
|---|---|---|
| Migrate EBS volumes | gp2 → gp3 | EBS CSI driver v1.19.0+ (PVC annotations) or VolumeAttributesClass API (EKS v1.31+) |
| Automate snapshot lifecycle | Manual → DLM | AWS Data Lifecycle Manager console |
| Enable EFS tiering | None → Lifecycle policy (7-90d) | EFS console / API |
| Identify over-provisioned volumes | Manual → AWS Compute Optimizer | Review IOPS/throughput utilization over 14d |
| Monitor volume metrics | Not tracking → Baseline established | Enable CloudWatch metrics (disable `--vol-metrics-opt-in` on large EFS — memory risk) |
| Clean up dangling volumes | Ad-hoc → Automated | Trusted Advisor or Popeye scans |

## Actuate-specific applicability

See [[2026-04-27_eks-storage-applicability]] for the per-recommendation mapping to our fleet.

## Related

- [[2026-04-27_eks-storage-applicability]] — Actuate-specific extraction
- [[2026-04-27_s3-cost-optimization]] — companion source for the S3-specific gap in this doc
- [[cost-architecture]] — Actuate's compute / inference / data / delivery cost layers
- [[2026-04-23_s3-tier3-cost-investigation]] — our existing S3 cost research
