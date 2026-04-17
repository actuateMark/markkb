---
title: "Source: Immix SMTP Alarm Format and Connect API"
type: source
topic: integrations/immix
tags: [source, integration, immix, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Immix Integration Overview

Immix is a central monitoring station (CMS) platform widely used in the security industry. Actuate integrates with Immix in two primary ways: as an alarm sender (pushing detection alerts via SMTP email) and as a VMS/stream source for the AutoPatrol and VCH products.

## Confluence Knowledge

The Immix Confluence space (IA -- "IMMIX Autopatrol") contains extensive documentation:

- **"Autopatrol DS Overview & Scope"** (page 98402309, space IA) -- describes the AutoPatrol product built as a collaboration between Immix and Actuate. AutoPatrol provides AI-powered automated video guard patrols, replacing manual camera cycling.
- **"Immix Dev Requests"** (page 94928979, space IA) -- tracks feature requests from Immix, including extended video duration (currently limited to 10s clips), configurable patrol duration (5 min minimum), and site-level information display on the Immix platform.
- **"AutoPatrol Launch Plan"** (page 7700490, space IA) -- launch planning for the AutoPatrol product.
- **"Immix VCH Requirements"** (page 52166700, space CHM) -- requirements for Immix Virtual Camera Healthcheck integration.
- **"actuate-alarm-senders"** (page 497745943, EDOCS) -- documents the alarm sender architecture including Immix SMTP sender.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/immix/` -- sends detection alerts to Immix via SMTP email. Config class at `actuate_config/alerts/immix/`. The Immix alarm sender extends `BaseAlertSender` and formats alert data as SMTP email messages with attached detection images.

**Integration Calls**: The `actuate_integration_calls` library does not have a dedicated Immix module; Immix stream integration is handled through the AutoPatrol WebSocket puller in `actuate_pullers`.

**VMS Integration**: The `autopatrol` and `vch` integration types in vms-connector handle Immix stream connections. Immix server sends streams to Actuate via HTTP/WebSocket through an API request (unlike direct RTSP pull).

## Auth Methods

- **Alarm sending**: SMTP credentials (email server configuration)
- **Stream access (AutoPatrol/VCH)**: Backend API authentication via Immix Connect API

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| Autopatrol DS Overview & Scope | 98402309 | IA |
| Immix Dev Requests | 94928979 | IA |
| Immix VCH Requirements | 52166700 | CHM |
| actuate-alarm-senders | 497745943 | EDOCS |
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
