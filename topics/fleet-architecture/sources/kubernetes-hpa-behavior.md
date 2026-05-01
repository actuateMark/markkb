---
title: "Source: Kubernetes Horizontal Pod Autoscaler Behavior"
type: source
topic: fleet-architecture
tags: [source, kubernetes, autoscaling, hpa, scaling-policy, stabilization-window, pod-scaling]
url: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
ingested: 2026-04-21
author: kb-bot
---

# Kubernetes Horizontal Pod Autoscaler Behavior

HPA is a **15-second control loop** (configurable via `--horizontal-pod-autoscaler-sync-period`) that queries the metrics API, computes `desiredReplicas = ceil(currentReplicas × currentMetric / targetMetric)`, and drives Deployments or StatefulSets toward the result. Scaling is skipped if the ratio stays within a 10% tolerance band — prevents thrash on tiny fluctuations.

## Metrics Sources

Four types are supported via the `autoscaling/v2` API: per-pod Resource metrics (CPU/memory, relative to requests), per-pod Custom metrics (raw values), Object metrics (single value describing a Kubernetes object), and External metrics (CloudWatch, Prometheus, etc.). **Resource requests must be set on containers — if absent, HPA takes no action on CPU/memory.** For queue-driven stages, External metrics (queue depth / `averageValue`) is the natural signal.

## Scaling Behavior API

The `behavior:` block (autoscaling/v2) gives fine-grained control over rate and stabilization:

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 0       # react immediately to spikes
    policies:
    - type: Percent
      value: 100
      periodSeconds: 15                 # double replicas every 15 s
  scaleDown:
    stabilizationWindowSeconds: 300     # look back 5 min before shrinking
    policies:
    - type: Percent
      value: 10
      periodSeconds: 60                 # remove max 10% per minute
```

**Stabilization window** prevents scale-down churn: HPA refuses to drop below the highest desired count seen in the window. For bursty video workloads this is the primary anti-thrash lever. **`selectPolicy: Max`** applies the most aggressive scale-up rule; **`selectPolicy: Min`** applies the most conservative scale-down rule.

## Multi-Metric Behaviour

When multiple metrics are declared, HPA scales to the **maximum replica count** demanded by any single metric. Stage-fleet designs (B, D) should model CPU + queue depth together — the effective scale-out is the envelope of both signals.

## Production Gotchas

- **Metric lag**: 15 s sync + scrape delay means a sudden camera burst can cause a brief overload window before pods land. Mitigate with `stabilizationWindowSeconds: 0` on scale-up and pre-warming `minReplicas`.
- **Missing requests → silent no-op**: a container without `resources.requests.cpu` will silently prevent CPU-based autoscaling.
- **Readiness gate**: new pods are excluded from the metric calculation until ready (after `--horizontal-pod-autoscaler-initial-readiness-delay`, default 30 s), preventing premature scale-down of a warming stage.
- **DaemonSets cannot be HPA-scaled** — not applicable to fleet designs, but relevant if any topology uses DaemonSet-style pullers.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Low HPA benefit — the monolith pipeline pod has mixed burst/steady load that averages out. VPA is more applicable than HPA here. HPA on the extracted alert fleet is useful (SQS-depth signal).
- **B — Stage Fleets**: Core scaling mechanism. Each of the five stage fleets (puller, motion, inference, observer, alert) needs an independent HPA with stage-appropriate signals — CPU for motion, queue depth for inference/alert. The `behavior:` stabilization tuning is critical to avoid chain-reaction thrash across stages.
- **C — Camera-Worker Fleet**: Single-fleet HPA on the worker pool, driven by aggregate camera count or CPU. Simpler than B — one HPA, one signal. The per-pod camera-count target is effectively a custom metric.
- **D — Event-Driven Pipeline**: Same per-stage HPA pattern as B, but NATS JetStream consumer-lag becomes the natural external metric (instead of Redis stream backlog). Motion-gating at the puller reduces downstream stage replica counts significantly.
- **E — Hybrid Sidecar**: Smart Puller fleet scales on camera count/CPU; Detection Core uses StatefulSet with camera-group affinity (HPA is awkward against StatefulSets with sticky state — VPA or manual sizing may be more appropriate here); Alert Dispatch HPA on SQS depth.

## Source
https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
