---
title: "System architecture — the layers, end to end"
type: synthesis
tags: [orientation, architecture, system-design, home]
updated: 2026-06-25
author: kb-bot
incoming:
  - home/README.md
  - home/first-steps.md
  - index.md
incoming_updated: 2026-06-25
---

# System architecture — the layers, end to end

[[what-is-actuate]] gives the one-line spine (frames in → detect → alerts out). This page expands it into the **layers** an engineer actually works in, and points each at its deep-dive topic. It's a map, not the territory — the detail lives in `topics/` (see [[the-topic-landscape]]).

```
                 ┌─────────────────────────────────────────────────────────────┐
 CAMERAS / VMS   │  Milestone · Avigilon · Genetec · Exacq · Eagle Eye · RTSP   │   ← integrations
 (frame source)  │  · AWS KVS · HikCentral · …  (each = an integration)         │
                 └───────────────────────────────┬─────────────────────────────┘
                                                  │ pull / decode frames
                 ┌────────────────────────────────▼────────────────────────────┐
 VMS CONNECTOR   │  puller → filter → observer → sender   (one pod per customer)│   ← vms-connector
 (the workhorse) │  AIMD back-pressure · sliding-window · config-threaded       │     + actuate-libraries
                 └───────────────────────────────┬─────────────────────────────┘
                                                  │ candidate frames
                 ┌────────────────────────────────▼────────────────────────────┐
 INFERENCE       │  inference API (v5 contract)  →  model catalog               │   ← inference-api
 (detect)        │  intruder/weapon/fire/loitering/line-crossing/…  (YOLO+VLM)  │     models · ai-models
                 └───────────────────────────────┬─────────────────────────────┘
                                                  │ detections
                 ┌────────────────────────────────▼────────────────────────────┐
 DISPATCH        │  alarm senders → monitoring centers                          │   ← integrations
 (alerts out)    │  Immix (primary) · Sentinel · Bold · Patriot · SureView · …  │     alerts-improvements
                 └─────────────────────────────────────────────────────────────┘

 CONTROL PLANE   admin API · external API (public v5) · settings/sensitivity     ← admin-api · external-api
 FLEET / INFRA   EKS (Connector-EKS) · fleet-arch redesign · autoscaling · cost  ← fleet-architecture · aws-cost
 OBSERVABILITY   New Relic · the operational dashboard · health checks           ← operational-health · new-relic
```

## The layers, explained

1. **Ingest (integrations).** Each VMS platform is a separate integration with its own quirks (auth, frame pull, [[rtsp-deep-dive|RTSP]] vs SDK vs cloud-KVS). Frame sources feed the connector's puller layer. → [[integrations/_summary]]
2. **[[vms-connector|VMS connector]] — the single most important codebase.** A per-customer pipeline: **puller** (get frames) → **filter** (drop uninteresting frames cheaply) → **observer** (run detection) → **sender** (dispatch alarms). It manages back-pressure with **AIMD** + a **sliding window** so a slow downstream doesn't melt the puller. Config is threaded through the pipeline from the control plane. Shared logic lives in **actuate-libraries** (published packages). → [[vms-connector/_summary]] · [[actuate-libraries/_summary]]
3. **Inference.** The connector calls the **inference API** (current external contract = **v5**) to score frames against the **model catalog**. Models are a mix of YOLO detectors and VLM-based detectors. The *catalog* (what each does) and the *DS/eval infra* (how we pick/validate models) are separate topics. → [[inference-api/_summary]] · [[models/_summary]] · [[ai-models/_summary]]
4. **Dispatch.** Detections become alarms, sent by per-center **alarm senders** to monitoring centers (Immix is the primary partner). Tuning to cut false positives is the alerts/settings work. → [[integrations/_summary]] · [[alerts-improvements/_summary]]
5. **Control plane.** **admin-api** (internal control) + **external-api** (the public v5 API partners consume — EBUS was first) configure connectors, sensitivity presets, and customer/site data. → [[admin-api/_summary]] · [[external-api/_summary]]
6. **Fleet & infra.** Everything runs on **AWS EKS** (cluster `Connector-EKS`, account `388576304176`, mainly `us-west-2`). Because every camera stream is compute, **fleet-architecture** (the redesign for running thousands of connectors economically) and **aws-cost** are first-class concerns. → [[fleet-architecture/_summary]] · [[aws-cost/_summary]] · [[compute-fleet/_summary]]
7. **Observability.** Production is observed in **[[new-relic|New Relic]]** (query rules: always scope by `cluster_name` + `container_name`, never `SELECT *`). The team's own operational dashboard (on firebat) aggregates fleet health. → [[operational-health/_summary]] · [[new-relic/_summary]]

## How code ships (environments)
Branch flow is roughly **feature → stage → rearchitecture → prod**; merges deploy via CI (GitHub Actions) + **[[argocd|ArgoCD]]** sync onto EKS. **actuate-libraries** is special: merging to its `main` **auto-publishes** stable packages to CodeArtifact, so connector pins must be updated deliberately (see [[engineering-process/_summary]] + the pre-merge workflow). The connector builds multi-arch images (ARM64 + x86) to ECR.

## Where to go deeper
For the *pipeline internals* there's a `connector-pipeline-expert` subagent; for *production triage* an `nrql-investigator`. Otherwise follow the topic links above, or [[the-topic-landscape]] for the full "learn X → go here" map.
