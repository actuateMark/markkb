---
title: "Roadmap — Watchman + Fleet Architecture"
type: synthesis
tags: [roadmap, watchman, fleet-architecture, home, handoff]
updated: 2026-06-25
author: kb-bot
incoming:
  - home/README.md
  - home/roadmaps/actuate-integration-tools.md
  - home/roadmaps/roadmaps.md
incoming_updated: 2026-06-25
---

# Roadmap — Watchman + Fleet Architecture

> The team's highest-leverage next initiative. This is the forward-looking overview; the deep design record is in [[fleet-architecture/_summary]] + [[watchman/_summary]], and the people/ownership detail is in [[2026-06-23_watchman-fleet-handoff-paolo-mike]]. **Owners: Mike (ENG-300, fleet/K8s) · Paolo (ENG-383, deployer/connector).**

## What these are, and why they're one effort
- **Fleet Architecture** is the redesign of the [[vms-connector/_summary|VMS connector]] away from the **site-per-pod monolith** (one pod per customer, 30+ libraries, [[sharding]] limits ~24 cameras, VPA over-provisioning, schedule race conditions, thundering-herd alerts) toward a **distributed multi-fleet** system where puller / inference / dispatch / coordination scale independently. Five candidate architectures (A–E) were scored; **Proposal E (hybrid sidecar) ranked top (8.05/10)** on cost (−20–40%) + independent scalability.
- **[[watchman-repo|Watchman]]** (PROD-118) is a new **cloud-native AI virtual-security-operator product** (multi-agent: connectivity → patrol → threat-detection → assessment → escalation), going **B2B direct** to mid-market sites (4–30 cameras). It's **greenfield**, so it's being built on a *simplified Proposal E* as its **Phase 0** infrastructure.
- **The link:** [[watchman-repo|Watchman]] Phase 0 is the **first product built on the target fleet shape** — it proves the economics. The growth path is **monotonic** (nothing thrown away): `Phase 0 (E-simplified) → Proposal E proper → v10 Cloud Video Analytics (~100k cameras)`.

## Current state (decided vs open)
**✅ Decided — Phase 0 shape:** E-simplified — uniform [[rtsp-deep-dive|RTSP]] puller fleet + stateless ("trimmed") detection fleet + alert dispatch + a **[[watch-entity|Watch]] Management Service** (fleet-singleton reconciler owning arm/disarm, lifecycle, schedule). Redis Streams frame bus (one stream/camera). RTSP-only, per-camera (no site grouping yet). Motion default-OFF. Backend = doubletake-pattern Lambda invoked during the connector run; dev AWS account + Terraform.

**❌ Open — the blockers to sequence:**
| Decision | Owner | Why it blocks |
|---|---|---|
| **Storage** (Postgres vs OpenSearch vs S3-vector) | Mike + Paolo | Gates the Judge backend schema + API skeleton — *the single biggest blocker* |
| **Lambda invocation** sync vs async | Paolo | Affects connector run lifecycle + write latency |
| **Pipeline-vs-connector parity** (unvalidated) | Paolo | If inputs diverge, backend plumbing breaks |
| **Kafka vs SQS/SNS** inter-agent bus (PRD vs Judge spec conflict) | Brian (product) | Platform-level; blocks Judge integration |
| **WireGuard / site-connectivity** routing for Proposal E | Mike + Paolo | If >20% of sites use per-site tunnels, E's puller design needs rework |
| **Alert ID / "alert group"** definition | Paolo/Valeri | Backend schema depends on it |
| **Hot-reconfigure** (connector has no settings-reload path) | joint | Site Supervisor needs dynamic retune on mode change |

## Recommended path forward
**This week:** joint walkthrough (done/ongoing) → **kick off the storage bake-off** (perf/cost/integration, target a pick by ~mid-July) → Valeri's connector-side Lambda lands, Paolo wires the deployer side → Mike scopes the Proposal E PoC.

**Phase 0 build (~4–6 wks from PoC start), in order:**
1. **M0** repo + skeleton (uv, three base images: puller/detection/WMS, CI).
2. **M1** single-camera vertical slice ([[rtsp-deep-dive|RTSP]] → Redis → detection → inference → sink → mock Judge).
3. **M2** bin-packed puller fleet (uniform pods, `cameras_per_puller`, HPA).
4. **M3** trimmed detection fleet + real Judge emit (SQS), scale on consumer-group lag.
5. **M4** [[watch-entity|Watch]] Management Service (fleet-singleton reconciler: lifecycle, arm/disarm, schedule).
6. **M5** observability + graceful teardown + **measured cost/frames/inference** (validates the economics case).

**In parallel:** storage bake-off → Judge backend schema → Lambda deploy wiring → API for Brad's UI. **Proposal E PoC** (Mike): smart puller w/ inline motion-filter (FDMD), stateful detection core, benchmark motion-drop rate (target 60–80%) + p95 latency.

## Top risks
1. **Storage choice slips → backend slips 4+ weeks.** Run the bake-off now.
2. **Pipeline-vs-connector parity is unvalidated** — audit before M5.
3. **Proposal E hinges on FDMD motion-drop economics** — if drop <50%, the cost case collapses; PoC-measure early.
4. **WireGuard tunnel assumptions** for E's puller fleet — validate site connectivity early.
5. **Stateful detection + spot interruption** — tracker snapshot→Redis→resume must be rock-solid.

## Read next (ranked)
1. [[2026-06-23_watchman-fleet-handoff-paolo-mike]] — the handoff: ownership split, decision gates, reading order. **Start here.**
2. [[2026-06-02_watchman-phase0-fleet-fit]] — the decided Phase 0 shape.
3. [[2026-06-16_watchman-pipeline-backend-meeting]] — newest backend direction (storage open).
4. [[2026-05-28_watch-management-service-design]] — the WMS master design (18 touchpoints, constraints).
5. [[2026-04-16_proposal-e-hybrid-sidecar]] — Proposal E full design (Mike's north star).
6. [[2026-05-29_watchman-judge-backend-io-contract]] — Judge I/O contract (blocks backend schema).
7. [[fleet-architecture/_summary]] · [[watchman/_summary]] — topic overviews (all 5 proposals, v10 platform, product intent).
