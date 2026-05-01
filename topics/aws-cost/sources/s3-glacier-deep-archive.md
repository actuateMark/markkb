---
title: "Source: New Amazon S3 Glacier Deep Archive"
type: source
topic: aws-cost
tags: [source, s3, glacier, deep-archive, storage-cost, long-retention, frame-storage]
url: https://aws.amazon.com/blogs/aws/new-amazon-s3-storage-class-glacier-deep-archive/
ingested: 2026-04-21
author: kb-bot
---

# New Amazon S3 Glacier Deep Archive

## What It Is

S3 Glacier Deep Archive (GDA) is AWS's lowest-cost storage tier, at approximately **$0.00099/GB/month** (us-east-1) — roughly 75% cheaper than S3 Glacier Flexible Retrieval (~$0.004/GB/month) and ~23× cheaper than S3 Standard (~$0.023/GB/month). Designed for data accessed at most once or twice per year with retrieval SLAs measured in hours.

## Key Constraints

| Parameter | Value |
|-----------|-------|
| Storage cost (us-east-1) | ~$0.00099/GB/month |
| Standard retrieval SLA | **12 hours** |
| Bulk retrieval SLA | **48 hours** |
| Minimum storage duration | **180 days** (billed even if deleted earlier) |
| Metadata overhead | 8 KB at Standard rates + 32 KB at GDA rates per object |
| Transition methods | Direct PUT, lifecycle rule, or S3-IT opt-in at 180d |

## Break-Even vs S3 Intelligent-Tiering

S3-IT Deep Archive Access tier activates at **180 days** at the same ~$0.00099/GB/month rate. Practical distinction is retrieval model: S3-IT Deep Archive Access still requires restore-before-read (12h SLA), same as standalone GDA. For objects stored continuously past 180 days without access, costs are **functionally equivalent**. Advantage of explicit GDA is determinism — you guarantee the cheaper rate without waiting for tiering engine to observe non-access.

For alert clips with a **30-day hot review window** followed by **indefinite retention**: store in S3 Standard or S3-IT for 30 days, lifecycle-transition to GDA. Cost crossover vs keeping in S3 Standard: approximately **day 2–3** of storage.

## Retrieval SLA — Critical Disqualifier for Operator Use Cases

**The 12-hour Standard SLA is unacceptable for operator-requested clip review** ("show me footage from 3 weeks ago"). This limits GDA to pure compliance/legal-hold retention where clips are never expected to be reviewed interactively. For any UI-accessible clip, Archive Instant Access (S3-IT, ms retrieval) or S3 Glacier Instant Retrieval ($0.004/GB, ms retrieval) is the floor.

## Interaction with API Call Volume

GDA does not change PUT costs during write — identical to S3 Standard for initial ingestion. Restore operations add a per-request fee on retrieval. **For our workload, GDA is relevant only for the terminal tier of already-reduced write volumes** — it does not address the primary 22-calls-per-window problem.

## Relevance to Fleet Proposals

- **A** (status quo): Could apply GDA lifecycle to old frames, but API call cost unchanged; storage savings marginal given frame sizes.
- **B** (in-process encoding): Ideal terminal tier for encoded alert clips after operator review window. Clips MB-scale, 180-day minimum acceptable for compliance.
- **C** (in-cluster blob + conditional promotion): Promoted clips are the GDA target. Non-promoted frames never leave cluster — GDA irrelevant for them.
- **D** (hybrid): Same as B — terminal tier for encoded clips post-review-window.
- **E** (edge): Post-upload lifecycle same as B/C.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: GDA is the recommended terminal tier for encoded clips held for compliance (>30 days). Pair with a 30-day lifecycle rule.
- **In-cluster blob + conditional promotion (§12)**: GDA applies only to the promoted-object tail. Primary cost reduction (not promoting non-eventful frames) dwarfs any GDA savings.
- **API-call cost structure**: **No interaction.** GDA is a storage-rate lever; API-call reduction must happen upstream via encoding or conditional promotion.

## Source
https://aws.amazon.com/blogs/aws/new-amazon-s3-storage-class-glacier-deep-archive/
