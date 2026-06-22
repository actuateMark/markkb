---
title: "Fleet-Coordinator Unification — Do Proposals B-prime, C, and E Share a Control-Plane Primitive?"
type: concept
topic: fleet-architecture
tags: [fleet, coordinator, control-plane, unification, proposal-comparison, open-question, autopatrol]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
incoming:
  - topics/fleet-architecture/reading-list.md
incoming_updated: 2026-05-27
---

# Fleet-Coordinator Unification Question

**Status (2026-04-22 evening): RESOLVED — coherent, unification viable.** API-sketch design-review at `topics/fleet-architecture/notes/syntheses/2026-04-22_fleet-coordinator-api-sketch.md` concluded: 15 RPCs across 5 resource types, consistent noun-verb structure, clean per-proposal coverage (C + E + B-prime), not a distributed monolith. Recommended **+1 to C and E on operational-simplicity axis**; applied in the re-score Addendum's "Conditional scenario" row (now promoted to final under affirmative outcome): E → 8.00, C → 7.55, E's lead 0.45 over C.

**Original framing (preserved for provenance):** open question, tracked. Surfaced 2026-04-22 during the B-prime synthesis, reinforced independently by the design-delta analysis. Survives the NR-reversal correction of 2026-04-22 because it's a structural question, not a cost question.

## The question

**Do Proposals B-prime, C, and E all depend on variants of the same control-plane service — call it a "fleet-coordinator" — such that the boundaries between those proposals are *implementation choices* rather than *architectural choices*?**

If yes: the three proposals collapse into one architectural family with different pod-shape + transport details, and PoC selection becomes simpler. If no: each coordinator has distinct responsibilities that justify the separation.

## Why this question is interesting now

Three proposals carry a coordinator-shaped service whose jobs overlap suspiciously:

| Proposal | Service | Responsibilities |
|----------|---------|------------------|
| **C — Camera-Worker Fleet** | Assignment Controller (see `topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md` §§27-49) | Camera → worker assignment, lease management, rolling-update drain, split-brain resolution |
| **E — Hybrid Sidecar** | Site Context Service (`topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md` §§33-36) | Camera-group → core-pod assignment, centralized schedule eval (fixes ENG-96), config cache, hot-path admin-api read consolidation |
| **B-prime — Stateless w/ Coordinator** | Blob Coordinator (`topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md`, new §"Blob Coordinator service") | Window-blob lease/lookup/close, promote-vs-drop decision on window-close |

All three are **not on the hot path of frames** (they're control-plane services), all three need **HA via leader-election or Raft**, all three own a **mapping-from-identifier-to-pod** ({camera → worker} / {camera-group → core} / {window → motion-pod}), and all three handle **lifecycle transitions** (assign, migrate, release).

If a single **fleet-coordinator** primitive could cover these jobs, the proposal landscape simplifies dramatically — the "how do we own camera-to-pod mapping with lifecycle semantics?" problem is solved once, and each proposal's distinguishing characteristic collapses to its hot-path pod shape.

## What a unified fleet-coordinator would own

Candidate responsibility set, taking the union of the three individual coordinators:

1. **Identifier-to-pod mapping** — camera, camera-group, window, schedule. All TTL-lease backed.
2. **Pod-lifecycle events** — promote (spin up a hot-path pod), demote (drain + release), reassign (split-brain resolution).
3. **Configuration propagation** — centralized config + camera registry + schedule eval. Fixes ENG-96 across all variants.
4. **Outcome-driven lifecycle** — for B-prime's window-blob variant: "this window closed with no detection, release the blob without S3 promotion." For E's site-context variant: "this schedule's armed-state changed, migrate the camera-group's running work."
5. **Admin-api read cache** — all three proposals need a hot-path reader of admin-api configuration.

A fleet-coordinator that owned these would be 3-5 replicas, Raft/etcd consensus, gRPC + streaming API surface. One service; not three.

## What survives as a proposal-distinguishing feature (if coordinator unifies)

- **Pod shape + transport:** A/B/C/D/E still differ in whether frames are transported between pods vs. in-process, whether the observer is monolithic or split, whether motion-gating happens at puller or downstream.
- **Frame-storage pattern:** C's zero-transport vs. B's 4-hop vs. E's motion-gated-1-hop vs. D's S3-ref — still distinct, still materially different for cost + latency.
- **Failure domain:** per-proposal, the shape of pod death + what's lost differs.

What would NOT distinguish them anymore:
- "Who owns camera-to-pod mapping?" → The fleet-coordinator.
- "How does schedule eval get to the hot path?" → The fleet-coordinator.
- "What service absorbs the admin-api read load?" → The fleet-coordinator.

## Arguments FOR unification

- **One hard problem, solved once.** Leader-election + lease-based identifier-to-pod mapping is genuinely hard; building it three times across three proposals is wasteful.
- **ENG-96 schedule-eval fix generalizes.** E was explicitly engineered to fix ENG-96 (schedule-eval race conditions) via centralized eval. If the fleet-coordinator owns that across all proposals, every future proposal gets ENG-96 closure for free.
- **Operational simplicity compounds.** A single coordinator type + a single per-proposal hot-path pod type = 2 service types to operate. The alternative (assignment + site-context + blob-coordinator as separate services) = 3-4 per proposal.
- **Cross-team reuse.** The coordinator pattern is also the right shape for the AutoPatrol schedule assignment, CHM probe assignment — both currently rolled-their-own. A shared primitive consolidates three team-specific controllers into one ([[2026-04-16_proposal-c-camera-worker]] §"Enhancement opportunities identified" calls this out).

## Arguments AGAINST unification

- **Single point of failure.** Three separate services give three failure domains; one unified service gives one. Raft quorum softens this but doesn't eliminate it.
- **API surface bloat.** A single service with {camera → worker}, {camera-group → core-pod}, {window → motion-pod}, schedule eval, config cache, lifecycle events... is architecturally doing four things at once. Services that do four things become services that do five, then six. Classic "distributed monolith" anti-pattern risk.
- **Deployment cadence mismatch.** The C-variant assignment-controller logic might evolve on a different cadence from E's site-context-service config logic. Forcing them into one service couples release-trains that don't need coupling.
- **Scoping blur.** "What goes into the fleet-coordinator?" becomes a design-review question on every PR. Three smaller services with clear boundaries may be operationally simpler despite the apparent duplication.

## What would resolve this question

1. **Prototype the minimum-viable fleet-coordinator API.** Cover the three proposals' union-of-responsibilities in one gRPC schema. If the API surface is coherent (≤20 RPCs, consistent noun-verb structure) → unification is plausible. If it's a sprawl (40+ RPCs spanning four unrelated domains) → keep separate.
2. **Benchmark lease churn rates across the three use-cases.** B-prime's window leases churn at ~5-30s per window (very high); E's camera-group assignments churn at multi-hour cadence; C's camera assignments churn on pod death (rare). A single coordinator handling three different churn profiles is either underprovisioned for B-prime or overprovisioned for E.
3. **Ask: does AutoPatrol + CHM reuse actually benefit?** If the shared-primitive story evaporates because AutoPatrol + CHM have incompatible requirements, the unification argument weakens.
4. **Prior art scan.** Is there a known-good precedent for "multi-responsibility control-plane service" that handles this pattern at scale? Or is every production system that tried this eventually split?

## Related KB

- `topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md` — Assignment Controller details
- `topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md` — Site Context Service details
- `topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md` — Blob Coordinator details (the synthesis that surfaced this question)
- `topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md` — cost-delta analysis (different angle, same structural observation)
- `topics/fleet-architecture/notes/concepts/k8s-controller-selection-guide.md` — StatefulSet vs Deployment choice for the coordinator
- `topics/fleet-architecture/notes/concepts/k8s-placement-primitives.md` — per-AZ coordinator placement
- `topics/personal-notes/notes/entities/mark-todos.md` §5 → tracking line-item

## Track / next steps

- [ ] Design-review: sketch the minimum-viable fleet-coordinator gRPC API covering C + E + B-prime responsibilities. Target ≤20 RPCs, consistent noun-verb structure. Output: `topics/fleet-architecture/notes/syntheses/2026-04-XX_fleet-coordinator-api-sketch.md`.
- [ ] Benchmark model: estimate lease-churn rate + read-rate for B-prime (window leases) vs E (camera-group) vs C (camera). If rates differ by 3+ orders of magnitude, unification is harder.
- [ ] Prior-art scan: research existing "multi-responsibility control-plane" patterns at scale. Ties into reading-list work for fleet-architecture.
- [ ] Feed this into the formal A-E re-score (gated on NR + CE data) — if the coordinator unifies, the "operational simplicity" scoring axis for B-prime/C/E shifts toward higher values.
