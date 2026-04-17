---
title: "Source: Bold Manitou SIA Protocol Integration"
type: source
topic: integrations/bold
tags: [source, integration, bold, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Bold Integration Overview

Bold is a central monitoring station (CMS) platform. Actuate integrates with Bold using the SIA (Security Industry Association) protocol via Manitou, Bold's alarm management software. The integration involves both an alarm sender and a custom site manager architecture.

## Confluence Knowledge

Two key Confluence pages were found in the Knowledgebase (kb) space:

- **"Bold"** (page 160204384, space kb) -- parent page for Bold documentation created by Tatiana (Oct 2025). Contains links to technical docs.
- **"Bold Site Manager"** (page 161120487, space kb) -- detailed technical documentation. Key points:
  - The Bold site manager sits in the EKS cluster and is launched as though it were a site by the deployer
  - It manages all sites associated with a given Bold server for a given customer
  - Sites must have a unique identification mapped to something within admin
  - Responsible for starting, stopping, and restarting all sites in the cluster associated with that Bold server
  - This is a distinct architectural pattern compared to standard single-site deployments

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/bold/` -- sends detection alerts to Bold's Manitou platform using the SIA protocol. Extends `BaseAlertSender`.

**Config**: `actuate_config/alerts/bold/` -- Bold-specific alarm sender configuration including Bold server connection details and SIA protocol parameters.

**Site Manager Architecture**: Unlike most integrations where one connector deployment = one site, Bold uses a multi-site manager pattern. The Bold site manager deployment manages multiple camera sites connected to a single Bold server. This is architecturally significant -- it handles lifecycle management (start/stop/restart) for all child sites.

## Auth Method

SIA protocol authentication -- the Bold integration uses SIA DC-09 or similar protocol standards for alarm transmission to Manitou. Connection parameters include the Bold server address and site identification mapping.

## Key Considerations

- Bold uses a unique multi-site manager architecture -- different from standard 1:1 deployer-to-site pattern
- SIA protocol is an industry standard for alarm transmission
- Each site must have a unique ID mapped in actuate_admin
- The deployer launches the Bold site manager as if it were a regular site

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| Bold | 160204384 | kb |
| Bold Site Manager | 161120487 | kb |
| actuate-alarm-senders: Alert Sender Reference | 496828438 | EDOCS |
