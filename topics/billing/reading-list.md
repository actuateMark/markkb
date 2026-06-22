# Reading List: Customer Billing

Sources informing the customer-billing-event topic ([[_summary]]). Organized by theme; biased toward what's directly applicable to the connector → SQS → Snowflake pipeline rather than abstract event-sourcing theory.

Convention: `- [ ] [Title](url) -- short description`. Items marked `*(seed)*` need URL resolution before reading. Check off with `[x]` as read + extract findings into `notes/concepts/` or `notes/syntheses/`.

---

## Internal — Confluence & KB Cross-refs

### Confluence
- [ ] *(seed)* **Billing system architecture** — find canonical Confluence page; if none, this is itself a documentation gap to close. Owner: data team or finance-eng.
- [ ] *(seed)* **Snowflake schemas + billing tables** — what tables are downstream of `event_queue_analytics.fifo`? Which columns drive invoicing? Data-team space.
- [ ] *(seed)* **Sales Order profile design** — Alibi billing-profile redesign Confluence page (parent to [[worklog-alibi-billing-redesign]]).
- [ ] *(seed)* **Customer onboarding flow** — billing-profile creation step; site/SO assignment hierarchy rules.

### Companion KB notes (read before external material)
- [x] [[_summary]] — topic overview
- [x] [[2026-05-11_billing-pain-post-mortem]] — founding doc
- [x] [[billing-events-catalog]] — what events exist
- [x] [[_todos|Topic todos]]
- [x] [[2026-05-07_site-product-started-deprecated]] — the dormant-event warning
- [x] [[2026-05-07_handoff-pr-1681-promotion]] — the deploy chain that closed the recent emit gaps
- [x] [[2026-05-06_cohort-f-investigation]] — the 642-camera audit
- [x] [[worklog-alibi-billing-redesign]] — sales-order profile primitive
- [x] [[2026-04-30_data-model-cascade-semantics]] — admin signal wiring + cascade gaps
- [x] [[autopatrol-cleanup-lambda]] — the prototype for self-righting in this domain
- [x] [[2026-05-04_admin-schedule-cascade-design]] — schedule→camera cascade design
- [x] [[2026-05-05_cohort-b-backfill-runbook]] — cohort-pattern reusable runbook
- [x] [[2026-05-07_cohort-b-no-backfill-decision]] — ADR for not-fixing a cohort
- [x] [[queue-consumer]] — SQS-to-Snowflake transport hop (vms-connector entity)
- [x] [[actuate-queue-consumer]] — library counterpart

---

## Event Sourcing & Idempotent Messaging

- [ ] *(seed)* **Martin Fowler — Event Sourcing** — the canonical framing. Read for vocabulary; our system isn't ES but the language helps.
- [ ] *(seed)* **Pat Helland — "Idempotence Is Not a Medical Condition"** — concise, opinionated; directly relevant to our per-stream idempotency guard pattern.
- [ ] *(seed)* **Exactly-once semantics in SQS FIFO** — AWS docs on `MessageGroupId` + `MessageDeduplicationId`; we use these (or should). Map current connector usage against the doc.
- [ ] *(seed)* **Outbox pattern** (microservices.io) — relevant if we ever decouple "event produced" from "event durably committed" (e.g., write to DB then emit, no in-memory race).
- [ ] *(seed)* **Saga pattern / compensating transactions** — for the reconciliation case where Snowflake ingested a wrong event and the correction is a second event.

## Snowflake & Pipeline

- [ ] *(seed)* **Snowpipe architecture** — what's the data ingestion path from S3/SQS into Snowflake? How does it handle retries / duplicates / out-of-order arrivals?
- [ ] *(seed)* **Snowflake table change tracking / streams** — could be the reconciliation primitive if we want to detect "row not present after expected ingest window."
- [ ] *(seed)* **dbt + billing models** — if billing aggregations are computed in dbt, where do the model definitions live? Who owns them?
- [ ] *(seed)* **Glue vs Lambda for SQS-to-Snowflake** — which we actually use; cost + ops implications. Cross-ref [[aws-cost/cost-architecture]].

## Reconciliation Patterns

- [ ] *(seed)* **Stripe Engineering blog — "Online migrations" / "Idempotent APIs"** — Stripe writes a lot about billing-pipeline correctness; mine for applicable patterns.
- [ ] *(seed)* **Uber Engineering — Money in motion**: any of their billing/financial event posts. Heavy on reconciliation as a first-class system.
- [ ] *(seed)* **Airbnb / Lyft engineering posts on revenue / billing reconciliation** — usually framed as "ledger" or "reconciliation engine."
- [ ] *(seed)* **Bank-grade reconciliation** — Brendan Gregg / Cindy Sridharan posts on systems that have to balance to the cent.

## Observability of Money-Flowing Systems

- [ ] *(seed)* **Charity Majors / Honeycomb — high-cardinality observability** — billing events are inherently high-cardinality (tenant × site × camera × product × event_type × act_a). Mine for how to query without sampling-bias.
- [ ] *(seed)* **OpenTelemetry semantic conventions for messaging** — if we add tracing to the SQS hop, what attributes should be on each span?
- [ ] *(seed)* **NRQL patterns for FIFO queue depth + age** — for the `event_queue_analytics.fifo` health dashboard.

## Internal patterns we ought to copy

The cleanup-Lambda is the existing in-house prototype for self-righting in this domain. Cross-link any future self-righting designs to:

- [[autopatrol-cleanup-lambda]] — entity
- [[2026-04-17_stale-schedule-cleanup-design]] — original design
- [[2026-04-20_cleanup-lambda-runbook]] — operations
- `/autopatrol-cleanup-lambda-check` skill — health monitoring pattern

## Drift / Cohort Audit Lineage

The "find a class of customer where something's wrong, label as Cohort X, run a runbook" pattern is the in-house cohort-audit framework. Cross-link future drift-detection designs to:

- [[2026-05-04_silent-camera-diagnosis]] — original A-F decomposition
- [[2026-05-01_silent-cameras-diagnosis]] — earlier audit
- [[2026-05-05_cohort-b-backfill-runbook]] — DRY-RUN + APPLY pattern
- [[2026-05-06_cohort-f3a-deactivate-runbook]] — patch-script pattern
- [[2026-05-07_cohort-b-no-backfill-decision]] — when NOT to backfill is the right call

---

## How to use this file

1. Items marked `*(seed)*` need URL/page-name resolution. First pass: walk the Confluence space for `billing`, `snowflake`, `sales order`, `invoice`.
2. When an item is read, tick `[x]` and extract findings into `notes/concepts/` (single-source capture) or `notes/syntheses/` (cross-source synthesis).
3. New sources surfaced during work → add here under the right category instead of scattering.
4. Cross-pollinate with [[aws-cost/reading-list]] and [[autopatrol/_summary]] reading lists.

## Related

- [[_summary]] — parent topic
- [[_todos]] — topic todo list
- [[aws-cost/_summary]] — sibling topic (infra cost vs customer revenue)
