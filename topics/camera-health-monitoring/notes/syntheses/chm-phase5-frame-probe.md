---
title: "CHM Phase 5: FrameProbe -- Visual Quality Analysis Beyond Blur"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-5]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase6-smtp-ailink-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase7-historical-trending.md
  - topics/integrations/rtsp/notes/entities/rtsp-enhancement-issues.md
  - topics/integrations/rtsp/notes/syntheses/rtsp-robustness-enhancement-plan.md
incoming_updated: 2026-05-01
---

# CHM Phase 5: FrameProbe -- Visual Quality Analysis Beyond Blur

## Problem Statement

Current frame-level analysis in CHM is limited to two metrics: FFT-based blur detection and Shannon entropy, both implemented in [[actuate-blur|actuate-blur's BlurHandler]]. `BlurHandler.detect_blur_fft_image()` computes a frequency-domain sharpness score by zeroing low-frequency FFT components and measuring the mean magnitude of the reconstruction. `BlurHandler.calculate_entropy()` computes a 128-bin grayscale histogram entropy using `scipy.stats.entropy`. These two metrics flag `BLURRED_VIEW` and `VIDEO_LOSS` (blank frame) conditions in `StreamQualityPacket`.

This leaves several common failure modes undetected:

- **Black frames**: IRcut stuck in night mode, lens cap left on, or video signal loss. Low entropy catches some of these, but a frame with uniform dark noise (pixel values 5-15) can have non-trivial entropy while being visually black.
- **Frozen frames**: Encoder freeze or NVR replay loop producing identical frames. No temporal analysis exists.
- **IR mode transitions**: Day/night auto-switch produces a legitimate dramatic visual change that triggers false SCENE_CHANGE alerts via [[actuate-suddenscenechange|actuate-suddenscenechange]].
- **Color channel loss**: Partial cable degradation or connector oxidation causes loss of one or two color channels. The frame looks greenish or magenta but blur/entropy remain normal.
- **Severe defocus**: Camera aimed at a wall, ceiling, or severely defocused. Blur metric may be low but not below threshold if there is any texture.
- **Intermittent focus hunting**: Autofocus cycling produces frames that alternate between sharp and soft. Single-frame blur check misses the pattern.

## Proposed Solution: FrameProbe Utility Class

A new `FrameProbe` class in `healthcheck/alerts/diagnostics/tools/frame_probe.py` that extends the visual analysis capabilities beyond what [[actuate-blur]] provides. FrameProbe operates on individual frames and short frame sequences (3-10 frames) collected during the healthcheck window.

### Class Interface

```python
from typing import Dict, List, Optional, Tuple
import numpy as np

class FrameProbe:
    """Visual quality analysis for healthcheck frames.

    Operates on BGR uint8 numpy arrays (OpenCV convention).
    Methods that require temporal context accept a list of frames
    collected at known intervals during the healthcheck window.
    """

    def __init__(self, config: Optional[dict] = None):
        """Initialize with optional threshold overrides.

        Args:
            config: Dict of threshold overrides. Keys:
                black_frame_threshold (int): Mean pixel ceiling. Default 10.
                frozen_ssim_threshold (float): SSIM floor for frozen. Default 0.999.
                ir_mode_std_threshold (float): Channel-diff std ceiling. Default 5.0.
                edge_density_floor (float): Minimum edge %. Default 0.01.
        """

    # --- Single-frame analyses ---

    def is_black_frame(self, frame: np.ndarray) -> Tuple[bool, float]:
        """Detect black/near-black frames.

        Returns:
            (is_black, mean_pixel): True if mean pixel < threshold across
            all channels. Different from low entropy -- uniform dark noise
            has non-trivial entropy but is visually black.
        """

    def detect_ir_mode(self, frame: np.ndarray) -> Tuple[bool, float, float]:
        """Detect infrared/night-vision mode.

        Returns:
            (is_ir, std_rg, std_rb): True if std(R-G) and std(R-B) < threshold.
            IR mode produces near-monochrome output where R, G, B channels
            are nearly identical. Used to suppress false scene-change alerts.
        """

    def color_histogram_fingerprint(self, frame: np.ndarray) -> np.ndarray:
        """Compute 32-bin RGB histogram fingerprint.

        Returns:
            histogram: Shape (96,) normalized float array -- 32 bins per channel.
            Use chi_squared_distance() to compare fingerprints across runs.
        """

    def chi_squared_distance(
        self, hist_a: np.ndarray, hist_b: np.ndarray
    ) -> float:
        """Chi-squared distance between two histogram fingerprints.

        Large distance indicates color drift: lens damage, cable degradation,
        color channel loss, or white balance failure.
        """

    def edge_density(self, frame: np.ndarray) -> float:
        """Compute edge pixel percentage of frame area.

        Uses Canny edge detection on grayscale conversion.
        Returns fraction (0.0 to 1.0) of pixels that are edge pixels.
        Values < 0.01 indicate wall/ceiling aim or severe defocus.
        """

    # --- Multi-frame temporal analyses ---

    def is_frozen(
        self, frame_sequence: List[np.ndarray]
    ) -> Tuple[bool, float]:
        """Detect frozen frames in a sequence.

        Returns:
            (is_frozen, min_ssim): True if SSIM > threshold across all
            consecutive frame pairs. Also checks FDMD delta_noise near zero
            as a secondary signal.
        """

    def temporal_consistency(
        self,
        frame_sequence: List[np.ndarray],
        timestamps: List[float],
        expected_interval: float,
    ) -> Dict[str, float]:
        """Analyze temporal consistency of a frame sequence.

        Returns dict with:
            blur_std: Std dev of blur metric across frames. High = focus hunting.
            mean_interval: Mean actual interval between frames.
            interval_jitter: Std dev of (actual - expected) intervals.
            frame_count: Number of frames analyzed.
        """
```

### Detailed Analysis Design

**`is_black_frame(frame)`**: Converts to all three channels, computes `np.mean(frame)` across the entire array. If the mean pixel value is below 10, the frame is classified as black. This is deliberately distinct from low entropy: a frame of uniform value 8 across all pixels has zero entropy but mean=8 (black). A frame with random dark noise (values 0-15) has moderate entropy (~3.5 bits) but is still visually black with mean ~7.5. The existing `calculate_entropy()` in [[actuate-blur|BlurHandler]] uses 128 bins on grayscale only, which misses the multi-channel signal.

**`is_frozen(frame_sequence)`**: Computes SSIM (Structural Similarity Index) between each consecutive pair of frames using `cv2.matchTemplate` with `cv2.TM_CCOEFF_NORMED` as a fast proxy, or `skimage.metrics.structural_similarity` if available. If all consecutive SSIM values exceed 0.999, the sequence is frozen. As a secondary check, computes `get_delta_noise()` from [[actuate-movement|actuate-movement's delta_noise module]] between the first and last frame -- a delta_metric near zero confirms the freeze. This dual approach catches both pixel-identical freezes (encoder loop) and near-identical freezes (NVR replay with compression artifacts).

**`detect_ir_mode(frame)`**: Splits the BGR frame into channels, computes `std(R - G)` and `std(R - B)` across all pixels. IR/night-vision cameras output near-monochrome frames where all three channels carry nearly identical values. When both standard deviations fall below 5.0, the frame is classified as IR mode. This signal is passed to [[actuate-suddenscenechange|CameraDisturbanceDetector]] to suppress scene-change alerts during day/night transitions. A camera switching from color to IR mode produces a dramatic histogram shift that SIFT matching correctly identifies as a scene change -- but it is an expected operational transition, not camera tampering.

**`color_histogram_fingerprint(frame)`**: Computes a 32-bin histogram per BGR channel (96 bins total), normalized to sum to 1.0. The fingerprint is compact (96 floats, 768 bytes) and stable across minor exposure changes. Stored in `healthcheck_data.diagnostics["frame"]["color_fingerprint"]` and compared against the previous run's fingerprint using chi-squared distance. A chi-squared distance exceeding a configurable threshold (default 0.5) across 3 consecutive runs indicates hardware degradation: corroding BNC connectors cause progressive blue channel loss, damaged IR filters cause persistent magenta tint, failing power supplies cause progressive desaturation.

**`edge_density(frame)`**: Converts to grayscale, applies Canny edge detection (`cv2.Canny(gray, 50, 150)`), counts non-zero pixels, and divides by total pixel count. Normal surveillance scenes have edge density between 0.03 and 0.25. Values below 0.01 (1%) indicate the camera is aimed at a featureless surface (wall, ceiling, sky) or is severely defocused. This catches cases where the blur metric from FFT analysis is above threshold (because there is some texture in the out-of-focus image) but the camera is clearly not providing useful surveillance footage.

**`temporal_consistency(frame_sequence, timestamps, expected_interval)`**: Computes the blur metric (via `BlurHandler.detect_blur_fft_image()`) for each frame in the sequence and reports the standard deviation. A high blur std dev (e.g., > 5.0) across frames collected at regular intervals indicates autofocus hunting -- the lens cycles between sharp and soft. Also reports mean frame interval and interval jitter (std dev of actual vs expected intervals) as secondary metrics for frame delivery consistency.

### Integration with BaseHealthcheckCamera

`FrameProbe` is invoked from `BaseHealthcheckCamera` during the healthcheck window, after frame collection but before result aggregation:

1. The existing healthcheck flow collects frames for blur/entropy analysis via `camera.get_stream_quality()`.
2. After that call, the same frame buffer (3-10 frames) is passed to `FrameProbe`.
3. Single-frame analyses (`is_black_frame`, `detect_ir_mode`, `edge_density`) run on the most recent frame.
4. Multi-frame analyses (`is_frozen`, `temporal_consistency`) run on the full sequence.
5. `color_histogram_fingerprint` runs on the most recent frame; comparison requires the previous run's fingerprint from DynamoDB.

### Data Model

Results are stored in `healthcheck_data.diagnostics["frame"]`:

```python
healthcheck_data.diagnostics["frame"] = {
    "is_black": False,
    "mean_pixel": 87.3,
    "is_frozen": False,
    "frozen_ssim": 0.42,
    "is_ir_mode": False,
    "ir_std_rg": 28.4,
    "ir_std_rb": 31.2,
    "edge_density": 0.12,
    "color_chi_squared": 0.03,
    "color_fingerprint": [...],  # 96 floats, persisted for next-run comparison
    "blur_std": 2.1,
    "mean_interval": 1.02,
    "interval_jitter": 0.08,
}
```

### Alert Integration

FrameProbe results feed into `StreamQualityHealthcheckRunner` and the alert generator:

- `is_black == True` sets `alert_topic = "video_loss"` with subject "Black frame detected (possible IRcut failure or lens cap)".
- `is_frozen == True` sets `alert_topic = "video_loss"` with subject "Frozen video detected (possible encoder freeze)".
- `is_ir_mode == True` suppresses any concurrent `SCENE_CHANGE` alert for the same camera in the same run.
- `edge_density < 0.01` sets `alert_topic = "camera_aim"` with subject "Camera aimed at featureless surface or severely defocused".
- `color_chi_squared > threshold for 3 runs` sets `alert_topic = "hardware_degradation"`.

### Performance Considerations

FrameProbe operations are lightweight relative to the existing blur/entropy calculations. SSIM on a 1080p frame pair takes ~5ms. Canny edge detection takes ~3ms. Histogram computation takes <1ms. The total additional cost per camera is under 30ms for single-frame analyses plus ~20ms for temporal analyses on a 5-frame sequence. This fits comfortably within the per-camera timeout budget described in [[chm-diagnostics-architecture]].

## Dependencies

- **[[opencv-entity|cv2]] ([[opencv-entity|OpenCV]])** -- Already a dependency of [[actuate-blur]] and [[actuate-movement]].
- **numpy** -- Already a core dependency.
- **[[actuate-blur]]** -- `BlurHandler.detect_blur_fft_image()` for temporal consistency analysis.
- **[[actuate-movement]]** -- `get_delta_noise()` for frozen frame secondary confirmation.
- **No new external dependencies required.**

## Effort Estimate

5-7 days. Breakdown: 2 days for core FrameProbe implementation and unit tests, 1 day for `BaseHealthcheckCamera` integration, 1 day for alert generator wiring and data model changes, 1-2 days for threshold tuning against production frame samples.

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal defining FrameProbe scope
- [[actuate-blur]] -- existing BlurHandler with FFT blur and Shannon entropy
- [[actuate-suddenscenechange]] -- CameraDisturbanceDetector using SIFT matching
- [[actuate-movement]] -- delta_noise and FrameDiffMotionDetector
- [[chm-diagnostics-architecture]] -- BaseHealthcheckCamera orchestration and per-camera timeout
- [[chm-phase4-generic-diagnostics]] -- GenericDiagnostics consuming FrameProbe results
- [[chm-phase7-historical-trending]] -- trending FrameProbe metrics over time
