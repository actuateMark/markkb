---
title: "AWS Cost — Topic Spinoff + Right-Sizing Attack Plan (2026-04-27)"
type: synthesis
topic: aws-cost
tags: [synthesis, aws, cost, spinoff, attack-plan, s3, ebs, eks, right-sizing, runbook]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/syntheses/2026-04-28_s3-cost-reduction-action-plan.md
  - topics/personal-notes/notes/daily/2026-04-27.md
incoming_updated: 2026-05-01
---

# AWS Cost — Topic Spinoff + Right-Sizing Attack Plan (2026-04-27)

The KB now has a primary `aws-cost` topic. This synthesis captures (a) what was relocated/ingested into it on the spinoff day, and (b) a ranked attack plan for the actual right-sizing work, deferred to a future session per user direction.

## Why this exists

Cost research had accumulated across four topics with no single home: an S3 Tier3 investigation in `infrastructure`, a layered `cost-architecture` synthesis in `actuate-platform`, an AWS Cost Explorer access-pattern note in `engineering-process`, and S3 storage-class source notes in `fleet-architecture`. The fleet-arch rescore had cost as a scoring axis; the OOM-surge triage had surfaced config-drift signals; the operational dashboard had cost-flavored signals queued. Without a primary topic, the threads were scattered.

User trigger 2026-04-27: spin off cost-related work into its own topic, seeded with the AWS EKS storage cost-opt best-practices doc, with the goal of right-sizing S3 cost usage. Topic created same day with full cross-link reciprocity preserved.

## What landed today (16 files in `topics/aws-cost/`)

### Relocated (7) — basenames preserved so wikilinks still resolve

- [[2026-04-23_s3-tier3-cost-investigation]] (synthesis) — load-bearing $42k/yr Tier3 driver investigation, was in `infrastructure`
- [[2026-04-23_s3-tier3-breakdown]] (concept) — underlying bucket-level data
- [[cost-architecture]] (synthesis) — cross-topic cost layers, was in `actuate-platform`
- [[actuate-cost-analysis]] (entity) — internal EKS cost-analysis tool, was in `infrastructure`
- [[aws-cost-explorer-access-pattern]] (concept) — was in `engineering-process`
- [[s3-intelligent-tiering]] + [[s3-glacier-deep-archive]] (sources) — were in `fleet-architecture/sources`

### Newly ingested (6 sources + 1 concept)

- [[2026-04-27_eks-cost-opt-storage]] — the seed AWS EKS storage best-practices doc (EBS / EFS / FSx / snapshots / images)
- [[2026-04-27_s3-cost-optimization]] — S3 user-guide cost-opt landing
- [[2026-04-27_s3-storage-lens]] — analytics surface, **highest leverage for "right-sizing" because it surfaces gaps automatically**
- [[2026-04-27_s3-intelligent-tiering]] — auto-tiering deep-dive
- [[2026-04-27_s3-lifecycle-rules]] — rule mechanics + transition cadence + cost gotchas
- [[2026-04-27_s3-multipart-upload-cleanup]] — orphan-MPU cleanup recipe
- [[2026-04-27_eks-storage-applicability]] (concept) — Actuate-specific applicability of the EKS doc

### Topic scaffolding

- [[aws-cost/_summary]] — overview, current cost picture, topic map, active right-sizing threads, cross-references
- [[aws-cost/_dive-queue]] — 7 next sources + 5 internal investigations queued

### Cross-links added

- `infrastructure/_summary.md` → aws-cost (acknowledges relocation of cost work)
- `actuate-platform/_summary.md` → aws-cost
- `engineering-process/_summary.md` → aws-cost
- `fleet-architecture/_summary.md` → aws-cost
- `sales-dashboard.md` ↔ aws-cost (reciprocal — [[sales-dashboard]] surfaces per-site cost data; auth-walled live UI but schema is documented in the entity)

## Current cost picture (snapshot, ground truth as of 2026-04-23 investigation)

- **S3 spend ≈ $398k/yr.** Tier3 = $42k/yr (10.7%), driven by lifecycle-expiration on per-frame "24h auto-delete" buckets, NOT replication.
- **Compute (EKS connector layer):** dominated by per-site Deployments + VPA. Largest lever: camera [[sharding]] (`shard_size=24`); crossing a shard boundary is +50-80% CPU. ARM/Graviton ≈ 20% savings vs x86.
- **GPU inference:** YOLO via `ds-server-container` + Inferentia2 mix. VLM workloads diverge sharply.
- **VPA over-provisioning** (ENG-78, Highest, unassigned): 3-5× CPU + 2× memory waste vs actual. EKS 1.35 (ENG-79) would unlock in-place pod resize.
- **S3 Tier3 ceiling:** $30-60k/yr range to eliminate the per-frame write-and-delete pattern. This is COUPLED to fleet-arch direction (proposals D/E in [[fleet-architecture/_summary]]) — not a standalone quick-win.

## Recommended attack plan (ranked by ROI / friction)

### Tier 1 — visibility & free wins (do these first; minutes-to-hours of effort)

1. **Enable S3 Storage Lens Free tier.** ~5-min console toggle. Daily dashboard surfaces missing lifecycle rules, orphan MPUs > 7d, transition gaps, storage-class distribution. Wins are read-only insight before any structural change. Source: [[2026-04-27_s3-storage-lens]].
2. **Confirm `aegis-all-frames-v2-sts` lifecycle rule is re-enabled.** One CLI: `aws s3api get-bucket-lifecycle-configuration --bucket aegis-all-frames-v2-sts`. Was disabled per [[2026-04-23_oom-surge-connector-limit-drift]]. If still disabled, re-enable.
3. **Orphan multipart upload audit.** `aws s3api list-multipart-uploads` across all buckets (Bash loop). Anything > 7d → abort + add the canonical lifecycle rule. Recipe: [[2026-04-27_s3-multipart-upload-cleanup]].
4. **Trusted Advisor cost-optimization scan.** Free for paid AWS Support tiers. One read-only console action — produces dangling-volume + under-utilized-resource lists. Pairs with item 1 for orientation.

### Tier 2 — bounded audits with concrete deliverables (hours of effort, mostly read-only)

5. **EBS volume type audit (gp2 vs gp3).** Single AWS CLI describe-volumes pass. Output: count + total size on gp2. Sets up the gp3 migration plan.
6. **Per-bucket lifecycle policy audit.** Heuristic: every bucket with > $X spend should have either a lifecycle config or an explicit annotation. Could grow into a `/cost-check` recipe + `s3_lifecycle_rules_disabled` dashboard signal.
7. **AWS Compute Optimizer review.** 14d util data already exists; recommendations come "for free" (read-only console). Direct overlap with VPA over-provisioning (ENG-78).

### Tier 3 — bounded implementation (small PRs)

8. **DLM (EBS snapshot lifecycle).** Declarative Terraform policy. Reasonable defaults: 7 daily / 4 weekly / 12 monthly retention. Once written, applies to all volumes tagged for snapshotting.
9. **Add `AbortIncompleteMultipartUpload` to every bucket missing it.** Tooling: per-bucket `put-bucket-lifecycle-configuration`. Loop driven by Storage Lens output from Tier 1.
10. **Intelligent-Tiering candidate evaluation.** Cost-model `actuate-2-month-storage` + `actuate-6-month-storage` + any other > 30d retention bucket; only enable Intelligent-Tiering where cost crossover is favorable AND object-size distribution is mostly > 128 KB.

### Tier 4 — multi-PR / multi-week

11. **gp2 → gp3 migration plan.** Phased rollout. EKS v1.31+ in-place via VolumeAttributesClass; older clusters need volume-modify + restart. Up to 20% volume cost reduction. Gated on item 5 (audit).
12. **S3 frame-bucket structural rework** (the fleet-arch coupled item). $30-60k/yr ceiling. Belongs to fleet-arch direction selection (proposals D/E), not a standalone cost workstream.

### Out of scope here (tracked elsewhere or external)

- VPA right-sizing — ENG-78 (external, unassigned).
- EKS 1.35 in-place pod resize — ENG-79 (external, unassigned).
- Savings Plans / Reserved Instances — queued in [[aws-cost/_dive-queue]].
- ECR lifecycle policies — queued in [[aws-cost/_dive-queue]].

## Synthesis takeaways

1. **The biggest single lever is structural, not configurational.** $30-60k/yr from frame-bucket rework dwarfs every other line. But it's coupled to fleet-arch direction selection — not actionable as a standalone cost project.
2. **The biggest UNTAPPED lever is visibility.** S3 Storage Lens (Free tier) would have surfaced several gaps the [[2026-04-23_s3-tier3-cost-investigation]] had to discover by hand. Enabling it before any structural change yields ongoing automated audit at zero cost.
3. **EBS / EFS / snapshots get less attention than S3** because EBS/EFS spend hasn't been quantified yet. Item 5 (audit) closes that loop.
4. **The AWS EKS storage cost-opt doc has no S3 guidance.** Its strength is EBS/EFS/snapshots/images — categories where Actuate hasn't done much. Pair it with the S3-specific sources for full coverage.
5. **The dive-queue is where future research goes.** S3 Inventory, Compute Optimizer, Savings Plans, ECR lifecycle, gp3 migration — all queued, not blocking.

## Pickup tomorrow / future session

Per user direction 2026-04-27: this work attacks as a proper todo tomorrow. First action when picked up should be **Tier 1 item 1 (Storage Lens Free)** — it's the lowest-friction step that sets up the rest with automated visibility. The Today's Scope entry on 2026-04-27 marks the spinoff complete; the Morning Follow-Ups block has a seed for 2026-04-28 to pick up.

## Related

- [[aws-cost/_summary]] — topic overview, all current cost-research
- [[aws-cost/_dive-queue]] — queued sources + investigations
- [[2026-04-23_s3-tier3-cost-investigation]] — load-bearing prior research
- [[cost-architecture]] — Actuate's cost layer map
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — where the structural-rework cost ceiling was last refined
- [[2026-04-23_oom-surge-connector-limit-drift]] — surfaced the `s3_lifecycle_rules_disabled` config-drift signal candidate
- [[skill-cost-check]] — operational primary for ad-hoc cost queries
