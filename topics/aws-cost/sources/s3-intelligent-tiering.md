---
title: "Source: Manage S3 Storage Costs with S3 Intelligent-Tiering"
type: source
topic: aws-cost
tags: [source, s3, storage-cost, intelligent-tiering, tiering, frame-storage]
url: https://aws.amazon.com/blogs/storage/manage-amazon-s3-storage-costs-granularly-and-at-scale-using-s3-intelligent-tiering/
ingested: 2026-04-21
author: kb-bot
---

# Manage S3 Storage Costs with S3 Intelligent-Tiering

## What It Is

S3 Intelligent-Tiering (S3-IT) automatically moves objects between access tiers based on observed access patterns, eliminating manual lifecycle rules on unpredictably-accessed data. A small per-object monitoring fee is charged monthly; **objects below 128 KB are exempt from this fee**.

## Tier Transition Schedule

| Tier | Transition Condition | Retrieval Latency |
|------|---------------------|-------------------|
| Frequent Access | Default (new objects) | ms |
| Infrequent Access | No access for **30 days** | ms |
| Archive Instant Access | No access for **90 days** | ms |
| Archive Access (opt-in) | 90+ days (configurable) | 3–5 hours |
| Deep Archive Access (opt-in) | **180+ days** (configurable) | ≤12 hours |

## Critical Threshold: 128 KB Minimum Object Size

Objects **below 128 KB** are exempt from the per-object monitoring fee — but they **also do not benefit from tiering**. They remain billed at Frequent Access rates regardless of access frequency. Our target JPEG frames sit at approximately 150 KB, which is **just above the threshold**: they qualify for monitoring and tiering, but the margin is thin. **Any compression run that reduces frames below 128 KB eliminates tiering benefit.**

## Cost Interaction with Per-Frame PUT Pattern

S3-IT **does not reduce API call costs** — each PUT is charged the same as S3 Standard (~$0.005/1,000 PUTs). The current 22-call-per-window pattern would be entirely unaffected by tiering class. S3-IT is a **storage cost lever, not an API cost lever.** At our write volumes, S3 API spend will dominate over storage costs until the API-call count problem is solved first.

## Suitability for Video Surveillance Workloads

For long-retention alert clips where access frequency drops sharply after the first 24–72 hours (operator review window), S3-IT is well-suited: clips will naturally migrate to Infrequent Access (30d) and Archive Instant Access (90d) without manual lifecycle management. The no-retrieval-charge model is attractive for operator-requested clip reviews that fall within the Archive Instant tier. The 12-hour Deep Archive Access tier is **unsuitable** for operator-driven retrieval.

## Relevance to Fleet Proposals

- **A** (status quo per-frame S3): No benefit — API call count unchanged; monitoring fee adds cost per frame.
- **B** (in-process encoding, clip-per-window): Highly relevant. Encoded clips are larger objects (well above 128 KB); tiering savings meaningful; Archive Instant Access aligns with "30-day hot review, then cold" retention.
- **C** (in-cluster blob + conditional promotion): Relevant to the promoted subset only. Promoted clips should use S3-IT or explicit lifecycle rules.
- **D** (event-driven): Same as B/C — clips tier well; retained keyframes need size audit against 128 KB floor.
- **E** (hybrid): Same lifecycle considerations post-upload.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: S3-IT is a natural lifecycle policy for encoded clips. Clips sized in the MB range benefit cleanly from tiering; no 128 KB floor concern.
- **In-cluster blob + conditional promotion (§12)**: For conditional promotion, S3-IT on promoted objects handles the retention tail. Non-promoted frames never reach S3 — the bigger win.
- **API-call cost structure**: **No impact.** Tiering is orthogonal to PUT/GET request pricing. S3-IT is a secondary lever that applies only after the primary API-call-count problem is resolved.

## Source
https://aws.amazon.com/blogs/storage/manage-amazon-s3-storage-costs-granularly-and-at-scale-using-s3-intelligent-tiering/
