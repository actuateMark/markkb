---
title: "Source: GStreamer, FFmpeg, Profiling, and Optimization Research"
type: source
topic: vms-connector
tags: [worklog, optimization, gstreamer, ffmpeg, profiling, pyspy, memray, rust, healthz]
ingested: 2026-04-14
author: kb-bot
---

# GStreamer, FFmpeg, Profiling, and Optimization Research

**Origin:** `/home/mork/Documents/worklog/worklog/optimization research.md`

A research scratchpad covering multiple optimisation vectors: alternative video decoders, profiling tools, Rust acceleration, Kubernetes health endpoints, and spot-node cost savings.

## Video Decoder Alternatives

The note contains a GStreamer debug pipeline command for testing RTSP pull via `gst-launch-1.0`, and mentions a plan to create two `UrlPuller` subclasses -- one using FFmpeg and one using GStreamer -- to compare performance and isolate a memory leak in the existing puller. A lightweight OpenCV build guide (for Raspberry Pi) is also referenced.

## Profiling Strategy

- **CPU profiling**: `pyspy` recommended over `cProfile` because `cProfile` cannot profile native (C/Rust) code.
- **Memory profiling**: `memray` recommended for tracking memory issues.
- **Deployment**: Run a sidecar process on Kubernetes (dev only) that watches for `pyspy` artifacts and uploads them to S3. Use an environment variable to toggle the profiler sidecar.
- **Shadow deployments**: Disable alarm sending and run shadow deployments of problem sites for safe profiling.

## Rust Acceleration (Toolbox)

Explores the idea of rewriting high-bottleneck Python code in Rust, particularly NumPy-adjacent operations. Also suggests using an async executor for blocking I/O-bound calls.

## Kubernetes Health Endpoints

- Design a `healthz` endpoint and status endpoint for the connector.
- Ensure graceful handoff during rescheduling: the new pod must be healthy before the old pod shuts down.
- Once `healthz` is reliable, enable Karpenter with spot nodes for cost savings.

## Significance

This note catalogs several optimisation research threads. The pyspy/memray profiling approach has been adopted. The GStreamer/FFmpeg puller alternatives and Rust acceleration remain open research items. The healthz concept has been partially implemented.
