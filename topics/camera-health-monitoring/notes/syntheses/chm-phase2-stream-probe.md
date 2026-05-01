---
title: "CHM Phase 2: StreamProbe -- Exposing Stream Metadata to Diagnostics"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-2]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase3-cross-camera-correlation.md
  - topics/integrations/rtsp/notes/entities/rtsp-enhancement-issues.md
  - topics/integrations/rtsp/notes/syntheses/rtsp-robustness-enhancement-plan.md
incoming_updated: 2026-05-01
---

# CHM Phase 2: StreamProbe -- Exposing Stream Metadata to Diagnostics

## Problem

The [[actuate-pullers|AvUrlFramePuller]] already collects rich stream metadata -- codec, frame rate, resolution, bandwidth, keyframe intervals, PTS discontinuities, decode errors, reconnection frequency -- but the diagnostic layer never sees any of it. The data exists in the puller's internal state and is logged or sent to [[new-relic|New Relic]] as isolated metrics, but it is never aggregated into a structured object available to `BaseDiagnostics` subclasses or healthcheck runners.

Today, the `StreamQualityHealthcheckRunner` evaluates stream quality using only blur score (FFT-based via [[actuate-blur]]) and entropy. It has no access to codec type, actual vs. expected FPS, bitrate, keyframe structure, or any transport-layer health signals. This means CHM cannot detect:

- A camera silently switching from [[h264-deep-dive|H.264]] to [[mjpeg-and-still-image-formats|MJPEG]] (massively increasing bandwidth)
- FPS dropping from 15 to 3 due to NVR load or bandwidth saturation
- [[gop-keyframe-fundamentals|Keyframe interval]] degradation causing decode artifacts
- Bandwidth spikes indicating stream misconfiguration
- Repeated reconnections indicating an unstable transport path

## Proposed Solution

Introduce a `StreamProbe` class that reads metadata from an `AvUrlFramePuller` instance (without modifying the puller code) and produces structured `StreamMetadata` and `StreamHealth` dataclass objects. These are stored in `healthcheck_data.diagnostics["stream"]` for use by alert generators and [[new-relic|New Relic]] logging.

## Detailed Design

### What AvUrlFramePuller Already Exposes

From source code analysis of `actuate_pullers.url.av_url_puller.AvUrlFramePuller` and `actuate_pullers.shared.base_puller.BasePuller`:

| Field / Method | Source | Type | Notes |
|---|---|---|---|
| `video_stream.codec_context.codec.name` | [[pyav-entity|PyAV]] stream after `connect_stream()` | `str` | `"h264"`, `"hevc"`, `"mjpeg"` |
| `video_stream.codec_context.width` | [[pyav-entity|PyAV]] codec context | `int` | Pixel width |
| `video_stream.codec_context.height` | [[pyav-entity|PyAV]] codec context | `int` | Pixel height |
| `video_stream.codec_context.pix_fmt` | [[pyav-entity|PyAV]] codec context | `str` | `"yuv420p"`, `"yuvj420p"` |
| `video_stream.codec_context.profile` | [[pyav-entity|PyAV]] codec context | `str` | `"High"`, `"Main"`, `"Baseline"` |
| `video_stream.average_rate` | [[pyav-entity|PyAV]] stream | `Fraction` | Declared FPS from stream header |
| `video_stream.time_base` | [[pyav-entity|PyAV]] stream | `Fraction` | Timestamp resolution |
| `bandwidth_tracker.get_bandwidth_kbps()` | `BandwidthTracker` | `float` | Current window bandwidth in kbps |
| `bandwidth_tracker.get_last_bandwidth_kbps()` | `BandwidthTracker` | `float` | Last reported window bandwidth |
| `bandwidth_tracker.get_total_bytes()` | `BandwidthTracker` | `int` | Total bytes since puller start |
| `stream_quality.resolution` | `StreamQualityPacket` | `int` | Set from `frame.shape[0]` after first frame |
| `stream_quality.fps` | `StreamQualityPacket` | `float` | Measured FPS from `run_healthcheck()` frame count |
| `_avdiscard_keyframe_count` | AVDiscard measurement | `int` | Keyframes counted during measurement window |
| `_avdiscard_packet_count` | AVDiscard measurement | `int` | Total packets in measurement window |
| `_avdiscard_measured_native_fps` | AVDiscard measurement | `float` | Measured native FPS from packet rate |
| `_avdiscard_keyframe_intervals` | AVDiscard measurement | `List[float]` | Intervals between keyframes in seconds |
| `_consecutive_failures` | Connection tracking | `int` | Consecutive connection failure count |
| `_connection_count` | Connection tracking | `int` | Total connection attempts |
| `_last_connection_duration` | Connection tracking | `float` | Seconds to establish last connection |
| `timestamp_tracker.discontinuity_count` | `TimestampTracker` | `int` | PTS discontinuity count |
| `connectivity.broken_stream` | `ConnectivityPacket` | `bool` | Whether stream connection failed |
| `connectivity.frame_returned` | `ConnectivityPacket` | `bool` | Whether at least one frame was decoded |

### StreamMetadata Dataclass

```python
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class StreamMetadata:
    """Static stream properties extracted from codec context and stream headers."""
    codec: Optional[str] = None                # "h264", "hevc", "mjpeg"
    profile: Optional[str] = None              # "High", "Main", "Baseline"
    resolution_width: Optional[int] = None
    resolution_height: Optional[int] = None
    pix_fmt: Optional[str] = None              # "yuv420p", "yuvj420p"
    fps_declared: Optional[float] = None       # from video_stream.average_rate
    fps_measured: Optional[float] = None       # from run_healthcheck frame count or _avdiscard_measured_native_fps
    bitrate_kbps: Optional[float] = None       # from bandwidth_tracker.get_last_bandwidth_kbps()
    keyframe_interval_s: Optional[float] = None  # avg from _avdiscard_keyframe_intervals
    gop_size_packets: Optional[int] = None     # estimated from packet_count / keyframe_count
    connection_time_ms: Optional[float] = None # _last_connection_duration * 1000
```

### StreamHealth Dataclass

```python
@dataclass
class StreamHealth:
    """Dynamic stream health indicators derived from puller runtime state."""
    fps_deviation_pct: Optional[float] = None     # abs(measured - declared) / declared * 100
    reconnection_count: int = 0                    # _consecutive_failures or _connection_count - 1
    pts_discontinuity_count: int = 0               # timestamp_tracker.discontinuity_count
    time_to_first_frame_ms: Optional[float] = None # measured during run_healthcheck
    bandwidth_kbps: Optional[float] = None         # current window bandwidth
    bandwidth_total_bytes: Optional[int] = None    # total bytes received
    broken_stream: bool = False                    # connectivity.broken_stream
    frame_returned: bool = False                   # connectivity.frame_returned
```

### StreamProbe Class

```python
class StreamProbe:
    """Reads stream metadata from an AvUrlFramePuller without modifying puller code.

    All data is extracted via public attributes and property accessors on the
    puller instance. No monkey-patching or internal state mutation.
    """

    @staticmethod
    def extract_metadata(puller) -> StreamMetadata:
        """Extract static stream properties from a puller after connection."""
        meta = StreamMetadata()

        # Codec context fields (available after connect_stream)
        video_stream = getattr(puller, '_avdiscard_video_stream', None)
        if video_stream and video_stream.codec_context and video_stream.codec_context.codec:
            ctx = video_stream.codec_context
            meta.codec = ctx.codec.name
            meta.profile = getattr(ctx, 'profile', None)
            meta.resolution_width = ctx.width
            meta.resolution_height = ctx.height
            meta.pix_fmt = getattr(ctx, 'pix_fmt', None)
            meta.fps_declared = float(video_stream.average_rate) if video_stream.average_rate else None

        # Measured FPS from AVDiscard or stream_quality
        meta.fps_measured = getattr(puller, '_avdiscard_measured_native_fps', None)
        if meta.fps_measured is None and hasattr(puller, 'stream_quality'):
            meta.fps_measured = getattr(puller.stream_quality, 'fps', None)

        # Bandwidth
        if hasattr(puller, 'bandwidth_tracker'):
            meta.bitrate_kbps = puller.bandwidth_tracker.get_last_bandwidth_kbps()

        # Keyframe interval from AVDiscard measurement
        intervals = getattr(puller, '_avdiscard_keyframe_intervals', [])
        if intervals:
            meta.keyframe_interval_s = sum(intervals) / len(intervals)

        kf_count = getattr(puller, '_avdiscard_keyframe_count', 0)
        pkt_count = getattr(puller, '_avdiscard_packet_count', 0)
        if kf_count > 0:
            meta.gop_size_packets = pkt_count // kf_count

        # Connection time
        conn_dur = getattr(puller, '_last_connection_duration', None)
        if conn_dur:
            meta.connection_time_ms = conn_dur * 1000

        return meta

    @staticmethod
    def extract_health(puller) -> StreamHealth:
        """Extract dynamic health indicators from a puller after healthcheck run."""
        health = StreamHealth()
        health.reconnection_count = getattr(puller, '_consecutive_failures', 0)
        health.broken_stream = getattr(puller.connectivity, 'broken_stream', False)
        health.frame_returned = getattr(puller.connectivity, 'frame_returned', False)

        if hasattr(puller, 'bandwidth_tracker'):
            health.bandwidth_kbps = puller.bandwidth_tracker.get_bandwidth_kbps()
            health.bandwidth_total_bytes = puller.bandwidth_tracker.get_total_bytes()

        # PTS discontinuities -- only available if TimestampTracker was instantiated
        # (it's a local variable in run_healthcheck, not a puller attribute,
        # so we'd need to stash it on the puller during the HC run)
        health.pts_discontinuity_count = 0  # TODO: requires storing tracker on puller

        return health
```

### How StreamProbe Reads Without Modifying the Puller

`StreamProbe` uses `getattr()` with fallback defaults on all puller attributes. It accesses only public properties (`connectivity`, `stream_quality`, `bandwidth_tracker`) and name-mangled internal state (`_avdiscard_*`, `_consecutive_failures`, `_last_connection_duration`) via Python's standard attribute access. No puller code changes are required for Phase 2.

The one exception is `TimestampTracker.discontinuity_count` -- currently a local variable inside `run_healthcheck()`. A minimal one-line change to stash the tracker as `self._timestamp_tracker` on the puller would expose this field. This is the only puller modification proposed.

## Integration

### StreamQualityHealthcheckRunner Enhancement

The existing `streamquality_healthcheck_runner.py` gains access to `StreamMetadata` and `StreamHealth` in its `generate()` method. Instead of evaluating quality solely from blur and entropy, it can now factor in FPS deviation, bitrate anomalies, and codec changes.

### New Alert Types

| Condition | Detection Logic | Alert Message |
|---|---|---|
| FPS drop | `fps_measured < fps_declared * 0.5` | "Camera FPS dropped from 15 to 3 (expected: 15)" |
| Codec change | `codec != expected_codec` (stored from previous healthy run) | "Codec changed from [[h264-deep-dive|H.264]] to [[mjpeg-and-still-image-formats|MJPEG]]" |
| Bandwidth spike | `bitrate_kbps > threshold_kbps` (configurable per site) | "Camera bandwidth 8500 kbps exceeds threshold (2000 kbps)" |
| Keyframe degradation | `keyframe_interval_s > 10.0` | "[[gop-keyframe-fundamentals|Keyframe interval]] 15.2s (expected <4s) -- decode quality degraded" |
| Unstable connection | `reconnection_count >= 3` | "Camera reconnected 5 times during healthcheck -- unstable transport" |

## Data Model

Stored in `healthcheck_data.diagnostics["stream"]`:

```python
healthcheck_data.diagnostics["stream"] = {
    "codec": "h264",
    "profile": "High",
    "resolution": "1920x1080",
    "pix_fmt": "yuv420p",
    "fps_declared": 15.0,
    "fps_measured": 14.8,
    "fps_deviation_pct": 1.3,
    "bitrate_kbps": 2048.5,
    "keyframe_interval_s": 2.0,
    "gop_size_packets": 30,
    "connection_time_ms": 1250.0,
    "reconnection_count": 0,
    "pts_discontinuities": 0,
    "broken_stream": False,
    "frame_returned": True
}
```

## Effort Estimate

2-3 days, broken down as:
- Day 1: `StreamMetadata` and `StreamHealth` dataclasses, `StreamProbe.extract_metadata()` and `extract_health()`, unit tests with mock pullers
- Day 2: Wire into `StreamQualityHealthcheckRunner`, populate `diagnostics["stream"]`, add new alert conditions
- Day 3: Integration test, [[new-relic|New Relic]] logging, alert template updates for new stream-quality alert types

## Files to Create/Modify

### Create
- `vms-connector/healthcheck/alerts/diagnostics/tools/stream_probe.py` -- `StreamProbe`, `StreamMetadata`, `StreamHealth`
- `vms-connector/test_vms/test_stream_probe.py`

### Modify
- `vms-connector/healthcheck/alerts/diagnostics/runners/streamquality_healthcheck_runner.py` -- invoke `StreamProbe.extract_metadata()` and `extract_health()` in `generate()`
- `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py` -- one-line change: `self._timestamp_tracker = timestamp_tracker` in `run_healthcheck()` to expose discontinuity count
- `vms-connector/camera/shared/base_healthcheck_camera.py` -- populate `healthcheck_data.diagnostics["stream"]` in `start_healthcheck_job()` after puller completes

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal with full architecture overview
- [[chm-phase1-network-probe]] -- Phase 1: network-layer root cause diagnosis
- [[chm-phase3-cross-camera-correlation]] -- Phase 3: cross-camera failure grouping
- [[actuate-pullers]] -- AvUrlFramePuller, BandwidthTracker, TimestampTracker source
- [[chm-diagnostics-architecture]] -- current diagnostic runner and dispatch patterns
- [[chm-rd-opportunities]] -- broader opportunities including FPS trending and degradation detection
