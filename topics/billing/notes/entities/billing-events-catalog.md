---
title: "Billing Events Catalog"
type: entity
topic: billing
tags: [billing, customer-events, catalog, site_product_ended, site_product_started, act_a, sqs, snowflake, queue-consumer]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
[]
incoming:
  - topics/billing/_summary.md
  - topics/billing/_todos.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/concepts/2026-05-11_eng-242-substantially-answered.md
  - topics/billing/notes/entities/actuate-bi-repo.md
  - topics/billing/notes/entities/sales-dashboard-repo.md
  - topics/billing/notes/entities/snowflake-billing-tables.md
  - topics/billing/notes/syntheses/2026-05-11_billing-pain-post-mortem.md
  - topics/billing/reading-list.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
incoming_updated: 2026-05-12
---

# Billing Events Catalog

Single source of truth for **every event in the customer-billing pipeline**. Each row: name, emit site, current consumer status, discriminator semantics, and current health. New billing-emit code MUST update this catalog in the same PR as it ships. New consumers MUST reference rows here.

This is the artifact whose absence cost us the [[2026-05-11_billing-pain-post-mortem|April-May 2026 firefight]] (Lesson 1).

## Event types

| Event name | Status | Producer(s) | Consumer | Discriminators | Last verified |
|------------|--------|-------------|----------|----------------|---------------|
| `site_product_ended` | **CANONICAL** — current billing pipeline runs on this | [[vms-connector|VMS connector]] — `connector_factories/shared/billing_emit.py` via `emit_site_product_event_for_stream(s)` | queue_consumer (analytics route) → [[snowflake-billing-tables|Snowflake billing tables]] | `act_a` (one of `patrol`, `healthcheck`, …); `admin_camera_id`; `product` | 2026-05-08 — ~446k/12h on stage, steady ([[2026-05-07_handoff-pr-1681-promotion]] §"Update 2026-05-08") |
| `site_product_started` | **DORMANT** — do not re-emit without consumer-side coordination | None in production code paths (all emit sites removed in PR #1685) | Not consumed by downstream billing | (would mirror `_ended`) | 2026-05-08 — 0/12h verified on stage |
| `subscription_started` / `subscription_ended` | **NOT IN CONNECTOR'S VOCABULARY** | None | Unknown | — | 2026-05-06 — confirmed 0 cluster-wide ([[2026-05-06_cohort-f-investigation]]) |
| `detection_started` | **NOT IN CONNECTOR'S VOCABULARY** | None | Unknown | — | 2026-05-06 — confirmed 0 cluster-wide |

## `site_product_ended` — the canonical event

### Schema (best current knowledge)

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `event_type` | string | hardcoded `"site_product_ended"` | Routed on by queue_consumer |
| `act_a` | string | per-emit-site | `patrol` (AutoPatrolConnectorFactory), `healthcheck` (VCH / CHM cronjobs), … |
| `admin_camera_id` | int / null | per-stream | `null` for site-level fallback emits (empty `camera_streams` case, PR #1683) |
| `product` | string | per-product loop OR fallback constant | Real product slug OR `_MISCONFIGURED_FALLBACK_PRODUCT` (formerly `_HEALTHCHECK_FALLBACK_PRODUCT` until PR #1683's rename) |
| `cid` | int | per-customer | Customer id (admin pk) |
| `tenant_id` | string | per-customer | Immix tenant UUID |
| `timestamp` / `time` | ISO-8601 | emit time | — |
| (additional fields) | — | TBD | Snowflake side may filter / project; full schema lives on the consumer side |

**Action item:** [[_todos]] item "Lock the event schema" — get authoritative schema from data-team / Snowflake table definition. Catalog rows above are reverse-engineered from emit code + NR logs.

### Emit sites (current — post PR #1688 bundle)

| Path | Trigger | Per-stream or site-level | act_a | Idempotency-guarded |
|------|---------|--------------------------|-------|---------------------|
| `AutoPatrolConnectorFactory.default()` — exit paths | every cronjob run completion (incl. error / empty-patrol-list) | per-stream | `patrol` | yes — `_billing_emit_lock` + `_billing_events_fired` (PR #1680) |
| `BaseConnectorFactory.__init__()` — empty-`camera_streams` site-level fallback (PR #1683) | site has zero cameras configured | site-level (`admin_camera_id=null`) | `patrol` (?) | yes |
| Healthcheck / VCH cronjob paths | every healthcheck cycle | per-stream | `healthcheck` | yes |
| Healthcheck fallback for empty products (PR #1682) | products list empty | per-stream | `healthcheck` w/ `_MISCONFIGURED_FALLBACK_PRODUCT` | yes |

### Emit sites NOT covered (the still-open crash-path gap)

Per [[autopatrol-deferred-backlog]] "Billing emit on crash / early-endrun paths" — the 2026-05-07 fleet-wide silent-billing scan showed 79% AP / 67% VCH cronjobs with zero `_ended` emits over 24h, far in excess of the cohort-F-driven prediction. The split between "completed but didn't emit" (a bug) vs "crashed before emit" (no mechanism) is unresolved. Options under consideration:

1. Emit `_started` at run-startup (would resurrect the dormant event — requires consumer-side coordination).
2. External watcher (pod-exit-without-billing-event → synthetic event).
3. atexit hook (limited by SIGKILL).

This is the largest known gap in the catalog. **Owned by topic todo "Close the crash-path emit gap."**

### Idempotency semantics

Per-stream guard, keyed `(event_name, admin_camera_id)`:

- Held in `BaseConnectorFactory._billing_emit_lock` + `_billing_events_fired`.
- Survives the `_started` retraction because the key includes `event_name` — when `_started` was emitted, it had its own entry separate from `_ended`.
- **Per-process, not per-cronjob-instance.** A new process gets a fresh set. SQS-side idempotency (FIFO `MessageDeduplicationId`) is the durability primitive for at-most-once across retries; this in-process guard prevents emit-twice within a single run.

## Transport — `event_queue_analytics.fifo`

- **SQS FIFO queue** in prod account `388576304176`, region `us-west-2`.
- **Volume**: ~330k `_ended` events / 24h cluster-wide (2026-05-06 measurement).
- **Routing**: queue_consumer's `analytics` consumer reads, processes, hands off to Snowflake pipeline.
- **FIFO ordering / dedup**: see SQS-FIFO docs. We use `MessageGroupId` for ordering (likely per-cid or per-tenant — confirm). Dedup window 5 min default.

## Downstream — Snowflake billing tables

- **Owner**: data team.
- **Path**: SQS → queue_consumer/analytics → ??? → Snowflake (likely Snowpipe or Lambda + COPY INTO).
- **Tables**: TBD — reading-list item to surface the canonical Confluence page.
- **Ingestion gaps observed**: Cohort F6/F5 (392 cams) emitted `_ended` correctly but Snowflake didn't ingest. Probable causes inventoried in [[2026-05-06_cohort-f-investigation]] §3: event_type filter, `act_a` filter (e.g., `healthcheck` events dropped), or table-mapping mismatch. Out-of-team-scope investigation; data-team handoff via cohort_f_tracker.json.

## `act_a` discriminator values

Current known values (non-exhaustive — confirm from emit code):

| `act_a` | Emitter | Meaning |
|---------|---------|---------|
| `patrol` | AutoPatrolConnectorFactory | A patrol cronjob completed (success / error / empty-list / misconfigured) |
| `healthcheck` | VCH / CHM healthcheck cronjob | A healthcheck cycle completed |
| (other?) | — | Audit emit-site code for any other producers |

**Action:** verify the exhaustive set by grepping `act_a=` in connector + library code; if any consumer drops a specific `act_a`, that's a candidate billing leak.

## Fallback constants

Per [[2026-05-07_site-product-started-deprecated]] + cohort-F PR history:

- `_HEALTHCHECK_FALLBACK_PRODUCT` — original name; pre-PR #1683. Used when a healthcheck-only site has empty `products`.
- `_MISCONFIGURED_FALLBACK_PRODUCT` — current name (post-PR #1683 rename). Same role. Renamed because "healthcheck-fallback" was ambiguous with the act_a discriminator.
- `_SITE_LEVEL_SENTINEL_CAMERA_ID` — placeholder `admin_camera_id` used in site-level fallback emits when the site has zero `camera_streams`.

## Cross-cutting code references

| File | Role |
|------|------|
| `vms-connector: connector_factories/shared/billing_emit.py` | Event-name-agnostic helpers: `emit_site_product_event_for_stream`, `emit_site_product_event_for_streams` |
| `vms-connector: connector_factories/shared/base_connector_factory.py` | `BaseConnectorFactory._emit_site_product_event(event_name)` wrapper + idempotency guard |
| `vms-connector: connector_factories/autopatrol/autopatrol_factory.py` | `AutoPatrolConnectorFactory.default()` — primary `patrol` emit site |
| `vms-connector: site_manager/connector/integrations/autopatrol_site_manager.py` | Site-manager-level emit sites |
| `queue_consumer: consumers/analytics/` | The SQS→Snowflake handoff for `event_queue_analytics.fifo` |
| `actuate-libraries: actuate_queue_consumer` | Library that queue_consumer derives from (see [[actuate-queue-consumer]]) |

## Lifecycle invariants we want to enforce

These are aspirational — the topic todos own the enforcement plan. Not all hold today.

1. **Every cronjob run that begins MUST emit at least one billing event before its process exits, regardless of exit cause.** (Today: violated on crash path.)
2. **Every billing event with a non-null `admin_camera_id` MUST correspond to an `is_deleted=False, active=True` Camera row in admin DB at emit time.** (Today: drift between admin and Immix means this is sometimes violated; cleanup-Lambda + cascade hook are the partial mitigations.)
3. **Every billing event sent to SQS MUST be reflected in Snowflake within X minutes (target: 10).** (Today: drift between SQS and Snowflake is invisible without a manual cohort audit; cohort F surfaced it.)
4. **No billing event MUST be emitted twice for the same `(event_name, admin_camera_id, run_id)`.** (Today: held by `_billing_emit_lock` in-process; SQS FIFO dedup window backs it; cross-process duplication on cronjob-retry is not currently checked.)
5. **The dormant `site_product_started` event MUST NOT be reintroduced without consumer-side coordination.** ([[2026-05-07_site-product-started-deprecated]] is the explicit warning.)

## Related

- [[_summary]] — topic overview
- [[2026-05-11_billing-pain-post-mortem]] — why this catalog exists
- [[_todos]] — work to operationalize the invariants
- [[2026-05-07_site-product-started-deprecated]] — dormant-event warning
- [[2026-05-06_cohort-f-investigation]] — gap inventory
- [[queue-consumer]] — SQS-to-integration entity (vms-connector)
- [[actuate-queue-consumer]] — library counterpart
