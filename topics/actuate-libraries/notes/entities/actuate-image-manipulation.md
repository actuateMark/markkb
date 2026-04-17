---
title: "actuate-image-manipulation"
type: entity
topic: actuate-libraries
tags: [library, image-processing, dewarping, fisheye, cython, native-code]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-image-manipulation

## Purpose

actuate-image-manipulation provides tools for pre-processing images before inference, with its primary capability being fisheye lens dewarping. The library wraps C-based image transformation code (fish2persp and fish2pano) via a Python/ctypes interface, enabling the Actuate platform to correct fisheye camera distortion by converting fisheye images to either perspective (rectilinear) or panoramic projections.

**Version:** 1.1.6

## Key Classes

### `Dewarp`
The main class. Loads a compiled shared object (`dewarp.*.so`) at construction via `ctypes.CDLL` and exposes two transformation methods.

#### `persp(input_data, options=None) -> bytes`
Converts a fisheye image to a perspective (rectilinear) view. Accepts raw image bytes and an optional CLI-style options string. Returns dewarped image bytes. Options include:
- `-w`/`-h` -- output width/height
- `-t` -- perspective FOV
- `-s` -- fisheye FOV
- `-c` -- fisheye center (x, y)
- `-r`/`-ry` -- fisheye radius (horizontal/vertical)
- `-x`/`-y`/`-z` -- tilt/roll/pan angles
- `-a` -- antialiasing level
- `-p` -- four polynomial distortion coefficients (a1-a4)

#### `pano(input_data, options=None) -> bytes`
Converts a fisheye image to a panoramic view. Same bytes-in/bytes-out pattern. Additional options include:
- `-v` -- vertical FOV
- `-la`/`-lo` -- latitude/longitude range
- `-f` -- generate remap file
- `-o` -- generate OBJ mesh
- `-2` -- split-screen mode

### `PERSP_OPTIONS` / `PANO_OPTIONS`
`ctypes.Structure` subclasses that mirror the C structs used by the native library. Default sentinel value of -500 signals "use library defaults" for each parameter.

## Native Code

The `lib/` directory contains the C source:
- **`fish2persp.c` / `fish2persp.h`** -- Fisheye-to-perspective transformation.
- **`fish2pano.c` / `fish2pano.h`** -- Fisheye-to-panoramic transformation.
- **`bitmaplib.c` / `bitmaplib.h`** -- Low-level bitmap I/O utilities.
- **`Makefile`** -- Build system for the shared object.

The build produces a `dewarp.cpython-*.so` via Cython/setuptools (the `dewarp.c` file is Cython-generated).

## Build System

Unlike most actuate-* libraries that use Hatch, this package uses **setuptools** as the build backend (with Cython as a build dependency) because it needs to compile C extensions. The `pyproject.toml` specifies `setuptools>=75.1.0`, `wheel`, and `cython>=3.0.11`.

## Dependencies

`setuptools`, `cython` (build-time). No actuate-* runtime dependencies. The compiled `.so` links against libjpeg-turbo at the system level.

## Consumers

- **vms-connector** -- Used when processing fisheye cameras. The connector creates a `Dewarp` instance and calls `persp()` or `pano()` on each frame before submitting it to inference, based on the camera's dewarping configuration.

## Notable Patterns

- The ctypes interface manually manages C memory: `free_memory()` is called after copying output bytes to Python, preventing memory leaks.
- Options are parsed from a CLI-style string format (e.g., `"-w 1920 -h 1080 -s 180"`) rather than keyword arguments, mirroring the original C tool's argument parsing.
- The sentinel value pattern (-500 for all numeric defaults) lets the C library distinguish "not set" from actual zero values.
- macOS/Homebrew build instructions are documented for local development with `llvm` and `jpeg-turbo`.
