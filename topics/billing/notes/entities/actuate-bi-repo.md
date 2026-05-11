---
title: "actuate_bi Repo (aegissystems/actuate_bi)"
type: entity
topic: billing
tags: [billing, actuate-bi, repo, snowflake, terraform, ordway, pipeline-ddl, snowflake-tasks, c2, c5]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# actuate_bi Repo (`aegissystems/actuate_bi`)

**Repo:** `https://github.com/aegissystems/actuate_bi`
**Local clone:** `/home/mork/work/actuate_bi`
**Purpose:** Snowflake billing-pipeline DDL + scheduling + Ordway upload tooling.

Closes the remainder of [[2026-05-11_eng-242-substantially-answered|ENG-242]] that [[sales-dashboard-repo]] couldn't — this is where the **authoritative** table/view/task definitions for `gold.billing.*` live.

## What this repo is

Snowflake-side data-pipeline source-of-truth. Defines the tables, views, schedule tasks, RBAC, and storage integrations that take raw connector events through to the `gold.billing.usage_monthly` surface Ordway invoices off. Also contains the Docker-packaged CLI that posts daily usage to Ordway.

**Authoritative deploy mechanism: Terraform.** SQL files under `sql/snowflake/` are reference/history — they drift from the deployed objects (see §"Critical drift" below). Always trust `tf/*.tf` over `sql/snowflake/*.sql` when they disagree.

```
actuate_bi/
├── sql/
│   ├── snowflake/      <-- reference SQL (DRIFTS — see below)
│   │   ├── gold/billing/        usage_monthly, top_parent, clip_received_day, ...
│   │   ├── raw/ordway/          subscription, product_tier, usage_products, usage_addon, ...
│   │   ├── raw/aws/             analytics_event, analytics_event_clean,
│   │   │                        site_product_run_day_last_year,
│   │   │                        camera_flags_per_day, tasks/*.sql, ...
│   │   └── storage_integration/ s3_integration_analytics, eu_s3_integration_analytics
│   ├── postgres/       <-- admin DB views (NOT deployed by this repo;
│   │                       checked in as contract — vw_top_parent etc.)
│   └── redshift/       <-- DEPRECATED entirely. Do not cite.
├── tf/                 <-- THE deployed source of truth
│   ├── tables.tf       <-- SITE_PRODUCT_RUN_DAY, SUBSCRIPTION, TOP_PARENT, ... authoritative columns
│   ├── views_gold_billing.tf  <-- gold-view bodies
│   ├── tasks.tf        <-- schedule + body for all Snowflake Tasks
│   └── README.md       <-- deploy contract + task table
├── noteboooks/         <-- (sic) Jupyter notebooks for loaders + ad-hoc
│   ├── Load Admin Data.ipynb       <-- nightly: builds raw.aws.top_parent from Postgres vw_top_parent
│   ├── Load Subscriptions.ipynb    <-- nightly: builds raw.ordway.subscription from Ordway API
│   ├── Upload Usage.ipynb          <-- daily: posts usage_monthly → Ordway via Docker CLI
│   ├── Load Admin Alibi.ipynb      <-- monthly: Alibi dealer dim
│   └── cli.py + src/utils.py       <-- top_parent_id → 'C-{:07}' Ordway customer-id formatter
├── docs/
│   ├── Sales_Dashboard_Guide.docx (irrelevant — sales-team UI guide)
│   └── ordway-usage-flow.md        <-- mermaid + prose of the upload triad
├── justfile            <-- only run/build/push for the Docker CLI image
├── .github/workflows/  <-- only CI: Docker build/push (NOT Terraform, NOT SQL)
└── tf/README.md        <-- read this BEFORE touching anything in tf/
```

## Authoritative DDL inventory

The full per-table DDL is in [[snowflake-billing-tables]] — that note is the canonical KB surface for "what is the schema." This entity note covers **where each definition lives in this repo** and **what's deployed vs reference-only**.

### Deployed gold-billing surface

| Object | Authoritative source | Reference SQL | Notes |
|---|---|---|---|
| `gold.billing.usage_monthly` (VIEW) | `tf/views_gold_billing.tf` L62-134 | `sql/snowflake/gold/billing/views/usage_monthly.sql` | UNION of usage_products + usage_addon, both with `HAVING sum(quantity) >= 3`. Hours-based threshold. |
| `gold.billing.top_parent` (VIEW) | `sql/snowflake/gold/billing/views/top_parent.sql` | (same) | Thin pass-through over `raw.aws.top_parent` — hides `integration_type` and `subscription_code`. |
| `gold.billing.clip_received` (TABLE) | Defined by the swap task | `sql/snowflake/gold/billing/views/clip_received_day.sql` is the upstream view | Daily-rebuilt at 9:15 AM ET; mirrors `raw.aws.clip_received_day`. |
| `gold.billing.site_product_run_day` (SPRD, TABLE) | `tf/tables.tf` L58-165 | (no `.sql` file; only the rebuild task references it) | Daily-rebuilt at 1 AM ET. **24+ columns** — see [[snowflake-billing-tables]]. |

### Ordway business-filter layer (the silent-drop)

| Object | Path | Filter logic |
|---|---|---|
| `raw.ordway.usage_products` (VIEW) | `sql/snowflake/raw/ordway/views/usage_products.sql` | **From SPRD.** INNER JOIN `product_tier` (product-name match). INNER JOIN `subscription` on `top_parent_id = customer_id`, pivoted on `special_pricing`. WHERE `account_stage='Top Parent' AND product<>'healthcheck' AND pt.active AND integration_type<>'Auto Patrol / Visual Camera Health'`. |
| `raw.ordway.usage_addon` (VIEW) | `sql/snowflake/raw/ordway/views/usage_addon.sql` | Parallel view for CHM/Slice/Fisheye. `quantity = healthcheck event count` for CHM. |
| `raw.ordway.subscription` (TABLE) | `tf/tables.tf` L968 (authoritative — `sql/.../subscription.sql` is **STALE**) | 7 columns: `id`, `customer_id`, `customer_name`, `created_date`, `updated_date`, `special_pricing` (BOOLEAN), `environment` (VARCHAR). `special_pricing` pivots the usage_products join. |
| `raw.ordway.product_tier` (VIEW) | `sql/snowflake/raw/ordway/views/product_tier.sql` | LEFT JOIN `product` → `tier`. **`is_addon = (t.id IS NULL)`** — a product is an addon iff it has no tier mapping. |

### Raw-event layer

| Object | Path | Notes |
|---|---|---|
| `raw.aws.analytics_event` (TABLE) | `sql/snowflake/raw/aws/tables/analytics_event.sql` (35 cols) + `tf/` adds `LOAD_TIMESTAMP` (36th col, drift — see below) | All `ACT_*` fields have column COMMENTs describing connector vs clip semantics. |
| `raw.aws.analytics_event_clean` (VIEW) | `sql/snowflake/raw/aws/views/analytics_event_clean.sql` | Literally `SELECT * FROM raw.aws.analytics_event GROUP BY ALL` — dedup. |
| `raw.aws.site_product_run_day_last_year` (VIEW) | `sql/snowflake/raw/aws/views/site_product_run_day_last_year.sql` | **24 columns including SUBSCRIPTION_ID.** This is where the silent-drop INNER JOINs live: `JOIN latest_name`, `JOIN raw.aws.top_parent`, `JOIN raw.aws.camera_flags_per_day`. Filter: `event_type='site_product_ended' AND event_timestamp >= current_date - interval '1 year'`. Aggregates `sum(act_10) → product_run_time`, `sum(act_1) → run_count`, listagg(act_e) → camera_names. |
| `raw.aws.camera_flags_per_day` (VIEW) | `sql/snowflake/raw/aws/views/camera_flags_per_day.sql` | Per-day camera state flags joined into SPRD-source view. |
| `raw.aws.top_parent` (TABLE) | `tf/tables.tf` L875 | 8 columns — gold view hides `integration_type` and `subscription_code`. Loaded nightly by `Load Admin Data.ipynb` from admin Postgres `vw_top_parent`. |

### Anti-recommendations (look billing-relevant, are NOT)

| Object | Why it's a trap |
|---|---|
| `sql/redshift/*` | Deprecated entirely. Do not cite. |
| `sql/postgres/views/vw_top_parent.sql` | Upstream admin-DB view — the Snowflake-side `top_parent` is a nightly snapshot of this. Do not cite as "the billing top_parent." |
| `raw.aws.last_camera_name` (VIEW) | Stale extract; production lookup is inlined as `latest_name` CTE inside `site_product_run_day_last_year`. |
| `raw.aws.eu_analytics_event` + EU pipeline | Separate EU-region pipeline; does NOT feed `site_product_run_day_last_year`. EU events appear parked, not in billing surface. Confirm before citing. |
| `raw.processing.usage` staging | Transient upload-pipeline table, not billing-DDL. |
| `raw.ordway.usage_pending / usage_processed / usage_skipped` | Upload-pipeline triad (post-`usage_monthly`), not consumption surface. |
| `gold.billing.customer_dealer` | Alibi dealer dim for sales attribution, not invoicing. |

## Scheduling — Snowflake Tasks (no Airflow, no external cron)

Authoritative table is in `tf/README.md` L120-135. Five tasks own the daily/monthly cadence:

| Task | Schedule | Warehouse | What it does |
|---|---|---|---|
| `raw.aws.analytics_event_copy_from_s3` | `30 */4 * * * US/Eastern` (every 4h at :30) | `DATA_LOAD` | Stages JSON from `@s3_analytic_event`, INSERTs into `analytics_event` with `SYSDATE() AS load_timestamp`. Triggered by cron, not S3 events. |
| `raw.aws.analytics_event_summarize_daily` | `0 1 * * * US/Eastern` (daily 1:00 AM ET) | `DATA_PROCESSING` | **The SPRD daily-swap.** CREATE→RENAME→RENAME→GRANT→DROP. **Not transactional** — see operational-risk note below. |
| `raw.aws.clip_received_day_summary` | (daily 9:15 AM ET) | `DATA_PROCESSING` | Parallel swap for `gold.billing.clip_received`. **Has `IF EXISTS` guard** on first RENAME (safer than SPRD swap). |
| `Load Top Parents` (`EXECUTE NOTEBOOK`) | daily 1:01 AM NY | — | Rebuilds `raw.aws.top_parent` from Postgres `vw_top_parent`. **Runs 1 min AFTER SPRD swap — race risk.** |
| `Load Subscriptions` (`EXECUTE NOTEBOOK`) | daily 1:20 AM NY | — | Rebuilds `raw.ordway.subscription` from Ordway API. |
| `Load Alibi Data` (`EXECUTE NOTEBOOK`) | monthly 1st at 3:01 AM NY | — | Alibi dealer dim. |
| `ORDWAY_EVENTS_UPLOAD` | 3:01 AM ET | `ACTUATE_SERVICES` (compute pool) | Runs `actuate` Docker image as Snowflake job service; reads `USAGE_PENDING`, POSTs to Ordway `usage_events/bulk`, writes to `RAW.PROCESSING.ORDWAY_EVENTS_DEV` (misleading name — production). |
| Ordway status checks | 5:30 AM + 8:30 AM ET | — | Scans for non-200 Ordway responses → Slack via `SLACK_NOTIFICATIONS` → SNS → Lambda → `#ordway`. |

`allow_overlapping_execution = false` on all tasks — prevents stacked runs if one is slow.

## Deploy mechanism

- **Terraform** owns Snowflake objects (databases, schemas, warehouses, stages, integrations, tables, views, tasks, RBAC). Remote state: `s3://actuate-snowflake-tf-state/terraform.tfstate` (us-west-2, AWS profile `actuate-tf-state`). Auth: key-pair JWT (`SNOWFLAKE_JWT`, private key in env `SNOWFLAKE_PRIVATE_KEY`).
- **Standard flow:** `terraform init && terraform plan && terraform apply` — **manual**, no CI auto-apply.
- **`sql/snowflake/` is NOT applied by anything.** Reference/history only. Drifts from deployed (see §"Critical drift").
- **GitHub Actions** (`.github/workflows/build-push.yml`): only CI is Docker build/push of the `actuate` CLI image to `actuate-ocb47239.registry.snowflakecomputing.com/raw/ordway/actuate` on every push to `main`. Uses OIDC for AWS, JWT for Snowflake CLI.
- **No Terraform CI**, **no SQL deploy CI**, **no linter**. `terraform plan` is the only dry-run.

## Critical drift between `sql/snowflake/` and deployed (Terraform-defined) objects

This is load-bearing — when in doubt, read `tf/*.tf` not `sql/snowflake/*.sql`:

1. **`raw.ordway.subscription`** — `tf/tables.tf` L968 has **7 columns** including `special_pricing` (BOOLEAN) and `environment` (VARCHAR); `sql/.../subscription.sql` shows **5 columns** (missing both). `special_pricing` is the load-bearing pivot for the `usage_products` join. The file even has a comment: "created by the notebook `Load Subscriptions.ipynb` and saved here for reference only."
2. **`raw.aws.analytics_event`** — SQL file has **35 columns**; deployed table has **36** because `analytics_event_copy_from_s3` adds `LOAD_TIMESTAMP` at ingest (`SYSDATE() AS load_timestamp`). The `analytics_event_clean` view lists `LOAD_TIMESTAMP` explicitly, confirming the discrepancy.
3. **`gold.billing.site_product_run_day`** — only `tf/tables.tf` defines it; no `.sql` file. KB note discovery missed: `BILLING_ID`, `RUN_COUNT`, `CAMERA_VIEW`, `EVENT_TYPE`, `START_TIME`, `PERSP`, `PANO`, `SPLIT`, `CAMERA_NAMES`, `SUBSCRIPTION_ID`. These are now in [[snowflake-billing-tables]].

When updating the [[snowflake-billing-tables]] inventory, **only trust `tf/*.tf` for column lists**.

## Operational risks (KB-worthy findings)

### 1. SPRD daily swap is NOT transactional

The body of `analytics_event_summarize_daily` is wrapped in `begin ... end` but **NOT in an explicit transaction**. Snowflake auto-commits each DDL individually. The sequence:

```sql
CREATE TABLE raw.processing.site_product_run_day_new AS
    (SELECT * FROM raw.aws.site_product_run_day_last_year);  -- auto-commit
ALTER TABLE gold.billing.site_product_run_day
    RENAME TO raw.cleanup.site_product_run_old;              -- auto-commit  (NO IF EXISTS guard)
ALTER TABLE raw.processing.site_product_run_day_new
    RENAME TO gold.billing.site_product_run_day;             -- auto-commit
GRANT SELECT ... TO ROLE report;                              -- auto-commit
DROP TABLE raw.cleanup.site_product_run_old;                  -- auto-commit
```

**Failure mode:** if the second RENAME fails after the first succeeded, `gold.billing.site_product_run_day` is **gone** (renamed to `raw.cleanup.site_product_run_old`) and stays gone until manual recovery. Anything querying SPRD during the failure window sees "table does not exist."

Mitigation today: `allow_overlapping_execution = false` + the fact that this has held in practice. The parallel clip-swap **does** have `IF EXISTS` on its first RENAME, so it's slightly safer. Open question whether to add the same guard to the SPRD swap. **Tracked in [[_todos]] as a new follow-up.**

### 2. `Load Top Parents` runs 1 min after the SPRD swap

SPRD swap kicks off at 1:00 AM NY. `Load Top Parents` notebook fires at 1:01 AM NY. If the swap takes >60s (typical: well under), `Load Top Parents` runs while SPRD is mid-swap. Whether `vw_top_parent` reads SPRD during that window is unclear; the race risk depends on what queries the notebook runs.

### 3. SQL files drift silently

There's no CI that diffs `sql/snowflake/*.sql` against the deployed objects. The `subscription.sql` drift went undetected (and was self-described in a comment). Anyone reading the file assuming it's authoritative will misunderstand the schema. **All inventory in [[snowflake-billing-tables]] now references `tf/*.tf` paths where they exist.**

## Ordway upload triad (for completeness; not billing-DDL)

Per `docs/ordway-usage-flow.md`:

```
gold.billing.usage_monthly
     │
     ▼  monthly export
raw.processing.USAGE_PENDING  <-- staging table; what the Docker CLI reads
     │
     ▼  POST /usage_events/bulk via ORDWAY_EVENTS_UPLOAD Snowflake job service
     │     (compute_pool=ACTUATE_SERVICES, EXTERNAL_ACCESS_INTEGRATIONS=ORDWAY_INTEGRATION)
     │     writes results to:
     ▼
raw.processing.ORDWAY_EVENTS_DEV  (misleading name — production)
     │
     ├─→ status check at 5:30 AM ET — scan non-200s → #ordway
     ├─→ status check at 8:30 AM ET — scan non-200s → #ordway
     │
     ▼
raw.ordway.USAGE_PROCESSED  (success) / USAGE_SKIPPED (filtered out)
```

Useful provenance for the "where do usage_monthly rows actually go" question; not in scope for ENG-242 (which asked about the consumption side, not the upload side).

## Reading order for new contributors

1. `tf/README.md` — the deploy contract + task table.
2. `tf/views_gold_billing.tf` — what the gold-billing surface looks like.
3. `sql/snowflake/raw/ordway/views/usage_products.sql` — the silent-drop logic.
4. `sql/snowflake/raw/aws/views/site_product_run_day_last_year.sql` — the second silent-drop logic.
5. `tf/tasks.tf` — the schedule.
6. `docs/ordway-usage-flow.md` — the upload triad.

Avoid reading `sql/snowflake/raw/ordway/tables/subscription.sql` (stale) or `sql/redshift/*` (deprecated) as authoritative.

## Cross-references

- [[snowflake-billing-tables]] — canonical schema KB; built from this repo's `tf/` + `sql/`
- [[sales-dashboard-repo]] — the consumer of this pipeline; surfaces unbilled/churn/reconciliation
- [[2026-05-11_eng-242-substantially-answered]] — what ENG-242 asked and how this repo closes it
- [[2026-05-11_billing-pain-post-mortem]] — Cohort F's silent-drop class is exactly the `INNER JOIN raw.ordway.subscription` mechanism documented here
- [[billing-events-catalog]] — SQS-side vocabulary; the Snowflake side documented here resolves into `act_a → product`, `act_11 → camera_id`, `act_10 → product_run_time`, etc.
- [[_todos]] — see new follow-ups NF6 (library extraction), NF7 (SPRD swap IF EXISTS guard), NF8 (SQL/TF drift CI)
- [[core-repo-suite]] — should move `actuate_bi` from "Clone on Need" to "Local"
- `kubernetes-deployments` repo — not directly relevant (actuate_bi uses Terraform + Snowflake compute pool, not K8s)
