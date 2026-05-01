---
title: "S3 Lifecycle Rules — Mechanics + Patterns"
type: source
topic: aws-cost
tags: [aws, s3, lifecycle, transitions, expiration, source]
url: "https://docs.aws.amazon.com/AmazonS3/latest/userguide/intro-lifecycle-rules.html"
ingested: 2026-04-27
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# S3 Lifecycle Rules — Mechanics + Patterns

Source: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/intro-lifecycle-rules.html>

The mechanics doc for S3 Lifecycle. Up to **1,000 rules per bucket**, XML config with metadata + filter + actions. The single highest-leverage cost surface for our S3 spend (per [[2026-04-23_s3-tier3-cost-investigation]], lifecycle-expiration on per-frame buckets is the dominant Tier3 driver — understanding rule mechanics is essential before any rework).

## Rule structure

1. **Metadata** — unique ID (≤255 chars), Status (`Enabled` / `Disabled`).
2. **Filter** — prefix, tags, object-size range, or `<And>` combinations.
3. **Actions** — Transition or Expiration, at specified dates / days.

## Actions

- **Transition** — move to another storage class at age threshold. For versioned buckets, applies to current version only.
- **Expiration** — delete or mark-for-delete. Behavior depends on versioning:
  - Non-versioned → permanent deletion.
  - Versioning-enabled → creates delete marker; original retained as noncurrent.
  - Versioning-suspended → null-version delete marker, replaces existing null version.
- **NoncurrentVersionTransition / Expiration** — for versioned buckets; gated on `<NoncurrentDays>` AND `<NewerNoncurrentVersions>` (1-100).
- **AbortIncompleteMultipartUpload** — clean up orphan MPU parts. Detail: [[2026-04-27_s3-multipart-upload-cleanup]].
- **ExpiredObjectDeleteMarker** — remove delete markers when zero noncurrent versions exist.

## Filter examples

```xml
<Filter><Prefix>logs/</Prefix></Filter>

<Filter><Tag><Key>archive</Key><Value>true</Value></Tag></Filter>

<Filter>
  <And>
    <Prefix>projects/</Prefix>
    <Tag><Key>env</Key><Value>prod</Value></Tag>
    <Tag><Key>retain</Key><Value>7years</Value></Tag>
  </And>
</Filter>

<Filter>
  <And>
    <ObjectSizeGreaterThan>500</ObjectSizeGreaterThan>
    <ObjectSizeLessThan>64000</ObjectSizeLessThan>
  </And>
</Filter>
```

**Note:** objects < 128 KB don't transition by default; set an explicit smaller minimum if needed.

## Canonical transition cadence + minimums

Standard → Standard-IA → Intelligent-Tiering → Glacier → Deep Archive. Minimum storage durations:

| Storage class | Minimum |
|---|---|
| Standard-IA / One Zone-IA | 30 days |
| Glacier Flexible / Instant | 90 days |
| Deep Archive | 180 days |

Transitions before the minimum incur **early-deletion fees**.

## Timing semantics

- **Age-based rules** — S3 adds the day count to creation/modification time, then **rounds up to the next midnight UTC** for the actual transition. Object created `2014-01-15 10:30 UTC` + 3d → fires `2014-01-19 00:00 UTC`.
- **Date-based rules** — must be ISO 8601 midnight UTC. The rule keeps applying after the date passes (matches future objects too). Past dates trigger immediate eligibility.
- **Noncurrent calculations** — based on the SUCCESSOR version's creation date, not the original object's date. New version on 1/15 → 1/15 is when noncurrent counting starts for the prior version.

## Gotchas (collated for the cost lens)

| Gotcha | Cost implication |
|---|---|
| Transitions cost money (per-PUT charge) | High-churn buckets accumulate transition fees rapidly — exactly the per-frame pattern we saw |
| Minimum-duration penalties | Don't transition Standard-IA/Glacier earlier than minimums |
| `AbortIncompleteMultipartUpload` incompatible with tag filters | Use prefix-only or no filter for orphan-MPU rules |
| `ExpiredObjectDeleteMarker` incompatible with tag filters | Use prefix-only |
| Lifecycle is eventually consistent | Recovery procedures must be aware (use copy-old-version method, not delete-current) |
| Retroactive: applies to future evaluations of all matching objects | Adding a rule does not retroactively penalize already-aged objects, but it WILL apply on next evaluation |
| < 128 KB objects don't auto-transition | Explicit smaller minimum required |

## Actuate applicability

- The **Tier3 driver** in [[2026-04-23_s3-tier3-cost-investigation]] is exactly the per-PUT transition charge above, applied to per-frame buckets where every write is paired with a 24h-later expiration.
- Our `actuate-2-month-storage` + `actuate-6-month-storage` use explicit Standard → Standard-IA → Deep Archive cadence (per the existing investigation) — they are well-aligned with the canonical pattern.
- **Open audit:** cross-check that our < 128 KB objects (small frames? thumbnails?) aren't excluded silently from intended transitions. Use S3 Storage Lens ([[2026-04-27_s3-storage-lens]]) to surface.
- **Open audit:** confirm `aegis-all-frames-v2-sts` lifecycle rule is re-enabled (was disabled per [[2026-04-23_oom-surge-connector-limit-drift]]).

## Related

- [[2026-04-27_s3-cost-optimization]]
- [[2026-04-27_s3-multipart-upload-cleanup]] — uses AbortIncompleteMultipartUpload action
- [[2026-04-27_s3-storage-lens]] — surfaces missing lifecycle rules
- [[2026-04-27_s3-intelligent-tiering]] — alternative auto-managed approach
- [[2026-04-23_s3-tier3-cost-investigation]]
