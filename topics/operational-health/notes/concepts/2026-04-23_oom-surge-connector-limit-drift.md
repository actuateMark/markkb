---
title: "OOM Surge 2026-04-23 — Connector Memory-Limit Drift (not a code regression)"
type: concept
topic: operational-health
tags: [oom, connector-memory-limits, fleet-drift, triage, k8s-limits]
jira: "OPS-XX"
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
---

# OOM Surge 2026-04-23 — Memory-Limit Drift, Not a Code Regression

Overnight OOMKill count hit 423/24h (4× baseline 103). Triage revealed this was **NOT a code regression, a deploy event, or node-pressure incident** — it was sustained per-pod memory-limit ceiling hits on misconfigured connector pods. One top offender (`connector-20628`, 87 kills) was patched mid-day: its limit was raised 384 MB → 1.6 GB and OOMs stopped immediately.

## Surge Shape (Triage Dismissal)

24-hour TIMESERIES from 2026-04-23 00:00 to 23:59Z shows a plateau, not a spike:

- Hours 0–2: baseline noise (6–8 kills/hr; rollover artifact)
- Hours 3–21: **steady 13–28 kills/hr plateau**
- Hours 22–24: subsiding (3–7 kills/hr)

A single deploy or node-pressure event would produce a sharp spike and recovery. This plateau across 18 hours of the day rules out instantaneous cluster-level triggers. The simultaneous entry of 7 new containers into the top-10 strongly suggests a **structural under-provisioning problem**, not a transient fault.

## Top Offender: connector-20628 Resolution

Pre-fix (hours 0–14):
- Memory limit: **384 MB**
- Working set peak: **401 MB** (touching ceiling)
- OOMKill rate: 5–6/hr

Mid-day patch (applied externally):
- Memory limit: **1.6 GB**
- Working set: stabilized at 930–960 MB
- OOMKill rate: **zero** (last 10 hours)

The process was **not leaking memory**. It was being killed at a hard ceiling while genuinely needing ~950 MB. The fix was not a code change — it was an external Kubernetes limit adjustment, confirming that the root cause is misconfigured resource bounds, not application behavior.

Comparison: `connector-14170` ("improving" prior heaviest offender) runs at 1.6 GB limit with ~975 MB working set; this is what correct sizing looks like.

## Fleet-Wide Memory-Limit Distribution

Scan of Connector-EKS fleet over the past 1 hour reveals structural under-provisioning:

| Limit Tier (MB) | Pod Count | Risk Assessment |
|---|---|---|
| ≥1.6 GB | 67 | Correctly sized |
| ~1 GB (981 MB) | 100 | Adequate headroom |
| 700–919 MB | 740 | Moderate risk |
| 480–652 MB | 840 | **High risk** |
| **384–426 MB** | **1,956** | **CRITICAL tier** |
| 300 MB | 1 | Outlier |
| **Total < 1 GB** | **~4,603** | **Majority of fleet** |

The 384–426 MB cohort (1,956 pods) is the highest latent-risk tier. None are currently exceeding 70% headroom utilization, but any inference-queue backup or video burst will push these pods over. This tier is the source of last night's sustained OOM plateau.

## Release Tracking — The Feb 9 VPA-Floor Removal

The drift is **not traceable to a vms-connector release**. The deployment template in `connector_deployer/src/yaml/deployment.py:48` specifies `limits: memory: 6Gi` (connector pods) and `limits: memory: 2Gi` (task pods). The observed 384–480 MB limits come from **VPA (Vertical Pod Autoscaler) adjusting limits downward** based on historical usage.

Traced to three commits in the `connector_deployer` repo:

| Commit | Date (UTC-3) | Change | Effect |
|---|---|---|---|
| `a5de5db` "remove vpa patch" | 2026-02-09 17:49 | Removed the code path that applied a minimum-memory floor on VPA at pod creation | **Prime suspect.** After this, VPA can recommend arbitrarily low limits based on observed usage alone. Pods previously pinned at a floor start drifting downward via VPA learning-loops. |
| `9736971` "Feature: change vpa min memory recommendation based on number of camera for Alarmquip lead" | 2026-03-04 14:34 | Added a selective floor (500 MiB + 150 MiB × camera count), but only when `lead == "Alarmquip"` | Restored the floor only for one lead segment. Everyone else still floorless. |
| `4367a39` "Fix VPA memory scaling to target Securitas Australia - Trial instead of Alarmquip" | 2026-03-04 15:00 (+26 min) | Corrected target from Alarmquip → "Securitas Australia - Trial"; renamed env var `ALARMQUIP_VPA_MEMORY_SCALING_FACTOR_MI` → `SMTP_VPA_MEMORY_SCALING_FACTOR_MI` | Floor now applies to a single different lead. Majority of fleet has no floor applied since 2026-02-09. |
| `cd4ff72` "Log VPA patch errors instead of silently swallowing them" | 2026-03-04 15:30 | Began surfacing previously-hidden VPA patch failures | Would have surfaced the Feb 9 regression earlier if in place. |

**Implication:** The 73-day gap between the Feb 9 floor-removal and the 2026-04-23 OOM plateau is VPA's learning-loop compression time. Pod memory limits drifted downward gradually as traffic patterns fluctuated; eventually a subset hit the natural floor (VPA minAllowed = 10 MiB in the cronjob VPA template) and became OOM-susceptible under any load spike.

**This is the class of regression that [[2026-04-23_release-acceptance-criteria]] §5 (config-surface drift) exists to prevent.**

## No Node Pressure, No Deploy Event

Cross-check via K8sNodeSample (24h window):
- Zero node evictions
- Zero `MemoryPressure` or `DiskPressure` condition flags
- Top-7 OOM offenders distributed across 5 different nodes (eliminates shared node → eliminates node-level cause)

No recent deploy anomalies. The 7 new top-offenders did not converge on OOM after a single release — they hit the plateau simultaneously, confirming a **capability ceiling**, not a fault.

## Secondary Finding: Platform Service Creep

`create-detection-window` entered the top-10 OOM list (9 kills) with the same plateau pattern. Platform services are also experiencing memory-limit ceiling hits. This broadens the scope: it's not just connectors.

## Unrelated Fleet Noise: feature/autopatrol-cleanup-emit

The unrelated `feature/autopatrol-cleanup-emit` branch is emitting 300–430 events/hr with `invalid image name` errors. This is feature-branch misconfiguration, not OOM-related; flagged for separate cleanup.

## Audit Workstream: Fleet Memory-Limit Baseline

Recommended scope:
- Raise the 384–426 MB cohort (1,956 pods) to ≥1 GB baseline
- Review 480–652 MB cohort (840 pods) for workload-specific justification; most should move to 1+ GB
- Baseline for correctly-sized connector: **1.6 GB limit** (working set ~950 MB, ~40% headroom)

Not urgent (no pods currently at >70% headroom usage), but the fleet is structurally brittle. Any sustained inference queue backup will cascade OOMs across 4,600+ pods.

## Cross-Refs

- [[2026-04-23_overnight-check]] — parent health-check synthesis
- [[2026-04-22_overnight-check]] — prior-day baseline
- [[mark-todos]] — audit workstream §OOM-fleet-limits (to be registered)
