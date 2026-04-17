---
title: "Source: Puller Type Catalog"
type: source
topic: vms-connector
tags: [worklog, puller, camera, integration, catalog]
ingested: 2026-04-14
author: kb-bot
---

# Puller Type Catalog

**Origin:** `/home/mork/Documents/worklog/worklog/puller tier list.md`

A brief catalog listing the known puller types in the vms-connector. Pullers are the components responsible for interfacing with camera streams and feeding frames into the processing pipeline.

## Puller Types

1. **URL Puller** -- The standard RTSP/HTTP stream puller. Connects to a camera URL, decodes frames via OpenCV, and pushes them to the frame queue.
2. **URL Puller Motion** -- Variant that operates mostly off SQS motion-ping queues. Also supports socket-based pings. Only pulls frames when motion is detected, reducing unnecessary inference.
3. **Milestone Puller** -- Socket-based puller specific to the Milestone VMS. Does not use OpenCV for connection; communicates via Milestone's proprietary socket protocol.
4. **Socket Puller** -- Generic socket-based puller (attributed to Paolo).
5. **JPG Puller** -- Pulls individual JPEG snapshots rather than a continuous video stream.
6. **S3 Puller** -- Pulls frames or video from S3 buckets (used for batch/gauntlet processing).
7. **SQS Puller** -- Receives frame references via SQS messages.
8. **Queue Puller** -- Pulls from an internal queue (likely for inter-process communication).
9. **Buffer Puller** -- Attributed to Paolo; likely a buffered variant for specific integration needs.

## Significance

This catalog is the most complete enumeration of puller types found in the worklog. It maps the diversity of camera connection strategies: continuous RTSP streams, motion-triggered pulls, VMS-specific socket protocols, snapshot polling, cloud storage reads, and message-queue-driven processing. Each puller type corresponds to a different integration's requirements for how frames enter the pipeline.
