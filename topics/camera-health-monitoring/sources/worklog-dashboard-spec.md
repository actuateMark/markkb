---
title: "Source: CHM Dashboard Specification"
type: source
topic: camera-health-monitoring
tags: [worklog, dashboard, figma, frontend, analytics-api]
ingested: 2026-04-14
author: kb-bot
---

# CHM Dashboard Specification

Worklog notes on the dashboard design for camera health monitoring.

## Figma Wireframe

Design wireframes are at: `https://www.figma.com/file/fTgzcn4TATidPgTj71Lqsx/Wireframes?type=design&node-id=1-47920`

## Implementation Approach

The dashboard should emulate the existing "analytics" endpoints from the Swagger API on the admin platform. This means the CHM dashboard backend reuses the same endpoint patterns and data structures as the analytics feature, adapted to serve healthcheck data instead of detection analytics. This reduces frontend work by keeping the API contract familiar.

## See Also

- [[healthcheck-architecture]] -- system context
- [[health-check-types]] -- the data the dashboard surfaces
