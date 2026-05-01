---
title: "S3 Incomplete-MPU Cleanup via Lifecycle"
type: source
topic: aws-cost
tags: [aws, s3, multipart, lifecycle, hidden-cost, source]
url: "https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-abort-incomplete-mpu-lifecycle-config.html"
ingested: 2026-04-27
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# S3 Incomplete-MPU Cleanup via Lifecycle

Source: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-abort-incomplete-mpu-lifecycle-config.html>

Incomplete multipart uploads (MPUs) are a stealth cost — uploaded parts persist indefinitely if the upload is initiated but never completed. They keep accruing storage charges until manually aborted or expired by lifecycle policy. **Easy to find and easy to fix** — should be a default rule on any bucket that accepts large-file uploads.

## Canonical lifecycle config

XML:

```xml
<LifecycleConfiguration>
  <Rule>
    <ID>cleanup-incomplete-mpu</ID>
    <Prefix></Prefix>
    <Status>Enabled</Status>
    <AbortIncompleteMultipartUpload>
      <DaysAfterInitiation>7</DaysAfterInitiation>
    </AbortIncompleteMultipartUpload>
  </Rule>
</LifecycleConfiguration>
```

JSON:

```json
{
  "Rules": [
    {
      "ID": "cleanup-incomplete-mpu",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7}
    }
  ]
}
```

## Apply via CLI

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket <bucket> \
  --lifecycle-configuration file://lifecycle.json

# Verify
aws s3api get-bucket-lifecycle-configuration --bucket <bucket>
```

## Discover existing orphans

```bash
aws s3api list-multipart-uploads --bucket <bucket>
```

Returns all in-progress uploads. Anything older than 7d is a clean abort candidate.

## Properties

- **No early-deletion penalty** — MPUs aren't subject to the storage-class minimum-duration penalties.
- **Applies to existing AND future uploads** matching the rule.
- **Scope control** — empty prefix targets all objects, or specify a prefix.
- **Safe** — only affects incomplete uploads; completed objects untouched.
- **Compatible with**: prefix filters only. NOT compatible with tag filters (per the broader [[2026-04-27_s3-lifecycle-rules]] mechanics doc).

## Actuate applicability

- **Audit candidate**: run `aws s3api list-multipart-uploads` across all our buckets; identify orphans and apply this rule wherever it's missing.
- **Default-on policy**: should be a baseline rule on every bucket that accepts uploads (conn frame buckets, customer-data, working-set, slicing). 7 days is a reasonable default; 1-3 for high-churn buckets.
- **Storage Lens** ([[2026-04-27_s3-storage-lens]]) flags this gap automatically — Free-tier metric.

## Related

- [[2026-04-27_s3-lifecycle-rules]] — broader lifecycle mechanics
- [[2026-04-27_s3-cost-optimization]]
- [[2026-04-27_s3-storage-lens]] — detects which of our buckets need this
- [[2026-04-23_s3-tier3-cost-investigation]] — current S3 spend baseline
