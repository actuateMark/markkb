---
title: "Enhanced CHM Diagnostics: Tooling Architecture Proposal"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, tooling, proposal, r-and-d, reliability]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Enhanced CHM Diagnostics: Tooling Architecture Proposal

## Problem Statement

Current CHM diagnostics are shallow. RTSP connectivity does a single HTTP GET (not even an RTSP probe). SMTP/AILink/generic integrations fall through to `DummyDiagnostics` -- a complete no-op. When a camera goes offline, the system reports THAT it's down but not WHY. Operators get "Camera offline" emails with no actionable root cause.

Meanwhile, the puller layer already collects rich stream metadata (codec, FPS, resolution, bandwidth via `BandwidthTracker`, keyframe intervals) that never surfaces to diagnostics.

## Proposed Architecture: Diagnostic Toolkit

Three shared utility classes, invoked by per-integration `BaseDiagnostics` subclasses when basic checks fail:

### NetworkProbe (new, `healthcheck/alerts/diagnostics/tools/network_probe.py`)

Standard library only (`socket`, `ssl`, `subprocess`). Diagnoses WHY a camera is unreachable:

| Method | What It Does | When Used |
|--------|-------------|-----------|
| `dns_resolve(hostname)` | Resolution time, IP match validation | Connectivity failure |
| `tcp_probe(ip, port, timeout)` | Port reachability + latency. Classify: refused (service down), timeout (firewall), unreachable (routing) | Connectivity failure |
| `ping(ip, count=3)` | RTT, jitter, packet loss | TCP timeout |
| `tls_check(ip, port)` | Cert validity, expiry | HTTPS NVR APIs |
| `wireguard_check(camera_ip)` | Tunnel last_handshake via [[actuate-wireguard]] DAO. Stale > 180s = tunnel dead | Camera on WG subnet |

**Diagnostic cascade for connectivity failures:**
```
Camera unreachable
  -> DNS check (fails? -> "DNS cannot resolve hostname")
  -> TCP port probe (refused? -> "Service not running")
  -> TCP timeout? -> WireGuard tunnel check
    -> handshake stale? -> "WireGuard tunnel down"
    -> handshake fresh? -> ping + traceroute
      -> ping fails? -> "Camera IP unreachable"
      -> ping high latency? -> "Network path degraded (RTT: Xms)"
  -> RTSP DESCRIBE (401? -> "Credentials invalid", 453? -> "Insufficient bandwidth")
```

### StreamProbe (new, wraps puller metadata)

Surfaces data the puller already collects but diagnostics never access:

| Metric | Source | Value |
|--------|--------|-------|
| Codec/profile | `video_stream.codec_context.codec.name` | h264, h265, mjpeg |
| Resolution | `codec_context.width/height` | Already in puller |
| Frame rate | `video_stream.average_rate` | Expected vs actual |
| Keyframe interval | `_avdiscard_keyframe_count` | GOP analysis |
| Bandwidth | `BandwidthTracker.bytes_per_window` | Already tracked, never used |
| Decode error rate | Count `InvalidDataError` vs total packets | Packet loss proxy |
| Frame jitter | PTS gap std dev vs expected 1/fps | Network congestion signal |
| Time-to-first-frame | Already tracked (`frame_not_sent`) | Not reported as metric |
| Reconnection count | Track `connect_stream()` calls per run | Stream stability |

### FrameProbe (extends [[actuate-blur]] + [[actuate-suddenscenechange]])

| Analysis | Method | Detects |
|----------|--------|---------|
| Black frame | Mean pixel < 10 | IRcut stuck, lens cap, video loss |
| Frozen frame | SSIM > 0.999 across sequence | Encoder freeze, NVR replay loop |
| IR mode | `std(R-G)` and `std(R-B)` < 5 | Auto day/night switch (suppress false scene changes) |
| Color drift | Chi-squared on 32-bin RGB histogram | Lens damage, cable degradation, color channel loss |
| Edge density | Canny edge % of frame area | Wall/ceiling aim, severe defocus |
| Temporal consistency | Blur metric std dev across frame sequence | Intermittent focus issues |

## Integration-Specific Enhancements

### RTSP (replace HTTP GET with real diagnostics)
- TCP probe to port 554 + RTSP DESCRIBE (actual protocol test)
- Stream metadata extraction from puller
- WireGuard tunnel check for tunneled cameras

### SMTP/AILink (replace DummyDiagnostics)
- Frame recency check: `time.time() - last_frame_timestamp`. No frames for 1 hour = alert
- Frame size validation: JPEG < 5KB = corrupt/incomplete
- SQS message latency: send time vs receive time gap

### Generic (replace DummyDiagnostics for all unknown types)
- TCP probe + frame recency + basic stream analysis
- At minimum, every integration gets network-level diagnostics

## Cross-Camera Correlation

Post-processing step in `BaseHealthcheckCamera.send_healthcheck_results()`:

1. **NVR correlation**: Group cameras by `base_url`/`server_ip`. If >50% fail, root cause = NVR, not cameras. Set `alert_topic = "nvr"`.
2. **WireGuard correlation**: Group by tunnel subnet. If all cameras on a tunnel fail, set `alert_topic = "wireguard_tunnel"`.
3. **Subnet correlation**: Group by /24. If entire subnet fails but others healthy, set `alert_topic = "network_switch"`.
4. **Temporal correlation**: Track if failures coincide with midnight reboots, DHCP renewal, DST transitions.

## Implementation Priority

| Phase | What | Effort | Impact |
|-------|------|--------|--------|
| **1** | NetworkProbe + enhanced RTSP connectivity (TCP+WG+RTSP DESCRIBE) | 3-5 days | High -- answers "why is it down?" |
| **2** | StreamProbe (expose puller metadata to diagnostics) | 2-3 days | Medium -- pure data pass-through |
| **3** | Cross-camera NVR/WG correlation in send_healthcheck_results | 2-3 days | High -- reduces alert noise |
| **4** | GenericDiagnostics replacing DummyDiagnostics | 1-2 days | Medium -- coverage for 24 integrations |
| **5** | FrameProbe (black/frozen/IR/drift) | 1 week | Medium -- visual quality analysis |
| **6** | SMTP/AILink diagnostics | 2-3 days | Medium -- frame recency + SQS latency |
| **7** | Historical trending (degradation detection) | 1-2 weeks | Medium-High -- proactive alerting |

## Data Storage

Diagnostic results stored in the incident's `data` dict (already freeform, used by DW diagnostics):
```python
healthcheck_data.diagnostics = {
    "network": {"dns_ok": True, "tcp_554_ok": False, "tcp_554_error": "timeout", "ping_rtt_ms": 45},
    "stream": {"codec": "h264", "fps": 15.0, "bitrate_kbps": 2048},
    "frame": {"is_ir_mode": False, "edge_density": 0.12},
    "correlation": {"nvr_group": "192.168.1.100", "nvr_cameras_down": 5, "nvr_cameras_total": 8}
}
```

Logged to New Relic for queryability. Used by alert generators for actionable email subjects: "WireGuard tunnel to Site X is down" instead of "Camera offline".

## Related

- [[chm-diagnostics-architecture]] -- current architecture
- [[chm-diagnostics-gap-analysis]] -- per-integration gap matrix
- [[chm-rd-opportunities]] -- broader R&D directions
- [[actuate-wireguard]] -- WireGuard tunnel health data
- [[actuate-blur]] -- existing blur/entropy analysis
- [[actuate-suddenscenechange]] -- SIFT scene change
- [[actuate-pullers]] -- stream metadata already collected
- [[performance-optimization-landscape]] -- resource budget considerations
