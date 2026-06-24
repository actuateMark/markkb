---
title: "Inference API E2M billing rules"
type: concept
topic: billing
tags: [billing, inference-api, e2m, events-to-metrics, new-relic, log-pipeline]
confluence: ""
created: 2026-05-14
updated: 2026-05-14
author: kb-bot
incoming:
  - topics/billing/_summary.md
  - topics/billing/notes/syntheses/2026-05-14_v5-tracking-fields-e2m-design.md
  - topics/inference-api/notes/concepts/2026-05-14_handoff-v5-release-verification.md
  - topics/inference-api/notes/syntheses/2026-05-14_v5-motion-history-single-frame-design.md
  - topics/personal-notes/notes/concepts/2026-06-22_dashboard-signals-catalog.md
  - topics/personal-notes/notes/daily/2026-05-14.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-24
---

# Inference API E2M billing rules

[[new-relic|New Relic]] Events-to-Metrics (E2M) is one of two billing-relevant telemetry paths Actuate operates. Distinct from the [[2026-05-11_billing-pain-post-mortem|customer-event SQS→Snowflake pipeline]] that feeds Snowflake-driven invoicing: E2M generates **NR dimensional metrics** from log records so the same data can be queried with NRQL `FROM Metric` (faster, sub-second over long ranges) and consumed by NR dashboards / alerts / cost reporting.

The canonical definitions live in [`actuate-inference-api/EventsToMetricRules.graphql`](https://github.com/aegissystems/actuate-inference-api/blob/main/EventsToMetricRules.graphql), a one-shot mutation that was run against [[new-relic|New Relic]]'s NerdGraph API on **2025-09-11 by Michael** and is the only source-of-truth for these rules today (no Terraform).

## The three rules in place

All three run against `FROM Log` events emitted by the prod Inference API Lambda (`function_name = 'InferenceAPI-prod'`), and require `fastapi.x-api-key IS NOT NULL` so they exclude unauthenticated probing.

| Metric name | Counts | Source log message | FACET dimensions |
|---|---|---|---|
| `inferenceApi.billing.requests` | One per request | `Received {N} frames for inference - starting inference` | `fastapi.path`, `requester_name` |
| `inferenceApi.billing.frames` | Sum of `{N}` per request (frames-per-request) | same as above (regex-parsed) | `fastapi.path`, `requester_name` |
| `inferenceApi.inference.slices` | Sum of `{N}` (slices-per-request, for sliced models) | `Total slices used for inference: {N}` | `fastapi.path`, `requester_name` |

The log message templates live at `inference_api/api/endpoints/common.py:67` (the `Received N frames` line is emitted at the start of every `_infer` and `infer_multi_model` call). All v3/v4/v5 detect-style endpoints flow through that code path, so the rules apply uniformly across API versions.

## How dimensions are attached

NR Logs carries structured fields, not just the message text. The fields the rules FACET on are attached by:

| Field | Source |
|---|---|
| `fastapi.path` | Powertools `LoggerRouteHandler` middleware (auto-injected on every FastAPI request, includes the route template like `/v5/detect`) |
| `fastapi.x-api-key` | Same middleware, captures request headers |
| `requester_name` | `inference_api/api/middleware/add_requester_name.py:15` — `logger.append_keys(requester_name=name)` after the auth lookup |
| `function_name` | Lambda-runtime metadata (auto on every log) |

Any `logger.append_keys(...)` call inside the handler adds the key to **every subsequent log line on that request**, so any structured field plumbed in there becomes available as an E2M FACET candidate.

## What's NOT yet faceted on

As of 2026-05-14, the three rules pivot **only on `fastapi.path` and `requester_name`**. Anything more granular (per-camera billing, per-request correlation, per-Actuate-camera-ID rollup) requires either:

1. **New E2M rules** that include the additional FACET dimensions — additive, doesn't touch existing series.
2. **Modifying existing rules** — breaking (resets metric history) and not currently the pattern.

The new v5 tracking fields landing in PR #71 (`request_id`, `camera_id`, `actuate_camera_id`) are wired into `logger.append_keys()` at the top of the v5 `detect` handler — they become available as FACET candidates the moment that ships, but no rule consumes them yet. See [[2026-05-14_v5-tracking-fields-e2m-design]] for the gap analysis + proposed follow-up rules.

## Account discrepancy worth flagging

The graphql file targets `accountId: 7081731`. The primary NR account documented in [[new-relic/_summary]] is `3421145`. Possible explanations:

- Sub-account specifically for E2M / billing-data — needs confirmation
- Stale account ID — would mean the rules were never actually created
- Different NR organization

Action: verify in NR UI which account owns these rules. Until verified, treat E2M counts as "best-effort signal" rather than billing-grade truth.

## Related

- [[2026-05-14_v5-tracking-fields-e2m-design]] — synthesis of the new v5 tracking fields and how they extend (don't replace) these rules
- [[billing/_summary]] — broader billing surface
- [[new-relic/_summary]] — NR account / event-type overview
- [[nrql-efficient-query-patterns]] — `FROM Metric` cost discipline
- [[2026-05-11_billing-pain-post-mortem]] — the parallel SQS→Snowflake billing pipeline (separate, complementary)
