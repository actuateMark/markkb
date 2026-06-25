---
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [person, engineering, inference, ml]
incoming:
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - topics/actuate-platform/notes/concepts/data-flow-architecture.md
  - topics/inference-api/_summary.md
  - topics/watchman/_summary.md
incoming_updated: 2026-06-25
---

# Michael Aleksa

Michael Aleksa is a software engineer at Actuate whose primary focus is the **inference pipeline** -- the system that runs ML models against camera frames in real time. He is the primary developer on [[inference-api/_summary|Actuate Inference API]], the external partner-facing FastAPI service deployed on AWS Lambda.

## Current Work (April 2026)

Michael's active sprint centers on three high-priority tickets:

- **ENG-71 -- Inference batching/compilation (Highest priority).** This effort aims to batch multiple frames into a single inference call and leverage model compilation (e.g., TensorRT or torch.compile) to improve throughput. Given that Actuate processes thousands of concurrent camera streams, even small per-frame latency reductions compound into meaningful cost and capacity gains.
- **ENG-67 -- YAM connector.** The YAM (Yet Another Model) initiative spans engineering and data science. Michael's piece is the connector layer that routes frames to the appropriate model server, working alongside [[uladzimir-sapeshka]] and [[zack-schmidt]] on the AI side (AI-211, AI-158).
- **ENG-39 -- Model accuracy improvements.** Tuning confidence thresholds, IOU parameters, and post-processing filters in [[actuate-filters]] to reduce false positives without increasing misses.

## Technical Domain

Michael works primarily within the **ds-model-prod** Kubernetes namespace, where Rust-based YOLO model servers handle inference. His code touches:

- **[[actuate-inference-client]]** -- the Python client that [[vms-connector]] pods use to call model servers.
- **actuate-inference-api** -- the external-facing FastAPI application (Mangum + Lambda container) that partners like EBUS and AlarmWatch use for on-demand detection.
- **Model server orchestration** -- coordinating which model version (v5 vs v8) serves which product (intruder, weapon, fire).

## Cross-Team Interactions

Michael collaborates closely with the Data Science team, particularly on the v8 model rollout. The v8 models (e.g., `int07-actuate003-v8`) are expected to replace the v5 generation (`intruder-384h-512w-svc`), and Michael's batching work in ENG-71 is a prerequisite for making v8 cost-effective at scale.

## See Also

- [[data-flow-architecture]] -- where inference fits in the overall pipeline
- [[actuate-platform/_summary|Actuate Platform Overview]] -- service inventory
- [[yam-connector]] -- the YAM initiative
