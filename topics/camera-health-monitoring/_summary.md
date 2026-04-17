---
title: Camera Health Monitoring (H1.1)
type: summary
topic: camera-health-monitoring
tags: [chm, h1-1, cs3, health, scene-change, connectivity]
jira: "CS3"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Camera Health Monitoring -- CHM (H1.1)

Monitors camera connectivity, recording status, image quality, scene changes, and frame rates. Sends email alerts and integrates with monitoring dashboards. **Most mature of the H1.x products.**

## Current Status (April 2026)

**Maintenance mode** -- 1 issue In Progress, 5 items ready to deploy but unreleased.

### In Progress
- **CS3-300** (Brad Murphy) -- Operator/activity logging

### Ready to Deploy
- CS3-430 -- Account for dummy incident type in CHM API (Mark Barbera)
- CS3-303 -- Disable/delete schedules for CHM-only sites (Victoria)
- CS3-31 (Highest) -- Auto-update reference images (Mark Barbera)
- CS3-58 -- Configuration per camera (Mark Barbera)
- CS3-323 -- Cam count discrepancy fix (Mark Barbera)

### High-Priority Backlog
- CS3-33 (Highest) -- Restructure incident table for email alerts
- CS3-42 (Highest) -- Generic API for external use
- CS3-44 -- Send alerts to Immix

## Detection Capabilities

Uses `actuate-suddenscenechange` (SIFT-based) for camera tampering/scene change detection. Health data stored in DynamoDB (Healthcheck, SceneChange tables).

## 50 Open Issues

Most epics are stale (last updated March 9): Scene Change (CS3-73), New Integrations (CS3-74), Feature Enhancements (CS3-72), Bug Fixes (CS3-71).
