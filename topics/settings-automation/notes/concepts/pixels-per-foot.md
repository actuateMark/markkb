---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [settings-automation, ppf, pixels-per-foot, camera-settings, datasets, otzar]
---

# Pixels Per Foot

Pixels Per Foot (PPF) is a metric used within [[settings-automation/_summary|Settings Automation (H1.4)]] to quantify how much visual detail a camera captures at a given distance. It directly informs which detection models and sensitivity settings should be applied to each camera. The PPF workstream is led by **[[otzar-jaffe|Otzar Jaffe]]** (SA-177), with active development since March 2026 focused on improving code quality and reducing output file size.

## What PPF Measures

PPF expresses the number of image pixels that represent one foot of real-world distance at a specific depth in the camera's field of view. A camera with 30 PPF means a one-foot-tall object occupies roughly 30 vertical pixels in the image.

Higher PPF means more detail is available for detection:
- **High PPF (>30)** -- Close-range, high-detail views. Suitable for object classification, facial features, weapon identification
- **Medium PPF (15-30)** -- Mid-range. Adequate for person detection, vehicle classification, basic behaviour analysis
- **Low PPF (<15)** -- Long-range, wide-angle views. Suitable only for motion detection and gross object presence

## Why PPF Matters for Settings

Different detection models have different minimum PPF requirements. A firearm detection model needs enough pixels on target to distinguish a weapon from a phone or tool -- it requires high PPF. A perimeter intrusion model only needs to detect a person-shaped blob crossing a line -- it can work at lower PPF.

By calculating PPF for each camera, the [[settings-automation/_summary|Settings Automation (H1.4)]] system can:

1. **Recommend appropriate models** -- Only enable detection types that the camera's resolution and placement can support
2. **Set sensitivity thresholds** -- Lower-PPF cameras need different confidence thresholds than high-PPF cameras
3. **Identify coverage gaps** -- Flag cameras where PPF is too low for the site's protection priorities
4. **Guide camera placement** -- Advise operators on where cameras should be positioned for specific detection goals

## PPF Calculation

Calculating PPF requires estimating real-world distances from 2D images. The approach likely involves:

1. **Reference objects** -- Using objects of known size (doors, vehicles, people) visible in the frame as scale references
2. **Depth estimation** -- Mapping how PPF varies across the frame (objects near the camera have higher PPF than objects far away)
3. **Camera parameters** -- Incorporating lens focal length and sensor size if available (from ONVIF metadata or manual configuration)

The calculation produces a PPF map across the camera's field of view, not a single number. Near-field regions may have 50+ PPF while far-field regions of the same camera drop to 10 PPF.

## Dataset Building

[[otzar-jaffe|Otzar Jaffe]]'s work includes building datasets to train and validate PPF estimation models. This involves:

- Collecting frames from diverse camera installations with known physical dimensions
- Annotating reference objects and their real-world sizes
- Training models to estimate PPF from camera frames without manual measurement
- Validating estimates against ground truth

The goal is automated PPF calculation: given a camera feed, the system should estimate PPF across the field of view without requiring an operator to measure anything. This is essential for [[watchman/_summary|Actuate Watchman]]'s [[onboarding-wizard|self-service onboarding]] -- a small business owner cannot be expected to measure distances and calculate pixels.

## Code Quality and Output Size

SA-177's current focus on reducing output file size suggests the PPF calculation produces spatial maps or dense data structures that are expensive to store. Optimisation likely involves compression, resolution reduction of the PPF map, or summarisation into zone-level averages rather than per-pixel values.

## Connection to Broader Settings Automation

PPF feeds into the Settings Recommender (SA-7 epic, owned by Thomas Kornfeld) as a primary input signal. Combined with site type (from [[onboarding-wizard|onboarding]] or manual configuration) and protection priorities, PPF enables the system to generate per-camera settings recommendations without manual tuning. This is a step toward the fully automated settings pipeline envisioned by the Settings Automation initiative.
