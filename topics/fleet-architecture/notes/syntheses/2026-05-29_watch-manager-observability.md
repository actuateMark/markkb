---
title: Watch Manager Observability — Metrics, Traces, Audit, SLOs
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: fleet-architecture
type: synthesis
tags: [watchman, fleet-architecture, manager-service, observability, instrumentation, slo]
related:
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-29_ait-watch-manager-integration]]"
  - "[[2026-05-29_watch-manager-failure-modes]]"
  - "[[topics/new-relic/_summary]]"
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/manager-touchpoint-catalog.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-failure-modes.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_site-supervisor-vs-watch-manager.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-backend-io-contract.md
incoming_updated: 2026-05-30
---

# Watch Manager Observability — Metrics, Traces, Audit, SLOs

## Why this note exists

The May 28 syntheses cover the *what* of the manager service but barely the *how-do-we-know-it's-working*. Touchpoint T18 (audit log) is one line. With [[watchman-repo|Watchman]] SLAs being **sub-2s [[webrtc-deep-dive|WebRTC]] live view** and **sub-10s detection-to-notification**, the manager's transition latency and reconcile-loop correctness must be observable end-to-end. This note pins the observability surface.

## Design principles

1. **Cardinality discipline.** Every metric labeled by `watch_id` will explode (~5k Watches ×  ~10 transition causes = 50k series). Default to `site_id` + `product` labels; use `watch_id` only on diagnostic counters with bounded retention.
2. **Trace propagation across the full chain.** Scheduler → manager → K8s → connector pod → SQS/Kafka billing event. Without a single trace ID, "did this arm actually result in a billed run?" requires correlation by timestamp + customer_id — fragile.
3. **Audit ≠ metrics ≠ logs.** Three sinks, three retention tiers, three query patterns. Don't conflate.
4. **Cardinality on the audit side is fine** — ClickHouse handles wide-cardinality, low-frequency writes well.

## Metrics catalog

### Reconcile loop
- `watch_manager_reconcile_tick_total{outcome=success|partial|fail}` — counter
- `watch_manager_reconcile_tick_duration_seconds` — histogram, buckets `[0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]`
- `watch_manager_reconcile_drift_size{type=arm|disarm|reconfigure}` — gauge, count of (observed ≠ desired) Watches per tick
- `watch_manager_reconcile_actions_total{action=create_deployment|delete_deployment|create_cronjob|delete_cronjob|patch}` — counter

### Transitions
- `watch_manager_transition_total{from, to, cause=cron|override|api|reconcile}` — counter
- `watch_manager_transition_latency_seconds{cause}` — histogram from intended-transition-time to actual K8s mutation issued
- `watch_manager_arm_now_latency_seconds` — histogram for manual override transitions (target: p95 < 5s)

### Schedule evaluation
- `watch_manager_eval_duration_seconds` — histogram for `evaluate_armed(...)` calls
- `watch_manager_eval_dst_skipped_total{tz, year}` — counter, increments when a DST spring-forward causes a skipped transition (constraint T3 from master)

### Manual overrides
- `watch_manager_override_apply_total{kind=arm|suppress}` — counter
- `watch_manager_override_active{kind}` — gauge
- `watch_manager_override_expired_total` — counter
- `watch_manager_override_revoked_total` — counter

### Manager → K8s actuator
- `watch_manager_k8s_call_total{verb=create|update|delete, resource=deployment|cronjob|vpa, outcome}` — counter
- `watch_manager_k8s_call_duration_seconds{verb, resource}` — histogram
- `watch_manager_k8s_orphan_total{resource}` — counter, K8s objects manager doesn't recognize (reconcile garbage)
- `watch_manager_deployer_retries_total` — counter for `connector_deployer` HTTP retries (today's 5-attempt exp backoff)

### Billing-event subscription (T17)
- `watch_manager_billing_observed_total{event=site_product_started|ended, run_id_class}` — counter
- `watch_manager_billing_expected_total` — counter; per-Watch run expectations the manager has issued
- `watch_manager_billing_missing_total{reason}` — counter, exactly-once-emit invariant violations (constraint #1) — alert on `>0` in 1h
- `watch_manager_billing_duplicate_total` — counter, same warning

### State store
- `watch_manager_state_read_duration_seconds{store=postgres|redis|raft|kafka}` — histogram
- `watch_manager_state_write_duration_seconds{store}` — histogram
- `watch_manager_state_consistency_check_total{outcome}` — counter (relevant for Raft / B′ where consistency invariants are stronger)

## Trace propagation

End-to-end trace IDs across:

```
scheduler tick → manager reconcile → K8s API → connector pod → SQS/Kafka billing → ClickHouse audit
```

Inject `trace_id` and `span_id` into:
1. The transition event Kafka envelope (`{watch_id, from, to, cause, trace_id, span_id}`).
2. The K8s mutation as an annotation: `actuate.io/trace-id: <id>`. Pod startup reads the annotation and adopts it as the root context for its lifetime.
3. The connector's `site_product_started`/`site_product_ended` SQS message body.
4. ClickHouse audit row.

OTLP via the existing `actuate-instrumentation` library (which is the home for shared instrumentation primitives per [[project_actuate_instrumentation_intent]]).

## Audit log

Every state-changing event lands in ClickHouse table `watch_manager_audit`:

```
event_id      UUID
event_ts      DateTime64
event_type    Enum8('transition', 'override_applied', 'override_expired', 'override_revoked',
                    'k8s_mutation', 'schedule_edit', 'reconcile_drift_detected')
watch_id      String
site_id       String
product       String
actor         String      -- user_id | "system:cron" | "system:reconcile"
trace_id      String
payload       JSON        -- event-type-specific
```

Retention: 13 months (covers a full year of audit history). Partitioned by month.

## SLOs

| SLO | Target | Measurement | Burn-rate alert |
|---|---|---|---|
| Manager reconcile tick success rate | 99.95% per 30d | `sum(reconcile_tick{outcome="success"}) / sum(reconcile_tick)` | 14x in 1h or 6x in 6h |
| Arm-now transition latency p95 | < 5s | `histogram_quantile(0.95, watch_manager_arm_now_latency_seconds)` | breach > 30 min |
| Scheduled-transition latency p99 | < 60s (matches Option B tick) | `histogram_quantile(0.99, transition_latency{cause="cron"})` | breach > 30 min |
| Billing exactly-once invariant | 100% per day | `(billing_observed - billing_expected) == 0` | any deviation pages immediately |
| K8s mutation success rate | 99.9% per 7d | counter ratio | 14x in 1h |
| Schedule eval correctness | (verified by Hypothesis CI) | n/a — property test count | CI gate, not runtime alert |

## Observability hooks tied to AIT testing

From [[2026-05-29_ait-watch-manager-integration]], hooks 1–4 are observability primitives that *also* enable test fixtures. The intersection:

| Hook | Observability value | Test value |
|---|---|---|
| 1. Structured transition events | Kafka topic with all transitions — feeds audit and downstream agents | F8 reconcile replay needs these events as input |
| 2. Idempotency keys on K8s mutations | Replay safety in prod; orphan detection | F4 contract testing asserts key presence and uniqueness |
| 3. Reconcile-loop telemetry | Operational visibility into drift convergence | Hypothesis "drift converges in K ticks" property |
| 4. Pure-function evaluation seam | Local debugging of "why is this [[watch-entity|Watch]] armed at this time?" | F2 / F9 property tests pivot off this seam |

**Build hooks 1–4 first.** They earn double payback (observability + tests).

## NR / Grafana dashboards needed

1. **Manager overview** — reconcile success rate, drift size trend, K8s mutation rate, p95 arm-now latency.
2. **Per-site [[watch-entity|Watch]] state** — current armed Watches per site, transition events in last 24h, manual overrides active.
3. **Billing invariant** — observed vs. expected, missing/duplicate counter trend; this is the "are we losing money?" dashboard.
4. **DST + day-boundary** — `eval_dst_skipped_total` trend; spike around DST dates.
5. **Reconciler drift over time** — `reconcile_drift_size` rolling average; a healthy manager has near-zero drift between ticks.

## NR query reference

Following the global CLAUDE.md NR query rules (aggregate first, scope to cluster_name = 'Connector-EKS', tight time windows, small `LIMIT`, named attributes):

```sql
-- Recent reconcile loop failures
SELECT count(*), latest(message)
FROM Log
WHERE container_name = 'watch-manager'
  AND level = 'ERROR'
  AND message LIKE '%reconcile%'
FACET site_id
SINCE 1 hour ago
LIMIT 10

-- Arm-now latency p95 trend
SELECT histogram(arm_now_latency_seconds, 50)
FROM Metric
WHERE service = 'watch-manager'
TIMESERIES SINCE 1 hour ago

-- Billing invariant breaches
SELECT count(*)
FROM Log
WHERE container_name = 'watch-manager'
  AND message LIKE '%billing_missing%'
SINCE 1 day ago
```

## Cross-references

- [[2026-05-28_watch-management-service-design]] — master design (T18 audit log → expanded here)
- [[2026-05-29_ait-watch-manager-integration]] — instrumentation hooks 1–12
- [[2026-05-29_watch-manager-failure-modes]] — partition behavior and alerting correlation
- [[topics/new-relic/notes/concepts/nrql-efficient-query-patterns]]
- [[topics/new-relic/notes/concepts/nr-connector-query-cookbook]]
- [[project_actuate_instrumentation_intent]] — `actuate-instrumentation` is the home for OTLP primitives
