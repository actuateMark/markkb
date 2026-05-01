---
title: "Observability & Tracing Requirements per Proposal"
type: concept
topic: fleet-architecture
tags: [observability, new-relic, tracing, otel, logs, metrics, nrql]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/reading-list.md
incoming_updated: 2026-05-01
---

# Observability & Tracing Requirements

Today's monolith is relatively easy to observe: one pod per site, one log stream per site, `container_name` scopes everything. Fleet architectures fragment that — logs and metrics now scatter across service types. This note catalogs what each proposal demands of our [[new-relic|New Relic]] setup ([[new-relic/_summary]]).

## Today's observability baseline

- **Logs:** connector writes structured logs; forwarded to NR. ~1.85B INFO / 26.5M WARNING / 187K ERROR per 24h.
- **Metrics:** `K8sContainerSample`, `K8sPodSample` from NR infrastructure agent.
- **Traces:** none. No distributed tracing today.
- **Query patterns:** [[new-relic/notes/concepts/nrql-efficient-query-patterns]] — always scope by `cluster_name = 'Connector-EKS'` + `container_name`.
- **Log-level strategy:** [[new-relic/notes/concepts/nr-log-level-strategy]].
- **Cookbook:** [[new-relic/notes/concepts/nr-connector-query-cookbook]] — ready-to-paste NRQL for common investigations.

## Additional surface area per proposal

| Proposal | New service types | Distributed tracing | Log scope needed |
|----------|:-----------------:|:--------------------|------------------|
| A — Minimal Split | +2 (puller, alert-sender) | Optional (single-hop) | Add `service_name` attribute; cookbook needs +2 service entries |
| B — Stage Fleets | +4 (motion, inference-coord, observer, alert-sender on top of puller) | **Mandatory** — 4 hops, can't debug without it | Major cookbook rewrite |
| C — Camera-Worker | +1 (worker, replacing pipeline-worker) + controller | Optional (in-process) | Primary key shifts from `site_id` to `worker_id`+`camera_id` |
| D — Event-Driven | +3 (puller, detector, observer) + alert-sender | **Mandatory** — 4 hops across 2 infra components (NATS + S3) | Traces must span NATS + S3 operations |
| E — Hybrid Sidecar | +3 (smart puller, detection core, alert dispatch) + site-context service | Strongly recommended (3 hops) | Log scope by `camera_group_id` |

## Distributed tracing strategy (for B, D, and E)

### OpenTelemetry + NR

- **Instrument at service boundaries only.** Every RPC, every Redis XADD/XREADGROUP, every NATS publish/subscribe, every S3 PUT/GET.
- **Propagation:** use the W3C `traceparent` header over HTTP and embed span IDs in Redis/NATS message metadata.
- **Sampling:** 1% head-based sampling for routine traffic; 100% tail-based when latency exceeds SLO. NR supports both.
- **Backend:** NR supports OTel natively (`otlp.nr-data.net`). No new backend.

### Span IDs as log correlation keys

- Every log line should include `trace_id` and `span_id` attributes so NR lets you click from log → trace → related logs.
- Propagate via `actuate-log` library — small surgical change.
- Once in place, debugging a slow frame is: grep by `frame_id` across services, see all spans, drill into the slow one.

## Metrics to emit per proposal

Every proposal needs the following custom metrics in addition to standard K8s metrics:

### Shared (all proposals)
- `actuate.frames.processed` (counter, by `camera_id`, `fleet`, `stage`)
- `actuate.frames.dropped` (counter, by reason)
- `actuate.inference.latency.ms` (histogram, by `model_id`)
- `actuate.tracker.snapshot.latency.ms` (histogram)
- `actuate.alert.emitted` (counter, by `integration_type`)

### Proposal-specific
- **A, B, D, E:** `actuate.stream.lag.entries` (gauge, per stream/camera) — backpressure signal
- **B, D:** `actuate.hop.latency.ms` (histogram, per hop)
- **C, E:** `actuate.worker.cameras.owned` (gauge, per worker pod) — bin-packing health
- **C:** `actuate.assignment.churn.rate` (counter) — rolling update health
- **D:** `actuate.s3.put.bytes`, `actuate.s3.get.bytes` — cost visibility
- **E:** `actuate.motion.drop.rate` (gauge, per camera) — the proposal's linchpin metric

## Log scoping strategy changes

Today: `cluster_name = 'Connector-EKS' AND container_name = 'vms-connector'` and `site_id = 'X'`.

### A
Scope becomes `container_name IN ('puller', 'pipeline-worker', 'alert-sender')`. Site-level aggregations still work via `site_id` attribute.

### B
`container_name IN ('puller', 'motion', 'inference-coord', 'observer', 'alert-sender')`. **Camera-level aggregations require propagating `camera_id` into every log entry across every service.** Non-trivial — audit every log line before cutover.

### C
**Shift primary key to `camera_id` + `worker_id`.** Cookbook ([[new-relic/notes/concepts/nr-connector-query-cookbook]]) needs rewriting — site-level investigations become "which workers have cameras from site X?" followed by per-worker lookup.

### D
Similar to B. Additional: S3 and NATS operation logs flow through their own event types; need query templates.

### E
`container_name IN ('smart-puller', 'detection-core', 'alert-dispatch', 'site-context')`. Camera-group aggregations via `camera_group_id`.

## Alerting policy changes

- **Today:** alert on container CPU > X, log-level ERROR > Y/min, VPA recommendations.
- **Fleet:** alert on stream lag (any proposal with streams), assignment churn (C), motion-drop rate out-of-band (E).
- **Per-fleet alert policy files** needed for each proposal — [[new-relic/_summary]] lists accounts and tools.

## Enhancement opportunities

- **Write service-agnostic NR queries now.** Instead of hardcoding `container_name = 'vms-connector'`, use a `service_category = 'connector'` tag. Multi-fleet future-proofing on today's setup.
- **Adopt OTel auto-instrumentation library for Python.** Zero-effort tracing for urllib3, httpx, redis clients. Would benefit today's monolith too.
- **Formalize log-line schema.** Every log must have `trace_id`, `span_id`, `camera_id`, `frame_id`, `site_id`. Enforcement via fitness function ([[2026-04-16_architecture-enforcement]]).
- **Build a fleet-health dashboard** in NR — [[2026-04-16_code-health-dashboard]] is the template. One page, per-fleet panels.

## References

- [[new-relic/_summary]]
- [[new-relic/notes/concepts/nrql-efficient-query-patterns]]
- [[new-relic/notes/concepts/nr-log-level-strategy]]
- [[new-relic/notes/concepts/nr-connector-query-cookbook]]
- [[new-relic/notes/concepts/nr-programmatic-deep-links]]
- [[2026-04-16_code-health-dashboard]]
