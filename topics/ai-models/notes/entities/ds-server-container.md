---
title: "ds-server-container"
type: entity
topic: ai-models
tags: [rust, yolo, inference, inferentia2, graviton4, neuron, sahi, docker, kubernetes]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/actuate-platform/notes/syntheses/watchman-vs-current-platform.md
  - topics/ai-models/notes/entities/actuate-inference.md
  - topics/ai-models/notes/syntheses/yolo-vs-vlm-detection-future.md
  - topics/aws-cost/notes/concepts/2026-04-27_eks-storage-applicability.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
  - topics/data-science/notes/concepts/training-pipeline-architecture.md
  - topics/data-science/notes/entities/ds-training-pipeline.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
incoming_updated: 2026-05-01
---

# ds-server-container

A Rust-based YOLO object-detection inference platform designed for AWS Inferentia2 hardware, with a companion SAHI-style slicing proxy on Graviton4. The repo produces two binaries deployed as Docker containers to Kubernetes.

## Architecture

The system is split into two servers that can be called independently:

- **inference_server** (x86_64) -- runs YOLO models on Inferentia2 `inf2.*` instances using NeuronCores. Targets AMD EPYC 7R13 (Zen 3) CPUs. This is the core inference path for native-resolution images.
- **slicing_server** (aarch64) -- runs on Graviton4 `c8g/m8g/r8g` instances (Neoverse V2). Implements SAHI-style tiling: splits high-resolution images into overlapping tiles, dispatches each tile to the inference server over HTTP, and merges the results. It deliberately avoids libtorch and Neuron SDK dependencies.

Clients send high-resolution images to the slicing server and native-resolution images directly to the inference server. The slicing server acts as a transparent proxy that improves detection of small objects in large frames.

## Workspace Structure

The repo is a Cargo workspace with 8 Rust crates -- 6 libraries and 2 binaries:

- **inference_common** -- shared types and utilities.
- **inference_image** -- image loading and manipulation (depends on common).
- **inference_postprocess** -- post-processing of detection outputs (depends on common).
- **inference_tensor** -- tensor handling (depends on image).
- **inference_neuronx** -- AWS Neuron SDK bindings.
- **inference_yolo** -- YOLO model orchestration (depends on common, image, postprocess, tensor, neuronx).
- **inference_server** -- the inference binary (depends on yolo).
- **slicing_server** -- the slicing binary (depends on common, image, postprocess).

## Development Workflow

All Cargo commands run inside a Docker-based dev container via `bin/cargo-docker`. The `justfile` provides recipes: `just build-builder` builds the [[dev-environment|dev environment]], `just dev-container-up` starts the long-running container, and `just validate` runs clippy, tests, formatting, and doc checks. A pre-commit hook is available to run validation automatically.

## Container Build Pipeline

Container images are built and pushed to ECR via `just` recipes: `ctr-build-and-push-builder` (multi-arch builder), `ctr-build-and-push-inference-server-base`, `ctr-build-and-push-all-model-images`, and `ctr-build-and-push-slicing-server`. Model-specific images are layered on top of the inference server base image.

## Documentation

The repo includes thorough docs covering architecture, both server APIs, development setup, container builds, model management (manifest format, download, compilation), Neuron compilation pipeline, CI/CD (GitHub Actions), testing (unit + inference accuracy/performance suites), and a crate guide.

## Relationship to Other Repos

This is the **production inference serving layer**. Models trained by [[ds-training-pipeline]] are compiled for Neuron and deployed here. The older Python-based [[actuate-inference]] repo serves as a client/evaluation tool, not the production server. The slicing server here replaces in-cluster slicing previously handled elsewhere.
