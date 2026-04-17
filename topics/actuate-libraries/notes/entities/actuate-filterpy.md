---
title: "actuate-filterpy"
type: entity
topic: actuate-libraries
tags: [library, ai-inference, kalman-filter, signal-processing, state-estimation]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-filterpy

Actuate's vendored fork of the `filterpy` library by Roger Labbe Jr. Provides Kalman filters and other Bayesian filtering algorithms used by the object tracking libraries. Version **1.0.1**.

## Purpose

Supplies the core state estimation primitives needed by `actuate-sort` and `actuate-botsort`. Rather than depending on the upstream `filterpy` PyPI package (which has stale releases and numpy 2.x incompatibility), Actuate maintains this fork with pinned numpy/scipy constraints and any needed patches.

## Key Modules

- **`kalman`** -- the primary module, containing:
  - `KalmanFilter` -- linear Kalman filter with predict/update cycle, stores state (`x`), covariance (`P`), process noise (`Q`), measurement noise (`R`), state transition (`F`), and measurement function (`H`).
  - `UKF` (Unscented Kalman Filter) -- for nonlinear systems using sigma points.
  - `EKF` (Extended Kalman Filter) -- linearized Kalman filter via Jacobians.
  - `CubatureKalmanFilter`, `IMM` (Interacting Multiple Model), `SquareRootKalmanFilter`, `InformationFilter`, `FadingMemoryFilter`, `FixedLagSmoother`, `MMAE`.
  - Sigma point generation functions (`MerweScaledSigmaPoints`, `JulierSigmaPoints`).
- **`common`** -- utility functions: `Q_discrete_white_noise`, `Q_continuous_white_noise`, `Saver` for recording filter state history.
- **`stats`** -- statistical functions: `gaussian`, `multivariate_gaussian`, `log_likelihood`, `mahalanobis`.
- **`gh`** -- g-h (alpha-beta) filter.
- **`discrete_bayes`** -- discrete Bayesian estimation.
- **`hinfinity`** -- H-infinity filter.
- **`leastsq`** -- least-squares estimation.
- **`memory`** -- fading memory filter variant.
- **`monte_carlo`** -- particle filter / Monte Carlo methods.

## Public API

```python
from actuate_filterpy.kalman import KalmanFilter
from actuate_filterpy.common import Q_discrete_white_noise, Saver
```

The `KalmanFilter` class is the most commonly used export. Initialize with `dim_x` (state dimension) and `dim_z` (measurement dimension), then configure `F`, `H`, `Q`, `R`, `P`, and `x` matrices before running the predict/update loop.

## Dependencies

- **External**: `numpy >=1.24.3,<2.0`, `scipy >=1.10.1,<2.0`
- **Internal**: none

Note the strict `numpy <2.0` pin, which ensures compatibility with the matrix operations in this library.

## Consumers

- `actuate-sort` -- uses `KalmanFilter` with a 7-state constant-velocity model for bounding box tracking.
- `actuate-botsort` -- uses its own `KalmanFilter` implementation internally but depends on `actuate-filterpy` as a transitive dependency.

## Notable Patterns

- This is a near-verbatim fork of the upstream `filterpy` (MIT-licensed), re-packaged under the `actuate_filterpy` namespace for monorepo compatibility.
- Requires Python 3.12+ (stricter than most other actuate libraries which require 3.11+).
- The numpy <2.0 constraint is critical because numpy 2.0 changed array casting behavior that breaks some matrix operations in the filter implementations.
