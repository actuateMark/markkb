---
title: "Connector Evolution"
type: synthesis
topic: vms-connector
tags: [synthesis, cross-topic, architecture, pipeline, sharding, inference, multiprocessing, history, vms-connector]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/offboarding/notes/concepts/2026-06-23_local-repo-audit.md
incoming_updated: 2026-06-24
---

# Connector Evolution

The [[vms-connector]] has evolved from a single-process Python CLI that pulled [[rtsp-deep-dive|RTSP]] frames and ran inference inline to a multi-process, sharded pipeline with async inference, 41 shared libraries, AIMD congestion control, and 19+ VMS integrations. This synthesis traces that evolution, explains the architectural forces that drove each transition, and addresses the coexistence of legacy and modern components in the current codebase.

## Origin: The Monolithic Connector

The original connector was a straightforward Python application. A single process connected to a VMS, pulled frames, ran object detection, and sent alerts. The codebase was a single repository with inline logic -- frame decoding, inference calls, filtering, and alert dispatch all lived in the same files. Configuration was simpler, integrations were fewer, and the pipeline concept did not yet exist.

This architecture worked for small deployments but hit fundamental limits as the platform grew: more cameras per site meant more threads competing for the GIL, more VMS types meant more conditional branching in the frame acquisition code, and more detection products meant more post-processing logic tangled into a monolith.

## The Rearchitecture: Pipeline and Libraries

The rearchitecture (which gives the production branch its name, `rearchitecture`) introduced three structural changes that still define the system.

**First: the chain-of-responsibility pipeline.** The [[pipeline-architecture]] decomposed frame processing into stateless steps linked in a forward chain. `BaseStep`, `BaseLink`, and `ImageDataPacket` (defined in the [[actuate-pipeline]] library) form the abstraction layer. Each step mutates the packet but holds no inter-frame state -- all temporal state lives on `ProductDataPacket` and `WindowDataPacket` objects carried forward by the camera's `last_data` reference. The three-phase design (pre-processing, processing, post-processing) with window steps (Save Window, Sliding Window) for temporal analysis emerged from the [[worklog-tech-doc-video-pipeline|Video Pipeline Design Document]], which formalized the abstractions that still underpin the codebase.

**Second: the library extraction.** Logic was pulled out of the monolith into 41 packages in a UV workspace monorepo ([[actuate-libraries]]), published to AWS CodeArtifact. The [[library-connector-dependency-map]] documents the result: at least 30 of the 41 libraries are direct or transitive dependencies of the connector. The critical path from frame to alert traverses 12 libraries minimum: `actuate-config` -> `actuate-pullers` -> `actuate-movement` -> `actuate-pipeline` -> `actuate-classic-inference-client` -> `actuate-filters` -> `actuate-connector-observers` -> `actuate-alarm-senders` -> `actuate-daos`. This extraction enabled independent versioning and testing but introduced a deep [[dependency-graph|dependency graph]] where a breaking change in a core library (especially [[actuate-config]], [[actuate-inference-objects]], or [[actuate-connector-observers]]) cascades through 7+ dependents.

**Third: the factory pattern.** The [[connector-factory]] replaced conditional integration branching with a dispatch hub (`generate_site()`) that reads `integration_type` from settings and lazy-imports the matching factory class. Each of the 19+ integration types gets a dedicated factory under `connector_factories/<integration>/`. `BaseConnectorFactory` provides the common initialization surface (DAO creation, observer construction, motion listener setup). Subclasses are minimal -- typically just parsing settings into a typed config and constructing integration-specific camera objects. This makes adding a new VMS integration a matter of writing a new factory and camera class rather than modifying shared code.

## The Sharding Layer

As sites grew beyond 20-30 cameras, GIL contention became the dominant performance problem. Multiple camera threads making synchronous `requests.post()` calls serialized around the GIL during DNS resolution and connection setup, creating a convoy effect that collapsed throughput.

[[sharding|Camera sharding]] via `ChunkedSiteManager` addressed this by forking the connector into multiple OS processes. Round-robin distribution (not sequential slicing) balances camera load across shards. The fork boundary is carefully managed: all camera objects, pipelines, and configs are built in the parent process before forking, but threads started during `__init__` do not survive `fork()`. The `AnalyticsSiteManager.run()` method explicitly restarts threads post-fork -- the [[inference-pool|AsyncInferencePool]], `upload_slices` threads, observer pool, GC collection, and async logging all reinitialize in the child.

Fork safety constraints pervade the codebase: no threads in `__init__`, signal handlers registered post-fork (the `if not self.in_shard` guard), jemalloc background thread re-enabled via `mallctl` after fork, and `QueueListener` rebuilt in each child process. These constraints are documented in the project's CLAUDE.md and represent hard-won lessons from production crashes.

The empirical cost of [[sharding]] is severe: crossing a shard boundary incurs at least 50-80% CPU increase. The [[worklog-sharding-strategy|Sharding Strategy]] source documents the finding that keeping even one additional camera on a single process saves 0.5-2 CPU -- enough to offset increases across 10 other sites. This drove the default shard size up to 24 cameras, and the proposed (but not yet implemented) dynamic [[sharding]] strategy that would log per-site performance to DynamoDB and adjust shard sizes based on observed utilization.

## The Async Inference Revolution

The [[inference-pool|AsyncInferencePool]] was the next major evolution. Rather than each camera thread making blocking `requests.post()` calls (which held the GIL), a single daemon thread runs an `asyncio` event loop with `httpx.AsyncClient`. Camera threads call `pool.post()`, which submits a coroutine via `asyncio.run_coroutine_threadsafe()` and blocks on `future.result()` -- releasing the GIL so other camera threads can execute.

The AIMD (Additive Increase, Multiplicative Decrease) congestion control -- starting at 48 concurrent requests, floor of 8, target 200ms latency, 0.75 decrease factor -- protects the inference server from overload. Three-component timing instrumentation (queue_ms, network_ms, gil_reacquire_ms) makes it straightforward to diagnose whether slowness comes from server saturation, local congestion, or GIL contention. The pool self-heals: if the event loop thread dies, the next `post()` call detects `not self._thread.is_alive()` and recreates the entire pool under a lock.

## Classic vs Modern Inference Clients

The coexistence of `actuate-classic-inference-client` (legacy, wrapping `requests.post()` via `YoloClient`) and `actuate-inference-client` (modern, httpx-based, sync+async) reflects the incremental migration strategy. `YoloClient` checks for an `inference_pool` attribute; if present, it routes through the AsyncInferencePool instead of making direct HTTP calls. This makes the pool opt-in and backward-compatible -- local development without the pool falls back to synchronous requests. Both clients share `actuate-inference-objects` (`Detection`, `BoundingBox`, `DetectionTag`) as the canonical type system.

The classic client persists because it is deeply integrated into 30+ downstream consumers, and replacing it requires validating that every code path that touches `YoloClient` works identically with the modern client. The pragmatic approach has been to layer the pool on top of the classic client rather than replace it wholesale.

## The VLM Layer

The newest evolution is the [[vlm-integration|VLM integration]] via [[actuate-vlm]]. This is architecturally distinct from YOLO inference: fully asynchronous (SQS FIFO queue -> [[vlm-inference]] GPU worker -> DynamoDB result), scale-to-zero via KEDA, and running on g5.2xlarge GPU instances rather than Inferentia2. The [[actuate-vlm]] client normalizes media to presigned S3 URLs, verifies queue existence once per client lifetime, and routes by stage (dev vs prod queues). VLM results are consumed by observer pipelines for scene description, anomaly explanation, and false positive filtering.

This layer exists entirely outside the synchronous pipeline -- it does not add latency to the frame processing path. Instead, it operates on confirmed detection events, adding a second-pass verification that can suppress or confirm alerts before they reach operators. The integration point is the observer layer, where VLM verdicts modify alert routing rather than frame processing.

## Optimization Research: Open Frontiers

The [[worklog-optimization-research|optimization research]] source catalogs vectors that remain open as of April 2026:

- **Alternative video decoders**: [[gstreamer-entity|GStreamer]] and [[ffmpeg-entity|FFmpeg]] puller variants to compare performance against [[opencv-entity|OpenCV]] and isolate a memory leak in the existing puller. Not yet implemented.
- **Rust acceleration**: Rewriting high-bottleneck NumPy-adjacent operations in Rust, particularly for compute-intensive filtering. Remains research-only.
- **[[adaptive-temperature|Adaptive temperature]]**: A [[adaptive-temperature]] concept proposing per-camera dynamic FPS adjustment based on recent detection activity -- "heat up" processing rate during active events, "cool down" during inactivity. Proposed but not implemented.
- **Kubernetes health endpoints**: `healthz` endpoint for reliable pod health reporting, enabling Karpenter spot-node scheduling for cost savings. Partially implemented.
- **Profiling infrastructure**: pyspy (CPU) and memray (memory) sidecar deployment on dev clusters for safe profiling of problem sites. Adopted.

## Architectural Summary

The connector's evolution follows a pattern of **layered isolation in response to scaling bottlenecks**:

1. **Monolith** -> **Pipeline + Libraries** (isolate concerns, enable independent testing)
2. **Single process** -> **Sharded multi-process** (isolate GIL contention across camera groups)
3. **Synchronous inference** -> **Async [[inference-pool|inference pool]]** (isolate HTTP I/O from GIL convoy effects)
4. **YOLO-only** -> **YOLO + async VLM** (isolate expensive verification from real-time processing)

Each layer added complexity (fork-safety constraints, AIMD tuning, SQS/DynamoDB polling) but solved a specific bottleneck that the previous architecture could not address. The result is a system that processes video at scale across 19+ VMS types, but carries the accumulated weight of its evolutionary history in the form of dual inference clients, fork-safety disciplines, and a 30+ library [[dependency-graph|dependency graph]]. Understanding this evolution is essential for anyone working on the connector -- the constraints are not arbitrary; they are the residue of production-validated decisions.
