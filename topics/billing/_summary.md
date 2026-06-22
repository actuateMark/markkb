---
title: Customer Billing Event Pipeline
type: summary
topic: billing
tags: [billing, customer-events, site_product_ended, snowflake, queue-consumer, reconciliation, self-righting]
created: 2026-05-11
updated: 2026-05-14
author: kb-bot
---

# Customer Billing Event Pipeline

The system that decides **what we invoice each customer for**. Specifically: tracking the cost-driving events (`site_product_ended`, healthcheck-fallback emits, patrol completions, etc.) that flow from the [[vms-connector|VMS connector]] → SQS (`event_queue_analytics.fifo`) → queue_consumer analytics route → Snowflake → revenue. Adjacent to but **distinct from** [[aws-cost/_summary|AWS Cost]] (what AWS bills *us*).

Sister surface to [[vms-connector/_summary|vms-connector]] (event producer), [[autopatrol/_summary|autopatrol]] (largest emit source today + cohort-investigation history), [[admin-api/_summary|admin-api]] (source-of-truth state that ought to match what's emitted), and the queue-consumer / analytics consumer (the SQS→Snowflake hop).

## Why this exists

Multiple weeks (PR #1675 → #1680 → #1682 → #1683 → #1684 → #1685 → #1688) of incremental connector PRs to patch billing-emit gaps surfaced one structural problem: there is no single authoritative model of **"a customer is being serviced, therefore an event should be emitted, therefore Snowflake should ingest one, therefore the invoice line should appear"** that we can verify end-to-end. Drift in any of the four hops is invisible until a cohort audit surfaces it. The [[2026-05-06_cohort-f-investigation|Cohort F investigation]] put numbers on it: of 642 silent cameras, **392 were Snowflake-ingestion gaps** (we emitted, Snowflake didn't ingest) and **250 were connector-side emission gaps** (we didn't emit on the failure / empty-products / idle paths). Both classes had been silently leaking customer billing for an unknown period.

This topic exists to make that pipeline **tight** (no leaks) and **self-righting** (drift detected and ideally auto-corrected).

## Founding documents

| Document | Purpose |
|----------|---------|
| [[2026-05-11_billing-pain-post-mortem]] | The narrative — what went wrong over the last several weeks, what we learned, what's still owed |
| [[billing-events-catalog]] | Catalog of every billing-relevant event we emit or consume: name, emit site, consumer, discriminator, current health |
| [[2026-05-14_inference-api-e2m-rules]] | Inference-API E2M billing rules — the NR-side path (parallel to SQS→Snowflake), 3 rules created 2025-09-11 |
| [[2026-05-14_v5-tracking-fields-e2m-design]] | v5 detect tracking fields → E2M design — what PR #71 adds to the NR pipeline, gap analysis, proposed follow-up rules |
| [[_todos\|Topic todo list]] | Tightening / self-righting / reconciliation work — categorized, prioritized, mark-todos-linkable |
| [[reading-list]] | Internal Confluence + external (event-sourcing, idempotency, Snowpipe, reconciliation patterns) |

## Scope

### In scope (this topic)
- **Customer billing events** — emission, transport, ingestion, aggregation. The path from "cronjob fired on customer X's site Y" to "Snowflake row that drives the invoice."
- **Source-of-truth state** for "is this customer/site/camera/product currently billable" — admin `Customer.active`, `Camera.is_deleted`, `AutoPatrolSchedule.is_deleted`, schedule_status, Immix scheduleStatus.
- **Reconciliation surfaces** — admin DB ↔ emitted events ↔ Snowflake ↔ Immix reality.
- **Cohort-based drift audits** (Cohort B/F lineage) — what they surfaced, when to re-run, when to automate.
- **Self-righting hooks** — cleanup-Lambda, cascade-on-delete, propagation hooks. When drift detected, what auto-corrects.
- **Sales-order / billing-profile hierarchy** — [[worklog-alibi-billing-redesign|alibi redesign]] is the foundational primitive at the customer→site→camera→billable-product level.

### Out of scope
- **AWS infra cost** — see [[aws-cost/_summary|AWS Cost]]. The two are linked (per-event SQS PUT cost shows up in aws-cost; the events themselves drive customer revenue here) but the surfaces are different and the audiences are different.
- **Pricing / contract terms** — what we charge per event, contract structures, SO-to-rate mapping. Lives in sales / finance systems, not engineering.
- **Per-tenant invoice presentation** — UI / report rendering downstream of Snowflake.

## Current state (2026-05-11)

| Layer | What we believe is true | Confidence |
|---|---|---|
| **Emission** | `site_product_ended` fires on patrol-success path (originally) + healthcheck-fallback (PR #1682) + misconfigured-fallback (PR #1683) + per-stream idempotency-guarded (PR #1680). `site_product_started` is dormant by policy (PR #1685 / #1688 removed all emit sites). | High — code paths inventoried; cohort F mostly addressed |
| **Crash / early-exit paths** | NOT covered. The 2026-05-07 fleet-wide silent-billing scan showed 79% AP cronjobs / 67% VCH cronjobs with **zero** `_ended` emits in 24h — much higher than the cohort-F-driven expectation. Split across legitimate-completion-but-no-emit (a bug) vs crashed-before-emit (no emit mechanism designed for this) is unresolved. | Low — see [[autopatrol-deferred-backlog]] "Billing emit on crash / early-endrun paths" |
| **Transport** | Connector → `event_queue_analytics.fifo` (SQS FIFO) → queue_consumer (analytics consumer) → Snowflake pipeline (Lambda/Glue/Snowpipe). Volume ~330k `_ended` / 24h cluster-wide. `act_a` discriminator distinguishes `'patrol'`, `'healthcheck'`, etc. | Medium — connector side verified; Snowflake side opaque |
| **Snowflake ingestion** | Per cohort F: F6/F5 (392 cams) were emitted-but-not-ingested. Pipeline owner is the data team. Gap class unconfirmed (event_type filter? `act_a` filter? table-mapping?). | Low — out-of-team-scope investigation |
| **Source-of-truth state** | Multiple gaps inventoried in [[2026-04-30_data-model-cascade-semantics]]: `Customer.active` doesn't propagate to cameras; AutoPatrolSchedule has zero signal wiring; Contract status doesn't cascade to Group/Customer; `Customer.restore()` is partial. | High (in code), Low (whether the drift is intentional vs accidental) |
| **Drift detection** | Manual cohort audits (B/F/etc). The [[autopatrol-cleanup-lambda]] catches one class of drift (Immix-deleted schedule → admin still active) automatically. Nothing systematically watches admin↔emit↔Snowflake. | Low — automation is partial |
| **Self-righting** | §3 cleanup-Lambda (Immix → admin), §25 cascade hook (admin schedule deletion → cascade cameras — disabled, no-backfill ADR 2026-05-07). No connector-side self-righting yet. | Low |

## Key principles

1. **One event class is canonical, and we know which.** Today: `site_product_ended` with `act_a` discriminator. `site_product_started` is dormant; do not re-introduce without consumer-side coordination ([[2026-05-07_site-product-started-deprecated]]).
2. **Emit on every customer-serviced moment, regardless of outcome.** Success, empty-products, misconfigured, idle, crashed — all should leave a billing trace. Crash-path is the current gap.
3. **Idempotency guards everywhere.** Per-stream `_billing_emit_lock` + `_billing_events_fired` (PR #1680); per-Lambda retry-idempotency on DDB counters (PR autopatrol_onboarder#5). New emit sites inherit, don't invent.
4. **Drift is a first-class signal, not an investigation trigger.** If admin says active and Snowflake says nothing, something is wrong — that's a dashboard signal, not a quarterly audit.
5. **Self-right where safe, alert where not.** The cleanup-Lambda is the model: detect drift (Immix-deleted-but-admin-active) → confirm via second source (Immix `get_schedule`) → soft-correct (`is_deleted=True`) → audit trail (Slack + NR custom event). Replicate this pattern up the stack.
6. **Cohort audits are the testing harness until self-righting is everywhere.** Cohort B/F runbooks are reusable — keep them current, run them periodically, retire each when its drift class is fully automated.

## Related topics

- [[aws-cost/_summary]] — adjacent / sister topic. Per-event SQS cost lives there; per-event revenue lives here. Cross-link liberally.
- [[vms-connector/_summary]] — emission code lives here. `connector_factories/shared/billing_emit.py` is the canonical helper.
- [[autopatrol/_summary]] — largest emit source + the cohort-investigation lineage. Cleanup-Lambda + cascade design live here.
- [[admin-api/_summary]] — source-of-truth state. Cascade semantics + signal wiring deep-dive at [[2026-04-30_data-model-cascade-semantics]].
- [[actuate-platform/_summary]] — partner-facing context. [[worklog-alibi-billing-redesign|Sales-order profile redesign]] is the billing-profile primitive.
- [[fleet-architecture/_summary]] — fleet redesign needs to preserve (and ideally tighten) billing emission across whichever paradigm wins. The chosen paradigm must include a "Billing & Reconciliation" subsection on par with the to-be-added "Monitoring & Alarms" dimension.
- [[software-architecture/_summary]] — the enforcement / dashboard sketches should include a billing-drift signal as a first-class panel.

## Status

- 2026-05-11 — Topic created. Founding post-mortem + events catalog + topic todos seeded.
- 2026-05-11 — Tag retrofit pass: every existing note touching customer billing events tagged `billing` and cross-linked.
- Next — work the topic [[todo-list|todo list]] (see [[_todos]]); promote priority items into [[mark-todos]] §N as they become this-week scope.
