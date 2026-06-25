---
title: "actuate-blur"
type: entity
topic: actuate-libraries
tags: [library, camera-stream, image-quality, blur-detection, fft, dynamodb]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/camera-health-monitoring/notes/syntheses/chm-enhanced-diagnostics-proposal.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase5-frame-probe.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-06-25
---

# actuate-blur

## Purpose

actuate-blur determines whether a camera frame is blurry and computes image quality metrics. It is used as part of the Actuate platform's health monitoring system to track camera feed quality and flag degraded streams. The library uses frequency-domain analysis (FFT) and entropy calculations to quantify image sharpness, and can persist blur metrics to DynamoDB for per-camera status tracking.

**Version:** 1.1.3

## Key Classes

- **`BlurHandler`** -- The sole public class. Provides methods for blur detection via FFT, entropy calculation, metric persistence to DynamoDB, and a combined calculate-and-update workflow.

## Public API

### `BlurHandler(blur_threshold=10)`
Constructor. Initializes with a configurable blur threshold and connects to the DynamoDB `CameraStatus` table.

### `get_blur_metric(img: np.ndarray) -> float`
Primary method for blur detection. Takes a NumPy image array, runs FFT-based blur analysis, and returns a numeric blur metric. Higher values indicate sharper images.

### `detect_blur_fft_image(image, size=60) -> float`
Core FFT algorithm. Converts the image to grayscale, computes the 2D FFT, zeroes out low-frequency components in a central square of the given `size`, reconstructs the image, and returns the mean log magnitude. A low mean indicates a blurry image (lacking high-frequency detail).

### `calculate_entropy(image) -> float`
Computes the Shannon entropy of the grayscale pixel histogram (128 bins). Low entropy indicates a uniform/featureless image.

### `update_blur_item(customer_name, camera_name, blur_metric) -> int`
Writes the blur metric to DynamoDB `CameraStatus` table for the given customer/camera. Returns the HTTP status code. On error, writes -9999 as a sentinel value.

### `calculate_and_update(frame, camera_name, customer_name) -> dict`
End-to-end workflow: calculates both blur metric and entropy, updates DynamoDB, and returns `{"blur": float, "entropy": float}`. On failure, returns `{"blur": 0, "entropy": 0}`.

## Dependencies

`boto3`, `opencv-python-headless`, `numpy`, `scipy` (for `scipy.stats.entropy`).

## Consumers

- **[[actuate-pullers]] / BasePuller** -- `StreamQualityPacket` uses blur and entropy metrics for health check reporting. When `customer.healthcheck.image_quality_check` is enabled, the puller evaluates frame quality.
- **Health monitoring dashboards** -- Blur metrics in the `CameraStatus` DynamoDB table are surfaced to operational dashboards.

## Notable Patterns

- The FFT approach is lightweight and does not require a trained model. It works by measuring the energy in high-frequency components: blurry images have attenuated high frequencies, resulting in a lower mean magnitude after zeroing the low-frequency center.
- [[sentinel-components|Sentinel]] value of -9999 written on DynamoDB update errors ensures downstream consumers can distinguish "error" from "sharp" or "blurry."
- The library directly instantiates a `boto3.resource("dynamodb")` in the constructor, coupling it to AWS at import time. This means test consumers typically need mocked boto3 or localstack.
- Exception handling is broad (`except Exception`) throughout, with logging but no re-raising, so blur failures never crash the pipeline.
