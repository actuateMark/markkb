---
title: VLM Pipeline Architecture
type: concept
topic: ai-models
tags: [vlm, vllm, sqs, dynamodb, keda, autopatrol, watchman, qwen, inference, architecture]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# VLM Pipeline Architecture

## Overview

Vision-Language Models (VLMs) serve a dual role in the Actuate platform: reducing false positives in the **AutoPatrol** automated monitoring workflow, and powering the **Watchman** assessment agent that provides scene-level understanding of security alerts. The VLM pipeline is architecturally distinct from the YOLO-based [[detection-pipeline]] -- it is asynchronous, queue-driven, and runs on GPU instances rather than Inferentia2.

## Architecture: Queue-Driven Inference

The production VLM pipeline follows a decoupled, KEDA-scaled pattern:

```
Alert Generated (S3 + SQS)
    |
    v
actuate-vlm (client library)
    |
    v
SQS FIFO Queue (per-model: vlm-{model}-{stage}.fifo)
    |
    v
KEDA ScaledObject -> K8s Deployment (scale 0-to-N based on queue depth)
    |
    v
vlm-inference Worker Pod [vLLM + Worker]
    |
    v
DynamoDB (results: WindowIdsV2 table) + Webhook (optional callback)
```

Each model gets its own SQS FIFO queue, Docker image tag, and Kubernetes deployment. KEDA scales replicas from zero when no work is pending, keeping GPU costs under control, and scales up as queue depth increases during alert surges.

## Key Components

### actuate-vlm (Client Library)

The Python client library that submits VLM requests from the connector pipeline or other services. It handles image upload to S3 (with content-hash deduplication), SQS message formatting, and result retrieval via DynamoDB polling or webhook callback. Both the AutoPatrol and Watchman use cases call through this library.

### vlm-inference (GPU Worker)

[[vlm-inference]] is a lightweight Docker container that polls its assigned SQS FIFO queue for work, runs inference via **vLLM** (an optimised LLM serving engine), and writes results to DynamoDB. Key design choices:

- **vLLM backend**: Provides OpenAI-compatible API, efficient KV-cache management, continuous batching, and tensor parallelism. The build script auto-detects the correct vLLM base image by reading the model's HuggingFace `config.json`.
- **Model isolation**: Each model runs in its own pod with a dedicated queue, preventing a slow model from blocking faster ones.
- **Stage routing**: `STAGE=dev` (default) routes to `vlm-{model}-dev.fifo`; `STAGE=prod` routes to `vlm-{model}.fifo`. Both worker and caller default to dev to prevent accidental production writes.
- **GPU tuning**: For 8B models on 24 GB VRAM (g5/g6 instances), recommended settings are `GPU_MEMORY_UTIL=0.95`, `ENFORCE_EAGER=true`, `MAX_MODEL_LEN=8192`.

### DynamoDB (Results Store)

VLM verdicts are stored in the `WindowIdsV2` table with `vlm_detail` (full model response) and `vlm_verdict` (pass/suppress decision) fields. Downstream consumers -- including the AutoPatrol workflow and the [[vlm-eval-visualizer]] review tool -- read from this table.

## KEDA Autoscaling

KEDA (Kubernetes Event-Driven Autoscaling) monitors SQS queue depth and scales worker deployments accordingly. The scaling configuration lives in `cluster-values.yaml` in the `kubernetes-deployments` repo. Key behaviors:

- **Scale to zero**: When no messages are in the queue, KEDA terminates all worker pods, eliminating GPU cost during quiet periods.
- **Scale up**: As queue depth grows, KEDA adds replicas. Each replica consumes a full GPU.
- **Cooldown**: Configurable cooldown periods prevent thrashing during bursty alert patterns.

This is critical for cost management: GPU instances (EC2 g5.2xlarge at approximately $1.21/hr) are expensive, and the surveillance workload is inherently bursty -- alert volumes spike at night when security events are most common.

## Dual Role: AutoPatrol and Watchman

### AutoPatrol FP Reduction

The primary production use case. After the YOLO-based [[detection-pipeline]] generates an alert, the VLM reviews the alert frames to determine whether the detection is a genuine security event or a false positive. The VLM can understand scene context that YOLO cannot -- a person in a delivery uniform vs. an intruder, a branch blowing in the wind vs. a person climbing a fence.

The AutoPatrol pipeline sends alert frames through [[actuate-vlm]] to the VLM queue. The worker processes the frames, and the verdict (`vlm_verdict`) determines whether the alert is suppressed or forwarded to the monitoring operator. This runs in the post-alert stage of the pipeline -- after all YOLO filters and observers have already fired.

### Watchman Assessment Agent

The Watchman use case is more sophisticated. Rather than simple pass/suppress decisions, the VLM acts as an **assessment agent** that provides structured scene analysis: what objects are present, what activity is occurring, risk assessment, and recommended actions. This powers automated report generation and intelligent escalation.

[[ds-smart-alert-supervisor]] implements frame-level alert verification combining detection heuristics (N-out-of-M frame rules, confidence thresholds) with VLM-based verification. It supports sliding window verification with persistence rules and specialised prompts per objective type (intruder, vehicle, loiterer). For vehicle objectives, prompts prioritise first-frame vs. last-frame cumulative motion analysis, and a `vehicle_moving_positive_override` can override a "No" verdict when structured sections describe movement.

Optional camera shake stabilisation aligns frames using phase correlation and ORB/affine alignment before VLM verification.

## Models in Use

| Model | Parameters | Use Case | Notes |
|-------|-----------|----------|-------|
| Qwen3-VL-8B-Instruct | 8B | Primary AutoPatrol | Production default, FP8 quantised |
| Qwen2.5-VL-32B-Instruct-AWQ | 32B | High-accuracy assessment | AWQ quantised |
| Gemma-3-12B-IT-FP8 | 12B | Alternative eval | Under evaluation |
| GPT-4o-mini | -- | LLM-as-Judge baseline | API-based, not self-hosted |
| Claude Haiku | -- | LLM-as-Judge comparison | API-based, not self-hosted |

The [[qwen3vl-aws]] repo provides a simpler, non-Kubernetes alternative: a direct HTTP API on a dedicated EC2 g5.2xlarge instance, useful for development and low-latency synchronous calls.

## Deployment and Promotion

Deployment flows through ArgoCD via the `kubernetes-deployments` repo. Dev and prod are separate deployments controlled by `cluster-values.yaml`. Promoting a model to production means setting `enabled: true` on the prod instance block and merging the PR. The build script (`scripts/build-and-push.sh` in [[vlm-inference]]) handles SQS queue creation, DLQ setup, S3 lifecycle policies, HuggingFace token management, base image detection, Docker build, and ECR push.

## Evaluation

VLM performance is evaluated using:
- [[vlm-eval-visualizer]] -- Streamlit app for manual TP/FP labeling of VLM verdicts against production alerts
- [[ds-smart-alert-supervisor]] -- frame-level verification with heuristics + VLM
- The "VLM/LLM Evaluation Scorecard" Confluence page tracks multi-model comparison results

## Related Notes

- [[vlm-inference]] -- GPU worker implementation
- [[qwen3vl-aws]] -- standalone Qwen3 deployment
- [[ds-smart-alert-supervisor]] -- frame-level verification toolkit
- [[vlm-eval-visualizer]] -- VLM verdict review tool
- [[detection-pipeline]] -- the YOLO pipeline that generates alerts upstream
- [[model-lifecycle-end-to-end]] -- where VLMs fit in the broader model lifecycle
