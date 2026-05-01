---
title: "qwen3vl-aws"
type: entity
topic: ai-models
tags: [repo, vlm, qwen, vllm, ec2, api, vision-language-model, inference]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/ai-models/notes/concepts/vlm-pipeline-architecture.md
  - topics/team-structure/notes/entities/alena-prashkovich.md
  - topics/team-structure/notes/entities/carlos-torres.md
  - topics/team-structure/notes/entities/clarissa-herman.md
incoming_updated: 2026-05-01
---

# qwen3vl-aws

Standalone deployment of Qwen3-VL-8B-Instruct-FP8 on an AWS EC2 `g5.2xlarge` instance, exposed as an OpenAI-compatible API endpoint. This is a simpler, non-Kubernetes alternative to the queue-based [[vlm-inference]] pipeline.

**Repo:** `aegissystems/qwen3vl-aws` (private, updated 2026-03-19)

## Purpose

Provides a direct HTTP API for [[vlm-inference|VLM inference]] without the SQS/DynamoDB queue machinery. Useful for interactive or low-latency use cases where callers want synchronous responses rather than the asynchronous poll-based pattern of `vlm-inference`.

## API Details

| Property | Value |
|----------|-------|
| **Endpoint** | `https://qwen3-api.internal.actuateui.net/v1` |
| **Model** | `Qwen/Qwen3-VL-8B-Instruct-FP8` |
| **Auth** | `x-api-key` header |
| **Max images** | 5 per request |
| **Max context** | 32,768 tokens |
| **Format** | OpenAI-compatible (`/v1/chat/completions`) |

The model runs quantised to FP8 for reduced VRAM usage on the 24 GB A10G GPU.

## Python Client

The repo ships an installable Python package (`qwen_client`) with a convenience function:

```python
from qwen_client import qwen3vl_fp8

# Text only
qwen3vl_fp8("What is the capital of France?")

# Single or multiple images
qwen3vl_fp8("Describe this", images=["photo.jpg"])
qwen3vl_fp8("Compare these", images=["a.jpg", "b.jpg"])
```

Install via pip from the private repo: `pip install git+ssh://git@github.com/aegissystems/qwen3vl-aws.git`

Configuration is via `.env` file with `QWEN_ENDPOINT`, `QWEN_API_KEY`, and `QWEN_MODEL`. API keys are managed by admins (see `ADMIN.md` in the repo).

## Infrastructure

Runs on a single EC2 `g5.2xlarge` instance (24 GB A10G GPU) with vLLM serving the model. This is a persistent, always-on deployment rather than a scale-to-zero pattern, making it suitable for development, experimentation, and workloads that need immediate response times.

## Relationship to vlm-inference

This repo predates the Kubernetes-based [[vlm-inference]] pipeline and serves a different access pattern. `vlm-inference` is asynchronous (SQS queue + DynamoDB results) with KEDA autoscaling, while `qwen3vl-aws` is synchronous HTTP on a dedicated EC2 instance. Both can serve Qwen3-VL-8B, but the queue-based system is preferred for production Autopatrol workloads due to its scaling and reliability properties.

## Related

- [[vlm-inference]] -- queue-based [[vlm-inference|VLM inference]] workers (production path)
- [[actuate-vlm]] -- client library for the queue-based pipeline
- [[ds-smart-alert-supervisor]] -- uses [[vlm-inference|VLM inference]] for alert verification
