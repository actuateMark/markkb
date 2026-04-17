---
title: "Source: Integration Diagnostics Class Design"
type: source
topic: camera-health-monitoring
tags: [worklog, diagnostics, integrations, class-design]
ingested: 2026-04-14
author: kb-bot
---

# Integration Diagnostics Class Design

Worklog notes outlining the class structure for per-integration diagnostic checks within the healthcheck system.

## Architecture

A **manager class** receives a healthcheck request, inspects the integration type, and selects the relevant diagnostic class for that integration. Each integration has its own diagnostic implementation.

## Diagnostic Flows

Four diagnostic flows are defined:

1. **Recording** -- verify the camera is recording
2. **Connection** -- verify network/API connectivity
3. **Stream quality** -- assess video stream health
4. **Image quality** -- assess captured image usability

All four flows run for every check, but most will remain unimplemented for most integrations (graceful no-ops).

## Class Hierarchy

The parent diagnostic class contains sub-checks:

- **HDD** -- hard drive health
- **NVR connection** -- connectivity to the network video recorder
- **Cam recording** -- per-camera recording status
- **Connection tests** -- general connectivity verification

Each integration subclass overrides only the diagnostics it can actually perform, leaving the rest as unimplemented stubs.

## See Also

- [[health-check-types]] -- broader check taxonomy
- [[healthcheck-architecture]] -- how diagnostics fit into the runner tree
