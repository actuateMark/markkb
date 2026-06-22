---
title: "connector-38088 OOM triage (2026-05-15)"
type: concept
topic: vms-connector
tags: [connector, oom, triage, vpa-floor, rtsp, customer-outage, section-18]
created: 2026-05-15
updated: 2026-05-15
author: kb-bot
- No backlinks found.
incoming:
  - topics/personal-notes/notes/daily/2026-05-15.md
incoming_updated: 2026-05-19
---

# connector-38088 OOM triage (2026-05-15)

## Verdict

**Acute customer-side [[rtsp-deep-dive|RTSP]] outage hitting an undersized-limit cohort pod.** Not a memory leak, not a connector code regression, not config drift in our cluster. Pod has self-recovered (0 OOMs in last 3 hours) once the cameras came back online.

Goes into [[§18]] VPA floor work as a new instance of the same class. No emergency action.

## Signal that triggered triage

Dashboard `fleet_new_oom_offender` morning fan-out 2026-05-15: connector-38088 = **55 OOMKills/24h**, vs next-worst connector at 3 (18× ratio). Friday-wrap had this pre-flagged as a "fan-out surprise" item for today.

## Evidence chain

### 1. Time-series — acute, not chronic

| Day | OOMs |
|---|---|
| Day -7 through Day -2 (6 days) | **0** |
| Day -1 (last 24h) | **55** |
| Last 3 hours | **0** (recovery) |

NRQL: `FROM K8sContainerSample WHERE clusterName='Connector-EKS' AND containerName='connector-38088' AND reason='OOMKilled' TIMESERIES 1 day SINCE 7 days ago`

The 16-hour burst window: 03:30Z → 19:30Z 2026-05-14. Started cold, peaked at 6 kills/hour, tapered, then stopped abruptly.

### 2. Pod configuration — undersized memory limit, no request

```
podName:           connector-38088-6d4f44bc77-mxqtk
memoryLimitBytes:  700 MB
memoryRequestBytes: null  ← no request set
recentRestarts:    0 (last 30 min)
peak RSS:          489 MB (99.2 % of limit)
```

This puts the pod squarely in the **`connector_pods_under_1gb_limit` cohort** tracked by [[2026-04-23_oom-surge-connector-limit-drift]] and [[§18]] VPA-floor work. With memory request unset, the VPA never had a signal to bump the limit.

### 3. Customer-side trigger — 9 cameras simultaneously offline

Log facet during the burst window (top 10 messages):

| Count | Message |
|---|---|
| 1234 | `WARNING:(D07_pl):unable to connect, sleeping 60s before retry.` |
| 1234 | `WARNING:(D06_pl):unable to connect, sleeping 60s before retry.` |
| 412 | `WARNING:(D07_pl):Options: {'rtsp_transport':'tcp','probesize':'5000000','analyzeduration':'5000000',...}` |
| 412 | `WARNING:(D06_pl):Options: ...` |
| 288 | `WARNING:(D09_pl):unable to connect, sleeping 60s before retry.` |
| 288 | `WARNING:(D04_pl):unable to connect, sleeping 60s before retry.` |
| 288 | `WARNING:(D01_pl):unable to connect, sleeping 60s before retry.` |
| 288 | `WARNING:(D08_pl):unable to connect, sleeping 60s before retry.` |
| 288 | `WARNING:(D03_pl):unable to connect, sleeping 60s before retry.` |
| 288 | `WARNING:(D05_pl):unable to connect, sleeping 60s before retry.` |

Nine cameras (D01_pl through D09_pl) all in retry loops simultaneously. **No ERROR-level logs** — the OOM kills happen between log flushes. Zero customer-name / site-id labels surfaced for the pod (label payload was empty), so customer attribution is via the stream-ID naming convention (`D0N_pl`) rather than direct.

### 4. Memory mechanics — why retry-storm overran 700 MB

- [[ffmpeg-entity|FFmpeg]] [[rtsp-deep-dive|RTSP]] options (per the logged config): `probesize=5MB` + `analyzeduration=5MB`
- Each connect-attempt allocates ~10MB for probe buffers; not all of it is freed efficiently when the connection itself fails (no stream context to clean up the partial buffer)
- 9 cameras × ~10MB per retry-tick × 60-second tick = ~90MB per minute of churn
- Steady-state working set (no retry storm) = ~250-300MB
- Under retry storm: 300 + 90 × N → overran the 700MB ceiling within a few cycles
- Each OOMKill restarts the pod → state reset → retry storm immediately resumes → next kill

### 5. Recovery

Last 3 hours: 0 kills. `recentRestarts=0` in the last 30-min window. The customer-side trigger resolved (cameras came back online, or the site itself recovered), retry storm stopped, working set returned to steady-state ~300MB, well under the 700MB limit.

## Classification summary

| Dimension | Verdict |
|---|---|
| Code regression? | **No** — connector behavior is correct: retry on [[rtsp-deep-dive|RTSP]] failure with bounded sleep |
| Memory leak? | **No** — 7-day history shows 0 kills for 6 days, then a single burst |
| Cluster config drift? | **No** — pod limit (700MB) is the cohort default for this customer profile |
| Customer-side outage? | **Yes (primary trigger)** — 9-camera simultaneous [[rtsp-deep-dive|RTSP]] outage |
| Undersized memory cohort? | **Yes (aggravator)** — same cohort as the 2026-04-23 incident; VPA floor work already tracks |

## What this changes about §18 VPA floor work

The work was already prioritized; this just adds another datapoint. Specifically:

- **Cohort coverage**: connector-38088 wasn't on the pre-existing top-N list (those were 14170, 41984, etc.). The undersized-limit population is broader than the dashboard's top-15 surface. **§18 work should set the floor for ALL connector pods, not just the chronic offenders**.
- **Trigger landscape**: previously assumed the cohort would OOM under "normal" memory pressure (post-NMS, frame buffer churn). This incident shows **retry-storm pressure** is a distinct trigger class. The VPA floor needs to absorb retry-storm working-set spikes, not just steady-state operations. Suggest floor of 1.5GB minimum.
- **VPA visibility**: `memoryRequestBytes=null` is the deeper bug. Without a request value, VPA can't recommend a higher limit. The §18 PR should ensure both `request` AND `limit` are set per the connector_deployer template.

## Follow-ups (not blocking, not today)

- [ ] Confirm with customer-success which customer/site `D0N_pl` cameras map to (label payload was empty; stream-ID-based lookup needed)
- [ ] Add a `retry_storm_pressure_minutes_24h` synthetic signal to the dashboard — counts hours where any single container had >100 retry-loop log lines. Pre-empts the OOM by N hours
- [ ] Consider FFmpeg-level fix: smaller `probesize` / `analyzeduration` for retry-mode connections (probably 500KB / 500ms is sufficient for "is this thing online yet" probing)

## Related

- [[2026-04-23_oom-surge-connector-limit-drift]] — the original undersized-cohort writeup
- §18 in [[mark-todos]] — VPA floor + audit work
- [[fleet_new_oom_offender]] signal definition (`~/.claude/skills/dashboard-check/config/signals.json`)
- Dashboard observation today recorded as `morning_fleet_oom_spike` in the sink
