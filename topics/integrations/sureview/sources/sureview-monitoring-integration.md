---
title: "Source: SureView Monitoring Integration"
type: source
topic: integrations/sureview
tags: [source, integration, sureview, documentation]
ingested: 2026-04-15
author: kb-bot
---

## SureView Integration Overview

SureView is a monitoring and alarm management platform. Actuate integrates with SureView as an alarm sender, pushing detection alerts to SureView's system. The integration is implemented within the `actuate-alarm-senders` library.

## Confluence Knowledge

Confluence search for "sureview" returned results primarily from EDOCS engineering documentation pages. No dedicated SureView page was found in the Knowledgebase (kb) space, suggesting the integration may be older or less heavily documented from a product/onboarding perspective.

Key references from EDOCS:
- **"actuate-alarm-senders: Alert Sender Reference"** (page 496828438, EDOCS) -- documents the SureView alert sender class with standard methods: `send()`, `send_chm()`, `send_clips()`.
- **"actuate-config: Alert Configuration Classes"** (page 497909761, EDOCS) -- documents SureView's alert config class.
- **"actuate-alarm-senders"** (page 497745943, EDOCS) -- architecture overview listing SureView among the monitoring platform alarm senders.
- **"Adding a new Queue Consumer"** (page 160072309, kb) -- references SureView in the context of queue consumer patterns, suggesting SureView may also receive alerts via the SQS queue consumer pipeline.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/sureview/` -- dedicated SureView alarm sender module. Extends `BaseAlertSender` and dispatches alerts to SureView's platform.

**Config**: `actuate_config/alerts/sureview/` -- SureView-specific configuration parsed from feature JSON.

**Queue Consumer Path**: SureView alerts may also flow through the `queue_consumer` service (SQS-based), which is an alternative delivery path used by some monitoring integrations. In this pattern: vms-connector writes detection data to DynamoDB/S3, an SQS message is enqueued, and the queue consumer processes it and delivers to SureView.

## Auth Method

Authentication details are encapsulated in the SureView alarm sender configuration. Configured per-site via `settings.json` feature data.

## Key Considerations

- Dual delivery paths possible: direct alarm sender OR queue consumer (SQS)
- No dedicated onboarding page in Confluence kb -- may need product documentation
- Part of the standard alarm sender pattern (config + sender class)
- Supports detection alerts, CHM alerts, and clip alerts

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
| actuate-alarm-senders | 497745943 | EDOCS |
| Adding a new Queue Consumer | 160072309 | kb |
