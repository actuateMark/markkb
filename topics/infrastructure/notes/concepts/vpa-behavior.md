---
type: concept
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
---

# VPA Behavior

Vertical Pod Autoscaler (VPA) automatically adjusts CPU and memory requests for [[vms-connector]] pods in the `rearchitecture` namespace. While intended to right-size workloads, VPA's current behavior at Actuate causes significant over-provisioning and operational instability.

## The Over-Provisioning Problem (ENG-78)

VPA recommendations consistently request **3-5x more CPU and 2x more memory** than pods actually use. The root cause is that VPA bases its recommendations on peak observed usage with a generous safety margin, but connector workloads are inherently bursty -- inference bursts spike CPU briefly, then the pod idles between frames. VPA treats these peaks as the steady-state requirement, inflating requests far beyond average consumption.

This over-provisioning wastes cluster capacity. Nodes fill up based on requested resources (not actual usage), forcing Karpenter to provision more nodes than the workload genuinely needs. The cost impact is substantial across a fleet of hundreds of connector pods.

## Patching Race Condition

VPA applies its recommendations by evicting the pod and recreating it with updated resource requests. This creates a **race condition with the Kubernetes API server**: if VPA issues a patch to update resource requests at the same moment the pod is being scheduled or reconciled, the conflicting writes can cause the pod to enter an error state. In practice, this manifests as **OOMKills** -- the pod restarts with incorrect or partially-applied resource limits and gets killed when it exceeds them.

This race condition is particularly damaging for connectors because each pod manages an active site with open camera streams, detection windows, and in-flight alerts. An unexpected restart means dropped frames, orphaned detection windows, and missed alerts until the pod fully reinitialises.

## Mid-Run Downscaling

VPA can also **downscale resources while a pod is actively processing**. If a connector is mid-inference-burst and VPA decides the pod's historical average warrants lower limits, it evicts the pod. The connector loses all in-memory state: camera connections, [[botsort-tracking|BoTSORT tracking]] histories, sliding window positions, and stationary filter baselines. Rebuilding this state takes minutes and causes a gap in detection coverage.

## Proposed Fix: In-Place Pod Resize (ENG-79)

EKS 1.35 introduces **in-place pod resize** (GA), which allows resource requests and limits to be updated without evicting the pod. This would eliminate the eviction-restart cycle entirely -- VPA could adjust resources on a running pod without interrupting camera streams or losing detection state.

The prerequisite is upgrading from EKS 1.32 to 1.35 (tracked as ENG-79, Highest priority, currently unassigned). Once in-place resize is available, VPA evictions would be replaced with live resource adjustments, and the patching race condition becomes irrelevant since no pod recreation occurs. The over-provisioning recommendations would still need tuning, but at least the operational disruption from applying them would be eliminated.

Both ENG-78 and ENG-79 are flagged as Highest priority in the [[kubernetes-deployments]] backlog.
