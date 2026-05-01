---
title: "vlm-inference"
type: entity
topic: ai-models
tags: [repo, vlm, vllm, inference, sqs, dynamodb, kubernetes, docker, gpu, autopatrol]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-vlm.md
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/ai-models/notes/concepts/vlm-pipeline-architecture.md
  - topics/ai-models/notes/entities/ds-smart-alert-supervisor.md
  - topics/ai-models/notes/entities/qwen3vl-aws.md
  - topics/ai-models/notes/entities/vlm-eval-visualizer.md
  - topics/ai-models/notes/syntheses/yolo-vs-vlm-detection-future.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
  - topics/settings-automation/notes/concepts/vlm-fp-reduction.md
  - topics/team-structure/notes/entities/clarissa-herman.md
incoming_updated: 2026-05-01
---

# vlm-inference

Lightweight Docker container that runs Vision-Language Models (VLMs) via vLLM, polling SQS FIFO queues for requests and writing results to DynamoDB. This is the GPU worker half of the VLM inference pipeline -- the client side lives in [[actuate-vlm]].

**Repo:** `aegissystems/vlm-inference` (private, updated 2026-04-10)

## Architecture

The worker follows a queue-driven, KEDA-scaled pattern:

```
SQS FIFO Queue -> KEDA ScaledObject -> K8s Deployment -> Worker Pod
                                                             |
                                                     [vLLM + Worker]
                                                             |
                                        DynamoDB (results) + Webhook (optional)
```

Each model gets its own SQS queue, Docker image tag, and Kubernetes deployment. KEDA scales replicas from zero based on queue depth.

## Model Support

Any HuggingFace model supported by vLLM can be deployed. The build script auto-detects the correct vLLM base image by reading the model's `config.json` from HuggingFace and checking for a specialised vLLM Docker image (`vllm/vllm-openai:{model_type}-cu130`). Models currently used include Qwen3-VL-8B-Instruct and Gemma 4.

Model naming uses two identifiers: the HF model ID (e.g., `Qwen/Qwen3-VL-8B-Instruct`) for downloads and vLLM, and a derived slug (e.g., `qwen3-vl-8b-instruct`) for Docker tags, SQS queues, DynamoDB fields, and caller references.

## Build and Deploy

A single build script (`scripts/build-and-push.sh`) handles everything: ensures SQS queues and DLQs exist, sets S3 lifecycle policies, fetches the HF token from Secrets Manager (passed as a BuildKit secret), auto-detects the base image, builds the Docker image, and optionally pushes to ECR. Deployment goes through [[argocd|ArgoCD]] via the [[kubernetes-deployments]] repo -- manifests are never applied directly.

Dev and prod are separate deployments controlled by `cluster-values.yaml` in `kubernetes-deployments`. Promoting to prod means setting `enabled: true` on the prod instance block and merging the PR.

## Queue and Stage Routing

Both worker and caller default to `STAGE=dev` to prevent accidental production writes. In Kubernetes, `STAGE` flows from `cluster-values.yaml` through Helm templates. Dev traffic goes to `vlm-{model}-dev.fifo`; prod to `vlm-{model}.fifo`.

## Caller

A Python caller (`scripts/caller.py`) wraps `submit_vlm_request()` for sending jobs. It accepts local files, S3 URIs, HTTP URLs, or data URIs as image/video inputs, auto-uploading local files to S3 with content-hash deduplication. Results can be retrieved by polling DynamoDB, direct lookup, or webhook callback.

## GPU Tuning

For 8B models on 24 GB VRAM instances (g5/g6), recommended settings are `GPU_MEMORY_UTIL=0.95`, `ENFORCE_EAGER=true`, and `MAX_MODEL_LEN=8192`. OOM mitigation involves lowering `MAX_NUM_SEQS` or `MAX_MODEL_LEN`.

## Dependencies

Minimal runtime: `vllm` (base image), `boto3`, `requests`. Private packages `actuate-sqs` and `actuate-queue-consumer` are pulled from CodeArtifact.
