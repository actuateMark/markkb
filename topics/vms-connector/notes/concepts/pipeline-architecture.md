---
title: "Pipeline Architecture"
type: concept
topic: vms-connector
tags: [connector, pipeline, chain-of-responsibility, inference, frame-processing]
created: 2026-04-13
updated: 2026-04-14
sources:
  - "[[worklog-rearch-main-loop]]"
  - "[[worklog-tech-doc-video-pipeline]]"
  - "[[worklog-puller-tier-list]]"
  - "[[worklog-frame-gap-buffering]]"
author: kb-bot
---

# Pipeline Architecture

The vms-connector processes video frames through a chain-of-responsibility pipeline defined in the `actuate-pipeline` library and invoked per-camera via `pipeline/image_pipeline.py`. Each camera thread runs its own pipeline instance, but all pipelines within a shard share a single [[inference-pool|AsyncInferencePool]] for HTTP inference calls.

## Pipeline Construction

`ImagePipeline` extends `PipelineRunner` (from `actuate_pipeline.core.pipeline_runner`) and builds the chain in `build_pipeline()`. It delegates to `PipelineFactory` (from `actuate_pipeline.core.pipeline_factory`), which assembles a linked list of step objects. The factory receives the connector config, per-camera config, yolo client, DAO manager, image cache, and a reference back to the pipeline runner itself. Steps are linked last-to-first so that each step's `next_step` pointer forms a forward chain: the first step returned by the factory is the head of the pipeline.

```python
# pipeline/image_pipeline.py
class ImagePipeline(PipelineRunner):
    def build_pipeline(self):
        pipeline_factory = PipelineFactory()
        self.first_step = pipeline_factory.build_pipeline(
            self.config, self.camera_config, self.yolo_client,
            self.dao_manager, self.image_cache, self
        )
        del pipeline_factory
```

The pipeline runner is built during factory creation (pre-fork). In sharded deployments, the `ChunkedSiteManager` forks after construction, so the pipeline objects are copied into child processes. Threads started during step `__init__` do not survive the fork -- they must be started post-fork in `AnalyticsSiteManager.run()`.

## Three-Phase Processing

Every frame passes through three phases, all implemented as stateless steps that mutate an `ImageDataPacket` object:

1. **Pre-processing** -- Camera metadata capture, frame resizing via `cv2`, downsampling to the configured FPS, motion detection filtering, and any integration-specific transforms. These steps can set `abort=True` on the packet to skip inference (e.g., when motion detection says the scene is static).

2. **Processing** -- The YOLO inference call itself. The `YoloProcessingStep` submits the frame to the inference server (via `actuate_classic_inference_client.YoloClient`). In production, the YoloClient delegates HTTP calls to the shard's shared `AsyncInferencePool`, which consolidates all inference requests onto a single asyncio event loop to avoid GIL convoy effects.

3. **Post-processing** -- Detection filtering (ignore zones, stationary object suppression, IOU deduplication, confidence thresholding), label remapping, sliding window logic (threshold counting over time), observer notification (loitering, line crossing, blacklist), and frame cleanup scheduling.

## Frame Flow Through the Camera

The camera's `pull()` method (`camera/shared/base_stream_camera.py`) runs a tight loop alternating between `get_frame()` and `get_result()`:

- **`get_frame()`** pulls the next decoded frame from the puller's frame buffer queue, stamps it with `approx_capture_timestamp`, stores it in the `TTLImageCache`, wraps it in an `ImageDataPacket`, and submits it to the pipeline's `first_step`.
- **`get_result()`** reads from the result buffer queue (populated by the pipeline's final step calling back into the camera). It calls `finish_pipeline(result)` to merge product state from the previous frame, then `send_alerts(result)` to dispatch any triggered alarms, and finally `notify(result)` to update observers.

The puller runs in its own thread (`_pl` suffix), decoding the RTSP/HTTP stream at the inbound FPS (often 15-30 FPS). Motion detection runs at full inbound rate. Downsampling to the configured analytics FPS (typically 1-3 FPS) happens in a pre-processing step before inference.

## Stateless Design

No step stores mutable state between frames. All inter-frame state lives on the `ImageDataPacket` and its nested `ProductDataPacket` / `WindowDataPacket` objects, which are carried forward by the camera's `last_data` reference. This means steps can be reordered or conditionally skipped without side effects, and the pipeline factory can compose different step chains for different product configurations.

## Core Abstractions (actuate-pipeline)

The pipeline is built on three base abstractions from `actuate-pipeline`:

- **BaseStep**: Abstract base class that all pipeline steps inherit from. Defines the interface for running, processing data, and ending a step. Steps are stateless -- they mutate the packet but hold no inter-frame state.
- **BaseLink**: Abstract base class for links between steps. Handles ending the previous step and starting the next, forming the forward chain. Steps are linked last-to-first during factory construction so each step's `next_step` pointer forms the chain.
- **ImageDataPacket**: The data envelope passed between steps. Accumulates results from every stage, giving downstream steps access to all upstream outputs. Contains nested `ProductDataPacket` and `WindowDataPacket` objects for inter-frame state.

## Window Steps

Window steps manage the temporal dimension of analytics:

- **Save Window Step**: Saves a window of frames for batch analysis of a frame sequence as a whole.
- **Sliding Window Step**: Moves a rolling window along the video sequence one frame at a time, used for threshold counting (e.g., N detections in M seconds).

## Boot Sequence

The pipeline is reached through a six-file critical path:

1. **connector.py** -- Bootstrap: loads settings, initialises dependencies.
2. **factory.py** -- Reads `integration_type`, builds the appropriate connector (see [[connector-factory]]).
3. **site_manager.py** -- Runs the site; connector type determines camera start strategy. Manages site-level metrics.
4. **Camera class** (e.g., `base_stream_camera.py`) -- Per-camera logic: frame receipt, alert dispatch, observer notification.
5. **puller.py** -- Stream interface: connection management, frame pulling, downsampling/resizing.
6. **image_pipeline.py** -- Pipeline execution through the three-phase chain.

## Puller Types

The connector supports 9+ puller types, each tailored to a different camera connection strategy:

| Puller | Mechanism | Use Case |
|--------|-----------|----------|
| URL Puller | RTSP/HTTP stream via OpenCV | Standard continuous video |
| URL Puller Motion | SQS motion pings / socket pings | Motion-triggered frame pull |
| Milestone Puller | Proprietary socket protocol (no OpenCV) | Milestone VMS |
| Socket Puller | Generic socket-based | Integration-specific |
| JPG Puller | JPEG snapshot polling | Snapshot cameras |
| S3 Puller | S3 bucket reads | Batch/gauntlet processing |
| SQS Puller | SQS message-driven | Cloud event-driven |
| Queue Puller | Internal queue | Inter-process communication |
| Buffer Puller | Buffered variant | Integration-specific |

## Timestamp Gap Buffering

The puller implements a timestamp smoothing algorithm to handle network jitter, camera clock drift, and reconnection gaps:

- **Small gaps (< 1 second)**: Advance timestamp by exactly `native_fps_gap` from the previous frame, smoothing minor jitter.
- **Sub-gap (< native_fps_gap)**: Bump to exactly `native_fps_gap` ahead, preventing timeline compression.
- **Large gaps (> 1 second)**: Reset to approximately 1 second behind wall-clock time, re-anchoring after reconnection without a sudden forward jump.

This trades strict timestamp accuracy for temporal consistency, which is the correct trade-off for analytics where consistent inter-frame intervals matter more than absolute time precision.

## Memory Management Integration

A `CleanupStep` at the end of post-processing marks frames for deletion by populating `result.frames_to_delete`. The camera's `finish_pipeline()` collects these into `_pending_frame_deletions`, and `_delete_pending_frames()` runs after alert sending and observer notification are complete. This event-based deletion is the primary mechanism; a time-based fallback thread handles frames that slip through (e.g., after pipeline crashes).
