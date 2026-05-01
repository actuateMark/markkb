---
title: "K8s Workload Controller Selection for Fleet Workloads"
type: concept
topic: fleet-architecture
tags: [kubernetes, controllers, deployments, statefulsets, fleet-design, decision-guide]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
---

# K8s Workload Controller Selection for Fleet Workloads

A standing reference for which K8s workload controller fits which fleet role. Distilled from [[kubernetes-workload-controllers|Kubernetes Deployments vs StatefulSets vs DaemonSets]] with per-proposal specifics for the fleet redesign.

## Decision Table

| Workload class | Controller | Why |
|---|---|---|
| Stateless stage workers (motion, inference-coord, alert dispatch) | **Deployment** | Interchangeable pods; ReplicaSet gives self-healing + rollout. Rolling-update `maxUnavailable` is the availability knob. |
| Stateful per-camera / per-camera-group workers (observer+filter, detection core) | **StatefulSet** | Stable ordinal names + stable DNS + per-pod PVs. Critical for camera-affinity designs. |
| Per-node agents (telemetry, GPU drivers, CNI plugins) | **DaemonSet** | Exactly-one-per-node guarantee; unordered rolling updates. |
| Batch reprocessing / one-shot jobs | **Job / CronJob** | Not relevant to continuous fleet workloads but used for cleanup-Lambda-adjacent maintenance. |

## Per-Proposal Mapping

- **A — Minimal Split**: Puller + alert fleets → Deployment. Pipeline worker stays 1-per-site; no StatefulSet needed (source confirms this).
- **B — Stage Fleets**: All 4-5 stages as Deployments. Observer+filter becomes a StatefulSet if strict per-camera affinity is required — this is B's key unanswered controller decision.
- **C — Camera-Worker**: Generic workers as Deployment + external Redis for state, **or** StatefulSet if camera identity must survive restart. Proposal C currently uses the Deployment + external state path.
- **D — Event-Driven**: NATS JetStream = StatefulSet (file-backed JetStream on EBS; PVC orphan retention must be set explicitly). Detector + observer = Deployments.
- **E — Hybrid Sidecar**: Detection core = StatefulSet with camera affinity. Smart puller = Deployment.

## StatefulSet upgrade answer

The open question in [[2026-04-16_proposal-e-hybrid-sidecar]] — "how does a rolling update of detection cores interact with tracker snapshotting?" — is answered by the `partition` field in `updateStrategy.rollingUpdate`. Set `partition: N` to upgrade only pods with ordinal ≥ N, enabling staged ordinal-based rollouts that limit how many camera workers are in-upgrade simultaneously. Combined with preStop snapshot handshake ([[pod-termination-sequence]]), this gives safe StatefulSet upgrades without losing tracker state.

## Gotchas to flag per proposal

- **Proposal D**: NATS JetStream StatefulSet PVC orphans require `persistentVolumeClaimRetentionPolicy: Delete` on the StatefulSet — otherwise scale-down leaves orphaned EBS volumes.
- **Proposal E**: Detection core StatefulSet upgrades need `partition`-field staging + per-pod snapshot protocol; without both, a rolling upgrade can flatten multiple cameras' tracker state simultaneously.
- **Proposal B/C (Observer)**: If choosing StatefulSet for per-camera state, budget for StatefulSet's inherently slower scale-down (ordered termination).

## Related

- [[kubernetes-workload-controllers]] — primary source
- [[pod-termination-sequence]] — upgrade behavior depends on clean pod-termination handshake
- [[pod-disruption-budgets]] — StatefulSet rolling updates don't respect PDBs; need `maxUnavailable: 0` in spec AND a PDB for drain protection
- [[2026-04-16_proposal-a-minimal-split]], [[2026-04-16_proposal-b-stage-fleets]], [[2026-04-16_proposal-c-camera-worker]], [[2026-04-16_proposal-d-event-driven]], [[2026-04-16_proposal-e-hybrid-sidecar]]
