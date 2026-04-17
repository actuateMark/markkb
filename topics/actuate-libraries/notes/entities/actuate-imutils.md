---
title: "actuate-imutils"
type: entity
topic: actuate-libraries
tags: [library, image-processing, opencv, utility, fork]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-imutils

## Purpose

actuate-imutils is Actuate's internal fork of the popular PyImageSearch `imutils` library. It provides convenience functions that simplify common OpenCV image processing operations such as translation, rotation, resizing, skeletonization, edge detection, contour sorting, and perspective transforms. The fork allows Actuate to vendor the library without external PyPI dependencies and to make internal modifications as needed.

**Version:** 1.0.4

## Key Functions (from `convenience` module)

- **`translate(image, x, y)`** -- Shifts an image by (x, y) pixels using an affine transform.
- **`rotate(image, angle, center=None, scale=1.0)`** -- Rotates an image around a center point (defaults to image center).
- **`rotate_bound(image, angle)`** -- Rotates an image and adjusts the bounding box so no content is clipped.
- **`resize(image, width=None, height=None, inter=cv2.INTER_AREA)`** -- Aspect-ratio-preserving resize. Specify either width or height.
- **`skeletonize(image, size, structuring=cv2.MORPH_RECT)`** -- Computes the topological skeleton of a binary image.
- **`opencv2matplotlib(image)`** -- Converts BGR to RGB for Matplotlib display.
- **`url_to_image(url)`** -- Downloads an image from a URL and decodes it into a NumPy array.
- **`auto_canny(image, sigma=0.33)`** -- Automatic Canny edge detection using median-based threshold selection.
- **`grab_contours(cnts)`** -- Compatibility wrapper for `cv2.findContours` across OpenCV 2/3/4 (which return different tuple lengths).
- **`is_cv2()` / `is_cv3()` / `is_cv4()` / `check_opencv_version()`** -- OpenCV version detection helpers.
- **`build_montages(image_list, image_shape, montage_shape)`** -- Arranges multiple images into a grid montage.
- **`adjust_brightness_contrast(image, brightness, contrast)`** -- Adjusts image brightness and contrast.

## Submodules

- **`contours`** -- Contour sorting utilities (left-to-right, right-to-left, top-to-bottom, bottom-to-top).
- **`paths`** -- Recursive image file discovery (`list_images()`).
- **`perspective`** -- Four-point perspective transform for document scanning and ROI extraction.
- **`encodings`** / **`face_utils`** -- Face encoding and landmark utilities.
- **`feature`** -- Feature detection helpers.
- **`object_detection`** -- Non-max suppression and object detection utilities.
- **`video`** -- Video stream and FPS helpers.
- **`meta`** -- `find_function()` for searching OpenCV function names.

## Public API

Import as `import actuate_imutils as imutils`, then call functions directly: `imutils.resize(img, width=300)`, `imutils.rotate(img, 45)`, `imutils.auto_canny(gray)`, etc.

## Dependencies

None. Zero external dependencies -- the library is pure Python using only standard-library and OpenCV/NumPy (expected to be available in the consumer's environment).

## Consumers

- **actuate-movement** -- Uses `resize` and `grab_contours` from the `core.motion_utils` module (which re-exports similar functions; the imutils versions are available as a fallback).
- **Other actuate-* libraries and connectors** that need quick image transforms without pulling in the upstream PyPI imutils package.

## Notable Patterns

- Forked from [PyImageSearch/imutils](https://github.com/PyImageSearch/imutils) and vendored under the `actuate_imutils` namespace to avoid dependency conflicts.
- Retains Python 2.7 compatibility code (`urllib` vs `urllib.request` branching) from the upstream fork, though the monorepo requires Python 3.11+.
- The `grab_contours` function is critical for cross-version OpenCV compatibility, as `cv2.findContours` changed its return signature between OpenCV 2, 3, and 4.
