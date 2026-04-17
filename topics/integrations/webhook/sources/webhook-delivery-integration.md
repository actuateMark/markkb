---
title: "Source: Generic Webhook Delivery Integration"
type: source
topic: integrations/webhook
tags: [source, integration, webhook, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Webhook Integration Overview

The webhook integration is a generic alarm sender that delivers detection alerts to customer-specified HTTP endpoints via webhook (HTTP POST). This provides a flexible integration path for customers who want to receive Actuate alerts in their own systems without using a specific monitoring platform.

## Confluence Knowledge

Confluence search for "webhook" returned results from multiple spaces, with the most relevant being EDOCS engineering documentation:

- **"actuate-alarm-senders: Alert Sender Reference"** (page 496828438, EDOCS) -- documents the webhook alert sender class. Supports standard methods: `send()`, `send_chm()`, `send_clips()`.
- **"actuate-config: Alert Configuration Classes"** (page 497909761, EDOCS) -- documents the webhook alert configuration class.
- **"actuate-alarm-senders"** (page 497745943, EDOCS) -- architecture overview listing webhook among the alarm sender implementations.
- **"actuate-integration-calls"** (page 497745962, EDOCS) -- client libraries documentation; webhook delivery may also route through integration calls.
- **"actuate-event-listener"** (page 497385476, EDOCS) -- event pipeline that routes events to SQS FIFO queues, which can feed webhook delivery.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/webhook/` -- generic webhook alarm sender. Makes HTTP POST requests to configured endpoint URLs with detection alert payloads (JSON + images).

**Config**: `actuate_config/alerts/webhook/` -- webhook-specific configuration including target URL, authentication headers, and payload format options.

## Auth Method

**Configurable**: The webhook sender supports configurable authentication since it targets arbitrary customer endpoints. Common patterns include:
- Bearer token in Authorization header
- API key in custom header
- Basic Auth credentials
- No auth (for internal endpoints)

## Payload Format

Webhook payloads typically include:
- Detection event metadata (timestamp, camera ID, site ID)
- Detection labels and confidence scores
- Image attachments (detection frame with bounding boxes)
- Alert type classification

## Key Considerations

- Most flexible integration -- works with any HTTP endpoint
- Generic pattern allows customers to build custom integrations
- Supports the full range of alert types (detection, CHM, clips)
- Auth is configurable per-site to match customer requirements
- Can serve as a bridge to monitoring platforms not directly supported
- Payload format should be documented for external partners

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
| actuate-config: Alert Configuration Classes | 497909761 | EDOCS |
| actuate-alarm-senders | 497745943 | EDOCS |
| actuate-event-listener | 497385476 | EDOCS |
