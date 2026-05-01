---
title: "Multi-Agent Pilot Staging (2026-04-21)"
type: staging
topic: fleet-architecture
tags: [staging, multi-agent-pilot, reading-list-ingest, pending-crossrefs]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
status: complete-crossrefs-applied-2026-04-22
---

## What's been applied (2026-04-21)

- [x] 9 source notes written to `sources/`
- [x] 5 concept notes written to `notes/concepts/` (deduped from 7 proposals):
  - `k8s-controller-selection-guide.md`
  - `k8s-placement-primitives.md` (merged from batch-1 `k8s-scheduling-primitives` + batch-2 `topology-spread-vs-pod-affinity`)
  - `pod-termination-sequence.md`
  - `vpa-bimodal-workload-limitation.md` (ENG-78 root-cause)
  - `scaling-layer-taxonomy.md`
- [x] `reading-list.md` — 9 entries ticked + graceful-shutdown URL fixed
- [x] `_summary.md` — Cross-Cutting Designs table updated with 5 new concept rows

## 15 targeted cross-reference edits — APPLIED 2026-04-22

All 15 K8s cross-refs applied across 9 files. Each addition is a 1-2 line Edit linking to the K8s source/concept notes produced by the 2026-04-21 multi-agent pilot. Pattern: find the referenced section, add the wikilink + 1-sentence rationale.

### `notes/syntheses/2026-04-16_proposal-a-minimal-split.md`
- [x] Linked `[[pod-topology-spread-constraints]]` in frame-transport cross-AZ section (specifies `topologyKey: topology.kubernetes.io/zone`, `ScheduleAnyway`)

### `notes/syntheses/2026-04-16_proposal-b-stage-fleets.md`
- [x] Linked `[[pod-topology-spread-constraints]]` + `[[pod-affinity-anti-affinity]]` under zone-aware routing (TSC `ScheduleAnyway` is the right tool; NOT O(n²) pairwise pod-anti-affinity)
- [x] HPA tuning note added after scaling model — `selectPolicy: Min` + `stabilizationWindowSeconds: 300`; Spot viable for Motion + InferenceCoord, NOT Observer (tracker snapshot cadence + Spot 2-min warning is too tight)

### `notes/syntheses/2026-04-16_proposal-c-camera-worker.md`
- [x] Linked `[[pod-disruption-budgets|PDB]]` + Eviction API pattern in "rolling-update drain logic" new-primitive
- [x] Spot-viability paragraph added to Scaling model — `karpenter.sh/do-not-disrupt` mitigation, worst-case 1-2 frames lost on 2-min Spot warning; cost advantage compounds with bin-packing

### `notes/syntheses/2026-04-16_proposal-d-event-driven.md`
- [x] NATS JetStream PDB requirement — `maxUnavailable: 1` for safe cluster upgrade; without it, node-drain can take JetStream below RAFT quorum (N/2+1) and stall all writes; linked `[[pod-disruption-budgets]]`
- [x] NATS consumer-lag HPA External metric — GPU-bound detector is CPU-light but queue-building, so CPU-based HPA under-provisions; updated Scaling table rows

### `notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md`  ← HIGH VALUE
- [x] **StatefulSet upgrade open question RESOLVED** — `partition` field in `updateStrategy.rollingUpdate` stages rollout by ordinal, waits for snapshot + grace-period before advancing; linked `[[kubernetes-workload-controllers]]` + `[[k8s-controller-selection-guide]]`
- [x] Linked `[[pod-affinity-anti-affinity]]` under Detection core locality (preferred-affinity on `topology.kubernetes.io/zone` so scheduler doesn't wedge)
- [x] Linked `[[vertical-pod-autoscaler-deep-dive]]` + `[[vpa-bimodal-workload-limitation]]` under VPA fix — explicit ENG-78 root-cause mechanism
- [x] Spot-viability paragraph added — Smart Puller Spot-eligible, Detection Core NOT (StatefulSet + 2-min warning too tight for snapshot cycle), Alert + Site Context are Spot-eligible

### `notes/syntheses/2026-04-16_graceful-failover-design.md`  ← HIGH VALUE
- [x] New `## K8s Mechanics` section linking `[[graceful-pod-termination-zero-downtime]]` + `[[pod-termination-sequence]]`; spelled out the typical 10-30 s `terminationGracePeriodSeconds` sizing (preStop drain + snapshot write latency + buffer); noted that "cold-start on upgrade" usually means grace-period too short, not snapshot-logic broken
- [x] New `## K8s Availability Primitives` section linking `[[pod-disruption-budgets]]` (`unhealthyPodEvictionPolicy: AlwaysAllow` detail) + `[[k8s-placement-primitives]]` (topology-spread ScheduleAnyway + AZ anti-affinity)

### `notes/concepts/tracker-snapshot-schema.md`
- [x] Added "K8s cadence bound" note under Snapshot cadence — `terminationGracePeriodSeconds` is the hard bound on 1-second cadence; linked `[[pod-termination-sequence]]` + K8s Mechanics section of graceful-failover synthesis

### `notes/concepts/memory-and-fork-safety.md`
- [x] Added VPA-churn bullet under Shared Risks — VPA `updateMode: Recreate` triggers unnecessary cold-resume cycles if snapshot cadence isn't sized for recommendation cadence; `InPlaceOrRecreate` (VPA v1.6+ / K8s 1.33+) is the mitigation; linked `[[vertical-pod-autoscaler-deep-dive]]` + `[[vpa-bimodal-workload-limitation]]`

### `notes/syntheses/2026-04-16_frame-transport-comparison.md`
- [x] Expanded Topology rule #1 — zone-aware pod scheduling via `[[pod-affinity-anti-affinity]]` + topology-spread; explicit preference for `ScheduleAnyway` over `DoNotSchedule` (the latter wedges under capacity pressure and is almost never right for cost-driven hints)

## Open questions from pilot (not yet routed to workstreams)

# Multi-Agent Pilot Staging — 2026-04-21

Raw output from a 3-subagent fan-out pilot processing the first 9 entries of `fleet-architecture/reading-list.md` (K8s fundamentals, deployment mechanics, autoscaling sections). Each subagent was Claude Sonnet 4.6 with `general-purpose` type; WebFetch + Read + Grep only, no Edit/Write. Outputs structured as source notes + concept proposals + cross-refs + fetch logs + open questions.

**Pilot metrics:**

| Metric | Value |
|---|---|
| Batches | 3 (3 URLs each) |
| Wall-clock | ~3-4 min per batch in parallel |
| Source notes drafted | 9 |
| Concept proposals | 7 (some overlap across batches) |
| Cross-reference proposals | 17 spanning 6 existing KB files |
| Open questions flagged | 10 (none blocking writes) |
| Fetch failures / URL changes | 1 (k8s termination tutorial moved → subagent substituted canonical pod-lifecycle page) |

**Pattern assessment:** the fan-out worked as designed. Subagent outputs followed the structured template; each was self-contained and mergeable. Concept dedup is needed (e.g. batch-1's `k8s-scheduling-primitives` and batch-2's `topology-spread-vs-pod-affinity` overlap; batch-3's `scaling-layer-taxonomy` naturally composes with batch-2's VPA content). This dedup is a main-agent serial pass, not something subagents can do without coordination.

**Next steps (for main-agent merge):**

1. Create `topics/fleet-architecture/sources/` directory (none exists)
2. Write 9 source-note files from the draft content below
3. Tick the corresponding entries in `reading-list.md` (Kubernetes section rows 1-5 except #2's URL needs updating per fetch log, Autoscaling rows 1-4)
4. Update `reading-list.md` Graceful Shutdown URL: `pods-and-endpoints-termination-flow/` → `pod-lifecycle/#pod-termination` (source was moved)
5. Dedupe concept proposals into a short list (target 3-5 new concept notes), then write them in a second pass
6. Apply cross-reference proposals to the 6 existing files (one-by-one review — each is a small edit)

**Do not auto-merge** — each concept note and cross-ref edit deserves eyeballs before committing. The source notes themselves are safer to batch-write since they're new files with no conflicts.

---

## Raw Subagent Outputs

Staging content from the 3 subagent runs preserved verbatim below. When ready to merge, read this file + apply the steps above.

### Batch 1 — K8s fundamentals (workload-controllers, topology-spread, disruption-budgets)

*(full output preserved in the session transcript; main agent will merge from there. Agent ID: a40dd60799404f984)*

Source notes drafted:
- `kubernetes-workload-controllers.md`
- `pod-topology-spread-constraints.md`
- `pod-disruption-budgets.md`

Concept proposals:
- `k8s-controller-selection-guide`
- `k8s-scheduling-primitives` *(overlaps w/ batch-2's topology-spread-vs-pod-affinity; merge)*

### Batch 2 — K8s deployment mechanics (pod-affinity, graceful-termination, VPA)

*(full output preserved in session transcript. Agent ID: ab7aba0528df8b045)*

Source notes drafted:
- `pod-affinity-anti-affinity.md`
- `graceful-pod-termination-zero-downtime.md`
- `vertical-pod-autoscaler-deep-dive.md`

Concept proposals:
- `pod-termination-sequence`
- `vpa-bimodal-workload-limitation` *(good standalone — ENG-78 root cause)*
- `topology-spread-vs-pod-affinity` *(merge w/ batch-1's k8s-scheduling-primitives)*

### Batch 3 — Autoscaling (HPA, Karpenter, EKS best-practices)

*(full output preserved in session transcript. Agent ID: a14d9dfe5441ff358)*

Source notes drafted:
- `kubernetes-hpa-behavior.md`
- `karpenter-node-provisioning.md`
- `aws-eks-karpenter-best-practices.md`

Concept proposals:
- `scaling-layer-taxonomy` *(composes w/ batch-2's VPA; highest-value standalone)*
- `karpenter-nodepool-patterns`

---

## Cross-Reference Proposals (grouped by target file)

### `notes/syntheses/2026-04-16_proposal-a-minimal-split.md`
- Add: link to `[[pod-topology-spread-constraints]]` in frame-transport section (specifies `topologyKey: topology.kubernetes.io/zone`, `ScheduleAnyway`)

### `notes/syntheses/2026-04-16_proposal-b-stage-fleets.md`
- Add: link to `[[pod-topology-spread-constraints]]` for per-stage zone-aware routing (explicitly calls out TSC with `ScheduleAnyway` as right tool, not O(n²) pairwise anti-affinity)
- Add: link to `[[pod-affinity-anti-affinity]]` for zone-affinity mechanics
- Add: HPA tuning note — `selectPolicy: Min` on scale-down with `stabilizationWindowSeconds: 300` to prevent chain-reaction thrash across the 4-hop pipeline; Spot viable for Motion + InferenceCoord (stateless), not Observer (stateful)

### `notes/syntheses/2026-04-16_proposal-c-camera-worker.md`
- Add: link to `[[pod-disruption-budgets]]` under "rolling-update drain logic" new-primitives section (PDB + Eviction API is the standard pattern)
- Add: `karpenter.sh/do-not-disrupt` annotation as mitigation for Karpenter consolidation evicting mid-processing; Spot viable because tracker snapshots to Redis at 1Hz (worst-case 1-2 frames lost on 2-min Spot warning)

### `notes/syntheses/2026-04-16_proposal-d-event-driven.md`
- Add: NATS JetStream StatefulSet needs PDB (`maxUnavailable: 1`) for safe cluster upgrade — link `[[pod-disruption-budgets]]`
- Add: NATS consumer-lag as natural External metric for HPA on Detector/Observer fleets (more accurate than CPU because NATS provides durable queue-depth signal)

### `notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md`
- **Primary answer to the StatefulSet upgrade open question:** use `partition` field in `updateStrategy.rollingUpdate` for staged ordinal-based rollouts; link `[[kubernetes-workload-controllers]]`
- Add: link to `[[pod-affinity-anti-affinity]]` under "Detection core locality" (camera-affinity StatefulSet + zone-spread mechanics)
- Add: link to `[[vertical-pod-autoscaler-deep-dive]]` under "VPA fix" benefit claim (explicit ENG-78 mechanism)
- Add: Spot risk for Detection Core StatefulSet — `do-not-disrupt` annotation or On-Demand-only NodePool required

### `notes/syntheses/2026-04-16_graceful-failover-design.md`
- **Primary cross-link for graceful-termination source:** add `## K8s Mechanics` section pointing to `[[graceful-pod-termination-zero-downtime]]` — preStop checkpoint pattern is the concrete K8s mechanism
- Add: `terminationGracePeriodSeconds` must be ≥ (preStop drain + snapshot write latency + buffer); SIGKILL deadline is hard bound on 1-second snapshot cadence
- Add: `## K8s Availability Primitives` section linking `[[pod-disruption-budgets]]` — PDB + `unhealthyPodEvictionPolicy: AlwaysAllow` is required alongside Redis snapshot for C/E

### `notes/concepts/tracker-snapshot-schema.md`
- Add: under "Snapshot cadence" — `terminationGracePeriodSeconds` hard bound on 1-second cadence; link `[[graceful-pod-termination-zero-downtime]]`

### `notes/concepts/memory-and-fork-safety.md`
- Add: VPA recreation-on-update triggers graceful-shutdown checkpoint cycle unplanned; link `[[vertical-pod-autoscaler-deep-dive]]`

### `notes/syntheses/2026-04-16_frame-transport-comparison.md`
- Add: under Topology rules — link `[[pod-affinity-anti-affinity]]` for topology spread + `ScheduleAnyway` constraint syntax

### `_summary.md` (topic summary)
- Add: under **Cross-Cutting Designs** section, a row for `scaling-layer-taxonomy` concept (when written) alongside frame-transport and graceful-failover — HPA/Karpenter/VPA choices are as cross-cutting as frame transport

---

## Open Questions Captured

1. **K8s cluster version** — TSC feature gates depend on 1.30+ (`minDomains` GA), 1.34+ (`nodeAffinityPolicy`, `matchLabelKeys` GA). Before writing TSC implementation specs for E, confirm EKS cluster version.
2. **PDB scope for A's 1-per-site pipeline workers** — a PDB with `minAvailable: 1` effectively serializes node drain at fleet scale. Decide whether A's pipeline workers carry a PDB at all.
3. **URL fix in reading-list** — Graceful Shutdown entry pointed at `pods-and-endpoints-termination-flow/` which 404s; should be `pod-lifecycle/#pod-termination`.
4. **terminationGracePeriodSeconds sizing** — depends on worst-case Redis write latency under load (not yet characterized). Suggest a spike / benchmark.
5. **VPA InPlaceOrRecreate mode** — GA in VPA v1.6.0 for K8s 1.33+. Could significantly reduce "VPA triggers unplanned restart" concern; verify EKS K8s version.
6. **Karpenter version pin** — `ds-terraform-eks-v2` should be checked to confirm whether `karpenter.sh/do-not-disrupt` annotation is available (Karpenter v0.32+).
7. **Detection Core Spot eligibility in E** — `do-not-disrupt` + Redis snapshot mitigation is plausible but unvalidated; PoC should include a Spot interruption simulation.
8. **NodePool per-fleet instance type mapping** — compute-optimized for motion/detector vs memory-optimized for observer. Not yet specified in any proposal.

## Related

- [[knowledgebase/topics/fleet-architecture/reading-list]] — source of the pilot entries
- [[knowledgebase/topics/fleet-architecture/_summary]] — topic summary for 5-proposal context
- [[engineering-process/notes/syntheses/2026-04-20_multi-agent-model-routing]] — synthesis that framed this pilot
- [[mark-todos]] §5 (Fleet architecture review) — today's parent scope item
