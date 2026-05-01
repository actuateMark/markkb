---
title: "Enhanced CHM Diagnostics: Tooling Architecture Proposal"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, tooling, proposal, r-and-d, reliability, rtsp]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase3-cross-camera-correlation.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase5-frame-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase6-smtp-ailink-diagnostics.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase7-historical-trending.md
  - topics/camera-health-monitoring/reading-list.md
  - topics/personal-notes/notes/daily/2026-04-20.md
incoming_updated: 2026-05-01
---

# Enhanced CHM Diagnostics: Tooling Architecture Proposal

## Problem Statement

Current CHM diagnostics are shallow. [[rtsp-deep-dive|RTSP]] connectivity does a single HTTP GET (not even an [[rtsp-deep-dive|RTSP]] probe). SMTP/AILink/generic integrations fall through to `DummyDiagnostics` -- a complete no-op. When a camera goes offline, the system reports THAT it's down but not WHY. Operators get "Camera offline" emails with no actionable root cause.

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
| `tls_check(ip, port)` | Cert validity, expiry, **chain completeness** (detect missing intermediate), CA trust path. Distinguishes: expired / self-signed / chain-incomplete / hostname-mismatch / wrong-time-on-pod | HTTPS NVR APIs, WSS stream endpoints (e.g. `dev.powerplus.com`) |
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
| Codec/profile | `video_stream.codec_context.codec.name` | [[h264-deep-dive|h264]], h265, mjpeg |
| Resolution | `codec_context.width/height` | Already in puller |
| Frame rate | `video_stream.average_rate` | Expected vs actual |
| [[gop-keyframe-fundamentals|Keyframe interval]] | `_avdiscard_keyframe_count` | [[gop-keyframe-fundamentals|GOP]] analysis |
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
- TCP probe to port 554 + [[rtsp-deep-dive|RTSP]] DESCRIBE (actual protocol test)
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

## Case Studies Motivating the Proposal (Post-Deploy 2026-04-20)

Two concrete failure modes surfaced during PR #1654 post-deploy investigation that exactly match the "reports THAT it's down but not WHY" problem. Both are worth preserving here as the project's north-star use cases.

### Case 1: SSL cert-verify on `dev.powerplus.com` — see [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]]

- **Symptom in healthcheck output:** 23 cameras on one site, `broken_stream: true`, `resolution: 0`, `fps: 10000`, `is_blank_frame: true`, `current_run_status: unchanged` for 37 days — reads exactly like "customer's cameras are offline."
- **Actual root cause:** WebSocket TLS handshake fails because `dev.powerplus.com` serves leaf cert only (no intermediate). Python's `ssl` module does not chase AIA. 3,870 attempts in 7 days, 100% failing.
- **How it was diagnosed:** ran `openssl s_client -connect dev.powerplus.com:443 -servername dev.powerplus.com -showcerts` — returned chain length 1 + `Verify return code: 21`, immediately identifying missing-intermediate as the class. ~2 minutes of diagnosis once the procedure was known.
- **What this proposal would have told us automatically:** `NetworkProbe.tls_check` running on first broken_stream event would have classified this as "chain-incomplete: leaf signed by Sectigo DV R36, intermediate missing" in the healthcheck diagnostic output. Operator sees actionable root cause immediately; no "camera appears offline for 37 days" false alarm.

### Case 2: streamId-null rejection on `raise_patrol_alert` — see [[2026-04-20_streamid-null-patrol-alert-bug]] / GH#1656

- **Symptom:** `raise_patrol_alert failed: status=400 $.streamId could not be converted to System.Guid`. 66 failures per week on `:stage`; 2 per 72h on `:latest` post-merge.
- **Actual root cause:** `streamId` is sourced from `get_patrol_stream`, which is the same call that failed. Architectural dead-lock between us and Immix's schema. Needs backend coordination.
- **How it was diagnosed:** code-trace from emission site up through the library, then fleet-wide cross-tag FACET to distinguish "new on :latest" (misleading) vs "pre-existing on :stage" (accurate). The `/bug-dive` skill codified this 8-phase methodology.
- **What this proposal would NOT solve:** this one isn't in the NetworkProbe / StreamProbe / FrameProbe scope — it's an API-contract failure at the alert-dispatch layer, not a stream-acquisition layer. But it's a motivating example of the broader thesis: **the customer-visible "cameras offline" signal can be any of {network, TLS, DNS, API-contract, state-propagation, actual camera down}**, and today we can't tell them apart from a customer-facing healthcheck payload.

### Diagnostic Procedure (reusable — added to `/bug-dive` skill + this proposal)

When you see an SSL cert-verify error in any connector log AND healthcheck sentinel values (`resolution: 0`, `fps: 10000`, `is_blank_frame: true`):

```bash
echo | openssl s_client -connect <host>:<port> -servername <host> -showcerts 2>&1 | head -80
```

Decision tree:
- Chain length 1 + `Verify return code: 21` → **server missing intermediate** (server-side fix: chain completion)
- Chain length > 1 + `Verify return code: 19 (self-signed in chain)` → self-signed / private-CA (client-side CA bundle fix)
- Chain length > 1 + `Verify return code: 0 (ok)` → cert is fine; check pod clock skew, CA bundle age
- Connection refused / timeout → not a cert issue; TCP / firewall / DNS

This is the procedure the proposed `NetworkProbe.tls_check` should implement as structured output. Classifying the failure mode in the healthcheck payload — instead of emitting sentinel values — is the delta between the current system and the post-proposal system.

### Lessons Feeding the Architecture

1. **[[sentinel-components|Sentinel]] values (resolution=0, fps=10000) are the root problem.** They let the whole stack lie about the reason for failure — they flatten every possible cause to "unknown camera offline." Any diagnostic output that replaces them should be structured and layered (DNS / TCP / TLS / application) rather than a single boolean.
2. **Client-visible "nothing happened" ≠ "nothing was attempted."** TLS handshakes that fail don't reach application-level logs on either side. The diagnostic needs to record *attempt* telemetry, not just *success* telemetry. `NetworkProbe` cascade from DNS → TCP → TLS → application should log each stage's outcome, not just the final result.
3. **Cross-team diagnostics need machine-readable classification.** When the failure is on a third-party endpoint (PowerPlus, Immix), we need to hand them a concrete fingerprint ("leaf-only cert chain, missing Sectigo DV R36 intermediate") not "camera appears offline." `NetworkProbe.tls_check` should emit a classification token (`TLS_CHAIN_INCOMPLETE`, `TLS_EXPIRED`, `TLS_SELF_SIGNED`, `TLS_HOSTNAME_MISMATCH`, `TLS_OK`) that can be included in an escalation ticket.

## Implementation Priority

| Phase | What | Effort | Impact |
|-------|------|--------|--------|
| **1** | NetworkProbe + enhanced [[rtsp-deep-dive|RTSP]] connectivity (TCP+WG+[[rtsp-deep-dive|RTSP]] DESCRIBE) | 3-5 days | High -- answers "why is it down?" |
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

Logged to [[new-relic|New Relic]] for queryability. Used by alert generators for actionable email subjects: "WireGuard tunnel to Site X is down" instead of "Camera offline".

## Related

- [[chm-diagnostics-architecture]] -- current architecture
- [[chm-diagnostics-gap-analysis]] -- per-integration gap matrix
- [[chm-rd-opportunities]] -- broader R&D directions
- [[actuate-wireguard]] -- WireGuard tunnel health data
- [[actuate-blur]] -- existing blur/entropy analysis
- [[actuate-suddenscenechange]] -- SIFT scene change
- [[actuate-pullers]] -- stream metadata already collected
- [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]] -- case study 1: TLS chain incomplete misread as camera offline
- [[2026-04-20_streamid-null-patrol-alert-bug]] -- case study 2: API-contract dead-lock at alert dispatch layer
- [[mark-todos]] §2d -- AP/VCH alert-flow diagnostic-enhancement workstream (parent tracking for both cases)
- [[performance-optimization-landscape]] -- resource budget considerations
