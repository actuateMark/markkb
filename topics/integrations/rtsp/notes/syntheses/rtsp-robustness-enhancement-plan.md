---
title: "RTSP Robustness Enhancement Plan"
type: synthesis
topic: integrations/rtsp
tags: [synthesis, rtsp, robustness, reliability, observability, proposal]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# RTSP Robustness Enhancement Plan

Comprehensive analysis of the RTSP integration (the default/foundational integration type) with specific enhancement proposals ranked by impact/effort.

## Quick Reference: Top 3 Wins

1. **Exponential backoff with jitter** on reconnect -- 1-2 hours, prevents thundering herd
2. **Replace RTSPDiagnostics HTTP GET with TCP+RTSP DESCRIBE** -- 4-6 hours, answers "why is it down?"
3. **RTSP error code classification** (401/403/453/461) -- 4-6 hours, stops futile retries

## Current Capabilities Inventory

See full report for details. Key facts:
- **7 puller variants** (AvUrl, GstUrl, MotionBased x3, OnOffMotion, legacy OpenCV)
- **Transport**: Hardcoded TCP, no UDP fallback
- **Retry**: Fixed 60s on initial failure, 5s on stream loss. No backoff, no jitter.
- **HW acceleration**: CUDA/NVDEC, VideoToolbox, VAAPI, AMF (auto-detected)
- **AVDiscard optimization**: Keyframe-only mode when native FPS > 1.5x target
- **BandwidthTracker**: Active but only reported every 5 min to NR + DynamoDB
- **Metadata extracted but not surfaced**: codec, FPS, keyframe intervals, connection duration, consecutive failures, PTS discontinuities, decode errors

## Known Weaknesses

### Silent Failures
- `read_frame()` in UrlFramePuller returns `(None, None)` silently on errors
- Bare `except:` blocks swallow all errors in multiple locations
- BandwidthTracker loses partial window data on disconnect

### Missing Error Classification
- All stream errors treated identically (ConnectionRefused, Timeout, InvalidData, PermissionError)
- No RTSP error code handling (401, 403, 453, 454, 461 all land in generic handler)
- RTSPDiagnostics does HTTP GET instead of RTSP probe

### Reconnection Issues
- Fixed retry interval causes thundering herd on NVR restart (100 cameras × 60s = synchronized storm)
- No jitter on any reconnection path
- `unable_to_connect_alarm` fires once and never resets

## Enhancement Tiers

### Tier 1: Do Immediately (hours, high impact)

| Enhancement | Effort | Impact |
|-------------|--------|--------|
| Exponential backoff with jitter | 1-2 hrs | Prevents thundering herd |
| Expose keyframe interval to NR | 1-2 hrs | Detects misconfigured cameras |
| Expose connection metrics to NR (duration, failures, reconnections) | 2-3 hrs | Fleet-wide health dashboards |
| Codec/profile/level extraction | 2-3 hrs | H.265 performance diagnosis |
| Fix bare except: blocks | 30 min | Stop swallowing errors |
| Add `get_stream_diagnostics()` to AvUrlFramePuller | 2-3 hrs | Enables all Phase 2 CHM work |

### Tier 2: Do Next (days, high impact)

| Enhancement | Effort | Impact |
|-------------|--------|--------|
| RTSP error code classification (401/403/453/461) | 4-6 hrs | Stop futile retries |
| Network error classification (DNS/refused/timeout) | 3-4 hrs | Actionable diagnostics |
| Replace RTSPDiagnostics with TCP+RTSP DESCRIBE | 4-6 hrs | Real connectivity testing |
| Transport fallback (TCP→UDP→interleaved) | 4-6 hrs | Fix ~5% connection failures |
| Connection health scoring (0-100) | 1-2 days | Proactive degradation detection |
| Black/frozen frame detection at puller level | 4-6 hrs | Catch visual failures early |

### Tier 3: Plan (days-weeks, medium-high impact)

| Enhancement | Effort | Impact |
|-------------|--------|--------|
| Graceful degradation ladder (reduce FPS before disconnect) | 2-3 days | Maintain partial service |
| Dead camera classification (rebooting vs removed vs misconfigured) | 1-2 days | Reduce false alerts |
| Adaptive FPS based on stream conditions | 2-3 days | Resource optimization |
| Pre-flight RTSP DESCRIBE validation | 4-6 hrs | Faster failure detection |
| Cross-camera NVR correlation | 2-3 days | 60-80% alert noise reduction |

### Tier 4: Research (weeks, medium impact)

| Enhancement | Effort | Impact |
|-------------|--------|--------|
| Keepalive for motion-gated cameras | 3-5 days | Eliminate 2-3s connection latency |
| Connection pooling for multi-stream NVRs | 1-2 weeks | Reduce TCP connections 60-80% |
| Shared NVDEC pool per shard | 1 week | GPU resource efficiency |

## RTSP Error Code Recovery Strategy

| Code | Meaning | Current Behavior | Proposed |
|------|---------|------------------|----------|
| 401 | Bad credentials | Retry forever | **Stop retrying**, alert "credentials_invalid" |
| 403 | IP blocked/license exceeded | Retry forever | **Stop retrying**, alert "access_forbidden" |
| 404 | Bad stream path | Retry forever | **Stop retrying**, alert "stream_not_found" |
| 453 | Insufficient bandwidth | Retry forever | **Backoff**, try lower-quality stream |
| 454 | Session expired | Retry in 5s | **Reconnect immediately** (correct) |
| 461 | Unsupported transport | Retry with same transport | **Switch to UDP** |

## Graceful Degradation Ladder

1. **Normal**: Full FPS, motion detection active
2. **Mild** (>5% decode errors): Drop to keyframe-only (AVDiscard NONKEY)
3. **Moderate** (>20% errors): Reduce to 1 FPS, disable motion detection
4. **Severe** (>50% errors): Drop to 0.2 FPS (1 frame/5s), extensive logging
5. **Dead** (>30 min no frames): Stop retrying, alert operator

## Unsurfaced Metadata (Available Today)

| Metric | Code Location | Why It Matters |
|--------|--------------|----------------|
| Codec profile/level | `video_stream.codec_context.profile` | Optimization recommendations |
| Keyframe interval | `_avdiscard_keyframe_intervals` | Detect misconfigured GOP |
| Consecutive failures | `_consecutive_failures` | Chronic camera/network issues |
| Connection duration | `_last_connection_duration` | Network/DNS quality |
| PTS discontinuities | `TimestampTracker.discontinuity_count` | Stream stability |
| Decode error rate | Count exceptions in decode path | Packet loss proxy |
| Time-to-first-frame | Calculable but not tracked | Connection quality |
| Reconnection count | `_connection_count` (exists for snapshots) | Stream reliability |

## Related KB Notes

- [[chm-phase1-network-probe]] -- NetworkProbe directly enhances RTSP diagnostics
- [[chm-phase2-stream-probe]] -- StreamProbe surfaces all unsurfaced metadata above
- [[chm-phase5-frame-probe]] -- FrameProbe adds visual quality analysis
- [[performance-optimization-landscape]] -- Pipeline-wide optimization context
- [[adaptive-temperature]] -- Proposed context-aware FPS (complements adaptive FPS)
- [[memory-management]] -- Memory constraints affecting puller design
- [[rtsp-components]] -- Current RTSP component inventory
