---
title: "EBUS UI Configuration Mapping"
type: concept
topic: ebus-integration
tags: [ebus, ui, configuration, vms, accellence, v5]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/integrations/ebus/_summary.md
  - topics/integrations/ebus/notes/concepts/phase1-vs-phase2.md
incoming_updated: 2026-05-27
---

# EBUS UI Configuration Mapping

EBUS is a video management system built by Accellence Technologies (Germany). Its **AlarmReceiverVCA** component provides a UI for configuring and displaying video content analysis (VCA) results. This note documents how EBUS UI settings map to [[v5-api-design]] parameters during [[integrations/ebus/_summary|EBUS]] Phase 1.

## Configuration Mapping

When an EBUS operator sets up Actuate detection for a camera, they interact with EBUS's native configuration interface. Each EBUS setting translates to a specific v5 API concept:

| EBUS UI Setting | What the Operator Sees | v5 API Mapping |
|----------------|----------------------|----------------|
| **Server Configuration URI** | A URL field for the VCA server | Points to `/v5/models` endpoint |
| **VCA-server** | Name/label for the server | Set to "Actuate" |
| **Object model dropdown** | Dropdown of available models | Populated dynamically from `GET /v5/models` response (intruder listed first) |
| **VCA filter threshold** | Sensitivity/confidence slider | Maps to `confidence_threshold` stored on the API key |
| **Object types** | Checkboxes for object classes | Populated from `detection_classes` field in `GET /v5/models` response |

## Dynamic Population

A key design feature is that the EBUS UI does not hardcode Actuate's model list or detection classes. Instead:

1. EBUS calls `GET /v5/models` to discover which models are available (each model includes its `detection_classes`)
2. The operator selects a model (e.g., `intruder`)
3. The operator selects which object types to detect from the model's `detection_classes` (using the allow-list)

This dynamic discovery means new models or detection classes can be added on the Actuate side without requiring EBUS software updates.

## Detection Display

When EBUS sends a frame to `POST /v5/detect`, the API returns detection results including:

- **Label** -- the detected object class (e.g., "person", "car")
- **Confidence** -- detection confidence score
- **Bounding box** -- coordinates of the detected object in the frame

EBUS's AlarmReceiverVCA overlays this information on the video image, showing bounding boxes with labels and confidence scores. The component also provides statistical analysis capabilities for reviewing detection trends.

## Phase 1 Constraints

Phase 1 ships with the `intruder` model only. The `motion-plus` model is planned as the second model type. Because v5 is designed for single-frame inference, the stationary object filter is always disabled -- EBUS sends individual JPEGs, not video streams, so temporal filtering is not applicable.

## Confidence Threshold

The VCA filter threshold in EBUS maps to `confidence_threshold`, which is set at the API key level in DynamoDB. This means the threshold is a per-customer configuration managed by Actuate (via the [[admin-api/_summary|Actuate Admin API]]), not something the EBUS operator changes per-request. This design prevents partners from accidentally setting thresholds too low and generating excessive false positives.

## Reference

- [Phase 1 API to UI Mapping](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/493092870) (Confluence)
- [[v5-api-design]] -- full API specification
- [[shared-auth-pattern]] -- authentication architecture
