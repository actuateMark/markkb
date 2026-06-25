---
title: "What is Actuate?"
type: concept
tags: [orientation, overview, platform, home]
updated: 2026-06-25
author: kb-bot
incoming:
  - home/README.md
  - home/first-steps.md
  - home/how-to-use-this-kb.md
  - home/system-architecture.md
  - home/the-topic-landscape.md
  - index.md
incoming_updated: 2026-06-25
---

# What is Actuate?

**Actuate is an AI video-surveillance platform.** It turns a customer's *existing* security cameras into a proactive threat-detection system — no new hardware. Actuate ingests live video from the cameras a site already runs, applies computer-vision detection models (intruder, weapon, fire, loitering, …), and when something matters dispatches an alert to whoever monitors that site (a central monitoring station, or the customer directly).

The pitch in one line: **"AI that watches the cameras so a human only looks when it counts."** It cuts false alarms and lets a monitoring center cover far more cameras per operator.

## The data flow (the spine of the whole platform)

```
VMS platforms  ──►  VMS connector  ──►  inference API + models  ──►  alarm senders  ──►  monitoring centers
(frames IN)        (pull/decode)       (detect)                     (dispatch)          (alerts OUT)
```

1. **Frames come IN** from a **VMS** (Video Management System) — Milestone, Avigilon, Exacq, Genetec, Eagle Eye, generic [[rtsp-deep-dive|RTSP]], [[aws-kvs-entity|AWS KVS]], etc. Each is an *integration*. → [[integrations/_summary|integrations]]
2. The **[[vms-connector/_summary|VMS connector]]** is the workhorse: it pulls/decodes frames, runs them through a configurable pipeline (puller → filter → observer → sender), and manages back-pressure. This is the single most important codebase. → [[vms-connector/_summary]]
3. Frames are scored by **detection models** via the **[[inference-api/_summary|inference API]]**. The model *catalog* (what each detector does) is one topic; the *ML/DS infrastructure* (eval, shadow testing, training) is another. → [[models/_summary|models]] · [[the-topic-landscape]]
4. Detections become **alerts**, dispatched by **alarm senders** to **monitoring centers** — Immix (primary partner), [[sentinel-components|Sentinel]], [[bold-components|Bold]], Patriot, SureView, etc. → [[integrations/_summary]]

## The products built on that spine
- **[[autopatrol/_summary|AutoPatrol]]** — automated guard-tour / virtual patrol of camera fleets (a major H1 initiative).
- **[[camera-health-monitoring/_summary|Camera Health Monitoring]]** — detects offline/degraded cameras.
- **[[watchman/_summary|Watchman]]** — fleet-scale monitoring pipeline.
- **Alerts & Settings automation** — tuning sensitivity, reducing false positives → [[alerts-improvements/_summary|alerts]] · [[settings-automation/_summary|settings]].

## The platform pieces (services)
- **[[vms-connector/_summary|VMS connector]]** — the per-customer pipeline (above).
- **[[inference-api/_summary|Inference API]]** — model serving (v5 is the current external contract).
- **[[admin-api/_summary|Admin API]]** / **[[external-api/_summary|External API]]** — control plane + the public v5 API consumed by partners (EBUS was the first).
- **[[fleet-architecture/_summary|Fleet architecture]]** — the redesign for running thousands of connectors economically.

## Where Actuate runs
Production is on **AWS** (account `388576304176`, primarily `us-west-2`), EKS-based ([[infrastructure/_summary|infrastructure]]), observed in **[[new-relic|New Relic]]** ([[new-relic/_summary|new-relic]] · [[operational-health/_summary|operational-health]]). There's a substantial **fleet/cost/perf** concern because every customer camera stream is compute → [[fleet-architecture/_summary|fleet-architecture]] · [[aws-cost/_summary|aws-cost]] · [[profiling-and-performance/_summary|profiling]].

## Next
- New to the codebase? → **[[the-topic-landscape]]** ("where do I go to learn X?").
- New to the *KB itself*? → **[[how-to-use-this-kb]]**.
- Operating the team's automation? → **[[2026-06-22_actuate-footprint-handoff]]** ("what runs where").
