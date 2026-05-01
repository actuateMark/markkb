---
title: "Source: Vertical Pod Autoscaler (VPA) Deep Dive"
type: source
topic: fleet-architecture
tags: [source, kubernetes, vpa, autoscaling, resource-requests, burst-workload, eng-78, memory-management]
url: https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
ingested: 2026-04-21
author: kb-bot
---

# Vertical Pod Autoscaler (VPA) Deep Dive

## Core mechanics

VPA consists of three components: **Recommender** (observes usage history, produces CPU/memory recommendation bounds), **Updater** (evicts pods whose requests fall outside recommended bounds), and **Admission Controller** (webhook that patches resource requests on pod create/recreate). Recommendations are expressed as `lowerBound / target / upperBound`.

## Update modes

| Mode | Behavior |
|------|----------|
| `Off` | Compute recommendations only; no pod mutation |
| `Initial` | Apply on pod creation only; no evictions |
| `Recreate` | Evict + recreate if outside bounds |
| `Auto` | Same as Recreate today; `InPlaceOrRecreate` in v1.4+ |
| `InPlaceOrRecreate` | Try in-place resize first (K8s 1.33+); fall back to evict |

`InPlaceOrRecreate` is GA in VPA v1.6.0 but requires Kubernetes 1.33+ with `InPlacePodVerticalScaling` feature gate.

## Why VPA over-provisions burst+steady workloads (ENG-78 root cause)

VPA's recommender fits a **single recommendation** to a historical usage window. When a pod runs both a steady baseline load (idle pull loop) and intermittent bursts (inference), the recommender observes the burst peaks and raises the `target` request to cover them — even though bursts are rare. The pod is thus over-provisioned during the 90%+ of time it is not bursting.

This is structural, not a tuning failure: VPA has no concept of bimodal workload distributions. The fix is **workload separation** — burst work and steady work in distinct pods, each with its own VPA. Each VPA then sees a unimodal usage distribution and recommends tightly.

## Known hard limitations

- **Incompatible with HPA on the same resource metric.** VPA on memory + HPA on CPU is the only safe combo.
- **Pod recreation on update** (unless `InPlaceOrRecreate` + K8s 1.33+). For stateful pods, this triggers the full graceful-shutdown + checkpoint cycle on every VPA update — an unplanned cost.
- **Recommendations can exceed node allocatable** — pods go `Pending`. Mitigate with `--container-recommendation-max-allowed-cpu/memory` flags.
- **Multiple VPA objects matching the same pod = undefined behavior.**
- **Not tested at large cluster scale.** Performance degrades with many VPA objects.

## Startup Boost (alpha v1.7.0)

New `startupBoost` field multiplies CPU request at pod create, then scales back in-place after readiness. Relevant for inference pods with JVM/torch cold-start overhead.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Pipeline worker VPA problem unchanged — burst+steady still cohabitate. ENG-78 not resolved by A. Puller and alert fleets are steady-load and VPA well.
- **B — Stage Fleets**: Each stage fleet is workload-homogeneous — inference pods are bursty, observer pods are steady, puller pods are steady. Each fleet gets a clean VPA. **Directly fixes ENG-78 at the cost of architectural complexity.**
- **C — Camera-Worker**: Generic workers mix burst+steady per-pod still, but load is smoother due to bin-packing across cameras. Partially improves VPA accuracy vs today. Proposal note acknowledges "fixes ENG-78 partially."
- **D — Event-Driven**: Detector pods are purely burst (event-triggered), observer pods are purely steady. Clean VPA separation. Similar fix quality to B.
- **E — Hybrid Sidecar**: Proposal note explicitly calls out "VPA fix — smart puller is steady-load; detection core is bursty" as a benefit. Detection core VPA sees only inference bursts; puller VPA sees only steady pull rate. **Best structural alignment with ENG-78 fix among proposals evaluated.**

## Source
https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
