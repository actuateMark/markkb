---
title: "ppf (Pixels Per Foot)"
type: entity
topic: settings-automation
tags: [depth-estimation, pixels-per-foot, machine-learning, python, torch]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# ppf (Pixels Per Foot)

Experimental repository for determining **[[pixels-per-foot|pixels per foot]]** throughout an image using depth estimation. The project name internally is `actuate-depth`. It explores multiple approaches to depth-aware spatial calibration -- mapping pixel distances in camera frames to real-world measurements.

## Purpose

Pixels-per-foot (PPF) is a critical parameter for Actuate's [[detection-pipeline|detection pipeline]]. Knowing the physical scale at different points in an image allows the system to filter detections by real-world size, set appropriate sensitivity thresholds, and reduce false positives. Currently PPF values are configured manually per camera; this repo explores automated approaches using monocular depth estimation.

## Repository Contents

The repo is a flat collection of Python scripts (no installable package) with the following training and inference experiments:

- **ppf_train.py** -- Base PPF training script.
- **ppf_train_diode_cnn.py** -- CNN training using the DIODE (Dense Indoor and Outdoor DEpth) dataset.
- **ppf_train_transformer.py** -- Transformer-based PPF model training.
- **ppf_train_neuralfield.py** -- Neural field approach to PPF estimation.
- **ppf_infer.py** -- Inference script for the base model.
- **ppf_infer_transformer.py** -- Inference script for the transformer variant.
- **diode_depth_stats.py** -- Statistical analysis of the DIODE depth dataset.
- **diode_view_dataset.py** -- Dataset viewer for DIODE samples.
- **inspect_exr.py** -- Utility for inspecting Blender `.exr` depth map files.
- **view_depth.py** -- Interactive depth map viewer.

## Tech Stack

Python 3.11+, PyTorch, NumPy, Matplotlib, Pillow, OpenEXR, tqdm. Dependencies are managed with `uv` (see `pyproject.toml` and `uv.lock`).

## Status

This is a research/experimentation repo, not a production service. It explores multiple model architectures (CNN, transformer, neural fields) for the same task, suggesting the team is still evaluating which approach works best. The repo was updated as recently as 2026-04-13, indicating active development.

## Relationship to Settings Automation

Automated PPF estimation would feed into the broader settings automation effort -- if depth models can reliably estimate real-world scale from a camera view, the system could auto-configure per-camera detection thresholds without manual calibration, reducing onboarding time for new camera installations.
