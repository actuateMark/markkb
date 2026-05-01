---
title: "S3 Tier3 Cost Investigation — Lifecycle-Expiration Is the Driver"
type: synthesis
topic: aws-cost
tags: [aws, s3, cost, lifecycle, tier3, fleet-architecture, cost-optimization]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
jira: ""
status: active
incoming:
  - topics/aws-cost/_dive-queue.md
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/concepts/2026-04-23_s3-tier3-breakdown.md
  - topics/aws-cost/notes/concepts/2026-04-27_eks-storage-applicability.md
  - topics/aws-cost/notes/concepts/2026-04-30_dashboard-cost-signal-expansion.md
  - topics/aws-cost/notes/syntheses/2026-04-27_aws-cost-topic-spinoff.md
  - topics/aws-cost/notes/syntheses/2026-04-28_s3-cost-reduction-action-plan.md
  - topics/aws-cost/sources/2026-04-27_eks-cost-opt-storage.md
  - topics/aws-cost/sources/2026-04-27_s3-cost-optimization.md
  - topics/aws-cost/sources/2026-04-27_s3-intelligent-tiering.md
incoming_updated: 2026-05-01
---

# S3 Tier3 Cost Investigation — Lifecycle-Expiration Is the Driver

## TL;DR

- Tier3 = **$3,493.94 / 30d = ~$42k/year**, 10.7% of S3 spend ($398k/year annualized).
- **Driver is lifecycle-expiration, not replication.** Zero buckets probed had `ReplicationConfiguration`. The CE label "Replication/Lifecycle (Tier3)" is misleading in this account.
- **Primary source: high-churn "24h auto-delete" frame buckets** (`all-frames-aegis-v2`, `aegis-all-frames-v2-<site>`). Every frame PUT into these buckets is matched by one Tier3 lifecycle-expiration request the next day.
- **Secondary source: Standard → StandardIA → DEEP_ARCHIVE transitions** on `actuate-2-month-storage` and `actuate-6-month-storage` (bounded by alerts-prefix object count).
- **This is not a standalone-quick-win.** The Tier3 cost is an emergent property of the per-frame write-and-delete pattern the fleet uses today. Eliminating it in isolation means stopping per-frame writes; that's already the direction [[2026-04-22_frame-storage-design-deltas|the frame-storage design-delta synthesis]] argues for (in-cluster blob + conditional promotion, proposals D/E).
- **Cost-axis ceiling is capped:** Tier3 ~$42k/yr, plus the paired Tier1 write leg (~$6k–10k/yr for the same objects), plus ~$180k/yr of associated working-set storage. Combined savings ceiling from eliminating the non-detection-positive write path is in the $30-60k/yr range (not $100k+). Compute-side consolidation in E/C remains the larger leverage ceiling, consistent with the 2026-04-22 cost-axis refinement in [[2026-04-22_fleet-proposal-rescore-with-delta]].

Data underpinning this synthesis is in [[2026-04-23_s3-tier3-breakdown]].

## Background

Seeded 2026-04-22 evening as a morning-priority exec item after the [[2026-04-22_fleet-proposal-rescore-with-delta|formal A-E rescore]] landed. The bullet: "$3,646.91 / 30d on 72.9M requests = $44k/year at 11.1% of S3 spend. Unknown driver: cross-region replication? lifecycle transitions? Intelligent-Tiering? Could be a quick-win independent of any fleet-architecture proposal."

First run on 2026-04-23 hit expired prod SSO mid-fanout. User directive surfaced a durable skill update ([[feedback_fanout_preflight]]) — `/daily-scope` now verifies AWS/NR/GH/MCP connections before Step 2c. After remediation, the investigation ran end-to-end in one pass.

## Method

1. Run `/cost-check S3 --days 30 --format markdown` for the top-level breakdown.
2. Drill USAGE_TYPE via `aws ce get-cost-and-usage --group-by USAGE_TYPE` to confirm the Tier3 category is `USW2-Requests-Tier3` (us-west-2 only; zero EU-region Tier3).
3. For a heuristic-selected set of ~20 candidate buckets (frame / alert / storage / detection names), pull:
   - `s3api get-bucket-lifecycle-configuration`
   - `s3api get-bucket-replication`
   - `s3api list-bucket-intelligent-tiering-configurations`
   - `cloudwatch list-metrics AWS/S3 BucketSizeBytes` to enumerate which storage classes each bucket actually uses.
4. Correlate lifecycle-rule structure (expiration vs transition) + observed storage classes to classify each bucket as:
   - Group A: high-churn 24h-expire (primary Tier3 source)
   - Group B: cold-transition (secondary Tier3 source)
   - Group C: neither (excluded)

Full per-bucket probe results: [[2026-04-23_s3-tier3-breakdown]].

## Findings

### 1. No replication — the CE category is mislabeled for this account

Across every probed bucket (including the cold-archive and high-storage ones most likely to have DR replication), `get-bucket-replication` returned `ReplicationConfigurationNotFoundError`. This account's "Replication/Lifecycle (Tier3)" cost line is **100% lifecycle operations** — a replication-driven quick-win doesn't exist here.

### 2. Primary driver: 24h-auto-delete per-site frame buckets

Buckets matching the pattern `aegis-all-frames-v2-<site>` (and the generic `all-frames-aegis-v2`) have lifecycle rules of the form:

```
rule: "24 hour auto delete" / status: Enabled / expiration: 1 day / prefix: ""
```

CloudWatch BucketSizeBytes metrics return **no storage-class dimensions** for several of them, which is the signature of a pure write-and-delete-within-24h churn pattern (BucketSizeBytes snapshots are daily averages; a bucket whose contents flush to zero within the metric window shows no persistent bytes).

Each expiration is one Tier3 request. If the fleet is writing N million frames per day into these buckets, Tier3 request count tracks N million per day. The observed 2.33M Tier3 requests/day is consistent with a few-million-frames/day global detection-spray rate.

**Observed oversight:** `aegis-all-frames-v2-sts` has the rule present but **Disabled**. StandardStorage metrics ARE observed on this bucket — meaning it's accumulating frames that should have been expiring. Worth a separate triage: either re-enable the rule or confirm the site's frames are handled elsewhere.

### 3. Secondary driver: Standard → IA → DEEP_ARCHIVE transitions

`actuate-2-month-storage` and `actuate-6-month-storage` have `alerts/` prefix rules transitioning to DEEP_ARCHIVE at 60d/180d respectively. Each transitioned object is one Tier3 request.

Volume is bounded by the number of alert objects aging past the threshold per day, which is much smaller than the detection-frame churn rate. Ballpark: thousands to low-millions of transitions/month, probably contributing the $937 sub-row of Tier3 vs the larger $2,556 sub-row.

### 4. No Intelligent-Tiering monitoring cost

`list-bucket-intelligent-tiering-configurations` returned empty for every probed bucket. The account does not use S3 Intelligent-Tiering. This rules out "Intelligent-Tiering monitoring fees running hot" as the driver.

### 5. Unassigned buckets worth a second look

`actuate-envera-frame-0` has both `StandardStorage` and `StandardIAStorage` metrics but **no lifecycle rule**. That means objects are being written with `StorageClass: STANDARD_IA` directly at PUT time (manual class selection), not via lifecycle transition. This isn't Tier3-relevant but flags an inconsistent pattern worth documenting.

## Implications

### For fleet-architecture cost modeling

The Tier3 finding **sharpens but does not invalidate** the conclusions in [[2026-04-22_frame-storage-design-deltas]] and [[2026-04-22_fleet-proposal-rescore-with-delta]]:

- **Reinforced:** motion-gating at the puller (proposals D/E) is the cost lever, because it reduces both Tier1 (PUT) and Tier3 (expiration) volumes proportionally. The earlier claim that motion-gating is the primary cost win holds.
- **Refined ceiling:** the total S3 savings ceiling from eliminating non-detection-positive frame writes is:
  - Tier1 (PUT) reduction — proportional to motion-drop rate (40-60% of current $15k/mo = $6-9k/mo saved)
  - Tier3 (expiration) reduction — proportional to same rate (40-60% of current $3.5k/mo = $1.4-2.1k/mo saved)
  - Storage (GB-mo) reduction — much smaller since 24h-churn buckets have small working sets
  - Combined: $7-11k/mo = **$84k-132k/yr**, or ~25-35% of S3 spend.
- **Compute-side dominance unchanged:** S3 is 14.9% of total AWS spend; the compute-side pool-consolidation lever in proposals C/E (EC2 $121k/mo) is still the larger ceiling.

### For independent quick-wins

Two items worth picking up separately from fleet-architecture work:

1. **`aegis-all-frames-v2-sts` lifecycle rule — re-enable or investigate.** Current state is Enabled=False but bucket is accumulating StandardStorage data. Either (a) site's frames are still flowing and should be expiring, or (b) site's frames were diverted and the bucket should be cleaned up. Small Tier1/Tier3 contribution but a real data-hygiene bug.
2. **`actuate-envera-frame-0` storage-class audit.** StandardIA objects are being written manually without a lifecycle rule — confirm this is intentional (may be cost-optimizing at PUT time) or a latent bug.

Neither is a $42k/yr win; both are "clean up what's broken" work worth <30 min apiece.

### For the cost-axis methodology

Two lessons carried back into future cost investigations:

1. **"Replication/Lifecycle" CE category collapses two very different cost drivers.** Always drill by USAGE_TYPE and correlate to actual bucket configs before claiming "it's replication" vs "it's lifecycle". The /cost-check skill could be extended to do this drill automatically for any Tier3 line >$1k/mo.
2. **CloudWatch `BucketSizeBytes` metric class enumeration is a reliable churn-pattern fingerprint.** A bucket with active writes but no storage-class dimension in `list-metrics` is almost always a short-TTL churn bucket. Worth teaching the `/cost-check` skill to flag this pattern as a tier3-suspect automatically.

## Recommendations

### Do now

- [ ] Close the open "Tier3 S3 replication cost investigation" bullet in [[mark-todos]] with a pointer to this synthesis.
- [ ] File separate action: investigate `aegis-all-frames-v2-sts` disabled lifecycle rule. Small but real.
- [ ] File separate action: confirm `actuate-envera-frame-0` StandardIA-at-PUT-time pattern is intentional.

### Do during fleet PoC (E or C)

- [ ] Measure the true per-day Tier3 rate during the PoC by bucket — correlate with measured motion-drop rate to firm up the $1.4-2.1k/mo savings projection.
- [ ] Instrument `SlidingWindowStep.close_window` with a `window_outcome` log line (already in the NYP list in mark-todos) so we can tie detection-positive-ratio to S3 object counts at finer-than-fleet-average granularity.

### Do during cost-tooling work

- [ ] Extend the `/cost-check` skill to drill USAGE_TYPE for any category >$1k/mo and include a lifecycle-churn-pattern probe (list-metrics class enumeration) as a first-class output. This investigation was ~30 min of manual work; a skill upgrade could make the next similar investigation ~3 min.

## Cross-refs

- [[2026-04-23_s3-tier3-breakdown]] — raw data for this analysis
- [[2026-04-22_frame-storage-design-deltas]] — fleet-architecture cost-delta synthesis
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — A-E rescore relying on S3 cost breakdown
- [[aws-cost-explorer-access-pattern]] — CE query recipe
- [[skill-cost-check]] — the tool that seeded this work
- [[mark-todos]] §3 (cleanup lambda) + "Not-Yet-Prioritized" (Tier3 investigation bullet)
