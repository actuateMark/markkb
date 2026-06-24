---
title: "ADR: Watchman MVP Slim Connector Design"
type: synthesis
topic: fleet-architecture
tags: [watchman, connector, mvp, design, slim-entrypoint, adr, rtsp]
jira: ""
confluence: ""
created: 2026-06-01
updated: 2026-06-01
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/2026-06-01_terminology-conflict-watchman-ambiguity.md
  - topics/fleet-architecture/notes/syntheses/2026-06-02_watchman-phase0-fleet-fit.md
  - topics/offboarding/notes/concepts/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - topics/personal-notes/notes/daily/2026-06-01.md
  - topics/watchman/_summary.md
incoming_updated: 2026-06-24
---

# ADR: Watchman MVP Slim Connector Design

Architectural decision and plan record for the **[[watchman-repo|Watchman]] MVP slim connector** — a heavily pared-down [[rtsp-deep-dive|RTSP]] ingest path built to feed the cloud [[watchman-repo|Watchman]] platform. Data path: [[rtsp-deep-dive|RTSP]] stream → optional motion gating → AI inference → light detection filtering (confidence + zone only) → emit to [[watchman-repo|Watchman]] services. Built MVP-first, on a foundation that grows into the bigger fleet ecosystem via the event-bus seam.

**Status:** Design complete; no code yet.  
**Decision date:** 2026-06-01  
**Related:** [[2026-06-01_terminology-conflict-watchman-ambiguity|Watchman terminology resolved]], [[2026-05-28_watch-management-service-design|Watch Management Service]], [[watchman/_summary|Watchman Product Summary]]

---

## Goal

A minimal connector for the cloud [[watchman-repo|Watchman]] platform that:
1. Ingests [[rtsp-deep-dive|RTSP]] streams
2. Optionally gates on motion (per-camera toggle)
3. Runs AI inference via direct modern client
4. Filters detections (confidence + zone polygons only)
5. Emits detection metadata to [[watchman-repo|Watchman]] services

Built as a **fresh entrypoint**, not an inheritance hierarchy override, to avoid rewriting sliding-window, metric-counter, and billing machinery. MVP-complete on day one, but architected to grow into the fleet decomposition (Proposals A, E) without a rewrite.

---

## Why a Slim Build, Not Config-Down the Existing Connector

Investigation (2026-06-01) found that while blacklist, observers/trackers, motion, AutoPatrol, and VCH can be toggled off via config, the **sliding-window and metric-counter machinery is structurally embedded**:

- **`build_default_pipeline()`** in `pipeline_factory.py` hard-wires `SlidingWindowDetectionStep`
- **`get_result()`** in `image_pipeline.py` calls `self.window_logic()` unconditionally
- **`send_alerts()`** in `event_library/` sends `site_product_ended` events (billing tied to window close)
- **`endrun()`** in `SiteManager` closes detection windows and calls `send_chm_product_event()` on every exit path

Attempting to "configure the full connector down" to [[rtsp-deep-dive|RTSP]]→inference would force you through:
- `BaseConnectorFactory.__init__()` (billing SIGTERM wiring)
- `AnalyticsSiteManager.endrun()` (billing + window close + observer cleanup)
- Window-shaped `send_alerts()` (metric counters, window reset)

**Result:** overriding more code than you reuse. A new `integration_type` would still inherit the full superstructure. **Therefore: fresh slim entrypoint that imports load-bearing libraries without the window/billing superstructure.**

---

## Confirmed Decisions

1. **Target = cloud [[watchman-repo|Watchman]].** Not the on-prem variant mentioned in the v10 document. See [[2026-06-01_terminology-conflict-watchman-ambiguity]] for disambiguation.

2. **Inference via `actuate-inference-client` (modern client).** Direct call to the production inference endpoint, NOT the legacy `actuate-classic-inference-client` + `YoloClient` + `AsyncInferencePool` path. Clean-slate, adopt modern directly.

3. **Sink transport: HTTP POST (pluggable interface).** Default v1 = HTTP POST of detection metadata + frame reference to [[watchman-repo|Watchman]] service. Behind a `WatchmanSink` interface so v2+ can swap to Kafka / Redis-Streams publisher without touching the ingest+inference core. **This interface IS the event-bus seam from v10 and Proposals A & E** — the extraction point that lets the MVP grow into distributed architectures.

4. **Motion = per-camera toggle, default OFF.** Enable when ONVIF/triggered ingest is added (v10 insists on running own motion on triggered streams — camera triggers are too noisy to trust). MVP: static settings file; growth: dynamic control via [[watch-entity|Watch]] Manager.

5. **Clean separation from monolith.** Slim entrypoint imports libraries; **does NOT inherit SiteManager, Factory, billing, or window superstructure.** Leaning toward a new clean repo or standalone entrypoint in vms-connector (final repo-location decision still open).

---

## Architecture: Minimal Runner

Per camera: **puller thread → frame → inference → filter → sink**.

### Reuse (imported as libraries)

- **`actuate-pullers`** — `AvUrlFramePuller` (basic); `MotionBasedAvUrlFramePuller` behind motion toggle
- **`actuate-inference-client`** — modern direct inference client (replaces AsyncInferencePool + YoloClient)
- **Filter steps** — `raw_model_filter_step` (confidence), `ignore_polygonal_zones_step` (zone polygons)
- **`actuate-inference-objects`** — detection shapes, label constants
- **`build_local_pipeline()`** — reference template at `actuate-pipeline/pipeline_factory.py:150` (windowless pipeline for local YOLO testing)

### Strip / never wire

- **Billing** — no `send_chm_product_event()` / `site_product_ended` events
- **Blacklist** — no per-camera blacklist filtering
- **Observers/trackers** — no BoTSORT, no motion observer, no state persistence
- **Sliding-window products** — no `SlidingWindowDetectionStep`, no window logic, no `metric_counter`
- **Event library / dispatch** — no `MultiAlertSender`, no SQS/Immix delivery
- **AutoPatrol / VCH** — no scheduling, no recurring [[healthchecks]]
- **Diagnostics** — no jemalloc/tracemalloc/memory-breakdown logging (keep lean for MVP)
- **Fork-safety / [[sharding]]** — no multiprocessing (deferred; per-process thread pool on each camera is sufficient for MVP)

### Sink Seam (growth path)

```python
class WatchmanSink:
    async def emit(self, detection_event: Dict) -> None:
        """Emit detection metadata to Watchman services."""
        pass

class HttpWatchmanSink(WatchmanSink):
    async def emit(self, detection_event: Dict) -> None:
        # v1: HTTP POST to Watchman service
        pass

class KafkaWatchmanSink(WatchmanSink):
    async def emit(self, detection_event: Dict) -> None:
        # v2+: event-bus publisher
        pass
```

The sink is **the event-bus extraction point** that lets the MVP grow into Proposal A (Minimal Split: extract puller + alert sender) and Proposal E (Hybrid Sidecar: smart puller + Detection Core) without a rewrite.

---

## How It Maps to the Bigger Ecosystem (Growth Path)

The slim connector is architecturally the v10 **"ingest-streaming + analytics branch"**:
- **[[pyav-entity|PyAV]] ingest** → motion tier-0 gate → detector call → emit

The emit-to-watchman-services boundary is:
- The **v10 event-bus seam** (frame-bus → event-bus transition)
- The **extraction point in Proposal A** (Minimal Split: puller + alert sender split from pipeline)
- The **extraction point in Proposal E** (Hybrid Sidecar: smart puller + Detection Core)

**Density scaling later:** a minimal process-sharding loop (not `ChunkedSiteManager`, which duplicates billing). Keeping the `WatchmanSink` swappable is what lets the MVP grow into the fleet decomposition without a rewrite.

See [[2026-06-01_v10-cloud-platform-vs-fleet-proposals|v10 vs Fleet Proposals]] for how slim connector fits the larger rearchitecture landscape.

---

## Open Items / Next Steps (No Code Yet)

1. **Detection event schema.** Define the detection metadata shape the [[watchman-repo|Watchman]] services expect at the sink endpoint. Coordinate with:
   - [[2026-05-28_watch-management-service-design|Watch Management Service design]] (what does the manager ingest?)
   - [[2026-05-29_watchman-judge-backend-io-contract|Judge agent IO contract]] (alert ingest + disposition shapes)

2. **[[actuate-inference-client|Actuate-inference-client]] surface.** Confirm the modern client's API:
   - Endpoint URL (production vs staging)
   - Request shape (batch size, timeout, retry policy)
   - Response shape (detections, scores, tracking IDs if applicable)
   - Batching strategy (do we batch per-camera or per-site?)

3. **Repo location decision.** Options:
   - New slim repo (e.g., `watchman-slim-connector`) — clean separation, focused CI/CD
   - Standalone entrypoint in `vms-connector` — reuse CI, shared lib deps, but signals "this is another mode of the monolith"
   - **Decision pending:** design is repo-agnostic; either works. Prefer new repo for clean messaging if budget allows.

4. **Settings / config schema.** Define for MVP:
   - [[rtsp-deep-dive|RTSP]] URLs
   - Model configuration (weights, input size, confidence threshold)
   - Sink endpoint ([[watchman-repo|Watchman]] service URL)
   - Per-camera motion toggle (boolean, default false)
   - Zone polygons (per-camera, optional)

5. **How config + scheduling reaches the connector.** Options:
   - **MVP:** static `settings.json` deployed with the pod
   - **Growth:** subscribes to the [[2026-05-28_watch-management-service-design|Watch Manager]] control plane (two-stage resolution: lifecycle → per-product activation) and the scheduler-service (derived from v10 two-stage design)

6. **Reminder:** Per KB feedback ([[feedback_live_streaming_v1_paused|Live Streaming v1 paused]]), Live Streaming v1 implementation and cross-repo BUILD work are gated on explicit user approval. This design/plan level work is fine; code/branches/PRs are blocked until approval.

---

## Success Criteria (MVP)

1. Slim connector ingests [[rtsp-deep-dive|RTSP]], runs inference, emits detection metadata to [[watchman-repo|Watchman]] service without window/billing/blacklist overhead
2. Per-camera motion toggle works (toggle ON → motion filtering applied; toggle OFF → all frames processed)
3. Confidence + zone filtering produces expected detection subsets
4. End-to-end latency [[rtsp-deep-dive|RTSP]] frame → [[watchman-repo|Watchman]] service emit is <5s (p95) on a 10-camera trial
5. Architecture allows growth path to fleet decomposition (Proposals A, E) via `WatchmanSink` interface swap

---

## Related Notes

**Terminology & Context:**
- [[2026-06-01_terminology-conflict-watchman-ambiguity|Watchman Terminology Resolved]] — this is "cloud [[watchman-repo|Watchman]]" scope
- [[watchman/_summary|Watchman Product]] — platform overview, agent architecture, operating modes
- [[2026-05-29_watchman-prds-summary|Watchman PRDs + Agent Specs]]

**Fleet Architecture:**
- [[2026-06-01_v10-cloud-platform-vs-fleet-proposals|v10 vs Fleet Proposals]] — positions slim connector in the broader landscape
- [[2026-06-01_cloud-video-analytics-platform-v10|v10 Source Architecture]] — event-bus seam, detector-router, two-stage resolution reference
- [[2026-04-16_proposal-a-minimal-split|Proposal A — Minimal Split]] — puller + alert sender extraction (reachable via slim connector growth)
- [[2026-04-16_proposal-e-hybrid-sidecar|Proposal E — Hybrid Sidecar]] — smart puller + Detection Core (reachable via slim connector growth)

**[[watch-entity|Watch]] Management Service & Integration:**
- [[2026-05-28_watch-management-service-design|Watch Management Service Design]] — what the manager ingests and how it orchestrates
- [[2026-05-29_watchman-judge-backend-io-contract|Judge Agent IO Contract]] — detection ingest shape, disposition fan-out
- [[2026-05-28_fleet-rearch-briefing-overview|5-Min Briefing]] — TL;DR and proposal context

**Pipeline & Inference Reference:**
- [[build_local_pipeline|Build Local Pipeline]] — windowless pipeline template (actuate-pipeline/pipeline_factory.py:150)
- [[actuate-inference-client|Actuate Inference Client]] — modern inference client API (to confirm vs AsyncInferencePool + YoloClient)
