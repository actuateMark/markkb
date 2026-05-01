---
title: "Dashboard cost-signal expansion (19 signals, cached aggregate)"
type: concept
topic: aws-cost
tags: [dashboard, cost, ce, drift, observability, signals, dashboard-check]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
---

# Dashboard cost-signal expansion

## Why

Mark's standing concern: AWS cost drift can surface 14-30 days late if we only look at /cost-check ad-hoc. The minipc dashboard already caught operational drift fast (`fleet_new_oom_offender`, `connector_no_patrols_to_run_24h`); cost was a gap. Goal: bake cost-line drift detection into the same hourly cron, with thresholds calibrated on real 7-day baselines so anything genuinely abnormal turns yellow/red the next morning instead of the next monthly invoice.

Trigger: 2026-04-30 user directive — *"expand the cost signals on our minipc dashboard significantly. I'd like a lot more insight on that, especially if we start drifting."*

## What landed

19 cost signals on `/dashboard-check`, source `ce_daily`, all calibrated against the 2026-04-23 → 2026-04-30 7-day baseline.

| Signal | Baseline ($/day, 7d avg) | Yellow | Red | Notes |
|---|---|---|---|---|
| `cost_total_daily` | $7,788 | >$9,750 | >$11,700 | Top-of-funnel scalar |
| `cost_top_services_daily` | (FACET top-15) | — | — | Drives drift detection per-service |
| `cost_ec2_compute_daily` | $4,663 | >$5,800 | >$7,500 | Largest line — Compute BoxUsage |
| `cost_s3_daily_total` | $1,106 | >$1,500 | >$2,500 | Tightened from prior $1,800/$2,500 |
| `cost_dynamodb_daily` | $573 | >$750 | >$1,100 | |
| `cost_ec2_other_daily` | $445 | >$700 | >$1,200 | NAT + EBS + ELB legacy |
| `cost_ecs_daily` | $181 | >$280 | >$500 | Fargate |
| `cost_rds_daily` | $152 | >$230 | >$400 | |
| `cost_vpc_daily` | $144 | >$220 | >$350 | NAT-GW-hours |
| `cost_aws_config_daily` | $129 | >$200 | >$400 | Surprising line ($47k/yr) |
| `cost_cloudwatch_daily` | $93 | >$150 | >$250 | Logs ingestion + metrics + alarms |
| `cost_elb_daily` | $71 | >$110 | >$180 | |
| `cost_glue_daily` | $51 | >$100 | >$250 | Jobs + crawlers + catalog |
| `cost_sqs_daily` | $44 | >$80 | >$150 | |
| `cost_lambda_daily` | $24 | >$60 | >$150 | |
| `cost_s3_breakdown_daily` | (FACET 7 cats) | — | — | Decomposes S3 by USAGE_TYPE |
| `cost_s3_tier3_daily` | $130 | >$200 | >$400 | Replication ($44k/yr line) |
| `cost_s3_storage_daily` | $399 | >$500 | >$700 | GB-month |
| `cost_s3_tier1_daily` | $496 | >$700 | >$1,000 | PUT request volume |

Every per-service signal carries `regression_rules: ["baseline_drift"]` so a 2σ shift flags before the absolute threshold trips.

## Architecture

**One CE call per service-level run, one CE call per S3 breakdown run** — total ≤2 CE calls per dashboard cron, regardless of how many cost signals are wired.

The dashboard-check cron runs hourly. Each run, the collector:

1. Runs `_ce_aggregate_yesterday(profile)` once — single CE call grouped by SERVICE.
2. Runs `_ce_s3_breakdown_yesterday(profile)` once — single CE call filtered to S3, grouped by USAGE_TYPE, classified by `/cost-check`'s shared classifier (Tier1/2/3/Storage/DataTransfer/EarlyDelete/Retrieval/Other).
3. Each per-signal collector pulls its slice from one of these two cached dicts.

CE pricing is ~$0.01/page; with caching this is ~$0.02 per hourly run = ~$15/month. Without caching it would have been ~$140/month.

The cache key is the UTC date, so a single Python invocation reuses results across signals. Next hourly run repopulates from a fresh CE call — yesterday's data settles within ~24h on AWS's side.

## Files changed

- `~/.claude/skills/dashboard-check/collect.py` — added `_ce_aggregate_yesterday`, `_ce_s3_breakdown_yesterday` cached helpers + 17 thin per-signal wrappers + `_ce_service_daily(svc_name)` curry helper. Registered all in `AWS_DISPATCH`.
- `~/.claude/skills/dashboard-check/config/signals.json` — replaced two stub entries (`aws_daily_spend_delta`, `aws_top10_service_delta`) with the working `cost_total_daily` + `cost_top_services_daily`. Updated `cost_s3_daily_total` baseline. Added 16 new entries.
- Pushed to minipc via targeted `rsync` (avoiding phase-07 which would have collided with a sibling session's settings.json edits for the morning-prep allowlist work).

## Verification (2026-04-30 19:34Z run)

- Collector smoke-test on laptop returned all 19 signals successfully against prod.
- Triggered `run-dashboard-check.service` on minipc, exit code 0 (collect) + 2 (render: any-red).
- `GET /app/api/observations` returns all 19 cost signals tagged with `status` + `age_minutes`.
- Total dashboard signal count: 52 → **74**.
- Yesterday's actual values (2026-04-29 spend): $8,280.28 total, $5,036 EC2, $1,188 S3 (tier1=$547 / storage=$399 / tier3=$156), $601 DDB. All within green thresholds; tier3 elevated ~20% above baseline but below yellow (worth tracking — adjacent to mark-todos §5 pre-PoC Tier3 investigation).

## Drift detection in practice

Two complementary mechanisms:

1. **Absolute thresholds** — `yellow_above` / `red_above` per signal. Catches step-function regressions (a new replication policy adds $200/day to Tier3 → trips red).
2. **`baseline_drift` regression rule** — render.py compares today's value to a rolling baseline; >2σ flags even if absolute thresholds aren't crossed. Catches slow creep.

Threshold choices favor **catch a real problem within 24h** over **never false-positive**. We can re-tune in 7-14 days once sink history accumulates. AWS Config's $129/day baseline is calibrated tight (yellow $200) because the user has flagged it as surprisingly high — any further growth should surface immediately.

## What's not in scope (yet)

- **Per-bucket S3 cost** — needs CUR + Athena, not in CE base. Followup for the Tier3 driver investigation (mark-todos §5).
- **Per-tag cost** (e.g. inference-API-only) — possible via CE filter on `RESOURCE` or `TAG` keys, but requires upstream tag hygiene that hasn't landed.
- **Hourly cost trend** — CE doesn't reliably expose hourly granularity for all services; daily is the unit.
- **EU region split** — single-region account today; if EU prod expands enough to matter, add `cost_eu_west_1_daily` + `cost_us_west_2_daily` against `--filter REGION`.
- **Cost forecasting / anomaly detection via AWS Cost Anomaly service** — separate AWS feature, not via CE; could integrate as a separate `aws_ca_*` source.

## Cross-refs

- [[2026-04-23_s3-tier3-cost-investigation]] — the Tier3 line item these signals make trackable
- [[2026-04-28_s3-cost-reduction-action-plan]] — the action plan whose progress these signals validate
- [[skill-cost-check]] — the ad-hoc CE skill that informs this signal set
- [[skill-dashboard-check]] — host skill where these signals run
- mark-todos §9 — Operational Dashboard workstream (Phase 1b expansion)
- mark-todos §5 — Fleet architecture (Tier3 replication driver investigation feeds from these signals)

## Future signals (parking lot)

Worth adding if cost coverage proves valuable:

- `cost_eu_west_1_daily` — once EU spend grows past noise floor.
- `cost_inference_api_tagged_daily` — once `Project: inference-api` tag adoption is verified.
- `cost_per_environment_daily` — `Environment: prod|stage|dev` tags split. Useful for catching dev-cost drift.
- `cost_secret_egress_daily` — surprising-egress signal: NAT + S3 DataTransfer + CloudFront aggregated, since these are usually the "what changed" line.
