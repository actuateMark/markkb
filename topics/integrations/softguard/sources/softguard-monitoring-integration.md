---
title: "Source: Softguard Monitoring Integration"
type: source
topic: integrations/softguard
tags: [source, integration, softguard, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Softguard Integration Overview

Softguard is a monitoring and alarm management platform. Actuate integrates with Softguard as an alarm sender, pushing detection alerts to Softguard's system. The integration is implemented within the `actuate-alarm-senders` library.

## Confluence Knowledge

Confluence search for "softguard" returned results exclusively from EDOCS engineering documentation pages. No dedicated Softguard page was found in the Knowledgebase (kb) or Integrations spaces. The integration is referenced in the general alarm sender and config documentation:

- **"actuate-config: Alert Configuration Classes"** (page 497909761, EDOCS) -- includes Softguard alert configuration class extending `BaseAlertSenderConfig`.
- **"actuate-alarm-senders: Alert Sender Reference"** (page 496828438, EDOCS) -- documents the Softguard alert sender class.
- **"actuate-alarm-senders"** (page 497745943, EDOCS) -- architecture overview listing Softguard among monitoring platform senders.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/softguard/` -- dedicated Softguard alarm sender module. Extends `BaseAlertSender` with standard alert dispatch methods.

**Config**: `actuate_config/alerts/softguard/` -- Softguard-specific configuration parsed from feature JSON in `settings.json`.

## Auth Method

Authentication details are encapsulated in the Softguard alarm sender configuration, configured per-site. Specific auth method (API key, token, credentials) is defined within the sender class implementation.

## Key Considerations

- Minimal Confluence documentation -- no dedicated onboarding or configuration page exists
- Part of the standard alarm sender architecture (config from actuate-config + sender from actuate-alarm-senders)
- Present in the alarm-senders source tree, confirming it is an active integration
- Likely serves the Latin American market based on Softguard's geographic presence
- Documentation gap: would benefit from an onboarding page in the kb space similar to LISA or Evalink

## Source Code References

| Component | Path |
|---|---|
| Alarm Sender | `actuate-alarm-senders/src/actuate_alarm_senders/softguard/` |
| Alert Config | `actuate-config/src/actuate_config/alerts/softguard/` |

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| actuate-config: Alert Configuration Classes | 497909761 | EDOCS |
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
| actuate-alarm-senders | 497745943 | EDOCS |
