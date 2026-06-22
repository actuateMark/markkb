---
title: "ENG-242 — substantially answered by sales-dashboard repo (2026-05-11)"
type: concept
topic: billing
tags: [billing, eng-242, jira-followup, snowflake, sales-dashboard, c2, c5, c6, ticket-status]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
incoming:
  - topics/billing/_todos.md
  - topics/billing/notes/entities/actuate-bi-repo.md
  - topics/billing/notes/entities/sales-dashboard-repo.md
  - topics/billing/notes/entities/snowflake-billing-tables.md
  - topics/personal-notes/notes/daily/2026-05-11.md
incoming_updated: 2026-05-27
---

# ENG-242 — substantially answered by sales-dashboard repo

ENG-242 (filed 2026-05-11) asked the data team for the authoritative Snowflake DDL + consumer-side filter logic for billing tables downstream of `event_queue_analytics.fifo`. Hours later, user surfaced [[sales-dashboard-repo|sales-dashboard]] (`aegissystems/sales-dashboard`) as a likely source. **Investigation 2026-05-11 confirms ~90% of the ticket's ask is answered there.** Remainder is in sister repo `actuate_bi` (not yet cloned).

This note maps ENG-242 ask → what we now know, identifies what's still owed, and recommends next steps for the ticket.

## ENG-242 ask vs what we found

| ENG-242 asked for | What we found | Source |
|---|---|---|
| Snowflake table name(s) — warehouse / schema / table | `gold.billing.usage_monthly`, `gold.billing.site_product_run_day` (SPRD), `gold.billing.clip_received`, `gold.billing.top_parent`, `raw.aws.analytics_event` | [[snowflake-billing-tables]] table inventory |
| Full column list with types | Column lists captured for all 5 tables above (types inferred from query usage; not literal DDL) | [[snowflake-billing-tables]] table inventory |
| Consumer-side filter logic — which `event_type`, which `act_a` values, how `admin_camera_id=null` rows are handled, whether `_MISCONFIGURED_FALLBACK_PRODUCT` participates | (a) 3h threshold lives in `usage_monthly` only, via `HAVING sum(quantity) >= 3`; (b) `is_addon` filter excludes addon products (CHM/Slice/Fisheye) from camera counts; (c) `INNER JOIN raw.ordway.subscription` silently drops cameras without subscription; (d) `INNER JOIN top_parent + camera_flags_per_day` upstream of SPRD silently drops events without hierarchy mapping; (e) clip cameras have NULL `camera_id`, joined via `(site_name, camera_name)`; (f) VCH/Auto-Patrol excluded via `integration_type = 'Auto Patrol / Visual Camera Health'` | [[snowflake-billing-tables]] §"two silent-drop classes" + filter inventory |
| Ingest mechanism (Snowpipe / Lambda+COPY / other) | **Daily full-swap rebuild at 01:00 EST / 06:00 UTC** — not Snowpipe. Pipeline: `analytics_event_copy_from_s3` task → `raw.aws.analytics_event` → dedup view → SPRD swap → usage_monthly (HAVING 3h) | [[snowflake-billing-tables]] pipeline diagram |

## What's still owed (the 10% remaining gap)

The above answers the *intent* of every numbered request in ENG-242, but the **literal DDL files** are not in the [[sales-dashboard]] repo — they live in sister repo `actuate_bi/sql/snowflake/`. Confirming the exact `CREATE TABLE` / `CREATE VIEW` definitions for:

- `gold.billing.usage_monthly`
- `gold.billing.usage_products` (the Ordway business-filter view — where `INNER JOIN raw.ordway.subscription` lives)
- `gold.billing.site_product_run_day`
- `gold.billing.clip_received`
- `gold.billing.top_parent`
- The schedule task that triggers the 1 AM EST swap

…requires either (a) cloning `actuate_bi` and inventorying its `sql/snowflake/` tree, or (b) asking the data team to confirm whether the column lists + filter logic in [[snowflake-billing-tables]] match the authoritative DDL.

Path (a) is on our side and cheap — open work in [[_todos]].

## Recommendation for ENG-242

**Do not close.** Status update + scope reduction. Specifically:

1. **Comment on ENG-242** with:
   - "Substantial progress on our side — [[sales-dashboard-repo|sales-dashboard]] CLAUDE.md + `clients/snowflake.py` + `scripts/reconcile_cameras.py` document the tables, filter logic, and 1 AM EST swap mechanism. We've captured the inventory in our internal KB."
   - "Remaining ask narrowed to: please confirm whether the DDL files in `actuate_bi/sql/snowflake/` are the authoritative source. If yes, no further data-team action needed and we can close. If no, please point us at the canonical doc."
   - "Cloning `actuate_bi` next on our side. Will close this if the DDL files there match our reverse-engineered inventory."
2. **Leave open** until either (a) `actuate_bi` clone confirms, or (b) data-team confirms via Jira reply.
3. **Don't add a deadline** — this is no longer blocking on our side. R1 design can proceed against the known schema; if `actuate_bi` reveals a divergence, that's a re-scope, not a block.

## Downstream effects on the billing topic

Items unblocked by what we've already learned (don't wait on ENG-242 to act on these):

| [[_todos]] item | Status pre-investigation | Status post-investigation |
|---|---|---|
| **C5** — Snowflake-side schema mirror | Blocked on C2 (ENG-242) | **DONE-equivalent** via [[snowflake-billing-tables]] — promote a follow-up to verify against `actuate_bi` DDL |
| **C6** — Locate [[sales-dashboard]] deploy repo | Pending | **DONE** via [[sales-dashboard-repo]] |
| **T2** — Verify `act_a` discriminator coverage | Blocked on data-team confirmation | **Largely answered** — `act_a` in NR maps to `product` / `description` column in SPRD/`usage_monthly`. No `act_a` filter on the consumer side; the implicit filter is `INNER JOIN raw.ordway.subscription`. Open follow-up: confirm exhaustive `act_a` value set against actuate-libraries emit code (purely connector-side work). |
| **T3** — Site-level vs per-stream emit invariants | Blocked on data-team | **Substantially answered** — `admin_camera_id=null` (site-level fallback) rows would never match `camera_id` column on the Snowflake side. They appear in raw events but get dropped at the `INNER JOIN top_parent` step (since the upstream view joins on `customer_id`, not `camera_id`). Site-level fallback emits **don't participate in billing** as currently designed. **This is a real finding for the team** — flag in connector-side review. |
| **T4** — Sentinel-value billing audit | Blocked on data-team | **Substantially answered** — `_MISCONFIGURED_FALLBACK_PRODUCT` would appear in `product` column. Whether it joins to a real product_tier row is opaque to `reports@`. Since `usage_monthly` is built downstream of `usage_products` (which joins to Ordway), a fallback product without an Ordway SKU mapping likely silently drops too. **Confirm with data team.** |
| **R1 design** — admin↔emit dashboard signal | Snowflake-side deferred to R2 | **R2 partially merges into R1** — Snowflake IS queryable today; R1's right side can use SPRD (cleaner) or NRQL (no auth dependency). Update R1 design to note both options. |
| **R2** — Emit↔Snowflake reconciliation (data-team-owned) | Awaiting data team | **Partial unblock** — [[sales-dashboard-repo|`reconcile_cameras.py`]] is essentially the implementation. Wrap it into a Tier-1 signal; data-team engagement now scoped to F6/F5 root-cause only. |

## New follow-ups surfaced by this investigation

To be added to [[_todos]] (see "Updates to topic todos" section below):

- **NF1 — Clone and inventory `actuate_bi` repo.** Find the DDL files. Mirror the relevant ones in [[snowflake-billing-tables]] §"Table inventory." Closes the ENG-242 remainder.
- **NF2 — Promote `reconcile_cameras.py` to a Tier-1 dashboard signal.** Capture stdout output into JSON; classify green/yellow/red per R1 thresholds; schedule via systemd timer. Largely replaces the from-scratch R1 implementation.
- **NF3 — Production unbilled-camera follow-up — 444 cameras across 25 accounts.** Per `reconcile_cameras.py` Feb 2026 baseline ([[sales-dashboard-repo]]), Active [[watch-entity|Watch]] Security (132 cams), Aggregate Industries (102), Eagle Eye Networks (26), Alarm [[watch-entity|Watch]] (46), CAP Security (39) are running billable products but unbilled. **This is a direct revenue leak** — has been for at least a month. Coordinate with sales / billing to follow up.
- **NF4 — Trial conversion candidates — 1,169 cameras across 52 accounts.** Per same source: Securitas Australia (738 cams / 441 avg hrs), Fidelity ADT (20 / 877), Cam Security (11 / 1568) are running at production scale. Sales-facing follow-up.
- **NF5 — Wire [[sales-dashboard]] data into [[2026-05-11_billing-reconciliation-dashboard-design|R1]] more directly.** The dashboard already exposes `/api/unbilled`, `/api/no-usage`, `/api/churn` — R1's signal can be a 1-line HTTP poll instead of re-running queries.

## Updates owed to existing KB

1. **[[billing-events-catalog]]** — drop schema "TBD" qualifiers; replace with confirmed table/column inventory.
2. **[[_todos]]** — update C2, C5, C6, T2, T3, T4, R1, R2 statuses; add NF1-NF5.
3. **[[2026-05-11_billing-reconciliation-dashboard-design|R1 design]]** — note that R2 is partially in-scope (Snowflake queryable today); flag `reconcile_cameras.py` as the implementation; revise "data source decision" matrix.
4. **[[core-repo-suite]]** — move `sales-dashboard` from "Clone on Need" to "Local."
5. **[[mark-todos]] §28** — update Tickets line; surface NF2 as a near-term promotion candidate.

## Cross-references

- [[snowflake-billing-tables]] — the table inventory built from this investigation
- [[sales-dashboard-repo]] — the repo entity note
- [[2026-05-11_billing-reconciliation-dashboard-design]] — R1 design (needs revising in light of this)
- [[billing-events-catalog]] — needs schema-TBD removal
- [[_todos]] — gets multiple status changes
- [[2026-05-11_billing-pain-post-mortem]] — Cohort F6/F5 was exactly the missing-Ordway-subscription drop class
- [[2026-05-11_billing-and-followups-handoff]] — closes handoff item C6 + much of C2
- ENG-242 — the Jira ticket
