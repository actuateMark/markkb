---
title: "actuate-tests"
type: entity
topic: actuate-libraries
tags: [library, utility, testing, test-helpers, fixtures, sample-data]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-tests (v0.0.3) provides shared test helpers, sample data, and test fixtures for the actuate-libraries monorepo. It allows any library's test suite to access a standard base configuration and sample detection data without duplicating setup code.

## Public API

### `helper.py`

- **`get_file_path(base_path, relative_path, create=False)`** -- Resolves an absolute file path from a base and relative path. When `create=True`, creates intermediate directories. Used to locate test data files relative to the test module.

- **`get_image(image_name)`** -- Returns the absolute path to an image in the `data/` directory. Convenience wrapper around `get_file_path`.

- **`get_base_config()`** -- Loads `data/settings.json` and returns an `RTSPConnectorConfig` instance. This provides a fully-parsed configuration object for tests that need a realistic connector config without connecting to AWS or Camera Admin.

### `sample_data.py`

Contains pre-built detection data for testing inference and filtering logic:

- **`raw_model_response_vehicle`** -- A list of raw model response entries (label, confidence, bbox, width, height) simulating a traffic scene with cars, trucks, and persons.
- **`raw_model_response_staged`** -- A staged detection set with person, car, truck, and pistol detections at 1280x720 resolution.
- **`vehicle_polygonal_zones`** -- Sample polygonal ignore zone coordinates for testing zone-based filtering.

### `data/` directory

Contains static test assets: sample `settings.json`, test images, and other fixtures referenced by `get_file_path` and `get_image`.

## Dependencies

None declared in pyproject.toml. Has a dev dependency on `actuate-config` >=1.0.0 for `RTSPConnectorConfig`. At runtime imports `actuate_config.connector.rtsp.RTSPConnectorConfig`.

## Consumers

All library test suites that need shared test infrastructure. Import patterns:
- `from actuate_tests.helper import get_base_config, get_file_path`
- `from actuate_tests.sample_data import raw_model_response_staged`

[[actuate-config]] lists actuate-tests as a dev dependency.

## Notable Patterns

- **Shared settings.json fixture**: `get_base_config()` provides a canonical test configuration, ensuring all libraries test against the same settings structure.
- **Zero production dependencies**: This is a dev-only library; it should never appear in production dependency chains.
- **Convention-based test discovery**: Libraries use pytest with `tests/test_*.py` and `pythonpath = ["src"]`, importing actuate-tests helpers as needed.
