---
title: EBUS Integration (Accellence Technologies)
type: summary
topic: integrations/ebus
tags: [ebus, accellence, vms, integration, v5, partner]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/401735681"
jira: "ED-32"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# EBUS Integration

**EBUS** is a video management system (VMS) platform built by **Accellence Technologies** (Germany). Used by security monitoring centers to manage camera feeds, display alarms, and review video evidence. EBUS has an **AlarmReceiverVCA** component for displaying VCA results.

EBUS is the **first consumer** of the [[external-api/_summary|External API Initiative]] v5 detection API.

## Phase 1: API Integration (Current)

**Flow:** EBUS sends single JPEG frames -> Actuate v5 API -> threat detection results -> EBUS AlarmReceiverVCA

**Endpoints:**
- `GET /v5/models` -- lists available detection models with their detection classes and data schemas
- `POST /v5/detect` -- unified inference endpoint (model specified via `model_id` in request body)

**EBUS UI Configuration Mapping:**
| EBUS Setting | Maps To |
|-------------|---------|
| Server Configuration URI | `/v5/models` |
| VCA-server | "Actuate" |
| Object model dropdown | Populated from `GET /v5/models` response (intruder first) |
| VCA filter threshold | `confidence_threshold` on API key |
| Object types | From `detection_classes` field in `GET /v5/models` response |

**Display:** Video images with label, confidence, bbox overlay in AlarmReceiverVCA. Statistical analysis available.

**Phase 1 ships:** `intruder` model only. `motion-plus` planned as second model type.

## Phase 2: Clips Integration (Future)

EBUS sends **video clips** to Actuate; Actuate pushes alerts back via REST API.
- EBUS integration type added to Clip Viewer
- Same alarm visible in both EBUS AlarmReceiverVCA and Actuate Clips Viewer

## Phase 2b: Direct Integration Investigation (ED-33)

Two paths under consideration:
1. EBUS -> Actuate -> EBUS (SMTP/FTP)
2. Camera -> Actuate -> EBUS (SMTP/RTSP)

## Jira Tickets

| Ticket | Project | Status | Assignee | Summary |
|--------|---------|--------|----------|---------|
| **ED-4** | EU Deployment | In Progress | Unassigned | Parent: EBUS Integration |
| **ED-32** | EU Deployment | In Progress | Mark Barbera | Phase 1 API Integration |
| **ED-33** | EU Deployment | To Do | Unassigned | Investigate direct integration options |
| **ED-37** | EU Deployment | To Do | Unassigned | Testing Criteria |
| **ED-38** | EU Deployment | To Do | Unassigned | Testing Execution |
| **ENG-126** | Engineering | To Do | Mark Barbera | v5 API spec (technical implementation) |

## Key Design Decisions

- Per-customer API keys (not one key per EBUS)
- `detection_classes` allow-list (not `ignore_labels` deny-list)
- `vehicle` alias with server-side expansion
- Stationary filter always OFF for API (single-frame inference)

## Confluence Pages

- [Product Requirements](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/401735681)
- [Clips Integration Requirements](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/411795459)
- [Phase 1 API to UI Mapping](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/493092870)
