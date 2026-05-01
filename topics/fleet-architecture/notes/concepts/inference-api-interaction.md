---
title: "Inference API Interaction — Shared Dependency Across All Proposals"
type: concept
topic: fleet-architecture
tags: [inference, async-inference-pool, aimd, ds-server, lambda, shared-dependency]
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
  - topics/video-processing/notes/syntheses/decode-locality-per-proposal.md
incoming_updated: 2026-05-01
---

# Inference API Interaction

Every fleet proposal calls the inference API. The AIMD-controlled `AsyncInferencePool` is a shared primitive whose placement, reuse, or duplication is itself a design axis. This note captures how each proposal sits against the existing inference system.

## Background

- **Inference API** is a Lambda-deployed FastAPI service — [[inference-api/_summary]]. It is permanent K8s-exempt; connector pods call it via HTTPS.
- **`AsyncInferencePool`** — [[vms-connector/notes/concepts/inference-pool]] — consolidates all HTTP inference calls onto a single asyncio event loop in a daemon thread. AIMD (Additive Increase Multiplicative Decrease) congestion control: window starts 48, floor 8, ceiling 200; target 200 ms latency.
- **[[ds-server-container]]** — Rust YOLO inference server (separate from the Lambda API for some workloads). Per-model.

## Per-proposal placement

| Proposal | Where `AsyncInferencePool` runs | Pool count at 10× fleet |
|----------|--------------------------------|------------------------|
| A — Minimal Split | Pipeline worker (1 per site, unchanged) | ~N sites — same as today |
| B — Stage Fleets | **Dedicated Inference Coord fleet** (or every observer pod calls directly — open question) | Fewer, larger pools |
| C — Camera-Worker | Worker pod (1 per worker, shared across its camera group) | N workers ≪ N sites today |
| D — Event-Driven | Detector fleet (inference happens in detector stage) | Similar to B |
| E — Hybrid Sidecar | Detection core StatefulSet (1 per pod, shared by camera group) | Balanced middle ground |

**Lever:** fewer, bigger pools amortize AIMD convergence better. Each proposal's answer to "how many concurrent pools share the same Lambda endpoint?" materially affects inference-side queue behavior.

## Design decisions each proposal must make

1. **Pool-per-pod vs dedicated coord fleet.** B is the only one that even considers a dedicated coord. The question: does AIMD benefit from centralization, or does per-pod pool scale just as well?
2. **HTTP/2 multiplexing reuse.** [[actuate-inference-client]] uses HTTP/2 via httpx. Cross-fleet, do we keep httpx or switch? (Stick with it.)
3. **Resurrection semantics.** AsyncInferencePool self-heals if the event loop dies. Does this property survive fleet extraction? (Yes, but must be tested per proposal's process lifecycle.)
4. **Per-camera vs per-pool congestion tracking.** AIMD is pool-wide today. If a single slow camera drags the window down, all cameras in the pool suffer. Moot in C (cameras spread across many pods) but real in E (camera group shares a pool).

## Enhancement opportunities

- **Formalize the AIMD algorithm as its own tiny library** (currently embedded in `actuate-inference-client`). Would make reuse in proposal B's coord fleet trivial and create a reusable congestion-control primitive for non-inference uses (e.g., alert-sender throttling against Immix).
- **Per-camera AIMD bucketing** would decouple noisy-camera impact. Worth prototyping if B/E PoCs show AIMD convergence issues.
- **Inference API rate-limit signal.** Today AIMD infers congestion from latency. If the Lambda side exposed a concurrency-remaining header, we could pre-empt overshoot. Cross-team ask.

## Failure mode shared by all proposals

If the Lambda cold-starts en masse (e.g., after a deploy), p99 spikes, AIMD collapses the window, and the entire detection fleet backs off simultaneously. Proposal-agnostic — but proposal-sensitive in severity: B/D recover faster (stateless observers can re-scale), C/E recover at workload rate.

## References

- [[vms-connector/notes/concepts/inference-pool]] — AsyncInferencePool design
- [[vms-connector/notes/syntheses/performance-optimization-landscape]] — AIMD and inference latency bottleneck
- [[inference-api/_summary]] — Lambda-side API
- `actuate-libraries/actuate-inference-client` — HTTP/2 client on which AsyncInferencePool sits
