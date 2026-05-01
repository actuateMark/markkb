---
title: "VPA Bimodal Workload Limitation (ENG-78 Root Cause)"
type: concept
topic: fleet-architecture
tags: [vpa, autoscaling, eng-78, burst-workload, resource-requests, over-provisioning]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
---

# VPA Bimodal Workload Limitation (ENG-78 Root Cause)

The structural reason VPA over-provisions the current connector pipeline pod, and why it's not a VPA tuning failure but a workload-shape problem.

Primary source: [[vertical-pod-autoscaler-deep-dive]]. Parent issue: **ENG-78** (connector VPA over-provisioning).

## The Core Problem

VPA's Recommender fits a **single recommendation** to a historical usage window, producing `lowerBound / target / upperBound` values. The recommendation is a single point in resource-space.

When a pod runs both:
- **Steady baseline** (idle pull loop, ~X CPU ~M memory)
- **Intermittent bursts** (inference, ~10X CPU ~3M memory, 5% of time)

…the Recommender observes the burst peaks and raises `target` to cover them. The pod is thus over-provisioned during the 95%+ of time it is **not** bursting — consuming cluster capacity it doesn't need and inflating cost.

**This is structural, not a tuning failure:** VPA has no concept of bimodal workload distributions. No recommender tuning knob resolves it.

## Why the Connector Hits This Hardest

Today's connector pipeline pod is the textbook bimodal workload:
- Per-camera frame pulling (steady CPU, steady memory)
- Per-camera motion detection (bursty when motion detected)
- Periodic YOLO inference (bursty per-site clip)
- Tracker updates (bursty per-motion-event)
- Alert dispatch (bursty per-detection)

All cohabitate one pod. VPA sees the superposition and sizes for the worst case.

## The Fix: Workload Separation

Split burst work and steady work into distinct pods. Each pod gets its own VPA. Each VPA then sees a **unimodal** usage distribution and recommends tightly.

This is the structural benefit that every fleet-redesign proposal claims in varying degrees:

| Proposal | VPA fix quality | Why |
|---|---|---|
| **A — Minimal Split** | ❌ No fix | Pipeline pod still monolithic; ENG-78 persists. Only puller+alert benefit. |
| **B — Stage Fleets** | ✅ Direct fix | Each stage is workload-homogeneous. Clean VPA per fleet. |
| **C — Camera-Worker** | 🟡 Partial fix | Generic workers still mix burst+steady, but bin-packing smooths load vs today. |
| **D — Event-Driven** | ✅ Direct fix | Detector pods = pure burst, observer pods = pure steady. |
| **E — Hybrid Sidecar** | ✅ **Best fix** | Explicit "smart puller (steady) + detection core (bursty)" separation is the exact fix pattern. |

Proposal E's explicit VPA-fix benefit claim is validated by this source material.

## Other VPA Gotchas Worth Knowing

- **Incompatible with HPA on the same metric.** VPA on memory + HPA on CPU is the only safe combo.
- **Pod recreation on update** (unless `InPlaceOrRecreate` + K8s 1.33+). For stateful pods, each VPA update triggers the full graceful-shutdown + checkpoint cycle ([[pod-termination-sequence]]) unexpectedly. Stateful fleet pods on VPA should test this behavior in PoC.
- **Multiple VPA objects matching the same pod = undefined behavior.** Don't overlap selectors.
- **Recommendations can exceed node allocatable** — pods go `Pending`. Set `--container-recommendation-max-allowed-cpu/memory`.

## K8s Version Dependency

`InPlaceOrRecreate` mode (GA in VPA v1.6.0, requires K8s 1.33+ with `InPlacePodVerticalScaling` feature gate) changes the "VPA triggers unplanned restart" concern significantly. Before finalizing any proposal's VPA strategy, **confirm EKS cluster K8s version** — this affects whether `InPlaceOrRecreate` is available or `Recreate` is the only option.

## Related

- [[vertical-pod-autoscaler-deep-dive]] — primary source
- [[scaling-layer-taxonomy]] — VPA in context of HPA + Karpenter
- [[memory-and-fork-safety]] — VPA recreation triggers graceful shutdown unplanned; interaction with fork-safety on restart
- [[pod-termination-sequence]] — VPA-triggered pod recreation runs through this sequence
- ENG-78 — the Jira ticket this note is the root-cause analysis for
