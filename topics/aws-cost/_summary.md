---
title: "AWS Cost"
type: summary
topic: aws-cost
tags: [aws, cost, billing, s3, ebs, eks, fleet-architecture, cost-optimization, storage]
created: 2026-04-27
updated: 2026-04-29
author: kb-bot
---

# AWS Cost

The single home for Actuate's AWS cost research, investigations, and right-sizing work. Spun off 2026-04-27 from `infrastructure`, `actuate-platform`, `engineering-process`, and `fleet-architecture` to give cost a primary topic with its own dive queue and synthesis cadence. Existing notes were relocated; their basenames are preserved so wikilinks elsewhere in the KB still resolve.

## Current Cost Picture (2026-04-23 snapshot)

- **S3 spend ≈ $398k/yr** (annualized from 30d window). Tier3 requests = ~$42k/yr (10.7% of S3); driven by lifecycle-expiration on per-frame "24h auto-delete" buckets, NOT replication. Full breakdown: [[2026-04-23_s3-tier3-cost-investigation]] · data: [[2026-04-23_s3-tier3-breakdown]].
- **Compute (EKS connector layer):** dominated by per-site Deployment + VPA. The largest cost lever is camera [[sharding]] (`shard_size=24`) — crossing a shard boundary costs +50-80% CPU, so packing more cameras per shard saves materially. ARM/Graviton offers ~20% savings vs x86. See [[cost-architecture]] § "EKS Compute".
- **GPU inference:** YOLO via `ds-server-container` + Inferentia2 mix. VLM workloads diverge sharply in cost profile. See [[cost-architecture]] § "GPU Inference".
- **VPA over-provisioning:** ENG-78 documents 3-5× CPU and 2× memory waste vs actual utilization across hundreds of deployments. EKS 1.35 (ENG-79) would unlock in-place pod resize.

## Topic Map

### Investigations + analysis
- [[2026-04-28_s3-cost-reduction-action-plan]] — **ranked action plan** with savings × effort × confidence × standalone table across 12 levers. Tracked under ENG-183 (parent) + ENG-184…ENG-194 (sub-tasks). Plan file: `~/.claude/plans/methodical-pruning-oak.md`.
- [[2026-04-27_aws-cost-topic-spinoff]] — topic spinoff + tier-1/2/3/4 attack plan (predecessor to the action plan above)
- [[2026-04-23_s3-tier3-cost-investigation]] — load-bearing S3 cost-driver investigation (Apr 2026)
- [[2026-04-23_s3-tier3-breakdown]] — underlying bucket-level data
- [[cost-architecture]] — layered cost map across EKS / GPU / data / delivery

### Operational tooling
- [[actuate-cost-analysis]] — internal EKS cost-analysis tool (deployed via [[kubernetes-deployments]])
- [[sales-dashboard]] — surfaces per-site daily cost roll-up (compute / inference / slicing / storage) to the team. Pulls from a daily S3 CSV feed.
- [[skill-cost-check]] — `/cost-check` skill: AWS Cost Explorer queries via the `prod` profile, NR-style aggregation discipline. The operational primary for ad-hoc cost queries.
- [[aws-cost-explorer-access-pattern]] — concept note on querying Cost Explorer

### Concepts (cost-mechanics primers)
- [[2026-04-27_eks-storage-applicability]] — Actuate-specific applicability of AWS's EKS storage cost-opt best-practices (gp3 migration, EFS-IA, snapshot lifecycle, dangling-volume cleanup)

### Sources (ingested AWS docs)
- [[2026-04-27_eks-cost-opt-storage]] — AWS EKS Best Practices: storage cost optimization (EBS / EFS / FSx / snapshots)
- [[2026-04-27_s3-cost-optimization]] — AWS S3 user-guide: cost optimization landing page
- [[2026-04-27_s3-storage-lens]] — AWS S3 Storage Lens analytics
- [[2026-04-27_s3-intelligent-tiering]] — S3 Intelligent-Tiering deep-dive
- [[2026-04-27_s3-lifecycle-rules]] — S3 Lifecycle rule mechanics + transition patterns
- [[2026-04-27_s3-multipart-upload-cleanup]] — Incomplete-MPU cleanup via lifecycle
- [[s3-intelligent-tiering]] — earlier source note (relocated from fleet-arch)
- [[s3-glacier-deep-archive]] — earlier source note (relocated from fleet-arch)
- [[2026-04-29_minio-self-hosted-s3-tutorial]] — pavloshargan gist on self-hosted MinIO; reviewed against action plan, **no net-new actions** (hobbyist scope), but reinforced egress-dominance framing

## Active Right-Sizing Threads

| Surface | Status | Owner |
|---|---|---|
| **S3 frame-bucket Tier3 reduction** | Coupled to fleet-arch direction (in-cluster blob + conditional promotion, proposals D/E in [[fleet-architecture/_summary]]). Not a standalone quick-win. Savings ceiling $30-60k/yr. | tracked in fleet-architecture |
| **`aegis-all-frames-v2-sts` lifecycle rule disabled** | OOM-surge triage 2026-04-23 surfaced this as config-drift. §9 dashboard signal `s3_lifecycle_rules_disabled` is candidate. Need confirmation it's been re-enabled. | open |
| **gp2 → gp3 EBS migration** | 20% volume cost reduction; AWS-recommended default. Not yet planned for our EKS fleet. | not started |
| **EBS snapshot lifecycle (DLM)** | Not yet adopted; manual snapshot management today. | not started |
| **EFS Infrequent-Access tiering** | Up to 92% saving on 7-90d unaccessed files. EFS surface area in our fleet TBD. | not started |
| **Dangling EBS volume scan** | Trusted Advisor + Popeye candidate; no ongoing audit today. | not started |
| **VPA right-sizing** | Tracked under ENG-78 (Highest, unassigned). 3-5× CPU / 2× memory waste. | external |
| **EKS 1.35 in-place pod resize** | ENG-79 (also unassigned). Eliminates VPA eviction restarts. | external |

## Cross-References (cost as a factor, primary topic elsewhere)

- [[fleet-architecture/_summary]] — proposals A-E include cost as a scoring axis. [[2026-04-22_fleet-proposal-rescore-with-delta]] is the canonical rescore (cost-axis ceiling refinement).
- [[product-roadmap/_summary]] — cost concerns surface in [[improvement-opportunities]] and [[active-risks]].
- [[vms-connector/_summary]] — performance-optimization landscape touches cost via memory/CPU sizing.
- [[video-processing/_summary]] — `aws-video-services-decision-matrix` weighs build-vs-buy with cost.
- [[infrastructure/_summary]] — VPA, K8s, storage primitives the cost work attaches to.

## See Also

- `~/.claude/skills/cost-check/SKILL.md` — `/cost-check` skill source
- `aegissystems/actuate-cost-analysis` — repo for the internal EKS cost-analysis tool
- `aegissystems/sales-dashboard` — repo for the per-site cost dashboard
