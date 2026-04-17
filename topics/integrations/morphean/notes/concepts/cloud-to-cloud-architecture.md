---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [morphean, integration, architecture, cloud, videor]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/400261121"
jira: "PROD-67"
---

# Cloud-to-Cloud Architecture (Morphean)

Track A of the [[integrations/morphean/_summary|Morphean]] -- a platform-level integration between Actuate and Morphean's **VideoProtector REST API v2.54.0** that delivers Tier-1 analytics, [[camera-health-monitoring]], and [[autopatrol]] to all of Morphean's white-label partners (most notably VIDEOR, covering 30 countries and 170+ resellers).

## How It Works

Unlike Actuate's typical deployment where camera streams come directly from on-site VMS systems via RTSP, the Morphean integration routes video through Morphean's cloud platform first. The data flow is:

1. **Cameras** send RTSP streams to Morphean's VideoProtector cloud.
2. **Actuate ingests RTSP streams** from Morphean's cloud at 480p-720p resolution and 1 FPS. This is lower resolution and frame rate than typical direct connections, optimized for bandwidth and cost.
3. **Camera discovery** uses Morphean's `CameraAdminWS` API to enumerate available cameras per tenant.
4. **Analytics processing** runs through Actuate's standard pipeline: [[vms-connector]] pods pull frames, run them through model servers, apply filters, and generate alerts.
5. **Event push-back** returns alerts to both Actuate's live alerts dashboard and back to Morphean via their Event + Scenario system.

## Phase 1 Scope (9 Components)

The Phase 1 integration covers nine functional areas:

| Component | Description |
|-----------|-------------|
| **Authentication & tenancy mapping** | Map Morphean customers/sites to Actuate entities at the customer-site level |
| **White-label partner isolation** | Ensure VIDEOR and other Morphean partners see only their own data |
| **RTSP stream ingestion** | Pull camera feeds from Morphean cloud (480p-720p @ 1 FPS) |
| **Camera discovery** | Use `CameraAdminWS` to enumerate cameras per tenant |
| **Per-camera analytics toggle** | Enable/disable analytics within Morphean's partner UI |
| **Tier-1 analytics** | Intruder, vehicle, and other standard detections on Morphean frames |
| **Ignore zones & sensitivity** | Actuate-side configuration (Morphean has no dedicated ROI API) |
| **Event return path** | Push alerts back to Morphean via Event + Scenario system |
| **Usage data reporting** | Billing data for Morphean's consumption-based model |

A notable constraint is that **Morphean has no dedicated ROI (Region of Interest) API**, so ignore zones and sensitivity must be managed entirely on the Actuate side. This means the Morphean partner UI cannot natively display or edit Actuate ignore zones -- a UX gap that may need a workaround.

## Phase 2 (Planned)

Phase 2 extends the integration with:
- Alarm zone integration (deeper ROI support)
- CHM dashboards surfaced in Morphean UI
- AutoPatrol capabilities
- Webhook reliability improvements

## Key Contacts

- **Antoine and Jack** -- Morphean technical contacts
- **Tolga and Mehmet** -- Originally requested the integration

## See Also

- [[edge-hardware-track]] -- Track B, the alternative approach for legacy cameras
- [[integrations/morphean/_summary|Morphean]] -- parent topic
- [[revenue-drivers]] -- Morphean's role as a revenue multiplier
- [[data-flow-architecture]] -- Actuate's standard processing pipeline
