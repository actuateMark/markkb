---
title: "Source: Generic RTSP Protocol and ONVIF Standards"
type: source
topic: integrations/rtsp
tags: [source, integration, rtsp, documentation]
ingested: 2026-04-15
author: kb-bot
---

## RTSP Integration Overview

RTSP (Real Time Streaming Protocol) is the foundational VMS integration type for Actuate. It provides generic video stream pulling from any camera, NVR, or VMS that exposes RTSP URLs. This is the most widely used integration type and serves as the base pattern for most other VMS integrations.

## Confluence Knowledge

Extensive RTSP documentation exists across multiple Confluence spaces:

- **"vms-connector: RTSP Camera Simulator"** (page 497614850, EDOCS) -- full documentation of the RTSP camera simulator for local testing.
- **"actuate-pullers: Puller Integrations"** (page 497844226, EDOCS) -- documents UrlFramePuller and AvUrlPuller, the RTSP/HTTP stream pullers using cv2.VideoCapture and PyAV respectively.
- **"vms-connector: Supported Integrations"** (page 496828419, EDOCS) -- lists RTSP as the first integration type with Basic Auth.
- **"actuate-pullers"** (page 496795670, EDOCS) -- full documentation of the puller library including RTSP transport options and GPU decode.

## VMS-Connector Docs

Detailed RTSP documentation exists in vms-connector:
- `docs/integrations/rtsp.md` -- RTSP reference: simulator setup, local dev mode, GPU decode with `rtsp_transport: tcp`, key files (`connector_factories/rtsp/rtsp_factory.py`, `actuate_pullers.url.av_url_puller`)
- `docs/RTSP_CAMERA_SIMULATOR.md` -- full simulator guide: Docker-based simulator at `rtsp://127.0.0.1:8554/camera`, multi-camera setup, live webcam streaming via mediamtx + ffmpeg
- `docs/OPTIMIZED-CONNECTOR.md` -- RTSP GPU options, CUDA/VAAPI config, troubleshooting

## Auth Method

**Basic Auth**: RTSP URLs include username and password credentials (`rtsp://user:pass@ip:554/stream`). No API key or token -- authentication is embedded in the RTSP URL itself.

## Key Technical Details

- **Transport**: TCP recommended on GPU instances (`rtsp_transport: tcp` in FFmpeg options)
- **Puller classes**: `UrlFramePuller` (OpenCV-based), `AvUrlPuller` (PyAV-based with better H.264 handling)
- **GPU decode**: Supports CUDA and VAAPI hardware acceleration
- **FFmpeg options**: `probesize: 5000000`, `analyzeduration: 5000000` for reliable connection
- **Factory**: `connector_factories/rtsp/rtsp_factory.py` -- creates RTSP cameras and site manager
- **Local testing**: Camera simulator via `just play-camera-simulator` or mediamtx + webcam

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| vms-connector: RTSP Camera Simulator | 497614850 | EDOCS |
| actuate-pullers: Puller Integrations | 497844226 | EDOCS |
| vms-connector: Supported Integrations | 496828419 | EDOCS |
| actuate-pullers | 496795670 | EDOCS |
