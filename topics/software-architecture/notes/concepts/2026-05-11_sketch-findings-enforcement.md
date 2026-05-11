---
title: "Sketch findings — enforcement collector (2026-05-11)"
type: concept
topic: software-architecture
tags: [sketch-findings, enforcement, import-linter, fleet-architecture, migration-risk, rubric, handoff-7, vms-connector]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Sketch findings — enforcement collector (handoff #7)

Closes [[2026-05-11_billing-and-followups-handoff]] item **#7**. Implements the spec at [[2026-05-11_enforcement-as-proposal-scorer]] — produces a per-proposal violation count by running import-linter against vms-connector, mapped to the rubric's Migration Risk axis.

**What shipped:**
- 5 per-proposal contract files at `/home/mork/work/software-arch-sketches/data/proposal-contracts/{a,b,c,d,e}.ini`.
- Collector at `src/software_arch_sketches/enforcement/rules.py` — subprocess-invokes `lint-imports` against `$SKETCH_INPUT_REPO` (default `vms-connector`), parses stdout, applies bracket mapping, writes `data/violations.json`.
- import-linter added as a dep (`>=2.0`); resolves to 2.11 + grimp 3.14.

**End-to-end runs cleanly:** `make enforce` → 196 files / 283 deps analyzed in <60s per proposal.

## Real results vs spec predictions

| Proposal | Spec said | Collector found | MR bracket (collector) | MR (prior addendum, human) |
|---|---|---:|---:|---:|
| A — Minimal Split | LOW (10-50) | **30** | **8/10** | 9/10 |
| B — Stage Fleets | HIGH (200-500+) | **203** | **4/10** | 3/10 |
| C — Camera-Worker | MODERATE (50-150) | **169** | **4/10** | 6/10 |
| D — Event-Driven | HIGHEST (400-1000+) | **202** | **4/10** | 2/10 |
| E — Hybrid Sidecar | MODERATE (50-150) | **30** | **8/10** | 7/10 |

A and E land in bracket 8 (≤2 weeks mechanical refactor); B, C, D in bracket 4 (6–14 weeks; behavioral changes likely). Bracket spread is 8 ↔ 4 — useful signal.

## What was easy

1. **import-linter's CLI is simple.** Subprocess invocation with `--config <ini> --no-cache` and parsing stdout works in ~50 lines. No need to use the Python API.
2. **Contract files are stable across proposals.** Switching a `forbidden` rule from "camera ↛ pipeline" to "camera ↛ {motion, inference, pipeline, ...}" is mechanical; the proposal differs mainly in *which* packages are sources vs forbidden, not in the contract form.
3. **`(l.NNN)` line-number markers** are robust to import-linter's line-wrapping. Counting them gives an edge-count violation total without needing to handle indented continuation lines.
4. **The collector ran clean on every contract.** Once the source/forbidden overlap issue was resolved (see §"What broke" below), there were no environment / dependency / configuration surprises.

## What broke

1. **import-linter rejects overlapping `source_modules` / `forbidden_modules` lists** with `Modules have shared descendants.` This caught my first attempt at B and D, where the natural shape is "every stage is forbidden from importing every other stage." Resolution: split into per-source contracts (one block per source package, with the other N-1 packages as forbidden). B/D now have 6-7 contracts each.
2. **import-linter `layers` contract had the wrong semantics for our use.** A `layers` contract enforces strict layered architecture — lower layers can't import upper, but upper CAN import lower. For B (which wants NO direct calls in either direction), this caught only half the violations. Replaced with bidirectional `forbidden` blocks.
3. **My violation-counting regex was wrong on first pass.** I matched `^-\s+\S+ -> \S+ \(l\.\d+\)` (the top-level `- A -> B (l.NN)` line). But import-linter line-wraps long module names, and transitive chains are reported with indented continuation lines — neither matches that regex. Result: I undercounted by ~6×. Switched to counting `(l.\d+)` markers anywhere in the output.

## What surprised me

### 1. The intra-vms-connector cross-import surface is shallow

`grep` of all top-level cross-package imports surfaced only ~76 edges across 8 root packages. **Most of vms-connector's cross-stage coupling lives in actuate-libraries** (the `actuate_pipeline`, `actuate_event_library`, etc. packages), which is external to our root_packages and therefore invisible to the collector.

**Implication:** the collector's violation counts are an under-estimate of total migration cost for any proposal that wants to restructure layer boundaries that cross into actuate-libraries. The collector is honest about what it measures (import edges in the target repo); it just doesn't measure everything that matters. Documented as a known limitation; see §"Calibration caveats" below.

### 2. The hub-and-spoke shape concentrates risk in `connector_factories` + `site_manager`

Per the grep:
- `connector_factories → camera` (31 imports), `→ motion` (6), `→ event_library` (2)
- `site_manager → camera` (14), `→ motion` (2), `→ event_library` (8)
- `camera → pipeline` (2), `→ event_library` (2), `→ healthcheck` (8)

Almost all the cross-package edges flow OUT of `connector_factories` and `site_manager` to the leaf packages. The leaf packages (`pipeline`, `inference`, `motion`, `event_library`) barely import from each other — they're already isolated.

**This is what makes Proposal C (Camera-Worker) score lower MR than human estimated.** C wants to extract the controller-shaped logic from `connector_factories` + `site_manager` into a separate worker-vs-controller boundary. The collector flagged 169 edges; the human addendum said C was moderate (6/10). The collector says C is harder (4/10). The reality: connector_factories' hub-coupling is exactly the work C demands, and it's *more* code to refactor than human gut-check thought.

### 3. Proposal D is much less distant than the spec predicted

Spec predicted D at 400–1000+ violations (HIGHEST). Collector reports 202. D's per-stage isolation contracts (camera ↛ everything, motion ↛ everything, …) catch fewer edges than expected because most stages don't actually cross-import — the orchestration layer is the violator, not the runtime stages.

**Implication:** D's MR rises from the addendum's 2/10 to the collector's 4/10. D's qualitative complexity (JetStream + S3 Express + MinIO + filter-chain split + observability lift) IS real, but most of it lives in implementation, not the import graph. The collector can't see infrastructure churn.

### 4. Proposal E aligns better with current code than spec predicted

Spec predicted E at 50–150 violations (MODERATE). Collector reports 30. The sidecar/core_pod split (camera + motion as sidecar; inference + pipeline + event_library as core_pod) runs along existing seams — there are very few direct imports between those groups today.

**Implication:** E's MR rises from the addendum's 7/10 to the collector's 8/10. **E's lead over C in the composite ranking widens from 0.375 → 0.675** (see [[2026-05-11_rubric-monitoring-billing-dimensions]] for the recomputed table — note for follow-up).

## Calibration caveats

The collector's violation count is a **proxy for migration cost**, not a complete measure. Specifically:

| Captured | Not captured |
|---|---|
| Direct cross-package imports in vms-connector | Cross-package imports through actuate-libraries (external to root_packages) |
| Transitive chains within vms-connector | Implementation work outside the import graph (Redis Streams plumbing, JetStream consumer groups, MinIO ops, new pod-class shapes, control-plane state machines) |
| Edge count per forbidden pair | Whether the import is load-bearing (cold-path import vs hot-path call) |
| Number of edges | Difficulty of refactoring each edge (some are mechanical; some require API redesign) |

**The right way to use these numbers:** as a quantitative input to a rubric dimension, *not* as the rubric. Compose with qualitative human judgment for items the collector can't see.

## Dual-use realization (per the spec)

The contracts double as **post-PoC enforcement gates** for whichever proposal wins. Once a proposal is selected:

1. Move its `<letter>.ini` from `data/proposal-contracts/` into vms-connector's repo root as `.importlinter`.
2. Wire `lint-imports` into vms-connector's CI as a blocking check.
3. New imports that violate the chosen topology fail the build.

The contracts don't go in the bin after selection — they're the post-migration shape of the architecture.

## Bracket calibration check (per the spec's verification path)

> Bracket-band tightness. If all 5 proposals land in 2 brackets, the brackets are too coarse.

5 proposals → 2 brackets (8 and 4). **Brackets are slightly too coarse.** Refinement suggestion for follow-up: split the 4 bracket (151-300) into 4 (151-250) and 3 (251-300). That would push D (202) into bracket 4 while keeping B (203) close — or arguably distinguish them by a finer count.

For now, leave brackets as-is. The 4/10 cluster for B/C/D is qualitatively right: all three require non-trivial refactoring. Finer-grained brackets would over-fit to noise (the difference between 200 and 202 is not meaningful).

## Suggested follow-up — billing-emit-site fitness functions

The spec [[2026-05-11_enforcement-as-proposal-scorer|§"Billing-emit-site fitness functions"]] called for proposal-agnostic invariants:
- No direct emit construction outside `connector_factories/shared/billing_emit.py`.
- Idempotency-guard reached on every emit path.

**Not implemented in this loop.** Reason: the first invariant needs an AST-walker pytest check (import-linter can express "module X cannot import Y" but not "module X cannot call the constructor of class Y unless wrapped by helper Z"). The second invariant needs control-flow analysis. Both are out-of-scope for the import-graph-only collector this sketch is.

Tracked as a separate item in [[mark-todos]] §6: write `tests/architecture/billing/` pytest module per the AST-walker pattern in [[2026-04-16_architecture-enforcement]] §"Architecture Tests (pytest)."

## Recommendation — update the rubric synthesis

[[2026-05-11_rubric-monitoring-billing-dimensions]] should be updated with the collector-derived MR scores:

| Proposal | Prior MR (addendum, human) | New MR (collector) | Composite delta |
|---|---:|---:|---:|
| A | 9 | 8 | 4.90 → **4.80** |
| B | 3 | 4 | 6.875 → **6.975** |
| C | 6 | 4 | 7.40 → **7.20** |
| D | 2 | 4 | 6.40 → **6.60** |
| E | 7 | 8 | 7.775 → **7.875** |

**Net effect on the ranking:** E pulls further ahead of C (gap 0.375 → 0.675). The PoC-1=E / PoC-2=C recommendation is reinforced — collector-derived MR confirms E's structural alignment with current code AND surfaces that C's controller-extraction work is harder than human gut-check.

## Files

- `data/proposal-contracts/a.ini` through `e.ini` — per-proposal target topologies
- `data/violations.json` — collector output (machine-readable)
- `src/software_arch_sketches/enforcement/rules.py` — collector implementation
- This findings note

## Cross-references

- [[2026-05-11_enforcement-as-proposal-scorer]] — the spec (handoff #6) this implements
- [[2026-05-11_rubric-monitoring-billing-dimensions]] — needs MR-score update per "Recommendation" above
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — prior MR scores
- [[2026-04-16_architecture-enforcement]] — parent synthesis (enforcement methodology)
- [[2026-04-23_sketch-findings-metrics]] — sister sketch findings note (pattern source)
- [[2026-05-11_billing-and-followups-handoff]] §7 — handoff item this note closes
- [[mark-todos]] §6 — software-arch sketches workstream
