---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [alerts, immix, dispatch, integration, payload, bounding-boxes]
---

# Immix Dispatch

Immix is Actuate's primary monitoring center integration partner. The Immix dispatch workstream within [[alerts-improvements]] focuses on refining how Actuate sends alert data to the Immix platform, ensuring monitoring center operators receive rich, actionable information rather than bare notifications.

## Immix's Role in the Ecosystem

Immix operates as a monitoring center software platform. When Actuate detects a threat, the alert can be dispatched to Immix, where a professional monitoring center operator reviews it and takes action (contacting the client, dispatching police, etc.). This is the B2B2B channel: Actuate sells AI detection to monitoring centers that use Immix, who in turn serve end customers.

This channel generates significant revenue -- [[autopatrol]]'s VCH partnership with Immix is valued at approximately $800K over 12 months.

## Enhanced Interaction (AIM-3)

Epic AIM-3 covers enhanced interaction with Immix, last updated March 6. The goal is to move beyond basic alert forwarding to a richer integration where:

- **Alert payloads carry more context** -- detection type, confidence score, camera metadata, site information
- **Visual evidence is enhanced** -- clips and frames with overlaid bounding boxes showing exactly what triggered the alert
- **Alarm schedule synchronisation** -- AIM-91 (Jessica Bae) would receive schedule signals from Immix so Actuate knows when a site is armed/disarmed in the monitoring center's system

## Bounding Boxes on Clips

One concrete deliverable is adding bounding boxes to AutoPatrol clips sent to Immix. **Mark Barbera** has this ready to deploy (AUTO-351). This is a high-value improvement: when a monitoring center operator receives a clip, the bounding box immediately draws their eye to the detection, reducing review time from scanning the entire frame to verifying a highlighted region.

## Payload Refinement

The dispatch payload -- the data packet sent to Immix with each alert -- is being refined to include:

- **Detection metadata** -- model name, confidence score, detection class (firearm, intrusion, loitering, etc.)
- **Spatial data** -- bounding box coordinates, camera zone
- **Temporal data** -- timestamp, duration of event, whether the event is ongoing
- **Site context** -- site name, camera name, zone name, site type

Richer payloads enable Immix operators to make faster, better-informed decisions. A bare "motion alert" is much less useful than "Intrusion detected (92% confidence) at Front Gate, Site: Downtown Warehouse, after-hours event."

## Alert Dispatch Architecture (AIM-2)

Epic AIM-2 covers the alert dispatch pipeline itself. This is the infrastructure that routes alerts from Actuate's detection pipeline to external systems. Immix is the primary target, but the architecture should support additional integrations. Related backlog item CS3-44 in [[camera-health-monitoring]] tracks sending CHM alerts to Immix as well.

## Relationship to Watchman

[[watchman]] represents a pivot from the B2B2B model (through Immix/monitoring centers) to B2B direct (to commercial businesses). However, Immix integration remains important:

- Existing AutoPatrol customers are served through Immix and will continue to be
- Some Watchman customers may opt for professional monitoring as an add-on tier
- The [[multi-agent-architecture|Escalation Agent]] in Watchman could dispatch to Immix as one of its escalation channels alongside push, SMS, and phone calls

The payload refinement work benefits both products -- richer context helps whether the recipient is a professional Immix operator or a business owner using Watchman's [[triage-gamification|triage workflow]].

## Current Status

AIM-3 (Enhanced Immix interaction) was last updated March 6. AUTO-351 (bounding boxes on AP clips to Immix) is ready to deploy. The broader Alerts Improvements initiative is effectively stalled with 25 of 29 issues unassigned, but the Immix-specific work via AutoPatrol is further along.
