---
title: "project-auto-ignore-zones"
type: entity
topic: settings-automation
tags: [repo, langgraph, agent, ignore-zones, sam, segmentation, scene-classification, camera-settings]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# project-auto-ignore-zones

LangGraph-based agent that automatically generates and refines ignore zone suggestions for security cameras. Ignore zones are polygon regions that suppress irrelevant alerts in areas like sky, roads, and neighbouring properties.

**Repo:** `aegissystems/project_auto_ignore_zones` (private, updated 2026-03-31)

## Purpose

Configuring ignore zones for each camera is a slow, error-prone manual task during site onboarding. This agent transforms the process into a fast, explainable workflow: auto-suggest polygons, accept/reject with one click, refine with a slider or brush tool, and request alternatives with a re-click.

## Architecture

The agent uses a **progressive tool execution strategy** to balance quality with speed:

- **Stage A (Fast/Cheap)**: Scene classifiers, sky segmentation, edge/boundary detection.
- **Stage B (Medium)**: Region proposals when confidence is low.
- **Stage C (Heavy)**: SAM (Segment Anything Model) segmentation only when needed, gated by a compute budget.

### Camera Relation Classification

The agent first classifies how the camera relates to its site:

| Relation | Strategy |
|----------|----------|
| Inside looking out | Ignore sky, roads, neighbours; keep site interior |
| Outside looking in | Ignore foreground/public areas; keep the site region |
| Mixed/Unknown | Generate candidates from both families |

### Candidate Generation and Scoring

Multiple candidate ignore zones are generated (sky-based, boundary-aligned, layout-based, or explicit "no-ignore") and scored through hard checks (area bounds, fragmentation, valid geometry) and weighted soft scores (boundary alignment, shape simplicity, scene prior match, coverage appropriateness).

## Operator Interactions

All interactions are designed for sub-second response:

- **Accept/Reject**: Finalise or show next-best candidate (no recomputation).
- **Slider**: Morphological expand/contract of the zone boundary.
- **Brush**: Local add/remove edits.
- **Re-click**: Generate new suggestion at a specific point (may invoke heavier tools if budget allows).

## Tools

Tools are organised by cost category under `src/tools/`: sky segmentation (cheap), scene classifiers (cheap), boundary detection (cheap), geometry operations (cheap), and SAM segmentation (heavy). New tools inherit from `BaseTool` with a declared `ToolCategory`.

## Learning Pipeline

The agent logs all data needed for future improvement: scene classification results, all generated candidates and scores, operator edits, and final accept/reject state. This data feeds back to train better classifiers, tune scoring weights, and learn optimal defaults.

## Requirements

Python 3.12+, CUDA-capable GPU (recommended for SAM), AWS credentials for S3 image access. Internal Actuate packages installed via `scripts/install_actuate.sh`.

## Roadmap

Key items still in progress: camera relation classifier (currently placeholder), fence/boundary detection, point-prompted SAM for re-click, vehicle detection integration, batch processing for site onboarding, and a QA regression harness.
