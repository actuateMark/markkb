---
title: "Source: Kubernetes Deployments vs StatefulSets vs DaemonSets"
type: source
topic: fleet-architecture
tags: [source, kubernetes, deployments, statefulsets, daemonsets, workload-controllers]
url: https://kubernetes.io/docs/concepts/workloads/controllers/
ingested: 2026-04-21
author: kb-bot
---

# Kubernetes Deployments vs StatefulSets vs DaemonSets

Kubernetes offers three primary workload controllers for long-running processes, each with distinct identity and state guarantees.

**Deployment** manages stateless, interchangeable pods via a ReplicaSet. Pods have no sticky identity — they get new names and IPs on restart. Deployments handle declarative rollouts, rollbacks, and self-healing. Key gotcha: ConfigMap/Secret changes do not automatically restart pods; use `kubectl rollout restart`. Aggressive scaling can saturate node resources or CNI plugins. Best fit for stateless stage workers (inference servers, frame-processing queues, alert dispatchers).

**StatefulSet** manages pods with stable ordinal names (`pod-0`, `pod-1`), stable DNS hostnames (`pod-name.svc-name.ns.svc.cluster.local`), and per-pod PersistentVolumes. Startup/shutdown ordering is controlled by `podManagementPolicy`. Critical gotchas: PVC orphans are left behind on manual pod deletion unless `persistentVolumeClaimRetentionPolicy: Delete` is set; scale-down does not reclaim storage; upgrade parallelism is gated by the `partition` field in rolling-update strategy. Best fit for stateful per-camera workers that require durable identity — tracker state, per-camera model caches, per-device configuration locality.

**DaemonSet** schedules exactly one pod per node (or per matching node set). It provides node-local resource access and auto-provisions to new nodes. Rolling updates are unordered. Not suitable for camera-specific stateful workloads; suited for per-node telemetry agents, GPU drivers, or CNI plugins.

A practical controller-selection table for camera fleet workloads:

| Workload | Controller |
|---|---|
| Per-camera detection worker (tracker, filter chain) | StatefulSet |
| Shared inference API / alert dispatch | Deployment |
| Per-node telemetry/log forwarding | DaemonSet |
| Batch reprocessing | Job/CronJob |

For StatefulSet upgrades, use the `partition` field to perform staged ordinal-based rollouts, limiting how many camera workers are in-upgrade simultaneously.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Puller fleet and alert dispatch fleet are stateless — Deployment is the right controller. Pipeline workers remain 1-per-site (today's model); this source confirms no StatefulSet is needed for A's pipeline.
- **B — Stage Fleets**: Each stage fleet (motion, inference-coord, observer+filter, alert dispatch) maps to a Deployment. The observer+filter fleet holds tracker state per camera — if camera affinity is strict, StatefulSet becomes preferable there. This is B's key controller design decision.
- **C — Camera-Worker**: Generic workers holding N cameras of full pipeline are the central StatefulSet candidate if camera identity must be preserved across restarts. Alternatively, Deployment + external Redis state (the current design) decouples identity from the controller. Source clarifies the tradeoff explicitly.
- **D — Event-Driven**: NATS JetStream itself is a StatefulSet (file-backed JetStream on EBS). Detector/observer fleets are Deployments. Source confirms the gotcha: StatefulSet PVC orphans require explicit retention policy — relevant to NATS cluster lifecycle.
- **E — Hybrid Sidecar**: Detection Core is explicitly a StatefulSet with camera affinity. This source is the primary reference for E's StatefulSet upgrade behavior question (open question in proposal-e: "how does a rolling update of detection cores interact with tracker snapshotting?"). The `partition` field in rolling-update strategy is the answer.

## Source
https://kubernetes.io/docs/concepts/workloads/controllers/
