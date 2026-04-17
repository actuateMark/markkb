---
title: "Source: Rearch Main Loop Walkthrough"
type: source
topic: vms-connector
tags: [worklog, architecture, main-loop, rearch, pipeline]
ingested: 2026-04-14
author: kb-bot
---

# Rearch Main Loop Walkthrough

**Origin:** `/home/mork/Documents/worklog/worklog/architecture/main loop for rearch.md`

A guided walkthrough of the primary code path for a single connector run in the rearchitected codebase. The note traces execution from bootstrap to frame processing and identifies the key files at each stage.

## Boot Sequence

1. **connector.py** -- Bootstrap entry point. Loads the settings file and initialises dependencies needed for the run.
2. **factory.py** -- Reads the integration type from the settings file and builds the appropriate connector (see [[connector-factory]]).
3. **site_manager.py** -- Runs the site. The chosen connector type (healthcheck, default, etc.) determines the strategy for starting cameras. Also runs and manages site-level metrics.

## Per-Camera Runtime

4. **healthcheck_camera.py / base_stream_camera.py / etc.** -- Each camera class manages camera-level logic: sending alerts, receiving frames, saving results, and notifying observers.
5. **puller.py** -- Interfaces directly with the camera hardware or stream. Responsible for keeping the connection alive, pulling frames, and feeding them into the queue after applying downsampling and resizing logic.

## Pipeline Execution

6. **image_pipeline.py** -- Processes frames through inference and post-processing. Structured as a list of steps written in a functional style (no state stored in individual steps; all state travels on the data object passed along the chain).

The pipeline is split into three phases:

- **Pre-processing** (formerly the stream parser): camera metadata, cv2 transforms, and other preparation before inference.
- **Processing**: the YOLO inference call itself. This is the boundary where the old stream parser handed off to the old stream worker.
- **Post-processing**: everything after YOLO -- filtering logic (ignore zones, stationary, IOU), window logic, and related steps.

## Significance

This note is useful as a "follow the code" guide for anyone new to the rearch codebase. It establishes the six-file critical path and clarifies the functional/stateless design philosophy of the pipeline.
