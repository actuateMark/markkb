---
type: concept
topic: actuate-libraries
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
incoming:
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
incoming_updated: 2026-05-01
---

# Inference Client Evolution

The Actuate platform has gone through three generations of inference client design, each reflecting a shift in infrastructure and architectural thinking. Understanding this evolution explains why two YOLO clients coexist in the monorepo today and where [[actuate-vlm]] fits as the newest pattern.

## Generation 1: actuate-classic-inference-client (TCP Sockets, DNS Discovery)

[[actuate-classic-inference-client]] (v2.2.4) is the original inference integration. Its `YoloClient` class is a monolithic component that handles image resizing, center-padding, JPEG encoding (with optional TurboJPEG acceleration for 2-3x speedup), DNS-based server discovery, TCP socket communication, connection pooling across multiple model servers, and result parsing -- all within a single class hierarchy.

Server discovery works through `dnspython`: the client resolves the model service hostname via DNS, caches the results with a TTL, and distributes inference requests across the resolved endpoints. Each endpoint is managed as a `YoloEndpoint` with its own TCP connection. The `call_yolo()` method signature has accumulated 14+ parameters over time, including slicing parameters, confidence thresholds, model names, and image dimensions.

The client is tightly coupled to [[actuate-config]] (`CustomerConfig`) and [[actuate-daos]] (`DaoManager`), making it difficult to test in isolation or reuse outside the connector context. Its dependency on raw TCP sockets also means it cannot take advantage of HTTP/2 multiplexing or standard load balancing.

## Why the Migration Happened

Several factors drove the move away from the classic client:

**Infrastructure shift to Kubernetes.** When model servers moved to Kubernetes, DNS-based discovery became unnecessary -- Kubernetes provides built-in service discovery via DNS with stable `svc.cluster.local` hostnames. The TCP socket approach also conflicted with Kubernetes networking patterns that prefer HTTP-based health checks and load balancing.

**Multimodel serving.** Modern model servers (Triton, TorchServe) serve multiple models from a single process. The classic client's one-model-per-endpoint assumption did not fit this architecture. A multimodel client that discovers all available models from a single endpoint was needed.

**Maintainability.** The monolithic `YoloClient` class was hard to extend and test. Separating concerns (URI construction, HTTP transport, model discovery, result parsing) into distinct classes made each piece independently testable.

**Performance.** HTTP/2 multiplexing over a single TCP connection outperforms the classic client's pool of individual TCP sockets for typical inference workloads, especially when sending multiple concurrent requests to the same server.

## Generation 2: actuate-inference-client (httpx, Kubernetes-native)

[[actuate-inference-client]] (v1.1.2) is the modern replacement. It uses `httpx` with HTTP/2 enabled by default and is structured around clean separation of concerns:

- **`ModelUri` / `KubernetesModelUri`** -- abstract URI construction. `KubernetesModelUri` builds `http://{name}-svc.{namespace}.svc.cluster.local:{port}` URIs using Kubernetes FQDN conventions, eliminating the need for DNS discovery logic.
- **`MultimodelInferenceClient` / `AsyncMultimodelInferenceClient`** -- top-level clients that call the `multimodelz` endpoint to discover all models served by a single server instance. Each discovered model is exposed as an `InferenceModelClient`.
- **`InferenceModelClient` / `AsyncInferenceModelClient`** -- per-model clients that handle `infer(image, confidence)`. They resize the image to the model's expected input shape, POST JPEG bytes as multipart, parse the response into `Detection` objects from [[actuate-inference-objects]], and reverse any padding/scaling on bounding boxes.

The new client depends only on [[actuate-inference-objects]] (for the `Detection`, `Image`, and `InferenceModel` types) and `httpx`. It has no dependency on [[actuate-config]] or [[actuate-daos]], making it lightweight and independently testable.

Sync and async variants share the same URI and request logic; only the transport layer differs. This means the connector can use the sync client in its current threading model and migrate to async later without changing the inference logic.

## Complementary Library: actuate-inference-slicing

[[actuate-inference-slicing]] (v1.0.1) provides SAHI-style sliced inference for high-resolution images. The classic client had slicing logic built into its monolithic `call_yolo()` method. In the new architecture, slicing is a separate composable library that wraps any `InferenceModelClient` -- it divides the image into overlapping tiles, runs inference on each via the client, and merges results using a union-merge post-processor. This separation means slicing can be tested and improved independently of the HTTP transport layer.

## Generation 3: actuate-vlm (SQS + DynamoDB Polling)

[[actuate-vlm]] (v0.3.2) represents a fundamentally different pattern for inference clients. Vision Language Model inference is too slow for synchronous HTTP within the video pipeline, so [[actuate-vlm]] decouples request from response:

1. The `VLMClient.submit()` method sends a request to an SQS FIFO queue and writes a PENDING record to DynamoDB.
2. A GPU worker picks up the message, runs inference against a vLLM server, and writes the result back to DynamoDB.
3. The client calls `poll()` to check DynamoDB until the result appears.

Media handling normalizes all image references to presigned S3 URLs (downloading HTTP URLs, re-uploading local files) before sending to SQS. Model names are auto-normalized from HuggingFace IDs (e.g., `Qwen/Qwen3-VL-8B-Instruct` becomes `qwen3-vl-8b-instruct`).

This async-via-queue pattern could become the template for future inference clients that handle models too slow for synchronous HTTP, such as large language models or video analysis models. Its dependency footprint is minimal: only [[actuate-sqs]] internally, plus boto3, requests, and Pillow externally.

## Current State and Coexistence

Both [[actuate-classic-inference-client]] and [[actuate-inference-client]] are actively used in production. Existing `vms-connector` deployments that have not migrated continue using the classic client. New deployments and the rearchitecture branch use the new client. The migration path is straightforward because both clients ultimately produce `list[Detection]` output, but the operational change (TCP sockets to HTTP, DNS discovery to Kubernetes service names) requires per-deployment validation.

The three clients coexist because they serve different inference modalities: [[actuate-inference-client]] for real-time YOLO object detection, [[actuate-classic-inference-client]] as the legacy path for the same, and [[actuate-vlm]] for asynchronous VLM queries. Each reflects the infrastructure and performance constraints of its era.
