---
title: "Source: Evalink REST API Integration"
type: source
topic: integrations/evalink
tags: [source, integration, evalink, documentation]
ingested: 2026-04-15
author: kb-bot
---

## Evalink Integration Overview

Evalink is an alarm management platform. Actuate integrates with Evalink via a REST API to push detection alerts. The integration was released in early 2026 and is documented across multiple Confluence spaces.

## Confluence Knowledge

Several dedicated Evalink pages exist:

- **"Evalink"** (page 258211842, space kb, created Dec 2025 by Laura Reno) -- primary onboarding documentation:
  - Select "evalink" as the alarm type for the site at onboarding or from site settings
  - **Site-level config** (planned): evalink company ID (can be looked up in evalink portal or Actuate can retrieve via API)
  - **Camera-level config**: evalink object ID, evalink partition (defines which zone/area the alert maps to)
  - All config is currently at camera level in admin but intended to be split by level
- **"Evalink Integration Requirements"** (page 232325125, space Integratio) -- QA/QC checklist for the Evalink integration MVP. Scope: integration with alarm management platform Evalink to push alerts from Actuate.
- **"Evalink user permissions and organizational structure"** (page 238977025, space UPSM) -- documents the user/group/permissions hierarchy within evalink: user types, user roles, granular permissions, default and whitelisted workspaces.
- **"Feature release communication tracking"** (page 288129025) -- mentions evalink integration as a feature release item tracked in early 2026.

## Actuate Implementation

**Alarm Sender**: `actuate_alarm_senders/evalink/` -- sends detection alerts to Evalink's REST API. Extends `BaseAlertSender`.

**Config**: `actuate_config/alerts/evalink/` -- Evalink-specific configuration including company ID, object ID, and partition.

## Auth Method

**API authentication**: Evalink uses REST API authentication. The company ID serves as a top-level identifier, with object IDs and partitions providing camera-level targeting. Specific API credentials are managed in the alarm sender configuration.

## Key Configuration Fields

| Field | Level | Description |
|---|---|---|
| evalink company ID | Site | Can be looked up in evalink portal or retrieved via API |
| evalink object ID | Camera | Identifies the specific camera/device in evalink |
| evalink partition | Camera | Maps to zone/area within evalink for alert routing |

## Key Considerations

- Relatively new integration (Dec 2025 -- Jan 2026 timeframe)
- REST API based -- modern integration pattern
- Company/object/partition hierarchy mirrors evalink's organizational structure
- User permissions in evalink are complex (user types > roles > granular permissions)
- Integration QA checklist exists in the Integrations space

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| Evalink | 258211842 | kb |
| Evalink Integration Requirements | 232325125 | Integratio |
| Evalink user permissions | 238977025 | UPSM |
