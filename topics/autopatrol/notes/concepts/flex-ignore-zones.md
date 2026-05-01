---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [autopatrol, ignore-zones, flex-iz, cameras, scheduling, api]
---

# Flex Ignore Zones

Flex [[ignore-zones|Ignore Zones]] are the dominant active workstream in [[autopatrol/_summary|AutoPatrol (H1.2)]] as of April 2026. The feature allows multiple ignore zone (IZ) presets to be configured per camera, with different presets selectable per patrol schedule. This is a significant upgrade from the previous model where each camera had a single, static set of [[ignore-zones|ignore zones]].

## Problem Statement

[[ignore-zones|Ignore zones]] mask regions of a camera's field of view where detections should be suppressed -- busy roads, swaying trees, reflective surfaces. In practice, what counts as a nuisance zone changes with context. A loading dock that should be ignored during business hours (constant legitimate movement) may need full monitoring after hours. A retail entrance that generates constant foot traffic during the day becomes a high-value intrusion zone at night.

A single static ignore zone configuration forces operators to choose between daytime accuracy and nighttime coverage. Flex IZ solves this by letting each camera carry multiple named presets that activate according to schedule.

## Architecture

### API Layer
**Tatiana** is implementing the backend API (AUTO-500). The API must support:
- CRUD operations for IZ presets per camera
- Association of presets with patrol schedules
- Settings generation -- when a patrol schedule activates, the correct IZ preset must be resolved and applied to the [[detection-pipeline|detection pipeline]]

### Frontend
**[[brad-murphy|Brad Murphy]]** is building the frontend components across multiple tickets:
- **AUTO-446** -- Flex IZ on AP schedules (schedule-level preset selection)
- **AUTO-427** -- IZ preset management UI
- **AUTO-424 / AUTO-493** -- Bulk updating FE component (Highest priority, Ready to Deploy). This enables operators to apply IZ presets across multiple cameras simultaneously rather than configuring each one individually.
- **AUTO-425** -- Additional IZ frontend work

### QA
**Victoria Peccia** handles testing:
- **AUTO-408** -- IZ preset validation
- **AUTO-444** -- Flex IZ QA scenarios
- **AUTO-426** -- Preset selection QA

## Settings Generation Pipeline

When a patrol schedule triggers, the system must resolve which IZ preset applies to each camera at that moment. This involves:
1. Looking up the schedule's associated IZ preset for each camera
2. Generating the detection settings with the correct masked regions
3. Passing those settings to the AI [[detection-pipeline|detection pipeline]] so that events in ignored regions are suppressed

This is the same settings generation pipeline used across Actuate's products, extended to support preset selection. The work connects to the broader [[settings-automation/_summary|Settings Automation (H1.4)]] initiative.

## Relationship to Watchman

The Flex IZ concept is directly portable to [[watchman/_summary|Actuate Watchman]]. [[watchman-repo|Watchman]]'s [[patrol-vs-active-modes|Patrol Agent]] inherits from AutoPatrol's scheduling infrastructure, and ignore zone handling is part of that inheritance. In [[watchman-repo|Watchman]]'s context, the [[multi-agent-architecture|Site Context Agent]] could potentially automate IZ preset switching based on learned site rhythms rather than requiring manual schedule configuration.

## Current Status

This is the highest-activity workstream in AutoPatrol by ticket count and team allocation. The bulk update component (AUTO-424/493) is at "Ready to Deploy" status, and the schedule-level flex IZ work (AUTO-446/500) is in progress.
