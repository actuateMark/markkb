---
title: "ds-smart-alert-supervisor"
type: entity
topic: ai-models
tags: [repo, vlm, alert-verification, heuristics, streamlit, qwen, surveillance, frame-analysis]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/ai-models/notes/concepts/vlm-pipeline-architecture.md
  - topics/ai-models/notes/entities/qwen3vl-aws.md
  - topics/ai-models/notes/entities/vlm-eval-visualizer.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
incoming_updated: 2026-05-01
---

# ds-smart-alert-supervisor

Frame-level alert verification and analysis toolkit that combines detection heuristics with VLM-based verification. Ported from `ds-smart-alert-monitor` with a focus on simplified frame-level operations.

**Repo:** `aegissystems/ds-smart-alert-supervisor` (private, updated 2026-03-24)

## Purpose

When the Actuate pipeline fires a security alert, this tool can re-examine the alert at the frame level to determine whether it is a true positive or false positive. It applies two layers of verification: traditional detection heuristics (confidence thresholds, N-of-M frame rules) and VLM-based scene understanding that can interpret what is actually happening in the frames.

## Core Capabilities

### Detection Heuristics
- Detection-level filtering with minimum confidence thresholds.
- Alert-level heuristics using N-out-of-M frames rules (e.g., "at least 3 of 5 frames must contain a detection above threshold").
- Supports intruder, vehicle, and loiterer alert types.

### VLM Verification
- Supports Qwen2.5-VL (3B, 7B, 72B Instruct) and Qwen3-VL (4B, 8B, 30B Instruct) model families.
- Full-frame verification with scene understanding.
- Sliding window verification with persistence rules.
- Vehicle motion analysis prioritises first-frame vs. last-frame cumulative motion over adjacent-frame comparison, catching slow or subtle movement.
- `vehicle_moving_positive_override`: if structured VLM output describes a moving vehicle but the verdict line says No, the window can still be treated as confirmed.

### Data Handling
- Parses alert folders (metadata.json, settings.json, frames/).
- Extracts detections from `model_labels` and `pre_filter_raw_model_response`.
- Sorts frames by timestamp from metadata.
- Extracts camera settings and evidence conditions.

### Camera Shake Stabilisation
Before VLM window verification, the pipeline can optionally align frames to the first frame when global motion (e.g., wind) is detected, using phase correlation and ORB/affine alignment. Disable with `SMART_ALERT_STABILIZE=0`.

## Streamlit App

A simplified verification app provides a visual interface for frame-level review with persistence rules, default evidence display, and VLM verdict rendering per window.

## Installation

Requires Python 3.10+ and `uv`. VLM backends are installed as optional extras -- Qwen2.5-VL and Qwen3-VL require different `transformers` versions and cannot coexist. YOLO is optional since the supervisor works with pre-existing detections from alert metadata.

## Related

- [[vlm-inference]] -- queue-based VLM worker that this tool can leverage
- [[vlm-eval-visualizer]] -- complementary tool for reviewing VLM verdicts at scale
- [[actuate-vlm]] -- client library for submitting VLM requests
