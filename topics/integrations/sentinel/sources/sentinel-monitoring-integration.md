---
title: "Source: Sentinel Monitoring Platform Integration"
type: source
topic: integrations/sentinel
tags: [source, integration, sentinel, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Sentinel Integration Overview

Sentinel is a monitoring platform integrated with Actuate for alarm delivery. It is implemented as an alarm sender within the `actuate-alarm-senders` library. Sentinel connections are clip-based (SMTP/AILink), meaning frames arrive at intervals rather than as continuous streams.

## Confluence Knowledge

Confluence search for "sentinel" returned indirect references. The key technical documentation is found in the EDOCS space:

- **"actuate-alarm-senders: Alert Sender Reference"** (page 496828438, EDOCS) -- documents all alert sender classes including the Sentinel sender. The sender extends `BaseAlertSender` with methods for `send()`, `send_chm()`, and `send_clips()`.
- **"actuate-config: Alert Configuration Classes"** (page 497909761, EDOCS) -- documents Sentinel's alert configuration class extending `BaseAlertSenderConfig`.
- **"Motion Detection & Stationary Filter: Scoping Document"** (page 482541575, DS space) -- explicitly mentions that ~32K cameras run on clip-based connections including Sentinel, where frames arrive minutes apart rather than continuously. This impacts motion detection (FDMD) and stationary vehicle filtering, which were designed for continuous RTSP streams.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/sentinel/` -- dedicated sentinel alarm sender module in actuate-alarm-senders. Sends detection alerts to the Sentinel monitoring platform.

**Config**: `actuate_config/alerts/sentinel/` -- Sentinel-specific alert configuration parsed from `settings.json` feature data.

**Clip-based Nature**: Sentinel cameras are categorized as clip-based integrations. The connector receives frames via SMTP/clip delivery rather than continuous RTSP. This means motion detection and stationary filters may not function optimally -- this is an active area of DS investigation.

## Auth Method

Authentication details are configured per-site in the alarm sender configuration within `settings.json`. Specific auth mechanism (API key, token, etc.) is encapsulated in the Sentinel alarm sender class.

## Key Considerations

- Sentinel is clip-based, not stream-based -- affects which analytics products are available
- Part of the ~32K camera fleet using non-continuous frame delivery
- Motion detection scoping doc (Apr 2026) is evaluating how to handle clip-based integrations better

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
| actuate-config: Alert Configuration Classes | 497909761 | EDOCS |
| Motion Detection & Stationary Filter Scoping | 482541575 | DS |
