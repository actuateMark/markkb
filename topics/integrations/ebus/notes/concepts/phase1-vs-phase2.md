---
title: "Phase 1 vs Phase 2 Scope"
type: concept
topic: ebus-integration
tags: [ebus, phases, roadmap, clips, api, accellence]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Phase 1 vs Phase 2: EBUS Integration Scope

The [[integrations/ebus/_summary|EBUS]] with Accellence Technologies is structured in two major phases (plus an investigatory Phase 2b). Each phase delivers a different level of integration depth between EBUS and the Actuate platform.

## Phase 1: API-Only Integration (Current)

**Status:** In progress (ED-32, ENG-126)
**Assignee:** [[mark-barbera|Mark Barbera]]

Phase 1 is a **unidirectional, single-frame** integration. EBUS sends images to Actuate and receives detection results back. There is no persistent connection, no video streaming, and no alarm state management.

### Flow

```
EBUS VMS -> captures JPEG frame -> POST /v5/detect (model_id in body) -> Actuate returns detections
    -> EBUS AlarmReceiverVCA displays bounding boxes + labels + confidence
```

### Scope

- **Endpoints:** `GET /v5/models`, `POST /v5/detect`
- **Models:** `intruder` only at launch; `motion-plus` planned as the second model
- **Auth:** Per-customer API keys via [[shared-auth-pattern]]
- **UI integration:** EBUS operator configures detection through native VMS settings (see [[ebus-ui-config-mapping]])
- **Display:** AlarmReceiverVCA shows video frames with detection overlays (label, confidence, bounding box) and provides statistical analysis

### What Phase 1 does NOT include

- No video clip handling
- No alarm persistence on the Actuate side
- No bidirectional communication (Actuate does not push to EBUS)
- No integration with Actuate's Clip Viewer

## Phase 2: Clips + Bidirectional Integration (Future)

**Status:** Planned (see Confluence: [Clips Integration Requirements](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/411795459))

Phase 2 introduces **video clips** and **bidirectional communication**. EBUS sends video clips (not just single frames) to Actuate, and Actuate pushes alert notifications back to EBUS.

### Key additions over Phase 1

- **Clip ingestion:** EBUS sends video clips to Actuate for processing
- **Actuate Clip Viewer integration:** Alarms generated from EBUS clips are visible in both the EBUS AlarmReceiverVCA and the Actuate Clips Viewer
- **EBUS integration type in Clip Viewer:** A dedicated integration type is added to the Actuate platform so EBUS-originated clips are properly categorized
- **Bidirectional alerts:** Actuate pushes detection results back to EBUS via a REST API callback, rather than EBUS polling for results

### Impact

Phase 2 makes EBUS a fully integrated alarm sender in the Actuate ecosystem, similar to how existing integrations (Immix, Patriot, etc.) operate through the [[admin-api/_summary|Actuate Admin API]]'s [[integration-architecture]].

## Phase 2b: Direct Integration Investigation (ED-33)

**Status:** To Do
**Assignee:** Unassigned

Phase 2b is an investigation into alternative connectivity paths that bypass the current "EBUS sends to Actuate" model:

1. **EBUS -> Actuate -> EBUS (SMTP/FTP):** EBUS pushes images/clips via SMTP or FTP, Actuate processes them, results returned to EBUS
2. **Camera -> Actuate -> EBUS (SMTP/[[rtsp-deep-dive|RTSP]]):** Cameras send directly to Actuate (via SMTP or [[rtsp-deep-dive|RTSP]]), Actuate processes and pushes results to EBUS

These paths would eliminate the need for EBUS to orchestrate the image capture and API call, shifting that responsibility to either EBUS's existing SMTP/FTP export or the camera's native streaming.

## Jira Tickets

| Ticket | Phase | Summary | Status |
|--------|-------|---------|--------|
| ED-4 | Parent | EBUS Integration | In Progress |
| ED-32 | 1 | Phase 1 API Integration | In Progress |
| ENG-126 | 1 | v5 API spec (technical) | To Do |
| ED-37 | 1 | Testing Criteria | To Do |
| ED-38 | 1 | Testing Execution | To Do |
| ED-33 | 2b | Direct integration investigation | To Do |
