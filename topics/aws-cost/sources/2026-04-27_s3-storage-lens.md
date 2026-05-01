---
title: "AWS S3 Storage Lens"
type: source
topic: aws-cost
tags: [aws, s3, storage-lens, analytics, cost-optimization, source]
url: "https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage_lens.html"
ingested: 2026-04-27
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# AWS S3 Storage Lens

Source: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage_lens.html>

Organization-wide S3 analytics. Aggregates metrics across the entire AWS environment + delivers actionable insights through dashboards + automated reports. **Most useful surface for "right-sizing S3 cost usage" because it programmatically detects gaps that we'd otherwise need bespoke `/cost-check` recipes for** — missing lifecycle rules, orphan multipart uploads, transitions-not-yet-applied, etc.

## What it surfaces

- **Storage usage trends** — fastest-growing buckets/prefixes.
- **Storage class distribution** — objects eligible for transition to lower-cost tiers.
- **Request patterns** — per-bucket activity to optimize performance.
- **Cost optimization opportunities:**
  - Missing S3 Lifecycle rules.
  - Incomplete multipart uploads older than 7 days.
  - Lifecycle expiration/transition gaps.
- **Data protection compliance** — buckets lacking Replication, Versioning, encryption, or Object Lock.

## Drill-down levels

Organization → Account → AWS Region → Storage class → Bucket → Prefix → Custom group.

## Free vs Advanced tiers

| | Free | Advanced (paid) |
|---|---|---|
| Summary metrics | ✓ | ✓ |
| Cost-opt + data-protection metrics | basic | expanded |
| Activity metrics + status-code metrics | — | ✓ |
| Prefix aggregation | 1%, ≤10 levels | up to 50 levels, billions of prefixes |
| Recommendations | — | contextual |
| CloudWatch publish | — | ✓ (alarms, anomaly detection, metric math) |

## Output options

- **Interactive dashboards** in S3 console (default dashboard is preconfigured + free).
- **Daily CSV/Parquet reports** to an S3 bucket.
- **AWS-managed S3 table bucket** (`aws-s3`) for analytics services.
- **CloudWatch integration** (Advanced tier) for unified alerting.

## Operator use cases

1. **Cost optimization** — buckets without lifecycle rules; transition candidates.
2. **Performance tuning** — high error rates, small-object collections, suboptimal request patterns.
3. **Compliance + security** — encryption / versioning / replication / Object Lock coverage.
4. **Capacity planning** — fastest-growing buckets / forecast.
5. **Operational monitoring** — CloudWatch alerting on anomalies.

## Enabling

S3 console (default dashboard preconfigured) · AWS CLI · SDKs · S3 REST API. Custom dashboards can be scoped by region, bucket, or account (AWS Organizations).

## Actuate applicability

We don't currently use Storage Lens. The Free tier alone would surface several of our open right-sizing threads: missing lifecycle rules across our many frame buckets, orphan-MPU detection, storage-class distribution per prefix. **Recommended next step:** enable the Free tier dashboard and run for ~30 days; promote to Advanced if specific signals (CloudWatch alarms on anomalies) earn it.

## Related

- [[2026-04-27_s3-cost-optimization]] — landing page that points here
- [[2026-04-27_s3-lifecycle-rules]] — what Storage Lens flags as missing
- [[2026-04-27_s3-multipart-upload-cleanup]] — what Storage Lens flags after 7 days
- [[2026-04-23_s3-tier3-cost-investigation]] — our existing investigation; Storage Lens would have surfaced several of the same patterns automatically
- [[skill-cost-check]] — our current ad-hoc cost surface
