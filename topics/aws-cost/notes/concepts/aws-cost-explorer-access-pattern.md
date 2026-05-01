---
title: "AWS Cost Explorer Access Pattern (for skills/checks)"
type: concept
topic: aws-cost
tags: [aws, cost-explorer, observability, skills, cost-analysis]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
---

# AWS Cost Explorer Access Pattern

Proven 2026-04-22 during the frame-storage design-delta validation. Cost Explorer (CE) calls are now a first-class tool alongside NR + CloudWatch for skills + ad-hoc investigations.

## Profile + permission

- **Profile:** `prod` (points at acct `388576304176`)
- **Permission required:** `ce:GetCostAndUsage`, `ce:GetDimensionValues` (already granted)
- **Refresh:** standard SSO flow — `aws sso login --profile prod` if token expired
- **Do NOT use:** `dev` profile → different account (`558106312574`); CE there may or may not be enabled

## Canonical invocations

### 1. Service-level breakdown (any time window, any granularity)

```bash
AWS_PROFILE=prod aws ce get-cost-and-usage \
  --time-period "Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d)" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" "UsageQuantity" \
  --group-by "Type=DIMENSION,Key=SERVICE" \
  --no-cli-pager
```

Returns per-service cost. Use to spot which service dominates month-over-month.

### 2. USAGE_TYPE breakdown for one service (e.g. S3)

```bash
AWS_PROFILE=prod aws ce get-cost-and-usage \
  --time-period "Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d)" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" "UsageQuantity" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Simple Storage Service"]}}' \
  --group-by "Type=DIMENSION,Key=USAGE_TYPE" \
  --no-cli-pager
```

USAGE_TYPE is the cost-driver axis. For S3 this separates Tier1 (PUT/COPY/POST/LIST requests) / Tier2 (GET/SELECT) / Tier3 (replication) / Storage / DataTransfer / Retrieval.

### 3. Per-bucket / per-resource (requires CUR)

Basic CE does not filter by resource. For per-bucket cost breakdown you need **Cost and Usage Report (CUR)** exported to S3 + queried via Athena, OR **S3 Storage Lens**. Both are follow-up work — not blocking for fleet-wide signals.

## Output-processing recipe

CE returns deeply nested JSON. Summarize fleet-wide signals with Python/jq rather than reading raw rows.

Inline Python pattern (see 2026-04-22 frame-storage investigation for the exercised example):

```bash
AWS_PROFILE=prod aws ce get-cost-and-usage ... > /tmp/ce.json
python3 <<'EOF'
import json, collections
data = json.load(open('/tmp/ce.json'))
categories = collections.defaultdict(lambda: {'cost': 0.0, 'quantity': 0.0, 'types': []})
for bucket in data['ResultsByTime']:
    for g in bucket['Groups']:
        ut = g['Keys'][0]; cost = float(g['Metrics']['UnblendedCost']['Amount']); qty = float(g['Metrics']['UsageQuantity']['Amount'])
        # classify ut into a category (Tier1 → PUT, Tier2 → GET, TimedStorage → storage, DataTransfer → xfer, etc.)
        categories[classify(ut)]['cost'] += cost
        categories[classify(ut)]['quantity'] += qty
# print sorted by cost
EOF
```

## Discipline (same spirit as NR query rules)

1. **Never `--group-by` without `--filter`** on a single service — the unfiltered full breakdown can return thousands of USAGE_TYPEs with rounding-error-tiny costs.
2. **Always `--granularity MONTHLY`** for 30-day windows; use `DAILY` only when looking at trend. `HOURLY` is usually overkill and costs more CE API calls.
3. **Aggregate first, drill second.** Get the top-5 cost drivers first; only then filter down to the driver you care about.
4. **Cache expensive queries to `/tmp/` during a session** — CE calls are usage-billed and slow.
5. **Surface only aggregates in reports.** Don't dump raw ResultsByTime to the user; classify + summarize with cost + quantity + % of total.

## When to use CE vs NR vs CloudWatch

| Signal | Tool | Why |
|--------|------|-----|
| "How much is this service costing?" | CE | Direct answer |
| "Did cost spike yesterday?" | CE daily-granularity | Usage trend visible |
| "Why is cost X — which sites/cameras drive it?" | CUR + Athena (or CloudWatch metrics if tagged) | CE doesn't know per-resource |
| "Is this deploy bleeding money?" | CE daily-granularity + NR deployment-impact | Cost + operational correlation |
| "Is this API-call-dominated or storage-dominated?" | CE USAGE_TYPE breakdown | The canonical validation query |
| "What's the request latency?" | NR / CloudWatch | CE doesn't have latency |
| "Did errors spike?" | NR | CE doesn't have error signals |

## Ready-to-use: S3 fleet-wide cost breakdown (canonical starter query)

30-day S3 rollup with API-calls-vs-storage split computed:

```bash
# See /home/mork/Documents/worklog/knowledgebase/topics/engineering-process/notes/concepts/aws-cost-explorer-access-pattern.md
# for the canonical Python post-processing recipe.
AWS_PROFILE=prod aws ce get-cost-and-usage \
  --time-period "Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d)" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" "UsageQuantity" \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Simple Storage Service"]}}' \
  --group-by "Type=DIMENSION,Key=USAGE_TYPE" \
  --no-cli-pager
```

Expected output shape for Actuate prod (as of 2026-04-22):
- Total: ~$33k / 30 days
- API calls: ~63% (Tier1 PUTs dominate at ~$15k/30d for 2.8B requests)
- Storage: ~35%
- Data transfer: ~2%

## Related

- [[skill-autopatrol-cleanup-lambda-check]] — candidate for CE integration (DDB/SQS/Lambda invocation cost trend)
- [[skill-daily-scope]] — morning fan-out could include a weekly cost-drift exec item
- [[skill-log-check]] / [[skill-new-relic-log-review]] — operational-triage paired with cost-side view
- [[nrql-efficient-query-patterns]] — adjacent discipline for NR queries, same summarise-not-dump philosophy
- [[mark-todos]] Not-Yet-Prioritized → "AWS Cost Explorer integration for skills/checks" (the workstream tracking this capability build-out)
- Load-bearing first use: `topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md` (API-calls-dominate validation)
