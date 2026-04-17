---
title: "Source: AutoPatrol/VCH as Integration Type"
type: source
topic: integrations/autopatrol-integration
tags: [source, integration, autopatrol-integration, documentation]
ingested: 2026-04-15
author: kb-bot
---

## AutoPatrol Integration Overview

AutoPatrol and VCH (Virtual Camera Healthcheck) are Actuate integration types that connect to the Immix platform's camera streaming infrastructure. Unlike traditional VMS integrations where Actuate pulls streams directly from cameras, AutoPatrol/VCH receives streams from Immix's servers via WebSocket.

## Confluence Knowledge

Extensive documentation across multiple Confluence spaces:

- **"AutoPatrol"** (page 90144791, Vlad's space) -- high-level overview: AutoPatrol is an AI-powered automated video guard patrol developed in partnership between Immix and Actuate. Replaces manual camera cycling with AI-analyzed patrol clips.
- **"Autopatrol DS Overview & Scope"** (page 98402309, IA space) -- DS team scope and ML approach for AutoPatrol analysis.
- **"Rev 2 GenAI Autopatrol Product Description"** (page 68812801, IA space) -- product description for the GenAI-enhanced AutoPatrol.
- **"VCH vs CHM feature comparison"** (page 79986691, CHM space) -- critical comparison:
  - **CHM**: Actuate pulls streams directly from camera/NVR/VMS via RTSP/HTTP. Healthchecks every 15-120 min.
  - **VCH**: Immix server sends stream to Actuate via HTTP/WebSocket API request. 4 healthchecks per day.
  - VCH connectivity checks rely on Immix's infrastructure rather than direct camera access.
- **"Immix VCH Requirements"** (page 52166700, CHM space) -- requirements doc for the VCH integration.
- **"Autopatrol Launch Plan"** (page 7700490, IA space) -- launch planning and team assignments.

## VMS-Connector Documentation

From `docs/integrations/autopatrol.md`:
- **Patrol types**: AutoPatrol (monitoring with motion detection, longer streams, 30s retry delays) vs VCH (short healthcheck runs ~7-8s, API duration 2s)
- **API vs client duration**: Two separate parameters -- API duration tells Immix when to close WebSocket, client timeout is safety fallback
- **WebSocket puller**: `actuate_pullers.socket.autopatrol_websocket_stream_puller` with timeouts (open=30, close=10, recv=30s), 3 retry attempts
- **Thread timeout**: Must account for retries -- AutoPatrol: `run_duration + (2*30) + 30`; VCH: 240s worst case
- **Conditional motion**: AutoPatrol runs motion detection; VCH does not (healthcheck only)

## Integration Types in vms-connector

| Integration Type | Auth | Purpose |
|---|---|---|
| AutoPatrol | Backend API | AI-powered automated camera patrols |
| VCH | Backend API | Virtual Camera Healthcheck via Immix |
| Patrol | Backend API | Manual patrol mode -- specific camera sets on demand |

## Key Files

- `camera/autopatrol/autopatrol_camera.py` -- AutoPatrol camera implementation
- `camera/autopatrol/vch_camera.py` -- VCH camera implementation
- `actuate_pullers.socket.autopatrol_websocket_stream_puller` -- WebSocket stream puller
- `actuate_integration_calls/autopatrol/` -- API client for AutoPatrol server communication
- `connector_factories/autopatrol/` -- Factory classes

## Key Considerations

- Stream source is Immix (not direct camera access) -- dependency on Immix infrastructure
- WebSocket-based streaming -- different from RTSP-based integrations
- Two products share infrastructure: AutoPatrol (analytics) and VCH (healthcheck)
- Retry logic is complex due to WebSocket connection management
- Immix currently limits clips to 10s -- blocking feature for full patrol depth

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| AutoPatrol | 90144791 | personal |
| Autopatrol DS Overview & Scope | 98402309 | IA |
| VCH vs CHM feature comparison | 79986691 | CHM |
| Immix VCH Requirements | 52166700 | CHM |
| Autopatrol Launch Plan | 7700490 | IA |
