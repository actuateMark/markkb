---
title: "Source: Video Pipeline Design Document"
type: source
topic: vms-connector
tags: [worklog, pipeline, design-doc, extensibility, image-pipeline]
ingested: 2026-04-14
author: kb-bot
---

# Video Pipeline Design Document

**Origin:** `/home/mork/Documents/worklog/worklog/architecture/tech doc video pipeline.md`

A formal design document describing the video analytics pipeline architecture. This is the most comprehensive early specification of the pipeline's modular design, covering component abstractions, workflow, extensibility, and all processing phases.

## Core Abstractions

- **ImageCache**: Dual LRU cache (raw frame data + JPEG data) with configurable size. Provides fast access to recent frames.
- **BaseStep**: Abstract base class for all pipeline steps. Defines the interface for running, processing, and ending a step.
- **BaseLink**: Abstract base class for links between steps. Handles ending the previous step and starting the next, forming the chain-of-responsibility pattern.
- **ImageDataPacket**: The data envelope passed between steps. Accumulates results from every stage, giving downstream steps access to all upstream outputs.

## Workflow

Data flows from step to step via links. The pipeline begins with raw video data (decoded into frames) and terminates when the final step completes. Results are retrievable from the `ImageDataPacket`.

## Processing Phases

1. **Pre-processing**: Resize, grayscale conversion, and other frame preparation to improve downstream accuracy and reduce computational cost.
2. **Processing**: Object detection (bounding box generation) and motion tracking (trajectory association across frames).
3. **Post-processing**: False positive filtering and result aggregation over configurable time windows.
4. **Window steps**: Temporal management via Save Window (batch analysis of frame sequences) and Sliding Window (rolling frame-by-frame analysis).

## Extensibility

New steps and links are added by subclassing `BaseStep` or `BaseLink` and implementing the required methods. This modular design allows the pipeline to be reconfigured for different analytics products without modifying existing steps.

## Significance

This document formalises the abstractions (`BaseStep`, `BaseLink`, `ImageDataPacket`) that still underpin the current pipeline. The window step taxonomy (save vs. sliding) is still reflected in the codebase.
