---
title: "actuate-classic-inference-client"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, legacy, deprecated, yolo]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/filter-architecture.md
  - topics/actuate-libraries/notes/concepts/inference-client-evolution.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
  - topics/vms-connector/notes/syntheses/performance-optimization-landscape.md
incoming_updated: 2026-05-01
---

# actuate-classic-inference-client

Legacy YOLO inference client that communicates with model servers over raw TCP sockets and HTTP. Slated for deprecation in favour of `actuate-inference-client`. Version **2.2.4**.

## Purpose

Provides the original inference integration used by `vms-connector` before the HTTP/multimodel architecture was introduced. The `YoloClient` handles image resizing, center-padding, JPEG encoding (with optional TurboJPEG acceleration), server discovery via DNS, TCP socket communication, and result parsing -- all in a single monolithic class.

## Key Classes

- **`BaseYoloClient`** -- abstract base class defining the `call_yolo()` contract. Accepts frame bytes, slicing parameters, confidence threshold, model name, and image dimensions.
- **`YoloClient`** -- the production implementation. Manages a pool of `YoloEndpoint` connections, performs DNS-based server discovery with TTL caching, handles request routing across multiple model servers, and parses padded/unpadded inference responses.
- **`MockYoloClient`** / **`SlowStartingYoloClient`** -- test doubles for unit testing without a live inference server.
- **`LocalYoloClient`** -- variant for local development that connects to a model server running on localhost.
- **`YoloServer`** / **`YoloEndpoint`** -- lower-level connection management for individual inference endpoints.

## Public API

```python
from actuate_classic_inference_client import (
    BaseYoloClient,
    YoloClient,
    MockYoloClient,
    SlowStartingYoloClient,
    LocalYoloClient,
)
```

The `call_yolo()` method is the primary entry point, returning raw detection results.

## Dependencies

- **Internal**: `actuate-config` (CustomerConfig), `actuate-daos` (DaoManager), `actuate-threadpool`
- **External**: `dnspython >=2.6.1`, `PyTurboJPEG >=1.7.0`, `requests`, `cachetools`, `opencv-python`, `numpy`

## Consumers

Still used by existing `vms-connector` deployments that have not migrated to the new inference client. The slicing, ensemble, and multi-model routing logic in this client is being replaced by the combination of `actuate-inference-client` + `actuate-inference-slicing`.

## Notable Patterns

- TurboJPEG is used opportunistically (2-3x faster JPEG encoding) with graceful fallback to [[opencv-entity|OpenCV]].
- DNS-based server discovery with `dnspython` resolves model service endpoints, caching results in a TTL cache.
- Heavy coupling to `actuate-config` and `actuate-daos` makes this client harder to test and reuse compared to the newer client.
- The `call_yolo()` signature accepts many parameters (14+), reflecting accumulated feature flags over time.
