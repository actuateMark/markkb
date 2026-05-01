---
title: "S3 Intelligent-Tiering"
type: source
topic: aws-cost
tags: [aws, s3, intelligent-tiering, storage-class, cost-optimization, source]
url: "https://aws.amazon.com/s3/storage-classes/intelligent-tiering/"
ingested: 2026-04-27
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# S3 Intelligent-Tiering

Source: <https://aws.amazon.com/s3/storage-classes/intelligent-tiering/>

S3 Intelligent-Tiering moves objects between access tiers automatically based on observed usage. Best fit for "unknown, changing, or unpredictable access patterns" — not for workloads with stable access patterns where a fixed Standard-IA / Glacier choice would be cheaper net of monitoring fees.

(Distinct from the older [[s3-intelligent-tiering]] note in this same `sources/` dir, which covers the same ground from a different ingest. Cross-link, don't duplicate.)

## How it works

Three default tiers, transitions are automatic + retrieval-charge-free:

| Tier | Triggered after | Cost vs Standard |
|---|---|---|
| Frequent Access | (default placement) | baseline |
| Infrequent Access | 30 days no access | -40% |
| Archive Instant Access | 90 days no access | -68% |

If an object in IA / Archive Instant is accessed, it moves back to Frequent Access automatically.

## Optional opt-in archive tiers (asynchronous retrieval — restoration required before access)

| Tier | Triggered after | Cost vs Standard |
|---|---|---|
| Archive Access | 90 days no access | -71% |
| Deep Archive Access | 180 days no access | -95% |

These are NOT default; you opt in per bucket/prefix.

## Pricing model

- Small monthly **per-object monitoring + automation fee** plus standard storage charges.
- **Objects < 128 KB** are excluded from automatic tiering — they always sit at Frequent Access tier rates without monitoring charges.
- **No retrieval charges** between tiers within Intelligent-Tiering.
- **No minimum storage duration** (unlike Standard-IA's 30-day minimum).

## When it makes sense

- Data lakes / analytics with mixed hot/cold access.
- New apps without established access patterns.
- Buckets where the engineering cost of designing a manual lifecycle would exceed savings.

## When it does NOT make sense

- Stable, deterministic access patterns where Standard-IA / Glacier directly is cheaper net of monitoring fee.
- Buckets dominated by tiny objects (< 128 KB) — they never tier, but you still pay the monitoring fee.
- Short-lived objects (< 30 days) — they never reach IA, no savings, monitoring fee is pure overhead.

## Real-world results (per AWS)

- Shutterstock: 60% reduction on some buckets.
- Stripe: ~30%/month average savings.
- Cumulative customer savings: $6B+.

## Actuate applicability

- **NOT a fit for our 24h auto-delete frame buckets** (`all-frames-aegis-v2`, `aegis-all-frames-v2-<site>`). Objects expire before 30 days — they never reach Infrequent Access. Per-object monitoring fee is pure overhead.
- **Strong candidate for `actuate-2-month-storage` / `actuate-6-month-storage`** if access patterns are mixed/unknown. Currently using explicit Standard → Standard-IA → Deep Archive transitions; Intelligent-Tiering would auto-manage that. Worth modeling cost crossover.
- **Worth evaluating for any bucket > 128KB-objects-dominant + > 30 day retention + uncertain access.**
- **Storage Lens** ([[2026-04-27_s3-storage-lens]]) flags Intelligent-Tiering candidates automatically.

## Related

- [[2026-04-27_s3-cost-optimization]]
- [[2026-04-27_s3-storage-lens]] — how to find candidate buckets
- [[2026-04-27_s3-lifecycle-rules]] — manual alternative
- [[2026-04-23_s3-tier3-cost-investigation]] — our spend baseline
- [[s3-intelligent-tiering]] — earlier source note (same topic, different ingest)
- [[s3-glacier-deep-archive]] — companion archive-class source
