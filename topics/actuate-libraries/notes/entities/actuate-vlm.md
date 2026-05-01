---
title: "actuate-vlm"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, vlm, vision-language-model, sqs, dynamodb, async-polling]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-vlm

Client library for submitting Vision-Language Model (VLM) inference requests via AWS SQS FIFO queues and polling DynamoDB for results. Drop-in replacement for direct HTTP calls to a vLLM inference server. Version **0.3.2**.

## Purpose

[[vlm-inference|VLM inference]] is too slow and resource-intensive for synchronous HTTP within the video processing pipeline. This library decouples the request from the response: the client sends a message to an SQS FIFO queue, a GPU worker picks it up, runs inference against a vLLM server, and writes the result to DynamoDB. The client polls DynamoDB until the result appears.

## Key Classes and Functions

- **`VLMClient`** -- the primary class. Configurable with AWS region, stage (dev/prod), DynamoDB table, and S3 bucket. Provides:
  - `submit(model, prompt, *, images, video, max_tokens, temperature, extra_params, callback_url)` -- sends the request to SQS, writes a PENDING record to DynamoDB, returns a `request_id` UUID.
  - `poll(request_id, *, timeout, interval)` -- polls DynamoDB until status is COMPLETE or FAILED.
  - `run(model, prompt, **kwargs)` -- convenience method combining submit + poll.
- **`ModelNotDeployed`** -- exception raised when the target SQS queue does not exist, with setup instructions.
- **`submit_vlm_request()`** / **`poll_for_result()`** -- legacy module-level functions that delegate to a lazily-initialized default `VLMClient` instance.

## Public API

```python
from actuate_vlm import VLMClient, ModelNotDeployed, submit_vlm_request, poll_for_result
```

## Media Handling

The client normalises all media references to presigned S3 URLs before sending to SQS:
- HTTP/HTTPS URLs are downloaded, resized to max 1920x1080, and re-uploaded to S3.
- S3 URIs (`s3://bucket/key`) are presigned directly.
- Local files are resized and uploaded to S3.
- `data:` URIs are passed through unchanged.
Content-hash-based S3 keys prevent duplicate uploads of the same image.

## Dependencies

- **Internal**: `actuate-sqs` (QueueSender for FIFO queue publishing)
- **External**: `boto3 >=1.35.23`, `requests >=2.28`, `Pillow >=10.0`

## Consumers

Used by `vms-connector` observer pipelines that need scene description, anomaly explanation, or visual question answering from deployed VLM models (e.g., Qwen3-VL-8B-Instruct).

## Notable Patterns

- Model names are auto-normalised from HuggingFace IDs (e.g., `Qwen/Qwen3-VL-8B-Instruct` becomes `qwen3-vl-8b-instruct`).
- Queue existence is verified once per client lifetime and cached in `_verified_queues`.
- Stage-based routing: `prod` sends to `vlm-{model}.fifo`, `dev` sends to `vlm-{model}-dev.fifo`.
- Supports optional webhook callbacks (`callback_url`) for event-driven architectures.
