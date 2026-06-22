---
title: "AutoPatrol Tier Model + Detection Type Catalog (Immix spec)"
type: synthesis
topic: autopatrol
tags: [autopatrol, immix, tier, detection-types, commercial-agreement, pricing, dynamic-slicing, llm]
created: 2026-05-14
updated: 2026-05-14
author: mark
source: ~/Downloads/AutoPatrol Tiers & Detection Types.pdf (5 pages, Docusign Envelope ID CB4166BB-6CE3-47B5-8F09-4A4E79733D78)
incoming:
  - topics/autopatrol/notes/concepts/2026-05-14_autopatrol-tier-api-cross-reference.md
  - topics/autopatrol/notes/syntheses/2026-05-20_ap-summary-disable-plan.md
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/integrations/vch/notes/syntheses/2026-05-18_libav-decoder-warmup-frame-fix.md
  - topics/personal-notes/notes/daily/2026-05-15.md
incoming_updated: 2026-05-27
---

# AutoPatrol Tier Model + Detection Type Catalog (Immix spec)

Verbatim ingestion of the Immix-shared "AutoPatrol Tiers & Detection Types" PDF (Docusign Envelope ID CB4166BB-6CE3-47B5-8F09-4A4E79733D78). This is the authoritative reference for how Actuate must classify AutoPatrol alerts and stream requests when interacting with Immix. Cross-reference against the code surface lives in [[2026-05-14_autopatrol-tier-api-cross-reference]].

## TL;DR

For all practical purposes today:

- **Tier 1** = Camera Health Check / VCH. The PDF explicitly says *"This is VCH, not AutoPatrol — should not be returned for AutoPatrol."*
- **Tier 2** = Intrusion (Person, Vehicle, Bike, Vehicle Classification).
- **Tier 3** = Everything else that's currently in production: Threat Detection (Fire & Smoke, Vehicle ID by brand).

Tiers 4 (Compliance) and 5 (Management) are defined in the spec but flagged "Future, not in use, subject to change."

## Reporting Rule (load-bearing)

> "The AI Provider should return the value corresponding to the highest Tier associated with the detection types configured for that AutoPatrol, regardless of whether any detections were actually raised."

This applies regardless of whether the patrol fires any alerts. The tier we send must reflect the **maximum tier among configured detection types** for that AutoPatrol. Today the connector hardcodes the tier per code path — see the [[2026-05-14_autopatrol-tier-api-cross-reference|cross-reference note]] for the gap.

## Tier Table (PDF page 1)

| Tier | Solution | Actuate Detection Types | Notes |
|---|---|---|---|
| 1 | Camera Health Check | Visual Camera Health | This is VCH, not AutoPatrol — should not be returned for AutoPatrol. |
| 2 | Intrusion Detection | Person Detection; Vehicle Detection (In Motion & Static); Classification (car, truck, bus); Bike Detection (bicycle, motorcycle) | |
| 3 | Threat Detection | Fire & Smoke Detection; Vehicle ID (Amazon, DHL, FedEx, School Bus, UPS, USPS, Fire Truck); Non-UPS Vehicle ID | |
| 4 | Compliance | Future | Not in use, subject to change |
| 5 | Management | Future | Not in use, subject to change |

## Analytics Modules — Software Hierarchy (PDF page 2)

This is a separate framing — the **product feature hierarchy** used in marketing/sales material, not the tier-code mapping. Each higher module is "all of the previous module's analytics plus…":

**Camera Health Check:**
- Health
- Scene Change
- Tamper

**Intrusion Detection:** all Camera Health Check, plus:
- Presence of Persons
- Presence of Vehicles

**Threat Detection:** all Intrusion Detection, plus:
- Fire / Smoke Detection
- Fall Detection
- LPR (License Plate Recognition)
- Fight Detection
- Robbery Mask Detection
- Shoplifting Detection
- Crossline Detection
- Package Detection (Abandoned Object Detection, bag left behind, trash)
- Vehicle classification with attributes

**Compliance\*:** all Threat Detection, plus:
- Tailgating
- People Counting / Occupancy
- No Person Alert
- No Vehicle Alert
- Parking Violation Detection
- Direction of Travel
- Loitering / Dwell time
- Color of Clothing
- Uniform Recognition
- PPE Detection / Recognition (human attribute)
- Human with Backpack
- Dumping / Littering

**Management\*:** all Compliance, plus:
- Brand / Logo Recognition
- Crowd Detection / Density Estimation Heatmap
- Queue Management / Traffic Jam / Congestion
- OCR

`*` Compliance and Management are documented as future (Tier 4/5).

**Note on the two framings:** The Page 1 tier table is the **operational** classifier used for Immix integration. The Page 2 module hierarchy is the **product** taxonomy and contains analytics that may not yet have detection-code support in the connector. Where the two disagree (e.g., "Crowd Detection" appears in Page 3 commercial agreement and Page 2 Management module but is not listed in the Page 1 tier table), default to the Page 1 tier table for tier assignment.

## Commercial Agreement (PDF page 3)

**Actuate AI Solution Specification — Initial Development**

Base Detection Features:
- **Intruder detection:** Person, Vehicle
- **Crowd Detection**
- **Fire Detection**
- **Vehicle ID & No-UPS detection** — not configured by default, can be toggled on per individual camera

More Specific (associated with intruder detection):
- Specific # of persons or vehicles (occupancy)
- No person / no vehicle

Available attributes:
- Location in camera frame as set by operator
- Site and camera level "states" and historical data
- Reidentification of vehicles (based on existing analytics)
- Type of delivery vehicle (available by class) if enabled

**Dynamic Slicing Capabilities:**
- Enabled on higher-resolution cameras for higher detection confidence at greater distances.
- Camera must be lower than 4K resolution.
- Actuate runs an assessment at configuration time to check fit.
- If resolution is too low and dynamic slicing can't be applied, it is not possible to enable on the camera.

## Phase 2 — Large Language Model (PDF page 4)

LLM phase uses context from previous events, operator input, and across multiple camera streams + detections to make assessments. **Additional development required by Immix for this phase.**

Potential attributes to include:
- Security vehicle
- Emergency vehicle (fire, PD, EMS)
- Cleaning personnel
- Security guard
- Landscaping crew
- Uniformed individuals
- Doors / gates propped / open
- Gaps / cuts in fencing
- Lighting changes / anomalies

## Pricing — Schedule B (PDF page 5)

Fees are payable from Immix to Actuate for each feed processed by Actuate AI Solution as part of an AutoPatrol scheduled by a paying Licensee and processed by Actuate. **Charged once per Camera Feed per AutoPatrol scheduled and performed.** Excludes testing/demonstration. No upfront costs or volume commitments.

| Detection Type | Price | Pricing Information |
|---|---|---|
| Base Detection | $0.035 | Per camera stream per AutoPatrol |
| Base Detection + Dynamic Slicing | $0.08 | Includes Base Detection (not cumulative) |
| Large Language Model (LLM) | $0.06 | Additional Fee (on top of base) |

All Base Detection features outlined in Schedule A are included at the lowest price point. The higher price point unlocks dynamic slicing.

## Source

PDF: `~/Downloads/AutoPatrol Tiers & Detection Types.pdf`, ingested 2026-05-14. 5 pages. Docusign Envelope ID `CB4166BB-6CE3-47B5-8F09-4A4E79733D78`.

## Cross-references

- [[2026-05-14_autopatrol-tier-api-cross-reference]] — how `TierEnum`, `AutoPatrolDetectionCodeEnum`, `VCHDetectionCodeEnum`, and the `raise_patrol_alert` / `get_patrol_stream` call sites today align (and don't align) with this spec.
- [[vch-components]] — VCH = Tier 1 in this spec. Per-camera ~2s clip; Immix terminates the worker after the requested `Duration`.
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — Immix DeviceWorker lifecycle; relevant for understanding the stream-fetch side of the tier integration.
