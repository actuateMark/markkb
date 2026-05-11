---
title: "Sales Dashboard Repo (aegissystems/sales-dashboard)"
type: entity
topic: billing
tags: [billing, sales-dashboard, repo, snowflake, ordway, reconciliation, fastapi, c6, internal-tool]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Sales Dashboard Repo (`aegissystems/sales-dashboard`)

**Repo:** `https://github.com/aegissystems/sales-dashboard`
**Local clone:** `/home/mork/work/sales-dashboard`
**Production URL:** `https://sales-dashboard.internal.actuateui.net/`
**Current version (clone date 2026-05-11):** `v0.22.2`

Closes [[_todos]] **C6** (locate the sales-dashboard deployment repo). This is the home for the existing internal billing-and-revenue surface — and the canonical source for how to talk to the Snowflake billing tables (see [[snowflake-billing-tables]]).

## What this repo is

A read-only FastAPI service + vanilla-JS frontend that aggregates four (now five) external data sources into a single revenue-operations dashboard for the sales team. **The app never writes to any external source** — it caches, joins, and presents.

### Data sources

| Source | What it provides | Master / enrichment |
|---|---|---|
| **Ordway** | Invoices, revenue, billed-camera counts (from line items), payment status | **Master account list** (Pass 1) |
| **AWS S3 CSVs** | Daily per-site infra cost (compute, inference, slicing, storage) | Cost; Pass 2 fallback for cost-only accounts |
| **HubSpot** | Account type, status, owner, region | Enrichment |
| **Snowflake** | Site hierarchy, billed cameras, usage trends, churn detection (see [[snowflake-billing-tables]]) | Enrichment + drill-downs |
| **PostgreSQL (admin)** | Provisioned fleet — all onboarded cameras incl. Sentinel / AI Link / VCH | Reconciliation (via `reconcile_cameras.py`) |

### Existing pages (each `/<name>` route + `static/<name>.html`)

Already-shipped billing-and-revenue surfaces — these are reusable / extensible rather than rewritable:

| Page | Purpose | Billing-relevance |
|---|---|---|
| `/` (index) | Master account table + KPIs + trend charts | High — KPIs include `Unbilled Cameras` |
| `/unbilled` | **Cameras with 3h+ usage but not in `usage_monthly`** | **Directly relevant** — this is the [[2026-05-11_billing-reconciliation-dashboard-design\|R1]] surface already shipped, in a different form |
| `/no-usage` | Cameras provisioned in admin Postgres but zero events in Snowflake | **High** — surfaces the "is it onboarding or genuinely silent" question |
| `/billing-view` | Per-camera billing replica of Tableau "Total Cameras Report" | **High** — every camera with `is_billed` flag, source ∈ {Connector, VCH, CHM, Clip} |
| `/clip-billing` | Clip-pipeline-specific billing surface | Medium — Sentinel / AI Link / Umbo billing analysis |
| `/churn` | Cameras billed this month but inactive in last 7 days | Medium — mid-month churn detection |
| `/duplicates` | Clip cameras with duplicate `(site, camera_name)` pairs in provisioning | Medium — billing-confusion source |
| `/vch` | Auto Patrol / VCH provisioning vs activity (these are excluded from `usage_monthly`) | Medium — VCH-side fleet tracker |
| `/cost-report` | Infrastructure cost breakdown by account | (AWS-cost-side — overlaps [[aws-cost/_summary]]) |
| `/api-usage` | API endpoint volume metrics | Low — internal-ops |
| `/linking` | Admin page for manual cross-source account linking when name-match fails | Plumbing |

### Existing scripts

| Script | What it does |
|---|---|
| `scripts/reconcile_cameras.py --month YYYY-MM` | **Postgres ↔ Snowflake camera reconciliation report**. Effectively the operational implementation of [[2026-05-11_billing-reconciliation-dashboard-design]]. See "reconcile_cameras.py specifics" below. |
| `scripts/clear-prod-cache.sh` | Force cache eviction in prod (operational tool) |
| `phase0_discovery.py` (top-level) | Initial discovery script — early data-source inventory |

### Chat assistant

A Claude-powered Q&A widget (SSE streaming via `/api/chat`) using Sonnet (`claude-sonnet-4-20250514`). The system prompt includes business context (Ordway invoicing timing, cost-optimization history). Tools call existing backend functions. API key stored at `prod/actuate/sales-dashboard` → `anthropic_api_key`.

## Architecture

```
FastAPI app (src/sales_dashboard/main.py)
  routers/
    api.py     — JSON endpoints (/api/accounts, /api/cost/*, /api/unbilled, ...)
    pages.py   — HTML page routes
    chat.py    — Claude SSE streaming chat
  services/
    dashboard.py     — Core orchestration (get_unified_accounts, get_account_detail)
    account_matcher.py — Name normalization + ALIASES + _REVERSE_ALIASES tables
    linking.py       — Manual account-link persistence (S3-backed JSON)
  clients/
    ordway.py   s3_csv.py   hubspot.py   snowflake.py   postgres.py   newrelic.py
    secrets.py  — AWS Secrets Manager helper
  cache.py     — Two-tier TTL cache (L1 in-memory + L2 S3)
  background.py — Cache warmer (4h interval)

static/    — Vanilla JS + Chart.js frontend (no build step)
scripts/   — reconcile_cameras.py, clear-prod-cache.sh
docs/      — Sales_Dashboard_Guide.md (sales-team user guide)
```

### Caching contract

Two-tier with L1 in-memory + L2 S3 (`actuate-sales-dashboard` bucket, `cache/` prefix). Per-source TTL:

| Source | L1 TTL |
|---|---|
| Snowflake accounts/trend/usage | 24h |
| Snowflake camera/usage trend | 4h |
| Individual S3 CSVs | 7d (historical CSVs immutable) |
| S3 aggregated results | 4h |
| HubSpot | 24h |
| Ordway | 24h |

L2 S3 TTL defaults to 1h (`CACHE_TTL_S3_L2=3600`). Cache key → S3 path mapping: `dashboard:unified:2026-01` → `cache/dashboard/unified/2026-01.json`. Envelope: `{"value": ..., "expires_at": <unix_ts>}`. Failure mode: all S3 errors caught + logged, never raised — falls back to source fetch.

### Deploy mechanism

1. Bump version in `pyproject.toml`.
2. `uv lock` if deps changed.
3. Commit, tag (`vX.Y.Z`), push — CI builds Docker image → ECR.
4. Update `imageTag` in **`kubernetes-deployments` repo** at `argocd/env/388576304176/us-west-2/inference-eks-Ny9n/cluster-values.yaml`.
5. Push — ArgoCD auto-syncs.

**Cluster:** `inference-eks-Ny9n` (us-west-2). **Not** Connector-EKS — sales-dashboard rides the inference-EKS cluster.

## `reconcile_cameras.py` specifics (the script most directly relevant to billing reconciliation)

Per the extraction in [[snowflake-billing-tables]] and against `scripts/reconcile_cameras.py` (754 lines):

**Inputs:**
- `--month YYYY-MM` (only CLI arg; defaults to current month)
- `SNOWFLAKE_PASSWORD` env var (from `.env`)
- `AWS_PROFILE=prod` for Postgres-secret retrieval

**Postgres-side query** (filters to actively-onboarded customer cameras):
```sql
SELECT c.lead, c.name, ca.id, ca.camera_name, it.name AS integration_type, ...
FROM inframap_camera ca
JOIN inframap_customer c ON c.id = ca.customer_id
JOIN inframap_integrationtype it ON it.id = ca.integrationtype_id
WHERE c.active AND ca.active
  AND NOT COALESCE(ca.is_deleted, false)
  AND NOT COALESCE(c.is_deleted, false)
  AND c.lead NOT LIKE '%Actuate%'
  AND c.lead NOT LIKE '%Motion plus%'
```

**Snowflake-side queries** (against `gold.billing`):
- `usage_monthly NOT is_addon` for billed-camera totals
- SPRD with `HAVING SUM(product_run_time)/3600 >= 3` for "3h+ runtime" anti-join
- `clip_received` joined on `(site_name, camera_name)` for clip-pipeline integrations
- `top_parent` for hierarchy

**Categorization output** (printed to stdout as fixed-width tables):

| Bucket | Definition |
|---|---|
| Production (missing Ordway subscription) | SPRD 3h+ runtime, **not** in `usage_monthly`, top_parent not in `INTERNAL_NAMES`, top_parent does NOT match `(trial|pilot)` |
| Healthcheck only | Production-class above, but only product is `'healthcheck'` |
| Trial/Pilot | top_parent matches `(trial|pilot)` |
| Internal/Demo | top_parent in `INTERNAL_NAMES = {actuate, actuate v2, actuate playground, beta breakers - actuate, demo, demo company, connx - demo, brad test org}` |
| Below 3h threshold | SPRD runtime <3h |
| Deactivated mid-month | In Snowflake events but not in active Postgres |
| Provisioned-but-silent | In active Postgres, zero events in any Snowflake table |

**Feb 2026 baseline output** (per `CLAUDE.md` L286-294):

| Category | Postgres | Snowflake | Gap |
|---|---:|---:|---:|
| Connector cameras | 80,807 | 80,765 in SPRD | 257 (<1%) |
| Sentinel Verifier | 16,003 | 7,377 matched | 8,626 (54%) |
| AI Link | 5,417 | 3,165 matched | 2,252 (42%) |
| Auto Patrol / VCH | 2,406 | — | 2,406 (filtered by `usage_products`) |
| **Total** | **104,640** | **93,713** | **10,927** |

**Output mode:** stdout only. No file/CSV/JSON. (A Tier-1 wrapper would capture stdout or refactor it to emit JSON to `~/.local/state/minipc-tasks/billing/`.)

**Verdict:** this script is essentially the operational implementation of [[2026-05-11_billing-reconciliation-dashboard-design|R1]]. Promoting to a Tier-1 dashboard signal is largely:
1. Capture the totals (and per-bucket camera counts) into JSON instead of fixed-width stdout.
2. Classify each bucket green/yellow/red per `_todos` R1 thresholds.
3. Schedule via systemd timer on Firebat.

That's a 1-2 day implementation lift, not a from-scratch rebuild.

## Reusable Snowflake-client surface

If a separate Tier-1 reconciliation script wants to skip rewriting queries, it can import or copy from `sales_dashboard.clients.snowflake`:

| Function | Returns | Useful for |
|---|---|---|
| `get_unbilled_sites(month)` | Per `(top_parent, site_name)` rows: camera_count, products, hours, days_active | The headline reconciliation list — drop-in |
| `get_billing_view(month)` | Every camera with `is_billed` flag + `source` ∈ {Connector, VCH, CHM, Clip} | Full fleet-level dataset |
| `get_camera_churn(month)` | Cameras billed-this-month-but-quiet-7-days, with totals | Mid-month churn signal |
| `get_active_camera_ids(month)` | `{sprd_ids, clip_pairs}` | Building set-arithmetic against Postgres |
| `diagnose_clip_join(month)` | Orphaned `clip_received.site_name`s + matched-per-tp counts | Surfaces the silent-drop where clip rows have no `top_parent` |
| `get_vch_activity(month)` | VCH camera-level totals | Verify VCH-excluded fleet |

All are pool-aware (size 8, `_MAX_CONN_AGE=3600s`, retry-after-2s) and L1+L2 cached.

## Sister repo — `actuate_bi`

**The pipeline SQL / DDL lives at `../actuate_bi/sql/snowflake/`** ([[sales-dashboard-repo|sales-dashboard]] CLAUDE.md L146-160). That repo defines:
- `gold.billing.usage_monthly`
- `gold.billing.usage_products` (the Ordway business-filter view)
- `gold.billing.site_product_run_day`
- `clip_received` table
- The 1 AM EST swap task / scheduling

**`actuate_bi` is NOT currently cloned** at `/home/mork/work/actuate_bi/`. Cloning it would complete the ENG-242 answer (get the raw DDL files). Tracked in [[_todos]] as a follow-up.

## Operational gotchas

1. **Snowflake lockout.** `reports@actuate.ai` locks on multiple failed login attempts. May not auto-unlock. **Never connect without `SNOWFLAKE_PASSWORD` set.** Unlock: `ALTER USER "reports@actuate.ai" SET MINS_TO_UNLOCK = 0;` (admin only).
2. **Snowflake data is "a day behind".** SPRD rebuilds at 1 AM EST. Events arriving after that won't surface until the next day's rebuild. R1 design's 24h trailing window accommodates this.
3. **Trial/pilot/internal cameras silently exclude themselves from billing** via missing Ordway subscription. No explicit "trial" filter; the absence of the subscription is the mechanism.
4. **Some clip cameras have NULL `camera_id`.** Reconciliation must join on `(site_name, camera_name)`.
5. **VCH cameras are not in `usage_monthly`.** They're billed externally via Immix and are intentionally filtered out by `usage_products`.
6. **Most credentials still live in `.env`, not Secrets Manager.** Per CLAUDE.md L27: "TODO — Migrate all credentials to AWS Secrets Manager." For a Tier-1 reconciler, follow the README L98-127 pattern (pull from `prod/actuate/sales-dashboard` directly via boto3).

## Cross-references

- [[snowflake-billing-tables]] — table inventory + filter logic (drives off this repo's `snowflake.py`)
- [[2026-05-11_eng-242-substantially-answered]] — how this repo answers most of ENG-242
- [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]] — design that `reconcile_cameras.py` largely already implements
- [[billing-events-catalog]] — SQS-side vocabulary the dashboard's Snowflake-side resolves
- [[_todos]] — billing topic todos (C6 closes via this note; new follow-ups added)
- [[aws-cost/_summary]] — sales-dashboard also covers infra-cost surface; cross-link, don't duplicate
- [[core-repo-suite]] — should move sales-dashboard from "Clone on Need" to "Local"
- `kubernetes-deployments` repo — `argocd/env/388576304176/us-west-2/inference-eks-Ny9n/cluster-values.yaml` (where `imageTag` is updated to deploy)
- `actuate_bi` repo — sister repo with pipeline DDL (not yet cloned)
