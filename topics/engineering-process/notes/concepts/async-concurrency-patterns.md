---
title: "Async Concurrency Patterns for FastAPI"
type: concept
topic: engineering-process
tags: [async, asyncio, performance, fastapi, concurrency]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Async Concurrency Patterns for FastAPI

Patterns for handling CPU-bound and IO-bound work in async FastAPI endpoints without blocking the event loop. Extracted from the v5 inference API frame handler and inference pipeline.

## Problem: CPU Work in Async Handlers

FastAPI runs on an async event loop (uvicorn/Mangum). A single CPU-bound operation blocks all concurrent requests until it completes. PIL image validation takes 20-50ms per image — with 15 frames, that's 750ms of blocking.

## Pattern 1: `asyncio.to_thread` for CPU-Bound Work

Offload synchronous CPU work to the default thread pool executor:

```python
async def decode_frames(frames):
    # Queue each frame's PIL validation to run in a thread
    tasks = [
        asyncio.to_thread(_validate_image, raw, f"frame[{i}]")
        for i, raw in enumerate(decoded_frames)
    ]
    results = await asyncio.gather(*tasks)
```

**When to use:** PIL image operations, OpenCV frame processing, heavy serialization, any function that takes >5ms and doesn't need the event loop.

**Caveat:** Thread pool has a default size of `min(32, os.cpu_count() + 4)`. On Lambda with 1 vCPU, that's 5 threads. Don't queue hundreds of tasks.

## Pattern 2: `asyncio.gather` for Parallel IO

Run multiple IO-bound operations concurrently:

```python
# Download URLs and validate base64 frames at the same time
all_tasks = []
if b64_tasks:
    all_tasks.append(asyncio.gather(*b64_tasks))
if urls_to_download:
    all_tasks.append(download_images(urls_to_download))

gathered = await asyncio.gather(*all_tasks)
```

**When to use:** Multiple HTTP requests, parallel database queries, concurrent file reads. Any work that's waiting on IO, not computing.

## Pattern 3: Combining Both

A real implementation combines patterns 1 and 2:

1. Base64 decode happens synchronously (fast, <1ms per frame)
2. PIL validation is queued to `asyncio.to_thread` per frame (CPU-bound)
3. URL downloads use `aiohttp` session (IO-bound)
4. `asyncio.gather` runs all PIL threads + all URL downloads concurrently

Result: a 15-frame request with mixed base64 and URLs completes in ~max(single_PIL_time, single_download_time) instead of sum of all.

## Anti-Pattern: Synchronous Work in Async Loop

```python
# BAD: blocks the event loop for every frame
async def decode_frames(frames):
    for frame in frames:
        Image.open(BytesIO(frame))  # 50ms blocking per frame
```

```python
# GOOD: runs in parallel threads
async def decode_frames(frames):
    tasks = [asyncio.to_thread(validate_image, f) for f in frames]
    return await asyncio.gather(*tasks)
```

## Lambda-Specific Considerations

- Lambda has limited CPU (proportional to memory allocation — 1024MB ~ 0.6 vCPU)
- Thread pool parallelism is limited but still better than sequential blocking
- Network IO to model servers (200-3000ms) dominates total latency
- Optimize the pre-inference pipeline (validation, decoding) to minimize added latency before the network hop

## Reference Implementation

See [[v5-implementation-patterns]] in the inference-api topic for concrete file paths and code examples.
