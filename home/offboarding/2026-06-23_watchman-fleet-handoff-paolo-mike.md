---
title: "Watchman + Fleet-Architecture handoff — Paolo (deployer) & Mike (k8s)"
type: concept
topic: offboarding
tags: [offboarding, handoff, watchman, fleet-architecture, paolo, mike, eng-300]
created: 2026-06-23
updated: 2026-06-23
author: kb-bot
incoming:
  - home/README.md
  - home/offboarding/2026-06-22_manual-action-checklist.md
  - home/offboarding/offboarding-overview.md
  - home/orientation/first-steps.md
  - home/roadmaps/watchman-fleet-architecture.md
incoming_updated: 2026-06-25
---

# Watchman + Fleet-Arch handoff → Paolo & Mike

> Hands off the §5 fleet-architecture R&D + the **[[watchman-repo|Watchman]]** product design (ENG-300) — the "needs a named successor or it stalls" item — to **Paolo** and **Mike**, split along their strengths: **Paolo = deployment / connector-integration layer**, **Mike = fleet / cluster-orchestration layer**, with a short list of **joint** decisions. Goal: they can carry it without Mark. Full plan: [[2026-06-22_offboarding-plan]].

## Where it stands (one screen)

- **Phase-0 [[watchman-repo|Watchman]] shape decided** ([[2026-06-02_watchman-phase0-fleet-fit]]): greenfield, RTSP-only, **per-camera (no `site`)**, uniform **bin-packed puller pods** (`cameras_per_puller` the one knob), **Redis Streams** frame bus, motion gating default-OFF, **trimmed stateless detection**, a real (minimal) **[[watch-entity|Watch]] Management Service = FleetCoordinator**. Fleet-proposal fit: **E (hybrid sidecar)** is PoC-1, **C (camera worker)** PoC-2; grow-into target = v10 via E.
- **Backend direction** ([[2026-06-16_watchman-pipeline-backend-meeting]]): **doubletake-pattern Lambda** invoked *during* the connector run → writes to a window-id store. **Storage OPEN** (Postgres / OpenSearch [Jagadish] / S3-vector [Otzar]). AWS stays on the **dev account w/ Terraform** (no new account). **Valeri** is building the connector-side Lambda (~end of week).
- **Open** (from the 06-16 mtg): storage choice, Lambda invocation point (sync vs async), alert grouping / ID cleanup, pipeline-vs-connector parity, persistent-vs-ephemeral mode unification.

## The split

### 🟦 Mike — fleet / cluster-orchestration layer (k8s)
Owns the *how it runs on the cluster* questions. Maps directly to k8s experience.
- **PoC-1: stand up proposal E** (hybrid sidecar) — Lambda + translator + init container + minimal K8s manifest; stress with **mixed persistent + ephemeral load**. PoC-2: C (camera worker) as runner-up. ([[2026-04-16_proposal-e-hybrid-sidecar]], [[2026-04-16_proposal-c-camera-worker]])
- **Bin-packing + uniform puller pods** — set/validate `cameras_per_puller`; pod sizing; the independently-scaling puller / detection / dispatch K8s deployments + HPA.
- **[[watch-entity|Watch]] Management Service as a fleet-singleton reconciler** (controller pattern — k8s-native). ([[2026-05-28_watch-management-service-design]])
- **Redis Streams** deployment on the cluster; GPU node placement for detection + (later) forensic search.
- **EKS substrate** + the v10 grow-into path. ([[2026-06-01_v10-cloud-platform-vs-fleet-proposals]])

### 🟩 Paolo — deployment / connector-integration layer (deployer)
Owns the *how it gets built, deployed, and wired to the connector* questions. Adjacent to his ENG-269/282 custom-branch deploy work + connector_deployer ownership.
- **Connector-side Lambda integration** — coordinate with **Valeri** (building it ~end of week): invocation during the connector run, window-id table writes, deploy wiring.
- **doubletake-pattern Lambda** deploy + the window-id store plumbing. ([[doubletake]])
- **Pipeline-vs-connector parity validation** — confirm [[watchman-repo|Watchman]] pipeline output matches connector capability (motion blobs, frames, upstream signals); no missing inputs before backend plumbing.
- **The translator** — RunSpec.v1 → deployed pods (the deployer's domain); resolve the vestigial `customer.server_ip`/`username` fields under multi-camera [[rtsp-deep-dive|RTSP]].
- **connector_deployer** changes for [[watchman-repo|Watchman]] pods (carries naturally from his §18 VPA-floor work).

### 🟨 Joint (decide together — neither can own alone)
- **Storage choice** (Postgres vs OpenSearch vs S3-vector) — affects Mike's cluster footprint + Paolo's backend plumbing. Run the prototype perf/cost/integration bake-off.
- **Lambda invocation point** — sync vs async during the connector run.
- **Alert grouping / ID cleanup** scheme.
- **Mode unification** — must the chosen paradigm serve both ephemeral + persistent on the same primitives, or is bimodal config OK? ([[2026-04-16_evaluation-rubric]] persistent-mode rescore is still open.)
- **S3 cost levers** (ENG-183 / Tier3 replication driver) — infra-shared.

## Reading list (cost-ordered — read your layer's after the shared spine)

**Both, first:** [[2026-06-02_watchman-phase0-fleet-fit]] → [[2026-06-16_watchman-pipeline-backend-meeting]] → [[2026-06-02_frontend-sketch-ui]] · topic hubs [[topics/fleet-architecture/_summary]], [[topics/watchman/_summary]].
**Mike then:** [[2026-04-16_proposal-e-hybrid-sidecar]], [[2026-04-16_proposal-c-camera-worker]], [[2026-04-22_fleet-proposal-rescore-with-delta]], [[2026-05-28_watch-management-service-design]], [[2026-06-01_cloud-video-analytics-platform-v10]], [[2026-04-16_evaluation-rubric]].
**Paolo then:** [[2026-05-29_watchman-judge-backend-io-contract]], [[2026-06-01_adr-watchman-mvp-slim-connector]], [[doubletake]], the Run Service translator + RunSpec.v1 + DetectionEvent.v1 docs (`ephemeral-run-pilot` folder), [[2026-05-05_fleet-architecture-workstream-context]].

## Handoff mechanics (this week)
1. **One 60–90 min joint walkthrough** (Mark + Paolo + Mike), spine = the two 06-02 / 06-16 notes. Agenda: Phase-0 shape (15m) → topology + proposal fit, Mike-led (20m) → backend/Lambda/storage, Paolo-led (20m) → open-decision ownership split (20m) → Jira + next steps (15m).
2. **Jira — DONE 2026-06-23:** **ENG-300** reassigned → **Mike** ([[michael-aleksa|Michael Aleksa]]); **[ENG-383](https://actuate-team.atlassian.net/browse/ENG-383)** created → **Paolo** ("[[watchman-repo|Watchman]] connector-side Lambda + backend deploy integration", under ENG-5, linked to ENG-300). Both carry the full split in their descriptions/comments. Still to do: park **ENG-183** (S3 cost) with whoever takes infra (lean shared).
3. **Immediate next steps:** Valeri's connector-side Lambda lands ~end of week → Paolo wires the deployer side; Mike stands up the E PoC; joint storage bake-off kicks off (unblocks the API skeleton).

## Related
- [[2026-06-22_offboarding-plan]] · [[2026-06-22_actuate-footprint-handoff]] · [[2026-06-22_manual-action-checklist]]
- [[topics/fleet-architecture/_summary]] · [[topics/watchman/_summary]] · ENG-300 + [[watchman-repo|Watchman]] epic
