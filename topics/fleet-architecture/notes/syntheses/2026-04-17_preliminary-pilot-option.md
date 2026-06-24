---
title: "Preliminary Pilot Option — all 5 proposals at minimal fidelity (reference, not committed)"
type: synthesis
topic: fleet-architecture
tags: [pilot, poc, prototype, architecture, fleet, option]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/reading-list.md
incoming_updated: 2026-05-01
---

# Preliminary Pilot Option

A **forward-looking reference doc** — not an active workstream. Captures an alternative approach to the planned targeted PoCs: a lightweight preliminary pilot pass that stubs all 5 proposals in a shared harness first, then informs targeted-PoC scope.

The parent topic currently plans to go directly from proposal review → targeted PoCs per candidate. This doc captures the pilot-first option in case that sequence proves too risky or expensive when the time comes to decide.

**Not in [[mark-todos]].** This is a library entry — pull from it if/when the topic revisits sequencing.

## Why this option might be worth considering

The [[fleet-architecture/_summary|topic plan]] commits to targeted PoCs per candidate — each building "only the novel/risky piece." At ~1 week per PoC, 5 candidates is substantial, and the per-candidate PoC design in each proposal note is pre-informed only by paper analysis.

A preliminary pilot phase could:
- Surface unexpected complexity early when it's cheapest
- Let the shared harness (metrics, input, boundary contract) be built once
- Give real numbers for the pre-PoC [[2026-04-16_evaluation-rubric|rubric scores]] (currently speculative on cost and failover)
- De-risk the targeted PoC by letting each start from a working stub

## Shared harness (if adopted)

One harness, five stubs. The harness provides:

| Component | Purpose |
|-----------|---------|
| **Input source** | [[rtsp-deep-dive|RTSP]] fixture OR recorded video file OR synthetic frame generator — same interface for all 5 stubs |
| **Boundary contract** | Common input/output payload shape: `frame-in → detection-out`. All 5 stubs must conform. |
| **Metrics sink** | Standardized collection of end-to-end latency, CPU, memory, crash-to-recovery time |
| **Swap mechanism** | A flag or config to swap which proposal's stub is running against the same input |

If the harness isn't shared, cross-proposal comparison is noise.

## Per-proposal stub scope

Minimum viable implementation — not production-ready. Goal is "feel" + metrics.

| Proposal | Stub focus |
|----------|------------|
| [[2026-04-16_proposal-a-minimal-split|A — Minimal split]] | Puller + alerts as separate processes; monolith pipeline in between |
| [[2026-04-16_proposal-b-stage-fleets|B — Stage fleets]] | Each pipeline stage as an independent process, wired sequentially |
| [[2026-04-16_proposal-c-camera-worker|C — Camera-worker]] | Generic worker that accepts a list of cameras; bin-pack N cameras across M workers |
| [[2026-04-16_proposal-d-event-driven|D — Event-driven]] | NATS JetStream (or local broker) between stages; S3-ref or in-memory frame refs |
| [[2026-04-16_proposal-e-hybrid-sidecar|E — Hybrid sidecar]] | Smart puller sidecar + stateful core + async alert emitter |

## Per-pilot notes (if adopted)

For each proposal, write `fleet-architecture/notes/concepts/2026-XX-XX_pilot-findings-{A-E}.md` capturing:
- What was easy (surprisingly so)
- What broke / what took longer than expected
- Unexpected complexity discovered
- Rough perf observations (latency, CPU, memory)
- What this implies for the targeted PoC scope of this candidate

## Consolidation (if adopted)

After all 5 stubs run, write `2026-XX-XX_pilot-findings-summary.md` — a cross-proposal synthesis that:
- Updates the pre-PoC rubric scores with pilot data folded in
- Identifies which proposals have surprising-new-information and warrant targeted PoC priority
- Flags anything that should kill or de-prioritize a candidate (a dealbreaker surfaced by the pilot)

## Non-goals (even if adopted)

This approach is **not**:
- A production-ready prototype
- A decision-maker on its own — it feeds into targeted PoCs + rubric scoring
- A replacement for the `kubernetes-deployments` + `connector_deployer` deep-dive (still an [[fleet-architecture/_summary|open blocker]]); local pilots don't touch NAT/VPN/WireGuard topology, which is C-specific

## Timeline estimate (if adopted)

- Harness setup: 1-2 days
- Each stub: 0.5-1 day
- Per-proposal notes + consolidation: 1 day
- **Total preliminary pilot:** ~1-1.5 weeks

Compare against targeted PoCs at ~1 week per candidate — the preliminary pilot doesn't replace them, but should roughly halve the targeted-PoC uncertainty.

## When to consider this option

Pull this plan off the shelf if, when the time comes:
- The targeted PoC scopes per candidate feel too speculative to commit to without more data
- A candidate's proposal note lists many open questions that a minimal stub could resolve cheaply
- Team has bandwidth for a week of exploratory work before committing to multi-week PoCs
- The rubric scores pre-PoC are too close to differentiate confidently

## Related

- [[fleet-architecture/_summary]] — the parent topic (current plan is targeted PoCs, this is an alternative)
- [[2026-04-16_evaluation-rubric]]
- Proposal notes: [[2026-04-16_proposal-a-minimal-split|A]], [[2026-04-16_proposal-b-stage-fleets|B]], [[2026-04-16_proposal-c-camera-worker|C]], [[2026-04-16_proposal-d-event-driven|D]], [[2026-04-16_proposal-e-hybrid-sidecar|E]]
