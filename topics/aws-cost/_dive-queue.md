---
title: "AWS Cost — Dive Queue"
type: dive-queue
topic: aws-cost
tags: [dive-queue, aws, cost, research-pipeline]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# AWS Cost — Dive Queue

Sources + investigations queued for ingest. Process via `/kb-queue` or one-off `/kb-ingest <url>`. Items are removed once ingested into the topic.

## Already-ingested 2026-04-27 (initial topic seed)

- ✅ AWS EKS Best Practices: cost-opt storage → [[2026-04-27_eks-cost-opt-storage]]
- ✅ AWS S3 user-guide: cost optimization → [[2026-04-27_s3-cost-optimization]]
- ✅ AWS S3 Storage Lens → [[2026-04-27_s3-storage-lens]]
- ✅ S3 Intelligent-Tiering deep-dive → [[2026-04-27_s3-intelligent-tiering]]
- ✅ S3 Lifecycle rule mechanics → [[2026-04-27_s3-lifecycle-rules]]
- ✅ S3 Incomplete-MPU cleanup → [[2026-04-27_s3-multipart-upload-cleanup]]

## Next sources to ingest (AWS docs)

- [ ] **S3 Inventory** — `https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-inventory.html`. Builds a daily/weekly object-level inventory CSV. Useful for: orphan-MPU discovery at scale, lifecycle-policy gap audit, storage-class distribution per prefix.
- [ ] **S3 Replication cost** — `https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-overview.html` + `https://aws.amazon.com/s3/pricing/`. Cross-region replication has data-transfer + replicated-storage costs that are easy to under-budget. We confirmed 0 ReplicationConfigurations in the Tier3 investigation, but worth understanding the pricing model in case it's proposed for fleet redundancy.
- [ ] **AWS Cost Explorer pricing model** — `https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ce-what-is.html`. CE itself charges per API call; our `/cost-check` skill could grow guardrails.
- [ ] **AWS Compute Optimizer** — `https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html`. Recommends EBS / EC2 / Lambda right-sizing based on 14d util data. Direct overlap with VPA over-provisioning (ENG-78).
- [ ] **EBS gp3 migration via VolumeAttributesClass** — EKS v1.31+ feature; the canonical migration path the EKS doc points at.
- [ ] **AWS Savings Plans + Reserved Instances** — `https://aws.amazon.com/savingsplans/`. We don't currently use either at-scale; could be material on our compute spend.
- [ ] **ECR lifecycle policies** — `https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html`. We have multiple ECR repos (`arm_connector_rearch`, `connectors_rearch`, model images, etc.). Image accumulation is a stealth cost.

## Internal investigations to commission

- [ ] **Confirm `aegis-all-frames-v2-sts` lifecycle rule status** — was disabled per [[2026-04-23_oom-surge-connector-limit-drift]]; needs re-enable verification. One-shot via `aws s3api get-bucket-lifecycle-configuration --bucket aegis-all-frames-v2-sts`.
- [ ] **Per-bucket lifecycle policy audit** — heuristic-driven: every bucket with > $X spend / month should have either a lifecycle config or an explicit "no-lifecycle-needed" annotation. Could grow into a `/cost-check` recipe + dashboard signal.
- [ ] **Orphan multipart upload audit** — fleet-wide via `aws s3api list-multipart-uploads`; correlate with bucket spend.
- [ ] **EBS dangling-volume scan** — Trusted Advisor + Popeye approach (per [[2026-04-27_eks-cost-opt-storage]]).
- [ ] **Connector pod headroom-vs-OOM correlation** — cross-cuts §9 dashboard signal `connector_pod_headroom_over_70pct`. Not strictly cost, but related (over-provisioning is cost waste, under-provisioning is OOM waste).

## Synthesis candidates

Once 4-5 internal investigations land, fold into:

- [ ] **`2026-XX_actuate-s3-cost-optimization-roadmap.md`** — synthesis combining the [[2026-04-23_s3-tier3-cost-investigation]] findings with the AWS lifecycle/intelligent-tiering recipes. Should produce a prioritized to-do list (rule audit → orphan-MPU sweep → lifecycle gaps → intelligent-tiering candidates → frame-bucket structural rework).
- [ ] **`2026-XX_actuate-ebs-migration-plan.md`** — gp2 → gp3 migration for the EKS fleet, with rollout phases and expected savings.
- [ ] **`2026-XX_compute-cost-rightsizing.md`** — VPA + Compute Optimizer + EKS 1.35 + Savings Plans as a unified compute-cost track.
