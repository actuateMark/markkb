---
title: "CHM R&D Opportunities"
type: concept
topic: camera-health-monitoring
tags: [chm, diagnostics, rd, opportunities, roadmap]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# CHM R&D Opportunities

Research and development opportunities for advancing camera health monitoring beyond today's point-in-time, per-camera diagnostic model. These proposals are grounded in the [[chm-diagnostics-gap-analysis|gap analysis]] findings and the capabilities documented in integration component notes.

## 1. Untapped Integration APIs

Several integrations have rich management APIs that CHM does not leverage at all today.

**[[hikcentral-components|HikCentral]]** -- The Artemis API exposes device online/offline status, recording plan health, and storage pool capacity via the HMAC-SHA256 auth in `hikcentral_calls.send_request()`. The existing `subscribe_to_motion()` pattern could extend to device-offline events (131329) and storage warnings for real-time monitoring. Highest-value gap: growing customer segment with established auth module.

**[[eagle-eye-components|Eagle Eye]]** -- Cloud-hosted v3 API provides camera status, bridge health, recording status, and bandwidth per camera -- bypassing VPN/firewall issues. [[eagle-eye-components|eagle_eye_calls]] multi-account proxy tokens enable sweeping health data across reseller hierarchies in one run.

**[[milestone-components|Milestone]]** -- SOAP `GetConfiguration` contains recording server disk usage and device status that `MilestoneService.extract_settings()` ignores. `run_comparison()` detects camera-to-recording-server drift that could surface as a diagnostic signal.

**[[avigilon-components|Avigilon]]** -- Five stub diagnostic methods await implementation. `camera_exists_avigilon()` already queries `/cameras`; extending to extract recording status would be incremental.

**[[video-insight-components|Video Insight]] and [[openeye-components|OpenEye]]** -- Both have REST APIs but no `actuate-integration-calls` modules. Lightweight health-query clients would unlock native diagnostics.

## 2. New Diagnostic Types

The current diagnostic types (connectivity, recording, motion, stream quality, server, blur, scene change) cover the basics, but several high-value diagnostic categories are missing:

**Network latency and jitter** -- [[rtsp-components|AvUrlFramePuller]]'s `TimestampTracker` already detects PTS discontinuities and drift. Exposing inter-frame timing variance as a diagnostic metric would reveal network issues before visible degradation. The per-camera `BandwidthTracker` provides throughput data that could correlate with latency spikes.

**Frame rate trending** -- Track FPS over days/weeks to detect gradual degradation (e.g., 15 FPS drifting to 8 over two weeks signals developing hardware failure). The puller's FPS measurement provides raw data; the gap is persistence and trend analysis.

**Storage capacity monitoring** -- For on-premises VMS integrations with server APIs ([[digital-watchdog-components|DW]], [[milestone-components|Milestone]], [[exacq-components|Exacq]], [[hikcentral-components|HikCentral]]), query disk usage and retention days to prevent silent recording failures from full disks.

**NVR firmware version tracking** -- DW and Milestone APIs expose system versions. Fleet-wide firmware tracking identifies outdated systems with known vulnerabilities. Low-frequency (weekly) with high operational value.

## 3. VLM-Based Visual Quality Assessment

The current image quality pipeline uses FFT-based blur detection (`actuate-blur`) and SIFT-based scene change detection (`actuate-suddenscenechange`). These are effective for binary classification (blurred vs. sharp, scene changed vs. stable) but miss nuanced quality issues.

A VLM could assess quality holistically: partial obstructions (spider webs, condensation, sun glare), exposure issues, IR mode stuck-on during daytime, de-focused-but-not-blurred images, and LED color cast. One inference per camera per run produces a rich quality description at minimal cost. For scene change, a VLM could explain _what_ changed (construction, vegetation, camera shift) to reduce false-positive alerts.

## 4. Cross-Camera Correlation

Today each camera is diagnosed independently. When multiple cameras on the same NVR or network segment fail simultaneously, CHM creates N independent incidents. Cross-camera correlation would:

- **Detect NVR failures** -- If all cameras on a [[salient-components|Salient]] server or [[milestone-components|Milestone]] recording server go offline together, diagnose the NVR rather than N cameras. The Milestone `run_comparison()` already groups cameras by recording server; this grouping could feed correlation logic.
- **Detect network failures** -- Cameras sharing an IP subnet that fail together likely indicate a switch or VPN failure.
- **Reduce alert noise** -- A single "NVR offline" alert replacing 50 "camera offline" alerts dramatically improves operator experience.
- **Diagnose bridge failures** -- For [[eagle-eye-components|Eagle Eye]], all cameras behind a bridge failing simultaneously is a bridge issue, not a camera issue.

## 5. Historical Trending and Degradation Detection

CHM currently operates as a point-in-time snapshot system: each healthcheck run evaluates the current state and either creates or resolves incidents. Adding temporal analysis would enable:

- **Degradation curves** -- Track blur scores, FPS, and connectivity rates over weeks to catch developing hardware issues.
- **Baseline deviation** -- Per-camera baselines from "healthy" periods; alert on N-sigma deviations even when below static thresholds.
- **Seasonal patterns** -- Learn predictable degradation (IR fog in cold, sun glare at specific hours) to suppress false alerts.

The DynamoDB Healthcheck table already stores per-camera state; extending with time-series attributes would enable trending without major rearchitecture.

## 6. Integration with Site Context Agent

The [[autopatrol-integration-components|AutoPatrol]] ecosystem includes the Watchman Site Context Agent, which maintains real-time understanding of site layout, camera roles, and operational context. Integrating CHM with this agent would enable:

- **Priority-based alerting** -- Failed perimeter cameras at high-value sites escalate faster than interior cameras at low-risk sites.
- **Operational awareness** -- Suppress false scene-change alerts during known construction or reconfiguration.
- **Proactive predictions** -- Combine health trends with site context for predictive alerting.

The [[vch-components|VCH]] integration already bridges CHM and AutoPatrol via `VCHAlertSender`; extending this to consume site context is a natural evolution.
