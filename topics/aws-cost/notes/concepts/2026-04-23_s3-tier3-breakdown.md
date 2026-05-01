---
title: "S3 Tier3 Cost Breakdown — 2026-03-24 to 2026-04-23"
type: concept
topic: aws-cost
tags: [aws, s3, cost-explorer, tier3, lifecycle, replication]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
jira: ""
---

# S3 Tier3 Cost Breakdown — 2026-03-24 to 2026-04-23

Raw data snapshot for the 30-day Tier3 (replication / lifecycle) S3 investigation seeded 2026-04-22. Analysis + recommendations live in the synthesis: [[2026-04-23_s3-tier3-cost-investigation]].

## Source queries

- **Tool:** `/home/mork/.claude/skills/cost-check/run.sh S3 --days 30 --format markdown`
- **CE filter (USAGE_TYPE drill):** `aws ce get-cost-and-usage ... --granularity MONTHLY --group-by Type=DIMENSION,Key=USAGE_TYPE --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Simple Storage Service"]}}'`
- **Account:** `388576304176` (prod), `AWS_PROFILE=prod`
- **Region:** all, but the entire Tier3 cost is `USW2-*` (us-west-2)

## Top-level S3 breakdown (30d)

| Category | Cost (USD) | Quantity | % total |
|---|---|---|---|
| PUT/COPY/POST/LIST (Tier1) | $15,062.71 | 2.81B requests | 46.0% |
| Storage (GB-month) | $11,577.55 | 1.95M GB-mo | 35.3% |
| **Replication/Lifecycle (Tier3)** | **$3,493.94** | **69.88M requests** | **10.7%** |
| GET/SELECT (Tier2) | $1,877.52 | 4.68B requests | 5.7% |
| Data transfer | $696.40 | 10,035 GB | 2.1% |
| Retrieval fees | $42.63 | 4,263 GB | 0.1% |
| Early-delete fees | $2.20 | 176 GB-mo | 0.0% |
| **Total** | **$32,752.97** | — | 100% |

Annualized Tier3: ~**$41,927/year** (down marginally from the 2026-04-22 single-day pull of $3,646.91/30d — rolling-window artifact, not a trend).

## USAGE_TYPE drill (top 20 by cost)

Cost-ordered, raw output from the CE query. Two `USW2-Requests-Tier3` rows combine to the $3,493.94 Tier3 total (likely two linked payer-account buckets in consolidated billing):

| USAGE_TYPE | Cost | Requests |
|---|---|---|
| USW2-Requests-Tier1 | $9,516 | 1.90B |
| USW2-TimedStorage-ByteHrs | $5,131 | 230,952 GB-mo |
| USW2-Requests-Tier1 | $3,502 | 700M |
| **USW2-Requests-Tier3** | **$2,556** | **51.1M** |
| USW2-TimedStorage-SIA-ByteHrs | $2,403 | 192,288 GB-mo |
| USW2-TimedStorage-ByteHrs | $1,790 | 81,388 GB-mo |
| USW2-Requests-SIA-Tier1 | $1,479 | 148M |
| USW2-Requests-Tier2 | $1,358 | 3.40B |
| USW2-TimedStorage-GDA-ByteHrs | $1,015 | 1.03M GB-mo |
| **USW2-Requests-Tier3** | **$937** | **18.8M** |
| ... (remainder trails off below $800) | | |

Total EU region contribution to S3 spend: ~$40/30d (negligible in this analysis — all Tier3 spend is us-west-2).

## Key candidate buckets probed (lifecycle + replication + storage class)

**Probe method:** `s3api get-bucket-lifecycle-configuration`, `s3api get-bucket-replication`, `s3api list-bucket-intelligent-tiering-configurations`, and `cloudwatch list-metrics AWS/S3 BucketSizeBytes` to enumerate active storage classes per bucket.

### Group A — High-churn "24h auto-delete" frame buckets (primary Tier3 suspect)

| Bucket | Storage classes detected | Lifecycle rule |
|---|---|---|
| `all-frames-aegis-v2` | none in CloudWatch | `24-hour-auto-delete` — Enabled, expire=1d |
| `aegis-all-frames-v2-st-johns` | none | `24 hour auto delete` — Enabled, expire=1d |
| `aegis-all-frames-v2-western-springs` | none | `24 hour auto delete` — Enabled, expire=1d |
| `aegis-all-frames-v2-sts` | StandardStorage | `24 hour auto delete` — **Disabled** (data accumulating?) |
| `aegis-all-frames-v2-act-now` | StandardStorage | **(no lifecycle)** |
| `actuate-spray` | StandardStorage | `90 day TTL` — Enabled, expire=90d |

"No storage class in CloudWatch" + "expiration=1d" is the signature of a write/delete churn bucket: BucketSizeBytes metric snapshot never catches accumulated bytes because everything expires within the metric's 24h granularity.

### Group B — Cold-storage transition buckets (secondary Tier3 source)

Lifecycle transitions (Standard → StandardIA → DEEP_ARCHIVE) each cost one Tier3 request per transitioned object.

| Bucket | Classes | Lifecycle |
|---|---|---|
| `actuate-2-month-storage` | Standard, StandardIA, DeepArchive, stagings | Alerts→DEEP_ARCHIVE at 60d (prefix: alerts), several prefix-deletes |
| `actuate-6-month-storage` | Standard, StandardIA, DeepArchive, stagings | Alerts→DEEP_ARCHIVE at 180d (prefix: alerts/), first_frame delete |
| `actuate-blacklist-frames` | StandardStorage only | `delete-old` status=Enabled (no transition visible — probably expiration-only) |

### Group C — Checked, nothing relevant

- `actuate-alert-frame-archive` — no lifecycle, no replication, StandardStorage only, 75 GB
- `actuate-envera-frame-0` — no lifecycle, StandardStorage + StandardIA (why IA with no transition rule? → manual class selection at PUT time?), 3.4 TB
- `actuate-archived-alerts` — 0 GB snapshot; no lifecycle, no replication
- `actuate-analytic-event-archive` — 0 GB snapshot; no lifecycle, no replication
- `actuate-deployed-models`, `actuate-all-frames-v2-genesis`, `actuate-benchmark-datasets`, `actuate-ds-analytics`, `actuate-motion-vs-object`, `actuate-timestamp-detector`, `aegis-all-frames-archive-v2`, `autopatrol-patrol-frames`, `autopatrol-datasets` — no lifecycle, no replication

### No replication configs found

**Zero buckets probed had `ReplicationConfiguration`.** The "Replication/Lifecycle (Tier3)" CE category in this account is therefore **100% lifecycle operations**, not cross-region replication. The label is misleading in the /cost-check output.

### No Intelligent-Tiering configs found

None of the probed buckets have `list-bucket-intelligent-tiering-configurations` results. S3 Intelligent-Tiering monitoring fees are not a contributor.

## Volume math

- Tier3: 69.88M requests / 30 days = **2.33M requests/day**
- Group A buckets with 1-day expiration: each object written there generates 1 Tier1 (PUT) + 1 Tier3 (expiration) request. Round-trip cost-per-object: ~$0.000005 Tier1 + ~$0.00005 Tier3 = $0.000055 total; over millions of frames/day this compounds.
- Group B (cold tiering): each object transitioned Standard→IA or IA→DEEP_ARCHIVE is a single Tier3 request. At 60d/180d cadence, volume is bounded by object count in the alerts prefix.

**Implied split:** Group A (high-churn expiration) almost certainly dominates; Group B is a secondary contributor. The 281 total buckets in the account means there are more candidates worth probing — the Group A/B buckets above were selected heuristically by name pattern.

## Buckets not yet probed (follow-up surface)

Name pattern grep surfaced 40+ frame/alert/detect/clip/spray/autopatrol buckets beyond the sample above. EU region (`actuate-eu-*`) and autopatrol-specific (`autopatrol-*`, `actuate-eu-autopatrol-*`) would be worth a second pass if more attribution is needed. Given zero EU Tier3 cost, the EU-region sweep is low-priority.

## Cross-refs

- [[2026-04-23_s3-tier3-cost-investigation]] — the synthesis that interprets this data
- [[aws-cost-explorer-access-pattern]] — how the CE queries were run
- [[2026-04-22_frame-storage-design-deltas]] — fleet-architecture synthesis where frame-storage cost claims were last refined; Tier3 evidence here is load-bearing for the per-proposal cost-axis scoring
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — the A-E rescore that relied on earlier S3 cost breakdown; Tier3 driver confirmation sharpens the "motion-gating at puller" lever claim
- [[mark-todos]] §6, Not-Yet-Prioritized — "Tier3 S3 replication cost investigation" bullet that seeded this work
