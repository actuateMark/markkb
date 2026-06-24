---
title: "Snowflake Billing Tables"
type: entity
topic: billing
tags: [billing, snowflake, gold-billing, usage-monthly, site-product-run-day, clip-received, top-parent, reports-user, actuate-bi, c5]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
incoming:
  - topics/billing/_todos.md
  - topics/billing/notes/concepts/2026-05-11_eng-242-substantially-answered.md
  - topics/billing/notes/concepts/2026-05-11_nf2-deployment-state.md
  - topics/billing/notes/entities/actuate-bi-repo.md
  - topics/billing/notes/entities/billing-deferred-backlog.md
  - topics/billing/notes/entities/sales-dashboard-repo.md
  - topics/personal-notes/notes/concepts/2026-05-11_billing-and-followups-handoff.md
  - topics/personal-notes/notes/daily/2026-05-11.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# Snowflake Billing Tables

Authoritative inventory of the Snowflake tables/views that consume customer-billing events from `event_queue_analytics.fifo` (via S3 + `actuate_bi` pipeline) and produce the revenue surface used by Ordway invoicing and the [[sales-dashboard|sales dashboard]].

Closes [[_todos]] C5. Substantially answers ENG-242 (per [[2026-05-11_eng-242-substantially-answered]] — the remaining gap is the upstream DDL files in `actuate_bi/sql/snowflake/`).

Primary sources:
1. [[sales-dashboard-repo|sales-dashboard repo]]'s `CLAUDE.md`, `clients/snowflake.py` (2201 lines), and `scripts/reconcile_cameras.py` (754 lines). Verified 2026-05-11 against `~/work/sales-dashboard` at v0.22.2.
2. [[actuate-bi-repo|actuate_bi repo]]'s `tf/*.tf` (authoritative DDL) + `sql/snowflake/` (reference; **drifts in spots — trust `tf/` first**). Verified 2026-05-11 against `~/work/actuate_bi`.

**Authoritative source for column lists: `tf/*.tf` in actuate_bi.** The `sql/snowflake/*.sql` files are reference and have known drift (`subscription.sql` is missing the load-bearing `special_pricing` BOOLEAN column; `analytics_event.sql` is missing `LOAD_TIMESTAMP`). See [[actuate-bi-repo]] §"Critical drift" for the full list.

## Pipeline overview

```
event_queue_analytics.fifo (SQS, FIFO)
        │
        ▼  consumed by analytics route
  S3 (raw event drop)
        │
        ▼  analytics_event_copy_from_s3 task
  raw.aws.analytics_event              ◄── reports@ has explicit SELECT here
        │
        ▼  view (GROUP BY ALL dedup)
  raw.aws.analytics_event_clean
        │
        ▼  view
  raw.aws.site_product_run_day_last_year   ◄── INNER JOIN top_parent + camera_flags_per_day (silent drop!)
        │
        ▼  daily full-swap task at 01:00 EST / 06:00 UTC
  gold.billing.site_product_run_day  (SPRD — per camera per day)
        │
        ▼  views (business filters, Ordway joins)
  raw.ordway.usage_products    ◄── INNER JOIN raw.ordway.subscription (silent drop!)
        │
        ▼  view (HAVING sum(quantity) >= 3 — the 3h threshold)
  gold.billing.usage_monthly  ◄── the billing surface; what Ordway invoices off
```

**Key mechanism — daily full swap, not Snowpipe.** `gold.billing.site_product_run_day` is rebuilt **whole** at 1 AM EST. Events arriving after that rebuild won't surface in SPRD (or downstream `usage_monthly`) until the next day's rebuild. This is the source of "Snowflake seems a day behind" — it is. ([[sales-dashboard-repo]] FAQ "Why does Snowflake data seem to be a day behind?")

## Table inventory

All tables/views are in the `GOLD` database, except where noted. The `reports@actuate.ai` user has SELECT on GOLD + explicit grant on `raw.aws.analytics_event`. **It cannot reach `raw.ordway.*`** — so anything that needs to join to subscription, product_tier, or customer is forever opaque to that user.

### `gold.billing.usage_monthly` — THE billing surface (VIEW)

Authoritative DDL: `actuate_bi/tf/views_gold_billing.tf` L62-134. Reference: `actuate_bi/sql/snowflake/gold/billing/views/usage_monthly.sql`.

**Structure: UNION of two grouped SELECTs.** First half reads `raw.ordway.usage_products` (core products). Second half reads `raw.ordway.usage_addon` (CHM/Slice/Fisheye). **Both halves apply `HAVING sum(quantity) >= 3`** independently — the 3h threshold gates both surfaces.

Full column list (16):

| Field | Type | Notes |
|---|---|---|
| `top_parent` | string | Customer-hierarchy root (cross-references `gold.billing.top_parent`) |
| `top_parent_id` | int | Numeric pk of the top-parent customer |
| `date` | date | `date_trunc('month', date)` — first-of-month for the billing period |
| `first_date` / `last_date` | date | Activity bounds within the month |
| `quantity` | int | Hours for core products (`product_run_time / 3600`); event count for CHM (per usage_addon comment: "for chm, quantity is healthcheck event count") |
| `description` | string | The **product** name (Intruder, Loitering, Slicing, CHM, etc.) |
| `customer_id` | int | Admin pk |
| `charge_id` | string | Ordway charge id |
| `subscription_id` | string | Ordway subscription id |
| `camera_name` | string | — |
| `camera_id` | int | Connector camera id (matches admin Postgres `inframap_camera.id` for connector integrations) |
| `included_sku` | string | — |
| `last_site_name` | string | — |
| `is_addon` | bool | Addon products (CHM / Slice / Fisheye); **always filter `NOT is_addon` when counting cameras** (per [[sales-dashboard-repo]] CLAUDE.md L158) |
| `days_used` | int | Days within the month the camera ran the product |

**Invariant — the 3h threshold lives ONLY here.** SPRD has every event, no minimum runtime. `usage_monthly` UNIONs two upstream views, **both** with `HAVING sum(quantity) >= 3`. For core products this means 3 hours; for CHM/addons this means 3 events. A camera with 2h 59m runtime on a core product appears in SPRD but not in `usage_monthly` — and therefore is not invoiced.

### `gold.billing.site_product_run_day` (SPRD) — pre-billing event ground truth (TABLE)

Authoritative DDL: `actuate_bi/tf/tables.tf` L58-165. **No `.sql` file** — only the rebuild task references the columns.

Full column list (24):

| Field | Type | Notes |
|---|---|---|
| `event_timestamp` | timestamp | — |
| `start_time` | timestamp | First event in the day for this camera×product |
| `account_stage` | string | (Trial / Pilot / Production / Top Parent / etc.) |
| `top_parent` / `second_parent` | string | Hierarchy |
| `top_parent_id` | int | — |
| `site_name` | string | — |
| `integration_type` | string | [[rtsp-deep-dive|RTSP]], Milestone, Hanwha/DW/Nx, Exacq, Avigilon, Eagle Eye, Auto Patrol / Visual Camera Health, … |
| `customer_id` | int(38,0) | Maps to admin Postgres customer pk |
| `product` | string | Product slug (matches NR log `act_a` field) |
| `camera_id` | int | — |
| `billing_id` | int | (NR log `act_12`) |
| `camera_name` | string | — |
| `camera_view` | string | — |
| `camera_names` | string | LISTAGG of `act_e` |
| `event_type` | string | The producing event type (`site_product_ended`) |
| `product_run_time` | int | **Seconds** of runtime (matches NR log `act_10` field) |
| `run_count` | int | SUM of `act_1` |
| `persp` / `pano` / `slice` / `split` / `fisheye` / `chm` | bool | View-shape + addon flags |
| `subscription_id` | string | Sourced from `top_parent.subscription_code` |

**`data_retention_time_in_days = 1`** on this table — Time Travel is one day. If the daily swap goes wrong, you have a 24-hour window to recover.

**Invariant — SPRD already filtered for hierarchy match.** `site_product_run_day_last_year` (upstream view, `actuate_bi/sql/snowflake/raw/aws/views/site_product_run_day_last_year.sql`) is the source of the swap. It applies three INNER JOINs that silently drop events:

1. `JOIN latest_name l ON ae.act_11 = l.camera_id` — drops events without a camera-id match.
2. `JOIN raw.aws.top_parent t ON l.customer_id = t.customer_id` — drops events whose customer isn't in `top_parent`.
3. `JOIN raw.aws.camera_flags_per_day f ON ae.act_11 = f.camera_id AND date_trunc('day', ae.event_timestamp) = f.event_timestamp` — drops events without a matching day-flags row.

Plus a filter: `event_type = 'site_product_ended' AND event_timestamp >= current_date - interval '1 year'`. Anything older than 12 months silently drops from SPRD on the daily rebuild.

**This is the first silent-drop class** — distinct from the missing-subscription class downstream.

### `gold.billing.clip_received` — clip-pipeline cameras (Sentinel / AI Link / Umbo)

| Field | Notes |
|---|---|
| `clip_header_received` | Event timestamp |
| `site_name` / `camera_name` | The **join key** for clip cameras — NOT `camera_id` |
| `camera_id` | **Often NULL** for clip-pipeline rows |

**Invariant — clip cameras don't have ids on the Snowflake side.** Reconciliation must join on `(site_name, camera_name)`. The reconcile script uses `site_name || '::' || camera_name` as a synthetic key everywhere clip data is touched ([[sales-dashboard-repo]] `snowflake.py` L332-1403).

`clip_received` does **not** flow through SPRD. [[sentinel-components|Sentinel]] Verifier / AI Link / Clips bypass `usage_monthly`'s 3h threshold entirely — they're billed (or not) per clip-received regardless of runtime. Pipeline mapping (per [[sales-dashboard-repo]] CLAUDE.md L298-302):

| Postgres integration_type | Snowflake pipeline | Billed? |
|---|---|---|
| [[rtsp-deep-dive|RTSP]] / Milestone / Hanwha / DW / Nx / Exacq / Avigilon / Eagle Eye / etc. | SPRD → `usage_monthly` | Yes, **iff** 3h+ runtime AND has Ordway subscription |
| [[sentinel-components|Sentinel]] Verifier / AI Link / Clips / Umbo | `clip_received` | Yes (no threshold) |
| Auto Patrol / Visual Camera Health | SPRD (filtered out by `usage_products`) | No — billed externally via Immix |

### `gold.billing.top_parent` — customer-hierarchy dimension

| Field | Notes |
|---|---|
| `top_parent` | Top-of-hierarchy name (the unified account label) |
| `site_name` | Per-site name |
| `customer_id` | Maps to admin `inframap_customer.id` |
| `second_parent` | Intermediate group |
| `top_parent_id` | — |
| `account_stage` | — |

Used to roll up SPRD / clip rows to a single billable account.

### `raw.aws.analytics_event` — lifecycle events (for catch-up billing of deleted cameras)

`reports@` has explicit SELECT here. Used in [[sales-dashboard-repo]] `snowflake.py` to catch up clip cameras deleted mid-month. Field mapping (NR-log-style):

| Field | Meaning |
|---|---|
| `act_1` | Camera ID |
| `act_c` | Integration type (lowercase — `sentinel-verifier`, `ai-link`, `clips`) |
| `act_e` | Site ID (reused; same field is "camera name" elsewhere in NR — see [[billing-events-catalog]]) |
| `event_type` | `camera_onboarded` / `enabled` / `restored` / `deleted` / `disabled` |
| `event_timestamp` | — |

### Tables in `raw.ordway.*` — opaque to `reports@`, but inventoried in actuate_bi

Documented in [[actuate-bi-repo]] but **not queryable from the dashboard's `reports@` auth context.** A Snowflake admin with the right role can SELECT them; the dashboard cannot.

| Name | Type | Path | Purpose |
|---|---|---|---|
| `raw.ordway.usage_products` | VIEW | `actuate_bi/sql/snowflake/raw/ordway/views/usage_products.sql` | **Business-filter view that feeds `usage_monthly` (core products).** Reads `gold.billing.site_product_run_day`. INNER JOIN `product_tier` (product-name match) + INNER JOIN `subscription` on `top_parent_id = customer_id` pivoted on `special_pricing`. WHERE `account_stage='Top Parent' AND product<>'healthcheck' AND pt.active AND integration_type<>'Auto Patrol / Visual Camera Health'`. `quantity = product_run_time / 3600` (hours). |
| `raw.ordway.usage_addon` | VIEW | `actuate_bi/sql/snowflake/raw/ordway/views/usage_addon.sql` | Parallel view for CHM/Slice/Fisheye. `quantity = healthcheck event count` for CHM. |
| `raw.ordway.subscription` | TABLE | **`tf/tables.tf` L968 (authoritative)** — `sql/.../subscription.sql` is stale | 7 columns: `id`, `customer_id`, `customer_name`, `created_date`, `updated_date`, `special_pricing` (BOOLEAN), `environment` (VARCHAR). **`special_pricing` is the load-bearing pivot** for the usage_products join: `(ae.subscription_id = s.id AND s.special_pricing) OR (ae.subscription_id IS NULL AND NOT s.special_pricing)`. Populated by `Load Subscriptions.ipynb`. |
| `raw.ordway.product_tier` | VIEW | `actuate_bi/sql/snowflake/raw/ordway/views/product_tier.sql` | LEFT JOIN `product` → `tier`. Computes **`is_addon = (t.id IS NULL)`** — a product is an addon iff it has no tier mapping. Carries `active` flag from `product` (used to gate usage_products). |

**The `INNER JOIN raw.ordway.subscription` silent-drop** lives inside `raw.ordway.usage_products`. The mechanism: a camera's events reach SPRD, but if no `subscription` row exists matching their `top_parent_id` with appropriate `special_pricing` semantics, they never reach `usage_monthly`. This is the Cohort F6/F5 mechanism ([[2026-05-11_billing-pain-post-mortem]]).

## Pipeline operational risks (added 2026-05-11 from actuate_bi inventory)

These are KB-worthy because they're invisible to the connector and dashboard sides — they live in the Snowflake-task layer between event and billing.

### Risk 1 — SPRD daily swap is NOT transactional

`raw.aws.analytics_event_summarize_daily` (1 AM ET daily) executes 4 DDLs as auto-committed individual statements. If the second RENAME fails after the first succeeds, `gold.billing.site_product_run_day` is **gone** — the previous SPRD has been renamed to `raw.cleanup.site_product_run_old`, and the new SPRD doesn't exist yet under the canonical name. Anything querying SPRD during the failure window sees "table does not exist."

Mitigations today: `allow_overlapping_execution = false` + Snowflake Time Travel (`data_retention_time_in_days = 1`, so 24-hour manual recovery window) + the fact that this has held in practice.

The parallel clip-table swap **does** have `IF EXISTS` on its first RENAME, so it's safer. Tracked in [[_todos]] as NF7 (add the same guard to SPRD swap).

### Risk 2 — `Load Top Parents` race window

The SPRD swap kicks off at 1:00 AM NY. The `Load Top Parents` notebook task fires at 1:01 AM NY (rebuilds `raw.aws.top_parent` from Postgres `vw_top_parent`). If the SPRD swap takes >60s (typically much less, but no upper bound enforced), `Load Top Parents` runs while SPRD is mid-swap. If `vw_top_parent` reads SPRD during that window, behavior is undefined.

Status: theoretical, not observed in practice. Tracked in [[_todos]] as NF7 (alongside the IF EXISTS guard — same task body).

### Risk 3 — `sql/snowflake/*.sql` files drift silently from deployed objects

There is no CI in actuate_bi that diffs reference SQL files against the deployed Terraform-managed objects. Known drift:

- `raw.ordway.subscription` — file shows 5 columns, deployed has 7 (missing `special_pricing` + `environment`).
- `raw.aws.analytics_event` — file shows 35 columns, deployed has 36 (missing `LOAD_TIMESTAMP`).
- `gold.billing.site_product_run_day` — no `.sql` file exists; `tf/tables.tf` is the only source.

Anyone reading the SQL files assuming they're authoritative will get a stale picture. Tracked in [[_todos]] as NF8.

## The two silent-drop classes (CRITICAL for billing reconciliation)

These are the load-bearing failure modes the post-mortem named ([[2026-05-11_billing-pain-post-mortem]] §3):

| Drop class | Lives in | Symptom | Detected by |
|---|---|---|---|
| **Missing `top_parent` mapping** | `site_product_run_day_last_year` upstream view (INNER JOIN to `top_parent` + `camera_flags_per_day`) | Event reaches `raw.aws.analytics_event` but never appears in SPRD | [[sales-dashboard-repo]] `snowflake.py:diagnose_clip_join` (clip side); admin DB anti-join (connector side) |
| **Missing Ordway subscription** | `raw.ordway.usage_products` (INNER JOIN to `subscription`) | Camera appears in SPRD with 3h+ runtime, but NEVER appears in `usage_monthly` | [[sales-dashboard-repo]] `snowflake.py:get_unbilled_sites` — anti-join of SPRD against `usage_monthly` |

The **second** drop class is exactly what Cohort F's F6/F5 sub-cohort hit (392 cameras emitting `_ended` correctly but never invoiced). The repo's `reconcile_cameras.py` script is the operational instrument for detecting it ([[reconcile-cameras-script]] for details).

## Connection / auth contract

| Element | Value |
|---|---|
| Snowflake account | `actuate-ocb47239` |
| User | `reports@actuate.ai` |
| Default warehouse | `DEVELOPMENT` (per `config.py`) or `COMPUTE_WH` (per README test) |
| Database | `GOLD` |
| Permissions | `SELECT` on `GOLD`.*; explicit `SELECT` on `raw.aws.analytics_event`; **NO** access to `raw.ordway.*` |
| Connection timeouts | `login_timeout=30s`, `network_timeout=300s` |
| Secrets path | AWS Secrets Manager: `prod/actuate/sales-dashboard` (key: `snowflake_password`) |
| Region | `us-west-2` (hardcoded in [[sales-dashboard-repo]]) |

**LOCKOUT WARNING.** `reports@actuate.ai` **locks after multiple failed login attempts and may not auto-clear** — a Snowflake admin must manually run `ALTER USER "reports@actuate.ai" SET MINS_TO_UNLOCK = 0;` to release it. **NEVER attempt a connection without `SNOWFLAKE_PASSWORD` set.** ([[sales-dashboard-repo]] CLAUDE.md L41-43, README L132-160.)

The dashboard's connection pool (size 8) handles `_MAX_CONN_AGE=3600s`, `SELECT 1` health checks, and one retry-after-2s on query failure ([[sales-dashboard-repo]] `snowflake.py` L57-127). Any new Tier-1 reconciliation script should mirror this pool discipline rather than open raw connections.

## Field mapping — NR log → Snowflake column

For correlating connector log lines with Snowflake billing rows:

| NR log field | Snowflake column | Meaning |
|---|---|---|
| `act_10` | `product_run_time` (in SPRD) | Seconds |
| `act_11` | `camera_id` | Connector cameras only |
| `act_12` | (billing id) | — |
| `act_a` | `product` / `description` | Product name |
| `act_e` | `camera_name`; also reused as `site_id` in `raw.aws.analytics_event` | — |
| `act_f` | (account name) | — |
| `act_1` | (run count) | — |
| `act_5` | (start time) | — |
| `act_c` | `integration_type` (in lifecycle events) | Lowercased there |

To verify: sum `act_10` from NR for events **before 06:00 UTC** (the SPRD rebuild) and compare to SPRD's `product_run_time` for that day — they should match ([[sales-dashboard-repo]] CLAUDE.md L191-194).

## Implications for the existing KB

### Updates owed to [[billing-events-catalog]]
- §"Schema (best current knowledge)" — drop the "TBD" qualifier; the schema in this note is the authoritative-via-sales-dashboard set.
- §"Transport — `event_queue_analytics.fifo`" — replace "queue_consumer's `analytics` consumer reads, processes, hands off to Snowflake pipeline" with the explicit pipeline diagram above.
- §"Downstream — Snowflake billing tables" — replace "TBD — reading-list item to surface the canonical Confluence page" with this note's table inventory.
- §"`act_a` discriminator values" — note that the values land in SPRD `product` (not under `act_a` in Snowflake); `act_a` is the NR-log/SQS-event vocabulary, not the Snowflake column name.

### Updates owed to [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]]
- §"Data source decision" — Snowflake IS queryable today via `reports@` creds; the NRQL-only stance was based on the C2-blocked assumption. R1's right-side query can be SPRD-based (cleaner) OR NRQL-based (no auth dependency) — both work.
- §"Implementation outline" — much of the work is already done in [[sales-dashboard-repo]]'s `reconcile_cameras.py`; the Tier-1 collector can wrap or copy from it.

## Cross-references

- [[knowledgebase/topics/billing/_summary]] — topic overview
- [[billing-events-catalog]] — the SQS-side vocabulary (this note is the Snowflake-side counterpart)
- [[sales-dashboard-repo]] — entity note for the repo that exposes this data
- [[2026-05-11_eng-242-substantially-answered]] — what ENG-242 asked vs what we found here
- [[2026-05-11_billing-pain-post-mortem]] §"five separate emission-gap classes" — the gaps this table inventory helps detect
- [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]] — needs revising in light of this note
- [[reconcile-cameras-script]] (planned) — operational script that exercises every silent-drop detector
- `actuate_bi` repo (`../actuate_bi/sql/snowflake/`) — where the actual DDL files live; not yet cloned/inventoried
