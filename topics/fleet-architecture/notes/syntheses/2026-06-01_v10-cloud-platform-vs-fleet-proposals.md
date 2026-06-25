---
title: "Cloud Video Analytics v10 vs Fleet-Architecture Proposals — Alignment & Distinctions"
type: synthesis
topic: fleet-architecture
tags: [cloud-platform, v10, proposals, scheduler-service, detector-router, frame-bus, comparison, watchman]
jira: ""
confluence: ""
created: 2026-06-01
updated: 2026-06-01
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_v10-scheduler-and-state-resolution.md
  - topics/fleet-architecture/notes/syntheses/2026-06-02_watchman-phase0-fleet-fit.md
  - topics/personal-notes/notes/daily/2026-06-01.md
incoming_updated: 2026-06-25
---

# Cloud Video Analytics v10 vs Fleet-Architecture Proposals

**Received:** 2026-06-01. External design doc (Cloud Video Analytics Platform v10 — production cloud SaaS for ~100k cameras) cross-examined against our existing fleet-rearchitecture proposals (A–E, 2026-04-16).

**TL;DR:** v10 is **not** a fleet proposal per se. It's a **fully designed, specific architecture** for the cloud-only product. It aligns with features from proposals B, E, and the [[watch-entity|Watch]] Management Service design, but is a **forward-looking reference architecture**, not a replacement for the rearchitecture work. Below: where v10 reuses our designs, where it introduces new ideas, and what it clarifies about proposal feasibility.

## Alignments with Existing Work

### Frame-Bus (Redis Streams)

**v10:** Redis Streams, sharded by camera_id, TTL ≤5s. Carries lo-res JPEG (60 KB, 640×640, q=85) + motion polygon bbox-of-union. Post motion-gating: ~8 GB/sec.

**Existing:** Our [[2026-04-16_frame-transport-comparison]] evaluated Redis Streams for proposals A, B, E. This is the same bus. v10 **confirms** Redis Streams viability at 100k-camera scale and adds specific JPEG settings + motion-polygon payload schema.

**Implication:** Proposals B and E (both Redis frame-bus designs) gain real production reference numbers. L8s throughput target (<8 GB/sec post-gating) is a tuning spec we didn't have before.

### Scheduler-Service

**v10:** Stateless Python service, sharded by tenant_id. Two-stage resolution: camera lifecycle first, then per-product activation. Triggered by EventBridge (time), alarm-panel events, customer overrides. <100ms rule eval latency, <1s override propagation. Emits commands on `control` topic.

**Existing:** Our [[2026-05-28_watch-management-service-design]] designs a similar manager-service with lifecycle + product-state stages, but scopes it to [[watch-entity|Watch]]-level state (one [[watch-entity|Watch]] = one camera in some proposals, multiple in others). v10's scheduler-service is the **specific realization for the cloud product.**

**Implication:** Scheduler-service design space is **well-validated.** The two-stage approach (lifecycle-then-product) is the right granularity. Sparse rule storage + evaluation-time precedence resolution avoids the operational burden of dense per-(camera, product) configs. This suggests proposals B/E should lean on similar scheduler design.

### Detector-Router (NEW in v10)

**v10:** c8g.large × 4 reads per-(camera, product) state from scheduler-service, forwards frame-bus messages **only** to detector pools whose product is active. Primary cost-control gate.

**Existing:** None of our 5 proposals explicitly designed a per-product routing layer. This is **genuinely new.** It's the mechanism by which per-product scheduling actually saves cost — a consumer of detector CPU happens only if the product is ON for that camera right now.

**Implication:** Proposals B, C, D, E should adopt detector-router (or equivalent per-product fanout logic) as a cost-control component. This is a small stateless service but load-bearing for pricing model coherence.

### Frame-Bus + Event-Bus Split

**v10:** Hi-res pixels never traverse event-bus. Frame-bus carries lo-res only; downstream services (VLM, clip assembly) HTTP-fetch hi-res from ingest worker's ring buffer.

**Existing:** Proposal B (Stage Fleets) assumes frame-bus transience. Proposal E (Hybrid Sidecar) keeps hi-res on the ingest tier. v10 **formalizes this** as an architectural principle: "frame-bus for lo-res feed, hi-res stays on ingest, fetch on demand."

**Implication:** All proposals should adopt frame-bus as lo-res-only. This has cost implications (no Kafka throughput for pixel data) and API implications (ref-fetch endpoint on ingest workers is now standardized). Matches Proposal E's sidecar design pattern.

### Motion as Tier-0 Detection

**v10:** Motion detection runs in ingest, publishes first-class motion events with polygon coords to event-bus. Downstream uses: detector region-restriction (sparse YOLO), tracker still-time, LLM queries.

**Existing:** Proposals mention motion-gating but v10 **elevates** motion to first-class. It's not just a gate; it's a publishable signal that unlocks downstream optimizations. Aligns with motion polygon region-restriction in Proposal B.

**Implication:** Motion as a product/feature (not just an internal gate) is now confirmed for the cloud product. This unlocks UI features ("show motion events at 3am") and cost optimizations (motion-restricted detector regions).

### Site-State-Service (v1 Core)

**v10:** Real-time per-site rollups (active alarms, occupancy, activity vs baseline, camera health, business context). Redis materialization + ClickHouse snapshots, sharded by site_id. Defined as **v1 core capability, not premium.**

**Existing:** Proposals mention site intelligence but don't deeply specify the streaming aggregator. v10 **pins the architecture** (Redis for real-time, ClickHouse for history, site_id [[sharding]]) and **product positioning** (core, not premium). The [[2026-05-28_watch-management-service-design]] assumes similar rollup logic.

**Implication:** Site-state-service should be in the base proposal designs, not optional. It's foundational for "site-level NL intelligence" and for [[llm-service|LLM orchestration tools]].

### Observability Split (NR + ClickHouse)

**v10:** [[new-relic|New Relic]] for APM/alerting/ops logs. ClickHouse (already deployed for event-store) absorbs high-volume per-event logs. Saves $50-100k/mo vs full [[new-relic|New Relic]] at 100k cameras.

**Existing:** Proposals don't deeply specify observability layering. v10 **concretizes** the split: ClickHouse is not just a data warehouse; it's the hot path for high-cardinality observability. OpenTelemetry for vendor independence.

**Implication:** Observability cost is now part of cost models for proposals. ClickHouse partitioning strategy (tenant+site+day) should inform data-model choices in proposals.

## v10's New Contributions (Not in Proposals)

### Per-Product Cost Control via Detector-Router

v10 explicitly gates detector CPU by per-(camera, product) state via a dedicated router service. This is the mechanism by which per-product scheduling translates to cost savings. Proposals conceptually allow per-product scheduling but don't explicitly detail the cost-realization layer.

**Add to proposals B/C/D/E:** Detector-router (or equivalent fanout logic) should be specified as a load-bearing component.

### Two-Stage Resolution (Lifecycle + Product)

v10 separates camera lifecycle (is it streaming?) from product activation (which products active on this streaming camera?). This prevents a bug class where product rules are set but camera isn't streaming.

**Add to proposals:** Scheduler-service designs should adopt two-stage resolution as standard.

### Precedence Stack (5-Level Inheritance)

1. Active override (customer, explicit expiry)
2. Alarm-panel state (if applicable)
3. Camera-level rule
4. Site-level rule
5. Tenant default

v10 formalizes this precedence. Proposals mention sparse rules but don't specify the precedence order. **This should be standard across all proposals.**

### Sparse Rule Storage Schema

Concrete config example showing tenant_default + site-level overrides + camera-level overrides. Most customers set tenant default and a handful of overrides. The schema avoids dense per-(camera, product) explosion.

**Add to proposals:** Exact config schema (or template) for sparse rule storage.

### Hardware Specifics (2026 Silicon Roster)

v10 includes a detailed 2026 silicon roster:
- **Graviton4 c8gn.4xlarge** (200 Gbps NIC) for ingest / media
- **Inf2.xlarge** for YOLO (CNN canonical good-fit for Inferentia)
- **G6e.xlarge** for weapon detector (CUDA flexibility)
- **G7e.2xlarge** for VLM (**Blackwell, RTX PRO 6000, 96GB, new Feb 2026**)
- **Trn2.48xlarge** for LLM self-hosted summarization

Proposals have silicon choices scattered; v10 centralizes them. The **G7e.2xlarge for VLM is particularly new** (2026 availability) and suggests GPU fleet planning should account for Blackwell availability.

## Distinctions: v10 is Not a Fleet Proposal

v10 is a **finished product architecture** for a specific cloud-only offering (~100k cameras, us-west-2, multi-tenant SaaS). It does **not** replace the fleet-rearchitecture work (which is about decoupling vms-connector from site-per-pod monolith into independent services).

### Why v10 is Different

| Aspect | Fleet Proposals A–E | v10 |
|--------|-------------------|-----|
| **Scope** | How to split/scale the vms-connector pipeline | Turnkey cloud SaaS architecture |
| **Deployment** | Kubernetes (either site-per-pod or stateless fleets) | Explicitly AWS (EC2 instances specified by type/count) |
| **Multi-tenancy** | Not a focus (proposals assume single-site scaling) | Multi-tenant (tenant_id [[sharding]] on multiple services) |
| **State model** | Varies by proposal (some stateful, some immutable) | Explicitly stateless + cache (scheduler-service is stateless; state lives in config-service) |
| **On-prem deployment** | Not addressed | Explicitly out of scope ("Cloud-only by design; on-prem is [[watchman-repo|Watchman]]") |
| **Customer API** | Not addressed | REST (override-service) + webhook (alarm-panel) + web UI |

### Where Fleet Proposals Apply

Proposals A–E are for **decomposing vms-connector** — the ingest, pipeline, alert subsystem that ships to customers for deployment. v10 assumes a different topology entirely (managed cloud service, multi-tenant, no edge deployment).

**If** we decide to offer v10 as a product, proposals A–E still apply **within** v10's architecture. For example:
- **If v10 uses Proposal B (Stage Fleets):** ingest-streaming pods scale independently from detector-intruder pods, etc. within Kubernetes.
- **If v10 uses Proposal E (Hybrid Sidecar):** ingest-streaming is smarter, stateful; inference/alert fleets are dumb consumers of frame-bus.

The proposals are **orthogonal** to v10's product design. v10 specifies WHAT the service does; proposals specify HOW to decompose the vms-connector to serve it.

## Terminology Conflict: "Watchman" Ambiguity

**CRITICAL FLAG:** See [[terminology-conflict-note-watchman-ambiguity]].

v10 explicitly states (line 312): "Edge inference. Cloud-only by design. On-prem deployment is a separate product ([[watchman-repo|Watchman]]), not this one."

**BUT:** Our existing KB `watchman/_summary.md` defines [[watchman-repo|Watchman]] as a **cloud-native AI security operator platform** — not an on-prem product.

These two usages of "[[watchman-repo|Watchman]]" **directly conflict:**
- **v10's usage:** [[watchman-repo|Watchman]] = on-prem/edge product (distinct from this cloud platform)
- **KB's usage:** [[watchman-repo|Watchman]] = cloud-native multi-agent product (includes cloud deployment options)

**Resolution needed:** Clarify whether [[watchman-repo|Watchman]] is (a) cloud-only, (b) on-prem-only, (c) both, or (d) a portfolio of products. This affects product positioning and the cross-repo dependencies documented in [[2026-05-28_watch-management-service-design]].

---

## Recommendations for Proposal Updates

### Short term (before PoC selection):

1. **Add detector-router** to proposals B, C, D, E as a cost-control component
2. **Adopt two-stage resolution** (lifecycle + product) in scheduler-service designs
3. **Standardize precedence stack** (override > panel > camera > site > tenant) across all proposals
4. **Document sparse rule storage schema** with concrete examples

### Medium term (after PoC selection):

1. Use v10's silicon roster as a data point for cost models in the selected proposal
2. Validate Redis Streams settings (JPEG quality, TTL, throughput) against proposals B/E
3. Plan observability (NR + ClickHouse split) as part of deployment specs
4. Clarify [[watchman-repo|Watchman]] product boundaries (cloud vs edge vs both) before cross-repo dependency mapping

---

**v10 summary location:** [[2026-06-01_cloud-video-analytics-platform-v10]]
**[[watch-entity|Watch]] Management Service:** [[2026-05-28_watch-management-service-design]]
**Proposals index:** [[fleet-architecture/_summary#Candidate Architectures]]
