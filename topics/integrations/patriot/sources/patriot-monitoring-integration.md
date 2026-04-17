---
title: "Source: Patriot Monitoring Integration"
type: source
topic: integrations/patriot
tags: [source, integration, patriot, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Patriot Integration Overview

Patriot is a monitoring platform integrated with Actuate for alarm dispatch. Actuate sends detection alerts to Patriot via the `actuate-alarm-senders` library. Patriot dispatch validation is important enough to have a dedicated review skill in the vms-connector tooling.

## Confluence Knowledge

Confluence search for "patriot" returned results primarily from EDOCS pages documenting the alarm sender and config libraries:

- **"actuate-alarm-senders: Alert Sender Reference"** (page 496828438, EDOCS) -- documents the Patriot alarm sender class with methods `send()`, `send_chm()`, and `send_clips()`.
- **"actuate-config: Alert Configuration Classes"** (page 497909761, EDOCS) -- documents the Patriot alert configuration extending `BaseAlertSenderConfig`.
- **"actuate-alarm-senders"** (page 497745943, EDOCS) -- architecture overview listing Patriot among the monitoring platform senders.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/patriot/` -- dedicated Patriot alarm sender in the actuate-alarm-senders library. Dispatches detection alerts and CHM/healthcheck alerts to Patriot's platform.

**Config**: `actuate_config/alerts/patriot/` -- Patriot-specific configuration parsed from the site's feature JSON in `settings.json`.

**Operational Tooling**: The vms-connector repo includes a dedicated `/patriot-dispatch-review` skill (`.claude/skills/patriot-dispatch-review.md`) for validating Patriot alarm dispatch in New Relic logs. This indicates Patriot dispatch is operationally important enough to warrant specialized debugging support.

## Auth Method

Authentication is configured per-site via the Patriot alert sender configuration. Specific credentials and endpoint details are stored in the `settings.json` feature data and parsed by `PatriotAlertSenderConfig`.

## Key Considerations

- Patriot dispatch review is a dedicated operational skill, suggesting it is a high-volume or high-importance alarm destination
- The alarm sender supports standard detection alerts, CHM alerts, and clip-based alerts
- Part of the `actuate-alarm-senders` shared library architecture (config object from actuate-config + sender class from actuate-alarm-senders)

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
| actuate-config: Alert Configuration Classes | 497909761 | EDOCS |
| actuate-alarm-senders | 497745943 | EDOCS |
