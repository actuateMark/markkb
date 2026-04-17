---
title: "VCH Integration"
type: summary
topic: integrations/vch
tags: [integration, healthcheck, vch]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# VCH (Virtual Camera Healthcheck) Integration

VCH (Virtual Camera Healthcheck) is a **special-purpose integration type** in the Actuate platform dedicated to camera health monitoring rather than threat detection. While standard integration types (RTSP, Milestone, Orchid, etc.) focus on pulling video frames for AI inference, VCH focuses on verifying that camera streams are healthy, connected, and producing usable video.

## Purpose

VCH powers the [[camera-health-monitoring]] feature set. Instead of running detection models on video frames, VCH connectors run a suite of automated health checks on each camera stream, including:

- **Connectivity checks** -- verifying that the camera stream can be reached and is returning frames
- **Stream quality checks** -- measuring actual FPS, resolution, and detecting broken or degraded streams
- **Scene change detection** -- identifying when a camera's field of view has shifted unexpectedly (configurable sensitivity: low/medium/high)
- **Motion status monitoring** -- confirming that the camera is detecting scene motion (static feeds may indicate a problem)
- **Recording checks** -- verifying that the VMS is recording properly
- **Image quality checks** -- validating minimum resolution thresholds (default 360p)

These checks are configured via the `HealthcheckConfig` class in [[actuate-config]] at `connector/base_config/healthcheck_config.py`, which supports per-check enable/disable flags and separate alert email lists for each check type.

## Components

### Pullers

VCH reuses the standard pullers from [[actuate-pullers]] (URL-based or VMS-specific) but invokes their `run_healthcheck()` method rather than their standard `run()` method. Each puller's `run_healthcheck()` returns a `HealthcheckDataPacket` containing connectivity status, stream quality metrics, and related diagnostics.

### Config

The `HealthcheckConfig` class supports a `deployment` mode (mode 3 activates healthcheck runs), per-check configuration with individual alert email lists, and a `disabled_cameras` list to exclude specific cameras from monitoring. The `CustomerConfig` base class integrates `HealthcheckConfig` so that any integration type can optionally include health monitoring.

### Health Monitoring

The `actuate-healthmonitoring` library provides the `MessageSender` and `OneoffAlertSender` utilities for delivering health check results and alerts via email and SMS to configured recipients.

## Architecture

VCH runs as a connector instance within the [[vms-connector]] infrastructure, using the same deployment and configuration pipeline as regular detection connectors. The key difference is in the processing path: instead of feeding frames into detection models, VCH feeds them into health check routines that evaluate stream and camera health. Results are reported through health monitoring email/SMS alerts and stored in the camera status DAO. VCH is complementary to detection connectors -- a site can have both a detection connector (e.g., RTSP or Milestone) and a VCH connector running against the same cameras.
