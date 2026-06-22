---
title: "AdminDAO Call-Site Inventory"
type: concept
topic: data-access-control
tags: [admindao, migration, api-design, phase-2, inventory, vms-connector]
created: 2026-05-11
updated: 2026-05-13
author: kb-bot
incoming:
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_admin-incident-catalog.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-developer-tokens.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-vini-gateway.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-reliability-fix-plan.md
  - topics/data-access-control/notes/syntheses/2026-05-13_dig-followups.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/daily/2026-05-11.md
  - topics/personal-notes/notes/daily/2026-05-13.md
incoming_updated: 2026-05-27
---

# AdminDAO Call-Site Inventory

System-wide audit of every `AdminDAO` call site across the Actuate repo set (`/home/mork/work/`), categorized for the Phase 2 deprecate-and-replace migration. Initial audit conducted 2026-05-11 as a follow-up to [[2026-05-11_admin-db-access-hardening|the admin DB access hardening plan]]; **scripted re-audit landed 2026-05-13** and is now the source of truth.

> **Authoritative source (re-runnable):** `/home/mork/work/scripts/data-access-control/admindao-inventory.py` regenerates the inventory from current code. Output CSV at `/home/mork/work/scripts/data-access-control/output/admindao-inventory.csv`; markdown table at the same path with `.md`. The tables below are kept for narrative grouping; the script is canonical when they disagree.

## Headline (revised 2026-05-13)

**22 findings across 14 distinct files** (imports + instantiations + method calls combined). The narrative shorthand is "~10-14 sites" depending on count method; tractable in one focused sprint either way:

- **4 vms-connector Bucket B sites** — same `get_product_by_metrics` query pattern, one new endpoint covers all four. Plus 1 commented-out reference (`base_stream_camera.py:1337`) that's defensive evidence the pattern was contemplated elsewhere.
- **4 method-call Bucket A sites** — `actuate-monitoring` NR-mute (2), `queue_consumer/webhook` (`list_webhooks`), `queue_consumer/health` (`get_cameras`). Mechanical swaps.
- **4 Bucket C imports** — admin mgmt commands (2) + BI notebooks (2). Stay direct-DB.
- **Wrapper-only pattern (1, missed by initial audit):** `actuate-config/.../customer_config.py:48,58` instantiates `AdminDAO` solely to access its `.admin_api` attribute (`AdminDAO(...).admin_api.list_ai_models()`). Already API-routed semantically; migration is dropping the AdminDAO wrapper and instantiating `AdminApi` directly.
- **`queue_consumer/consumers/health/health_consumer.py:4,18` (missed by initial audit)** — instantiates AdminDAO + calls `get_cameras`. Bucket A; mechanical.

**The single highest-leverage endpoint to build:** `GET /api/option/?metric_names=X,Y,Z` — collapses the 4 `get_product_by_metrics()` sites in vms-connector (billing pipeline, feature → product SKU mapping) into one well-defined API call.

## Related direct-Postgres surface (not AdminDAO, but in-scope for Phase 2)

The scripted audit also surfaced two **non-AdminDAO direct-DB consumers** that the original synthesis missed entirely. See [[#Cross-references|cross-refs]] for the script that surfaced them:

- **`actuate-libraries/actuate-integration-calls/.../milestone/milestone_service.py:715`** — defines `pg_connection()` that reads `prod/actuate/postgres` directly via `psycopg2.connect`. Already carries `# TODO remove this entirely.` Library-level direct-DB inherited by every consumer that pulls the library.
- **`sales-dashboard/src/sales_dashboard/clients/postgres.py:31` + `scripts/reconcile_cameras.py:87`** — reads the admin secret, connects to `actuateadmin` DB. Self-documented as "READ ONLY" but enforced only by convention. **[[sales-dashboard|Sales-dashboard]] is a non-admin direct-DB consumer never mentioned in the synthesis.**

These belong in Phase 2's scope, not as Bucket additions to this AdminDAO inventory.

## Bucket A — Existing AdminApi method covers (mechanical swap)

Revised 2026-05-13 from script output:

| Repo | Call site | Method | Target AdminApi method |
|---|---|---|---|
| `queue_consumer` | `consumers/webhook/webhook_consumer.py:81` | `list_webhooks(stream_id=...)` | `AdminApi.list_webhooks()` |
| `queue_consumer` | `consumers/health/health_consumer.py:32` | `get_cameras(site_id)` | `AdminApi.list_cameras()` |
| `actuate-libraries/actuate-monitoring` | `src/actuate_monitoring/newrelic_monitor.py:86` | `get_new_relic_mute_rule_id(deployment_id)` | already an AdminApi wrapper internally; migration is dropping the AdminDAO instantiation |
| `actuate-libraries/actuate-monitoring` | `src/actuate_monitoring/newrelic_monitor.py:89` | `reset_new_relic_mute_rule_id(deployment_id)` | same as above |
| `actuate-libraries/actuate-config` | `src/actuate_config/connector/base_config/customer_config.py:58` | `AdminDAO(...).admin_api.list_ai_models()` (wrapper-only) | instantiate `AdminApi` directly; no DB code path involved |

**Risk:** Low. Each is a 1:1 swap with no semantic change. Cutover behind a flag, verify in stage, roll forward.

## Bucket B — New endpoint required

| Repo | Call site | Query intent | Endpoint to build |
|---|---|---|---|
| `vms-connector` | `chunked_site_manager.py:152` | `get_product_by_metrics()` — feature → product SKU mapping | `GET /api/option/?metric_names=X,Y,Z` |
| `vms-connector` | `patrol_site_manager.py:225` | same | same |
| `vms-connector` | `analytics_site_manager.py:1253` | same | same |
| `vms-connector` | `billing_emit.py:105` | same | same |

All four are the **same query pattern** invoked from different lifecycle hooks. One endpoint design covers all four sites. ~6 lookups per site session, so this is also the highest-frequency Bucket B query and a candidate for short-TTL caching.

**Risk:** Medium. This is on the billing path, which has tight correctness requirements ([[billing/_summary|Customer Billing Event Pipeline]]). Cutover needs careful testing — emit count must remain exactly once per camera per run.

## Bucket C — Out of scope (stays direct-DB)

| Repo | Surface | Disposition |
|---|---|---|
| `actuate_bi` | `noteboooks/src/admin_queries.py` + `.sql` files on disk | Stays — BI uses read-only role against read replica (per locked-in decisions). Revisit when Snowflake-style export is on the table. |
| `actuate_admin` | `inframap/management/commands/admin_dao_db_cleanup.py` | Stays — admin is the canonical data-model writer. |
| `actuate_admin` | other internal mgmt commands | Stays for the same reason. |

## Migration sequencing recommendation

**Phase 2a (Bucket A — ~4h):**
1. Swap all 6 Bucket A call sites to existing `AdminApi` methods.
2. Per-service API tokens already in place; verify token use is correct for each consumer.
3. Verify in stage; roll to prod behind a feature flag where the framework allows.

**Phase 2b (Bucket B — ~16h):**
1. Design `GET /api/option/?metric_names=X,Y,Z` endpoint on admin.
2. Add `required_scope` declaration (likely `options:read` or `billing_metrics:read` — depends on scope vocabulary decision).
3. Add `AdminApi.list_options_by_metrics()` method to `actuate-admin-api`.
4. Consider short-TTL cache in the connector for the lookup (this query was ~6/site/session — caching reduces admin load).
5. Cut over each vms-connector call site behind a flag. Validate billing emit count invariant in stage before prod.

**Phase 2c (cleanup):**
1. Remove `AdminDAO` import / `actuate-daos` AdminDAO usage from vms-connector and queue-consumer.
2. Once no non-admin consumer depends on `admin_dao.py`, move it into admin's own source tree and drop it from the `actuate-daos` package.

## Observations

- **The migration is much smaller than the "many services touching DB" framing suggested.** Once you separate Dynamo DAOs (out of scope) from the lone `AdminDAO` (in scope), there are ~10-14 call sites — not hundreds.
- **One pattern dominates Bucket B.** The `get_product_by_metrics()` repetition in vms-connector is 4 of the 4 Bucket B sites, all the same query. That's a strong signal it should have been a shared helper from the start; building it as one endpoint cleanly addresses the duplication.
- **No exotic queries.** Every call site maps to a clean REST endpoint. We don't need a generic "execute SQL via HTTP" escape hatch — confirms the Option Y decision was the right one.
- **Billing path is the riskiest cutover.** vms-connector's billing emit invariant has been the subject of multiple PRs (#1663, #1667, #1682, #1683, #1685). Phase 2b needs explicit test coverage of the emit lifecycle when admin API is reachable, slow, and unreachable.
- **Library-level consumers are part of the surface, not just service-level.** `actuate-monitoring` and `actuate-config` each instantiate `AdminDAO` inside library code; the synthesis's "only `admin_dao.py` needs migration" framing in §2.4 is misleading because the *consumer-side instantiation patterns* in those libraries also need rewriting. The data model boundary is correct (admin owns the schema); the migration scope is bigger than "one file" suggests.
- **[[sales-dashboard|Sales-dashboard]] and `actuate-integration-calls/milestone_service.py` are non-AdminDAO direct-DB consumers** that need their own migration plan — they're not in this inventory because they don't use AdminDAO, but they ARE in Phase 2's scope. See script `postgres-direct-callers.py` for the broader surface.

## Cross-references

- [[2026-05-11_admin-db-access-hardening]] — parent synthesis
- [[2026-05-11_admin-incident-catalog]] — admin reliability incidents that motivate the Phase 0 baseline
- [[2026-05-13_dig-followups]] — design dig follow-ups and pressure-test findings (2026-05-13)
- Scripts (authoritative source): `/home/mork/work/scripts/data-access-control/`
  - `admindao-inventory.py` — AdminDAO usage (this inventory's source)
  - `postgres-direct-callers.py` — broader Q2 surface (psycopg2, wireguard, etc.)
  - `admin-api-surface.py` — admin endpoint inventory (Phase 3 scope-vocabulary supply side)
  - Outputs: `output/*.csv` + `output/*.md`
