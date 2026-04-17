---
title: "Source: LISA/Leitstellensoftware Webhook API Integration"
type: source
topic: integrations/lisa
tags: [source, integration, lisa, documentation]
ingested: 2026-04-15
author: kb-bot
---

## LISA Integration Overview

LISA (Leitstellensoftware) is a German alarm receiving center (ARC) software platform. Actuate integrates with LISA as both an alarm sender and via integration calls, pushing detection alerts via a webhook-style REST API.

## Confluence Knowledge

A dedicated "LISA" page exists in the Knowledgebase space:

- **"LISA"** (page 247627790, space kb, created Dec 2025 by Laura Reno) -- key onboarding and configuration details:
  - To send alerts into LISA, select "LISA" as the alarm type for the site at onboarding or from site settings
  - **Camera-level configuration** requires: LISA server URL, LISA area, LISA zone, LISA token
  - The integration supports drawing ignore zones over alerts
  - Can pass non-clip related data to LISA
  - Configuration is currently at the camera level in admin

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/lisa/` -- sends detection alerts to LISA's webhook endpoint. Extends `BaseAlertSender`.

**Integration Calls**: `actuate_integration_calls/lisa/` -- client library for communicating with the LISA platform API. Handles authentication, API call formatting, and data delivery.

**Config**: `actuate_config/alerts/lisa/` -- LISA-specific configuration including server URL, area, zone, and token fields.

## Auth Method

**Token-based authentication**: Each camera is configured with a LISA token that authenticates requests to the LISA server. The token is part of the per-camera configuration in actuate_admin.

## Key Endpoints / API Details

- LISA server URL (configurable per-camera) -- webhook endpoint for alert delivery
- Alert payload includes detection data, images, and camera zone/area context
- Supports ignore zone overlays on alert images

## Configuration Hierarchy

Per the Confluence page, configuration is currently all at the camera level but the planned production-ready state would split between:
- **Site level**: Common LISA server settings
- **Camera level**: Area, zone, and camera-specific identifiers

## Key Considerations

- European market integration (German ARC software)
- Token-per-camera authentication model
- Supports both detection alerts and non-clip data
- Ignore zone drawing is supported on alert images

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| LISA | 247627790 | kb |
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
