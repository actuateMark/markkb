---
title: "actuate-inference-client"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, http-client, model-serving, async]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/filter-architecture.md
  - topics/actuate-libraries/notes/concepts/inference-client-evolution.md
  - topics/ai-models/notes/entities/intruder-v5-model.md
  - topics/ai-models/notes/entities/weapon-v8-model.md
  - topics/data-science/notes/concepts/detection-pipeline.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
  - topics/fleet-architecture/notes/concepts/inference-api-interaction.md
  - topics/team-structure/notes/entities/michael-aleksa.md
incoming_updated: 2026-05-01
---

# actuate-inference-client

HTTP client library for sending inference requests to YOLO model servers running inside Kubernetes. Provides both synchronous and asynchronous interfaces, with automatic model discovery via the multimodelz endpoint. Version **1.1.2**.

## Purpose

Abstracts the HTTP communication layer between the video processing pipeline and the GPU-backed inference servers. A connector creates one `MultimodelInferenceClient` (or its async variant), calls `update_multimodelz()` to discover available models, and then calls `model[name].infer(image, confidence)` to get back a list of `Detection` objects.

## Key Classes

- **`MultimodelInferenceClient`** / **`AsyncMultimodelInferenceClient`** -- top-level client. Accepts Kubernetes namespace, port, and service name. After calling `update_multimodelz()`, each discovered model is exposed both as an attribute and via the `model` dict.
- **`InferenceModelClient`** / **`AsyncInferenceModelClient`** -- per-model client. `infer(image, confidence)` resizes the image to the model's expected shape, POSTs JPEG bytes as multipart, parses the response into `Detection` objects, and reverses padding/scaling on bounding boxes.
- **`ModelUri`** -- abstract base class for constructing inference endpoint URLs (`/infer`, `/modelz`, `/multimodelz`).
- **`KubernetesModelUri`** -- concrete implementation that builds `http://{name}-svc.{namespace}.svc.cluster.local:{port}` URIs.

## Public API

```python
from actuate_inference_client import (
    MultimodelInferenceClient,
    AsyncMultimodelInferenceClient,
    ModelUri,
    KubernetesModelUri,
)
```

The `infer()` method returns `list[Detection]` with bounding boxes already de-padded and de-scaled to the original input image dimensions.

## Dependencies

- **Internal**: `actuate-inference-objects ~=1.1` (Detection, Image, InferenceModel)
- **External**: `httpx[http2] ~=0.27.2` (HTTP/2 support for lower-latency keepalive connections)

## Consumers

Used by `vms-connector` pipelines that need the newer HTTP-based inference path. Replaces the legacy `actuate-classic-inference-client` for new deployments.

## Notable Patterns

- Sync and async clients share the same URI and request logic; only the transport layer differs.
- The `multimodelz` endpoint returns all models served by a single Triton/TorchServe instance, allowing one client to manage multiple models.
- Uses `httpx` with HTTP/2 enabled by default for multiplexed requests over a single TCP connection.
- `KubernetesModelUri` uses FQDN (`svc.cluster.local`) by default for reliable DNS resolution across namespaces.
