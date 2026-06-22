---
title: "site_product_started is functionally dead — do not re-enable"
type: concept
topic: vms-connector
tags: [vms-connector, billing, site_product, deprecation, warning]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming:
  - topics/billing/_summary.md
  - topics/billing/_todos.md
  - topics/billing/notes/entities/billing-events-catalog.md
  - topics/billing/notes/syntheses/2026-05-11_billing-pain-post-mortem.md
  - topics/billing/reading-list.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/vms-connector/notes/concepts/2026-05-07_handoff-pr-1681-promotion.md
incoming_updated: 2026-05-27
---

# `site_product_started` is functionally dead — do not re-enable

**Audience:** anyone touching `connector_factories/shared/billing_emit.py`, `connector_factories/shared/base_connector_factory.py`, `connector_factories/autopatrol/autopatrol_factory.py`, `site_manager/connector/integrations/autopatrol_site_manager.py`, or any per-stream billing-event code in the connector.

## TL;DR

The `site_product_started` SQS event type **is not consumed by downstream billing**. Only `site_product_ended` is. Do NOT re-introduce calls to emit `site_product_started` in production code paths — they generate SQS volume that has no effect on billing aggregates and dilutes signal in dashboards.

The string `"site_product_started"` and the underlying mechanism still exist in the codebase as **dormant infrastructure**, retained in case downstream billing decides to consume it in the future. The shared helper `emit_site_product_event_for_streams` is event-name-agnostic by design — it's the call sites that have been removed.

## Why it's here at all

PR #1675 (2026-05-06) added a `startrun()` → `_emit_site_product_event("site_product_started")` pattern at the top of `AutoPatrolConnectorFactory.default()`, paired with `_emit_site_product_event("site_product_ended")` at every exit path. The intent was a started/ended billing pair per cronjob run so each customer's run was billable independent of patrol-completion outcome (the cohort F4/F3 silent-cam class in the [[2026-05-06_cohort-f-investigation]]).

Subsequently (PR #1684, 2026-05-07) it was confirmed that downstream only consumes `_ended`. The `_started` emit was net SQS waste. PR #1684 removed all calls to emit `_started` from production code paths but kept the helper event-name-agnostic to preserve the option of reviving `_started` cleanly later.

## What was removed in PR #1684

- `BaseConnectorFactory.startrun()` — the public method, deleted entirely
- The `self.startrun()` call at `AutoPatrolConnectorFactory.default()` line 50
- The `self._emit_site_product_event("site_product_started")` call in `BaseConnectorFactory.__init__`'s empty-`camera_streams` early-exit path
- All tests asserting `_started` emit behavior (the `TestStartrunEndrunWrappers.test_startrun_emits_started_and_does_not_exit` test, the `test_started_and_ended_track_independently` test, etc.)

## What's still in the codebase

- `emit_site_product_event_for_stream` and `emit_site_product_event_for_streams` in `connector_factories/shared/billing_emit.py` — event-name-agnostic helpers; can emit any event name. Today they're only ever called with `"site_product_ended"`.
- `BaseConnectorFactory._emit_site_product_event(event_name)` — the per-factory wrapper around the helper. Same agnostic behavior.
- `_HEALTHCHECK_FALLBACK_PRODUCT` (renamed to `_MISCONFIGURED_FALLBACK_PRODUCT` in PR #1683) and `_SITE_LEVEL_SENTINEL_CAMERA_ID` constants — unchanged.
- The `_billing_emit_lock` + `_billing_events_fired` per-stream idempotency guard from PR #1680 — still keyed on `(event_name, admin_camera_id)`. If `_started` were re-emitted, the guard would naturally separate it from `_ended`.

## Re-enabling guidance (if this ever needs to come back)

If downstream billing ever decides to consume `site_product_started`:

1. **Confirm the consumer-side change first.** Check `queue_consumer/` for the new handler. The connector should NOT emit `_started` events that downstream simply throws away.
2. **Restore the call sites surgically:**
   - Add `self._emit_site_product_event("site_product_started")` at the top of `AutoPatrolConnectorFactory.default()` (post-`__init__`, pre-patrol-fetch loop)
   - Add a matching emit in `BaseConnectorFactory.__init__`'s empty-`camera_streams` path BEFORE the `_ended` emit
   - Mirror the per-stream + site-level fallback paths (the helper handles both because it's event-name-agnostic)
3. **Restore tests:**
   - `TestEmitSiteProductEventHelper.test_emits_started_for_each_stream_x_product` (deleted in PR #1684; check git log for the original)
   - `TestBillingEmitIdempotency.test_started_and_ended_track_independently` (verifies the guard's per-event-name keying works for both)
   - `TestEndrunWrapper` → resurrect a `TestStartrunEndrunWrappers` form covering both
4. **Coordinate with billing system:** ensure billing-side aggregations include `_started` events; verify dashboards / queries don't double-count.

## Observability gotcha

If `_started` IS accidentally re-emitted today (e.g. someone copies one of the dead helpers in a new factory), the connector will:
- Generate SQS messages that queue_consumer's billing handlers will accept but ignore (queue_consumer routes by `event_type`)
- Dilute `event_queue_analytics.fifo` volume metrics
- Show up in `/dashboard-check` signals as fleet billing-volume drift
- Pass all tests that don't check call counts

There is no exception, no error log, no fleet-wide signal that catches it directly. The way you'd notice is unexplained SQS volume increase or noticing "we're emitting events nobody reads."

## Related

- PR #1675 — added the `startrun()` mechanism + `_started` emit
- PR #1680 — per-stream idempotency guard (still used by `_ended`)
- PR #1682 — added the `"healthcheck"` fallback (renamed to `"misconfigured"` in PR #1683)
- PR #1683 — renamed fallback + added site-level emit for empty camera_streams
- **PR #1684 — REMOVED `_started` calls; this is the deprecation pivot point**
- [[2026-05-06_cohort-f-investigation]] — original silent-cam analysis that motivated the started/ended pair design
- `connector_factories/shared/billing_emit.py` — the event-name-agnostic helper (still in use for `_ended`)
- [[autopatrol-deferred-backlog]] — "Billing emit on crash / early-endrun paths" follow-up item
