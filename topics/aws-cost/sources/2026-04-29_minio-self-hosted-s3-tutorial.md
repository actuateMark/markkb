---
title: "Self-hosted MinIO at home as S3 alternative (pavloshargan gist)"
type: source
topic: aws-cost
tags: [minio, self-hosted, s3, egress-cost, hobbyist, dev-only]
url: "https://gist.github.com/pavloshargan/15489a5060a5c20ab266d71c0dfe398f"
ingested: 2026-04-29
author: kb-bot
---

# Self-hosted MinIO at home as S3 alternative

GitHub gist by Pavlo Shargan. Tutorial-style write-up walking through a Windows-based MinIO server on a home network to avoid AWS S3 charges for a personal video-processing project (300-800 GB working set).

## What it covers

- **Cost framing** — author's premise: an example workload of 4 TB stored + 4 TB downloaded/month projects to ~$462/month on AWS S3 ($94 storage at $0.023/GB up-to-50TB-tier + $369 egress at $0.09/GB), versus a one-time ~$92 for a 4 TB external HDD. Egress dominates storage by ~4×.
- **Setup recipe** — NoIP dynamic-DNS, port-9000 forwarding on home router, MinIO Windows binary install, Certbot for Let's Encrypt SSL, MinIO `--certs-dir` placement, S3-compatible boto3 client points at the NoIP hostname instead of `s3.amazonaws.com`.
- **Caveats author flags** — ISP bandwidth ceiling on transfer-heavy workloads, manual backup responsibility on consumer-grade HDDs.

## Why this was reviewed

User flagged it during the morning routine as potential input to the [[2026-04-28_s3-cost-reduction-action-plan]] S3-cost-reduction work for the Actuate prod fleet.

## Reconciliation against the action plan

**No net-new actions.** The gist's premise (consumer-grade self-hosted MinIO on home Windows + NoIP DDNS) is a hobbyist solution and does not transfer to enterprise infrastructure. None of the 12 actions in [[2026-04-28_s3-cost-reduction-action-plan]] need amendment based on this source.

**One useful framing reinforced:**
- **Egress dominance** — the gist's $369/$94 egress-vs-storage ratio (~80% of the cost) reinforces a known-but-easy-to-forget asymmetry. Actuate's CE breakdown shows S3 data-transfer at 2% of total ($658 of $32,752 / 30d) — much smaller fractionally because the architecture keeps inter-service S3 traffic in-region (no internet egress on the hot paths). Worth reviewing whenever a fleet-architecture proposal would change which services pull frames across the AZ/region boundary; egress would compound fast if hot-path traffic shifted to public-internet patterns.

**Not applicable angles (recorded so we don't re-litigate):**
- "MinIO for dev/test buckets" — operational overhead (DDNS, SSL renewal, manual backups, ISP bandwidth) wipes any small bill savings. Trusted-Advisor + lifecycle-policy hygiene (Action 4 in the plan) catches dev-bucket waste at far lower cost.
- "Hybrid local-first video processing for cost reasons" — would re-architect the video pipeline for a tertiary lever; structural rework is already covered by Action 12 (frame-bucket pattern rework) which targets a $30-60k/yr ceiling via in-cluster blob + conditional promotion, not on-prem.

## Cross-links

- [[2026-04-28_s3-cost-reduction-action-plan]] — the canonical action plan; not amended by this source
- [[2026-04-23_s3-tier3-cost-investigation]] — confirms our S3 spend is dominated by Tier1 PUT churn + Tier3 lifecycle, not egress
- [[cost-architecture]] § "data" — Actuate's per-tier S3 cost composition
- [[knowledgebase/topics/aws-cost/_summary|aws-cost topic]]
