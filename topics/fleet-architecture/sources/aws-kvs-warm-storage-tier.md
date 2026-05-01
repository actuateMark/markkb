---
title: "Source: AWS KVS Warm Storage Tier — Optimizing Long-Term Video Storage Costs"
type: source
topic: fleet-architecture
tags: [source, aws, kvs, kinesis-video-streams, s3, fragment, warm-storage, cost, tiering]
url: https://aws.amazon.com/blogs/iot/optimize-long-term-video-storage-costs-with-amazon-kinesis-video-streams-warm-storage-tier/
ingested: 2026-04-21
author: kb-bot
---

# AWS KVS Warm Storage Tier — Optimizing Long-Term Video Storage Costs

AWS IoT Blog (2026-01) on the KVS dual-tier architecture. Closest published external analogue to our detection-window-to-clip pipeline design.

## Architecture Mechanics

KVS operates on a **fragment-based model**: the stream is segmented into fixed-duration fragments (producer-configured). Each fragment is the atomic unit of storage, billing, and retrieval. Two tiers:

- **Hot tier**: Real-time streaming; GB-based ingestion billing; for live viewing.
- **Warm tier**: Long-term retention backed by S3 Standard-IA; **billed per 1,000 fragments ingested (not per GB)**. 30-day minimum retention floor.

Tier selection is **stream-wide and static** — set at stream creation or changed globally. **No per-fragment conditional routing.**

## Cost Mechanics — Fragment Duration Is the Key Variable

Warm-tier ingestion cost is per fragment (fixed per-API-call pricing), making fragment duration the dominant cost lever:

| Fragment duration | Warm-tier savings vs hot |
|---|---|
| 2 s | 28% |
| 5 s | 48% |
| 20 s | 57% |

**Break-even vs hot tier: 1.06-second fragments.** Longer fragments spread the fixed per-call cost over more data bytes, improving efficiency — exactly the same insight as our §11 API-call-per-frame analysis.

At 4 Mbps, 1,000 cameras, 30-day retention, 5-second fragments: **$6,888/month warm vs $13,155/month hot.**

## Critical Mismatch with Our Design

KVS warm tier is **non-selective, stream-wide** — no detection-gated promotion. To implement §12 conditional promotion on top of KVS, you would need:

1. Ingest all frames to KVS hot tier (paying for non-eventful frames)
2. Extract eventful sub-fragments via `GetMediaForFragmentList` and re-upload
3. Accept 30-day minimum retention cost on all hot-tier data

**This defeats the primary cost goal of §12.** KVS warm tier is architecturally incompatible with conditional-promotion-only semantics.

## The Fragment-Duration Insight Is Transferable

The economic principle — **longer segments amortize per-API-call costs over more data** — directly validates §11's analysis. Our current 10-frame-per-PUT pattern is the worst case (each frame is its own "fragment"). A single encoded clip PUT is the optimal case (one "fragment" = one window).

## Relevance to Fleet Proposals

- **A — Minimal Split**: Not directly applicable. Fragment-duration insight reinforces that A's in-process encoding path is cost-optimal.
- **B — Stage Fleets**: Lesson warns against using S3 as inter-stage frame handoff (recreates per-frame PUT problem).
- **C — Camera-Worker**: Fragment-duration principle applies: each worker accumulates frames in-memory until window close, emits one PUT.
- **D — Event-Driven**: **NATS JetStream is a closer analogue to KVS's fragment model than S3 per-frame writes.** Warm-tier economics validate D's framing that the buffer layer should emit single objects to S3, not per-frame writes.
- **E — Hybrid Sidecar**: Lesson reinforces promoting only eventful windows as single encoded objects is the right cost shape.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: Strongly validates §11's API-call cost framing. KVS fragment-duration cost table is the external proof point that per-API-call pricing dominates over per-byte at scale.
- **In-cluster blob + conditional promotion (§12)**: KVS is architecturally misaligned. This source confirms KVS is NOT a drop-in for §12. Design must be custom.
- **API-call cost structure**: KVS's per-fragment billing is the same economic structure as S3 per-PUT pricing. Break-even tables directly analogous.

## Source
https://aws.amazon.com/blogs/iot/optimize-long-term-video-storage-costs-with-amazon-kinesis-video-streams-warm-storage-tier/
