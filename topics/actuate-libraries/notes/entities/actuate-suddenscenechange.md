---
title: "actuate-suddenscenechange"
type: entity
topic: actuate-libraries
tags: [library, camera-stream, scene-change, camera-disturbance, computer-vision, sac]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-suddenscenechange

## Purpose

actuate-suddenscenechange (commonly referred to as SAC -- Scene and Camera) detects sudden scene changes and camera disturbances in video streams. It identifies events such as camera displacement, rotation, occlusion, and drastic scene alterations. The library supports multi-level sensitivity, automatic EO/IR modality classification, and full state persistence via DynamoDB and S3 for cross-session recovery.

**Version:** 2.3.2

## Key Classes

### Core Detection
- **`CoreSceneAndCameraDisturbanceDetector`** -- Standalone detector with no DAO dependency. Accepts a frame and sensitivity level (`"low"`, `"medium"`, `"high"`). Processes frames via `process_frame(frame)` and returns a result packet indicating whether a disturbance was detected and its type.
- **`SceneAndCameraDisturbanceDetector`** -- Higher-level wrapper around the core detector.

### Integrated Detection (with DAO)
- **`IntegratedSACDetector`** -- Single-camera detector with full DAO integration. State is automatically saved after each frame. Accepts `camera_id`, `camera_name`, `dao_manager`, `sensitivity_level`, and optional `image_cache`.
- **`IntegratedSACDetectorBank`** -- Manages multiple `IntegratedSACDetector` instances for a camera, supporting on-demand detector creation and hour-based scheduling for different detection parameters.

### Utility Classes
- **`SimpleSceneChangePacket`** -- Data packet for [[scene-change-detection|scene change detection]] results.
- **`SimpleHistogramEqualizer`** -- Image preprocessing for improved detection accuracy.
- **`SimpleSubtractor`** -- Background subtraction component.
- **`SimpleSceneEventDetector`** -- Temporal analysis of detection event patterns.

### Configuration
- **`camera_base_params`** / **`camera_sensitivity_params`** -- Parameter dictionaries for base and sensitivity-specific detector configuration.
- **`SensitivityLevelParams`** -- Sensitivity configuration (low/medium/high) controlling detection thresholds.

## Public API

Standalone usage: `CoreSceneAndCameraDisturbanceDetector(frame, sensitivity_level="medium")` then call `process_frame(frame)`. Production usage: `IntegratedSACDetectorBank(camera_id, camera_name, sensitivity_level, dao_manager, image_cache)` for automatic state management and multi-modality support.

Utility functions: `crop()` for frame cropping (removes timestamp regions), `camera_base_params` and `camera_sensitivity_params` for configuration.

## Dependencies

`opencv-python-headless`, `numpy`, `scikit-image`. No internal actuate-* dependencies in the core package, though integrated classes expect `actuate-daos` and `actuate-image-cache` at runtime.

## State Persistence

State is persisted to DynamoDB tables (`scene_change_sac_table`, `scene_change_subtractor_state_table`) and S3 (`actuate-spray` bucket). Only background RGB images are stored -- features are recomputed on load via `extract_features()`, avoiding serialization issues and ensuring features always match current detector parameters.

## Consumers

Used by the connector pipeline when scene-change detection is enabled for a camera. The `IntegratedSACDetectorBank` is instantiated per camera stream and called each frame cycle.

## Notable Patterns

- Fresh-feature-on-load architecture: background images are saved, not serialized feature objects. On restore, features are recomputed, avoiding stale/incompatible feature data.
- Automatic EO/IR classification based on frame content analysis allows different detection parameters for electro-optical vs. infrared streams.
- Cropping (default 10% top/bottom) removes timestamp overlay regions that would otherwise trigger false scene changes.
- Comprehensive example suite in `examples/` with standalone, integrated, production-bank, and S3-storage demos.
