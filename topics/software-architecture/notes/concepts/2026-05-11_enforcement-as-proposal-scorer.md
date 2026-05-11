---
title: "Enforcement-sketch-as-proposal-scorer (2026-05-11)"
type: concept
topic: software-architecture
tags: [enforcement, fitness-functions, import-linter, fleet-architecture, migration-risk, rubric, scorer, billing-emit, handoff-6]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Enforcement-sketch-as-proposal-scorer

Closes [[2026-05-11_billing-and-followups-handoff]] item **#6**. Specifies how the [[2026-04-16_architecture-enforcement|architecture-enforcement sketch]] becomes a **quantitative input** to the fleet rubric's Migration Risk axis (per [[2026-05-11_rubric-monitoring-billing-dimensions]] which added Monitoring & Alarms + Billing & Reconciliation but left Migration Risk subjective).

Sister-item [handoff #7] is the **actual implementation** of the collector in `/home/mork/work/software-arch-sketches/src/software_arch_sketches/enforcement/`. This note is the spec; the next session writes the code.

## What this spec answers

> *Today the rubric's Migration Risk score (10% weight) is anchored on "weeks to ship" + reviewer gestalt. Can we replace half of that with a measurable "violation count when current vms-connector is held against the target topology of each proposal"?*

Yes. The mechanism:

1. For each fleet proposal A–E, write an import-linter contract describing its **target** layer/package structure. (See §"Per-proposal target topologies" below.)
2. Run that contract against the **current** vms-connector codebase using the existing `software_arch_sketches.enforcement` collector module.
3. Output a count of violations per proposal. **More violations = more code-shape churn required = higher migration risk** for that proposal.
4. Map violation counts to rubric bracket scores via the calibration in §"Score mapping" below.
5. Feed those scores into the rubric's Migration Risk axis, replacing the current eyeball estimate.

The collector also doubles as the **operational fitness function** for the chosen proposal once selected: after the migration, the same rules now describe the desired-state architecture, and CI fails on any regression. So the collector is dual-use: pre-PoC as scorer, post-PoC as enforcer.

## What this does NOT do

- It does **not** measure semantic migration risk (e.g., "this proposal requires a customer-comms change"). Only structural code-shape risk.
- It does **not** replace the rubric's other dimensions. Cost, scalability, ops simplicity, etc. stay where they are.
- It does **not** make a recommendation. It produces a number; the rubric makes the recommendation.
- It does **not** require fleet implementation. The target rules are described in import-linter syntax; the collector counts violations in the current code. **PoC isn't needed to produce these numbers — they're available the day after handoff #7 ships.**

## Per-proposal target topologies

Each proposal becomes one import-linter contract. The contract describes the **post-migration** boundary structure. Violations are imports in **today's** vms-connector that would break the proposal's intended shape.

Sourced from:
- [[2026-04-16_proposal-a-minimal-split]]
- [[2026-04-16_proposal-b-stage-fleets]]
- [[2026-04-16_proposal-c-camera-worker]]
- [[2026-04-16_proposal-d-event-driven]]
- [[2026-04-16_proposal-e-hybrid-sidecar]]

### Proposal A — Minimal Split

Boundaries: puller (frame-capture loop) vs processor (pipeline). Minimal change; one new boundary line through the existing site-pod.

```ini
[importlinter:contract:a-puller-processor-split]
name = A — Puller-Processor boundary
type = forbidden
source_modules = vms_connector.puller
forbidden_modules = vms_connector.processor.internals
ignore_imports =
    vms_connector.puller -> vms_connector.processor.frame_handoff_api
```

**Expected violation count: LOW (10–50).** Today's puller and pipeline share state freely but the shared surface is shallow.

### Proposal B — Stage Fleets

Boundaries: four stage pools (puller, filter, inference, alert) communicating only via Redis Streams. Stage N may only import from stage N-1's **output schemas** + shared infra.

```ini
[importlinter:contract:b-stage-layers]
name = B — Stage fleet layered architecture
type = layers
layers =
    vms_connector.alert
    vms_connector.inference
    vms_connector.filter
    vms_connector.puller
    vms_connector.shared

[importlinter:contract:b-no-direct-calls-across-stages]
name = B — Stages communicate only via Redis Streams
type = forbidden
source_modules = vms_connector.filter
forbidden_modules =
    vms_connector.inference
    vms_connector.alert
```

**Expected violation count: HIGH (200–500+).** Today's pipeline crosses these stage boundaries directly all the time — `SlidingWindowStep` calls inference inline; alert generation is co-located with detection. Every direct call is one violation.

### Proposal C — Camera-Worker Fleet

Boundaries: worker pool (camera-bin owner) vs assignment controller. Worker is mostly today's site-pod code; controller is new.

```ini
[importlinter:contract:c-worker-controller-split]
name = C — Worker / Controller boundary
type = forbidden
source_modules = vms_connector.worker
forbidden_modules = vms_connector.controller.internals
ignore_imports =
    vms_connector.worker -> vms_connector.controller.lease_api

[importlinter:contract:c-controller-no-worker-internals]
name = C — Controller doesn't reach into worker internals
type = forbidden
source_modules = vms_connector.controller
forbidden_modules = vms_connector.worker.runtime
```

**Expected violation count: MODERATE (50–150).** Worker is today's code; controller is greenfield. Most violations come from the controller-shaped extraction (assignment, lease, bin-packing logic) that lives sprinkled across today's site-pod.

### Proposal D — Event-Driven Pipeline

Boundaries: filter chain split across pods, communicating via JetStream. **Every direct cross-stage call** is a violation.

```ini
[importlinter:contract:d-jetstream-only-coupling]
name = D — Cross-pod coupling only via JetStream subjects
type = forbidden
source_modules =
    vms_connector.filter_chain
forbidden_modules =
    vms_connector.inference
    vms_connector.detection
    vms_connector.sender
ignore_imports =
    vms_connector.filter_chain -> vms_connector.shared.jetstream_client

[importlinter:contract:d-s3-express-only-frame-pass]
name = D — Frames pass only via S3 Express, never direct
type = forbidden
source_modules = vms_connector.filter_chain
forbidden_modules = vms_connector.frame_buffer
```

**Expected violation count: HIGHEST (400–1000+).** D is the most architecturally distant from today's code. Every in-process call between stages is a violation. This is exactly the structural signal D's high Migration Risk score (2/10 in [[2026-04-22_fleet-proposal-rescore-with-delta]]) was trying to capture.

### Proposal E — Hybrid Sidecar

Boundaries: sidecar (puller + FDMD frame-filter) vs core-pod (inference + sender + alert). Communicate via Unix-domain sockets / memfd / shared memory.

```ini
[importlinter:contract:e-sidecar-core-split]
name = E — Sidecar / Core-pod boundary
type = forbidden
source_modules = vms_connector.sidecar
forbidden_modules = vms_connector.core_pod.internals
ignore_imports =
    vms_connector.sidecar -> vms_connector.core_pod.frame_socket_protocol

[importlinter:contract:e-core-no-frame-capture]
name = E — Core-pod doesn't capture frames (sidecar's job)
type = forbidden
source_modules = vms_connector.core_pod
forbidden_modules = vms_connector.sidecar.puller
```

**Expected violation count: MODERATE (50–150).** Sidecar split is shallow; main violations are FDMD-related (frame-drop motion-detector) which today lives inside the pipeline rather than at the puller boundary.

## Score mapping (violations → rubric bracket)

The rubric's Migration Risk dimension is 0–10. Bracket the violation count:

| Violations | Migration Risk score (this dimension) | Interpretation |
|-----------:|--------------------------------------:|---|
| 0–25 | **10** | Behavior-preserving; structural shape already aligned |
| 26–75 | **8** | ≤2 weeks of mechanical refactor; flag-flippable rollout |
| 76–150 | **6** | 2–6 weeks; some hand-massaging needed |
| 151–300 | **4** | 6–14 weeks; behavioral changes likely |
| 301–600 | **2** | 14–28 weeks; significant rewrite |
| 600+ | **0** | Architecturally distant; effectively a new system |

These brackets are calibrated against the existing 0/2/4/6/8/10 cells in [[2026-04-16_evaluation-rubric]] §5 (Migration Risk). **A single re-score after handoff #7 will validate the calibration** — if the violation counts cluster too tightly within one bracket, widen the bands; if they spread too thin, narrow.

The collector emits a JSON envelope:

```json
{
  "sketch": "enforcement",
  "generated_at": "2026-05-XX",
  "input_repo": "/home/mork/work/vms-connector",
  "proposals": {
    "a": { "violations": 32, "bracket": 8, "rules_evaluated": 1, "rules_violated": 1 },
    "b": { "violations": 387, "bracket": 2, "rules_evaluated": 2, "rules_violated": 2 },
    "c": { "violations": 89,  "bracket": 6, "rules_evaluated": 2, "rules_violated": 2 },
    "d": { "violations": 612, "bracket": 0, "rules_evaluated": 2, "rules_violated": 2 },
    "e": { "violations": 71,  "bracket": 8, "rules_evaluated": 2, "rules_violated": 1 }
  }
}
```

The dashboard sketch's enforcement panel reads this directly per [[2026-04-16_code-health-dashboard]].

## Billing-emit-site fitness functions (separate from proposal scorer)

The handoff specified this as part of #6: *"Also: billing-emit-site fitness functions per [[billing/_todos]] C1 — no emit outside `connector_factories/shared/billing_emit.py`, idempotency guard reached on every emit path, new emit sites must update [[billing-events-catalog]]."*

These are **proposal-agnostic** invariants. They apply regardless of which proposal wins. Encoded as separate import-linter contracts on the **current** code:

```ini
[importlinter:contract:billing-emit-centralization]
name = Billing — All site_product_ended emits via billing_emit module
type = forbidden
source_modules =
    vms_connector.connector_factories
forbidden_modules = ()
# Inverse: only the shared emit module may build the event payload.
# Implementation note: this rule needs to express "no direct construction
# of site_product_ended events outside billing_emit" — likely requires an
# AST-level pytest check rather than pure import-linter.

[importlinter:contract:billing-emit-idempotency]
name = Billing — Every billing_emit call site reaches the idempotency guard
type = custom-ast-check
# Implementation note: walk each call site of emit_site_product_event_for_stream(s)
# and verify _billing_emit_lock + _billing_events_fired check is unavoidable.
```

These graduate the existing **pre-merge "did you update [[billing-events-catalog]]?" reviewer-checklist** to a CI gate. Adding/removing an emit site without updating the catalog fails the build.

**Implementation note:** import-linter alone can't fully express the idempotency-reached check; it'd need a small pytest sibling that AST-walks the emit-call neighborhoods. Handoff #7 should ship both: import-linter contracts for what's expressible there, plus a `tests/architecture/billing/` pytest module for the rest. The pytest module is mechanically straightforward — see [[2026-04-16_architecture-enforcement]] §"Architecture Tests (pytest)" for the AST-walker pattern.

## Sketch implementation outline (for handoff #7)

The `software_arch_sketches.enforcement` module currently emits an empty `violations.json` stub. Handoff #7's collector should:

1. Vendor a tiny per-proposal `.ini` config file per the §"Per-proposal target topologies" above, in `data/proposal-contracts/{a,b,c,d,e}.ini`.
2. For each, programmatically invoke import-linter (`importlinter.application.use_cases.read_user_options` + `lint_imports`) against `$SKETCH_INPUT_REPO`.
3. Aggregate the per-rule violation counts.
4. Apply the score bracket mapping above.
5. Write `data/violations.json` matching the schema in §"Score mapping" above.
6. Ship a findings note at `topics/software-architecture/notes/concepts/2026-05-XX_sketch-findings-enforcement.md` describing what was easy/broken/surprising (per the pattern from [[2026-04-23_sketch-findings-metrics]]).

**Implementation gotchas to expect:**
- import-linter's `[importlinter]` config wants a single `root_packages` line shared across all contracts; the per-proposal contract files will all set `root_packages = vms_connector` then differentiate by `source_modules` / `forbidden_modules`.
- vms-connector's actual top-level package is `connector_factories` (per [[billing-events-catalog]]), not `vms_connector`. Verify in handoff #7's PoC that the rules match the real package shape.
- The proposal contracts above reference packages like `vms_connector.worker`, `vms_connector.controller` that **don't exist today**. That's fine — import-linter happily reports zero matches for non-existent modules, and the **forbidden-import** flavors of rules still work because they're keyed off existing packages that *would* be split into those new packages.

## Why this matters (the fleet rubric tie-in)

[[2026-04-22_fleet-proposal-rescore-with-delta]] and [[2026-05-11_rubric-monitoring-billing-dimensions]] leave Migration Risk as the only rubric axis still scored by eyeball. That's been fine while the proposals' migration costs were qualitatively obvious (D is bigger than A). It becomes load-bearing if PoC results compress the cost / scalability axes and the rubric's pivot point shifts toward "which migration is cheapest."

Replacing half of Migration Risk with this collector's number isn't full quantification — it doesn't capture "this proposal needs customer-comms" or "this proposal needs a new on-call rotation." But it removes one degree of subjectivity at the dimension that's most at-risk of being weaponized in PoC-selection arguments.

The dual-use angle (pre-PoC scorer + post-PoC enforcer) makes the collector a justifiable investment regardless of which proposal wins — the rules don't go in the bin after selection.

## Calibration / verification path

Once handoff #7 ships and produces real numbers:

1. **Sanity check against the qualitative scores.** D should have the highest violation count; A should have one of the lowest. If A > D, something's wrong with the rules.
2. **Bracket-band tightness.** If all 5 proposals land in 2 brackets (e.g., 4 in `8-10` + 1 in `0-2`), the brackets are too coarse — widen bands or split the heavy bracket. If they spread 5 different brackets evenly, the brackets are right-sized.
3. **Re-score the rubric.** Update [[2026-05-11_rubric-monitoring-billing-dimensions]] §"Recomputed composite scores" with the collector-derived Migration Risk numbers. Note the delta vs the current eyeball scores.
4. **Commit the contracts as the proposal-selection deliverable.** Once a proposal wins PoC, lock its contract into the post-migration CI gate (the gate flips polarity: violations were target-shape-debt before selection, become regressions-from-target-shape after).

## Cross-references

- [[2026-04-16_architecture-enforcement]] — parent synthesis (enforcement methodology generally)
- [[2026-04-16_evaluation-rubric]] — Migration Risk axis defined here
- [[2026-04-22_fleet-proposal-rescore-with-delta]] — current Migration Risk scores
- [[2026-05-11_rubric-monitoring-billing-dimensions]] — handoff #4 (sibling — this note completes the rubric quantification arc)
- [[2026-05-11_billing-and-followups-handoff]] §6 — handoff item this note closes
- [[mark-todos]] §6 — software-arch sketches workstream (this note feeds the enforcement sketch's findings)
- [[2026-04-16_proposal-a-minimal-split]] / `-b-stage-fleets` / `-c-camera-worker` / `-d-event-driven` / `-e-hybrid-sidecar`
- [[billing-events-catalog]] — billing-emit invariants the fitness functions encode
- [[2026-04-23_sketch-findings-metrics]] — pattern for the post-implementation findings note
- `/home/mork/work/software-arch-sketches/src/software_arch_sketches/enforcement/` — code home for handoff #7
