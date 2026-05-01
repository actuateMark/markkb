---
title: Morphean / VIDEOR Integration
type: summary
topic: integrations/morphean
tags: [morphean, videor, hanwha, vsaas, cloud-to-cloud, edge, integration]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/400261121"
jira: "PROD-67"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Morphean / VIDEOR Integration

**Morphean** is a Hanwha cloud private labeller operating **VideoProtector** (VSaaS platform). Powers multiple white-label partners, most notably **VIDEOR** -- a major European security distributor covering **30 countries, 170+ resellers**. Strategic value: "one integration equals many customers."

**Status:** DRAFT (QA checklist recently created April 2026)
**Key contacts:** Antoine and Jack (Morphean technical), Tolga/Mehmet (requested integration)

## Track A: Cloud-to-Cloud Integration

**Objective:** Platform-level integration between Actuate and VideoProtector REST API v2.54.0 to deliver Tier-1 analytics, CHM, and AutoPatrol to all white-label partners.

**Phase 1 Scope:**
1. Authentication & tenancy mapping (customer-site level)
2. White-label partner isolation (VIDEOR and others under Morphean VSP)
3. [[rtsp-deep-dive|RTSP]] stream ingestion from Morphean cloud (480p-720p @ 1 FPS)
4. Camera discovery via Morphean API (`CameraAdminWS`)
5. Per-camera analytics enable/disable within Morphean partner UI
6. Tier-1 analytics on Morphean camera frames
7. [[ignore-zones|Ignore zones]] & sensitivity (Actuate-side, no dedicated ROI API in Morphean)
8. Event return path (alerts to Actuate live alerts + back to Morphean via Event + Scenario system)
9. Usage data reporting for billing

**Phase 2:** Alarm zone integration, CHM dashboards, AutoPatrol, webhook reliability

## Track B: Edge Hardware Integration

Deploy Actuate analytics on **VIDEOR's edge devices** (Toradex Verdin + DeepX AI acceleration) for legacy cameras without cloud video upload. Local VMS integration on same device.

## Confluence Pages

- [Integration Requirements](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/400261121)
- [QA/QC Checklist: Track A](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/494469121)
