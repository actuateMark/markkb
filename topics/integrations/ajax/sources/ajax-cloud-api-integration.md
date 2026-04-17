---
title: "Source: Ajax Systems Cloud API Integration"
type: source
topic: integrations/ajax
tags: [source, integration, ajax, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Ajax Integration Overview

Ajax Systems provides two integration paths with Actuate: direct NVR access (Ajax NVR) and cloud-based (Ajax Cloud). The Ajax Cloud integration uses Ajax's cloud API to receive motion-triggered clips rather than continuous RTSP streams.

## Confluence Knowledge

Two dedicated Ajax pages exist in the Knowledgebase (kb) space:

- **"Ajax"** (page 294813697, space kb, created Jan 2026 by Laura Reno) -- NVR integration guide:
  - Configures Actuate to directly pull streams from cameras connected to an Ajax NVR
  - Requires network configuration: NVR must be accessible from Actuate's infrastructure (port forwarding, VPN, or public IP)
  - Supports basic and advanced analytics (full stream access)

- **"Ajax Cloud"** (page 293502977, space kb, created Jan 2026 by Laura Reno) -- cloud integration guide:
  - Does not require unique network configuration -- cloud-to-cloud connection
  - Does NOT support direct stream connections, which limits available analytics products
  - Motion-triggered: when motion is detected on the Ajax device, clips/frames are sent to Actuate
  - Limited product support compared to direct NVR integration

## Actuate Implementation

**Integration Calls**: `actuate_integration_calls/ajax/` -- client library for communicating with the Ajax Systems cloud API. Handles authentication and API interactions for retrieving camera streams and motion events.

**VMS Connector**: Ajax is not listed in the standard `integration_type` matrix in `docs/backend/integrations.md`, but it has a dedicated integration-calls module, suggesting it may use a custom integration path or be mapped through another type.

## Auth Method

- **Ajax NVR**: Direct network access -- standard RTSP/HTTP credentials to the NVR device
- **Ajax Cloud**: Cloud API authentication -- likely API token or OAuth-based cloud-to-cloud auth handled in `actuate_integration_calls/ajax/`

## Key Differences: NVR vs Cloud

| Feature | Ajax NVR | Ajax Cloud |
|---|---|---|
| Connection | Direct RTSP to NVR | Cloud API |
| Network requirements | Port forwarding/VPN needed | None (cloud-to-cloud) |
| Stream type | Continuous | Motion-triggered clips |
| Analytics support | Full (basic + advanced) | Limited |
| Setup complexity | Higher | Lower |

## Key Considerations

- Two distinct integration paths serving different deployment scenarios
- Cloud path has limited product support due to clip-based nature
- NVR path provides full RTSP access but requires network configuration
- Both documented in kb space as of Jan 2026

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| Ajax | 294813697 | kb |
| Ajax Cloud | 293502977 | kb |
